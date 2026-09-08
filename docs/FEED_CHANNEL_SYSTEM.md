# Feed & Channel System — Status Documentation

*Audit date: Aug 23, 2026. All claims verified against the current codebase.*

This document maps the entire feed + channel pipeline in Kabuk, describes how each piece
is *supposed* to work, and separates what **actually works** from what **doesn't**. It
supersedes the older gap descriptions in `README.md` (Known Gaps), `TODO.md` (§Content/Channels),
and `docs/IMPROVEMENT_ROADMAP.md` (§Phase E) with precise file:line references.

---

## 1. Architecture Overview

```
                    ┌───────────────────────────────────────────────────┐
                    │                     UI LAYER                      │
                    │   ExploreView (feed)    ChannelView / ChannelPage │
                    │   WebChannelView         Omnibar / BrowseSession  │
                    └──────────────┬───────────────────┬────────────────┘
                                   │                   │
                    ┌──────────────▼───────────────────▼────────────────┐
                    │                  SERVICE LAYER                    │
                    │   FeedService (SharedFeedService)                 │
                    │   ├─ RssFeedSource   ├─ RedditFeedSource          │
                    │   ├─ FourchanSource  ├─ NostrFeedSource           │
                    │   └─ UsenetFeedSource                             │
                    └──────────────┬────────────────────────────────────┘
                                   │
                    ┌──────────────▼────────────────────────────────────┐
                    │              KNOWLEDGE LAYER (Drift/SQLite)        │
                    │   schema:Article + kabuk:FeedSubscription triples │
                    │   kabuk:NostrNote (global Nostr notes)            │
                    └───────────────────────────────────────────────────┘
```

Two independent data pipelines feed the Explore UI:

1. **Feed pipeline** — `FeedService.fetchItems()` → `createArticle()` → `schema:Article`
   triples → `articlesProvider` → Explore feed. This is the *main* pipeline.
2. **Channel pipeline** — plugin `fetchChannel()` / `FeedSource.fetchItemsPage()` →
   `Channel` + `ContentItem` / `ArticleData` → `ChannelView`, `ChannelPage`,
   `WebChannelView`. This pipeline is largely broken (see §5).

Nostr global notes use a *third*, disconnected path: `refreshNostrFeed()` writes
`kabuk:NostrNote` entities that **no UI widget ever reads** (see Gap F6).

---

## 2. Component Map

### 2.1 Feed sources (fetch + parse)

| File | Class | Type | Supports |
|---|---|---|---|
| `lib/platform/shared/rss_source.dart` | `RssFeedSource` | rss / atom | RSS 2.0 + Atom, media thumbnails, enclosures, RFC-2822 dates |
| `lib/platform/shared/reddit_source.dart` | `RedditFeedSource` | reddit | JSON API (unauthenticated), galleries, videos (HLS), crossposts, `after` cursor pagination |
| `lib/platform/shared/fourchan_source.dart` | `FourchanFeedSource` | fourchan | 4chan catalog JSON API, thumbnails |
| `lib/platform/shared/nostr_feed_source.dart` | `NostrFeedSource` | nostr | Hashtag / global / following / NIP-50 search streams (8 s timeout) |
| `lib/platform/shared/usenet_feed_source.dart` | `UsenetFeedSource` | usenet | Newznab indexer search |

### 2.2 Feed service (dispatch + detection)

- `lib/services/feed.dart` — `FeedItem`, `FeedSource`, `FeedService` interfaces.
- `lib/platform/shared/feed_service_impl.dart` — `SharedFeedService`:
  - `fetchItemsPage()` only delegates to `RedditFeedSource.fetchPage()` for cursor
    pagination; all other sources return `nextCursor: null` (`feed_service_impl.dart:70-75`).
  - `detectType()` — URL pattern matching: nostr → reddit → 4chan → usenet → .rss/.xml/.atom
    → validate-as-RSS → validate-as-Reddit (`feed_service_impl.dart:79-135`).
  - Registered in `lib/config/providers.dart:309` (`feedServiceProvider`).

### 2.3 Knowledge store types

- `lib/knowledge/types/article.dart`:
  - `ArticleData` (§schema:Article entity — the feed item).
  - `FeedSubscriptionData` (`kabuk:FeedSubscription` entity — the "following" record).
  - `createArticle()` — stamps `kabuk:expiresAt = published + 48h` (`article.dart:364`).
  - `markArticleRead()` — extends expiry to 7 days (`article.dart:473`).
  - `pruneStaleArticles()` — deletes expired unread non-bookmarked articles
    (`article.dart:496`); runs on app startup and after every refresh.
  - `listArticles()` (limit only, ordered by `datePublished` desc).
  - `deleteFeedSubscription()` — also deletes all articles tagged with the sub URI.
- `lib/knowledge/types/nostr_social.dart` — `NostrNoteData` (`kabuk:NostrNote`) — **separate
  from `schema:Article`**; used only by `refreshNostrFeed`.

### 2.4 Explore UI

- `lib/ui/explore/explore_view.dart` — the feed screen:
  - `articlesProvider` — `listArticles(limit: 200)` + URL dedup (`explore_view.dart:69-80`).
  - `subscriptionsProvider` — `listFeedSubscriptions()`.
  - `refreshAllFeeds()` — parallel fetch of all subscribed feeds; `force` bypasses the
    per-feed `refreshInterval`; **skips `feedType == 'web'`** (`explore_view.dart:250`);
    Reddit sort injected via `_buildRedditSortUrl()`.
  - `_fetchFeed()` — per-sub fetch + global URL dedup against `listArticles(limit: 2000)`;
    **swallows all errors → returns `[]`** (`explore_view.dart:347-353`).
  - `_loadMore()` — **Reddit-only** cursor pagination (`explore_view.dart:491-568`).
  - Filters: `feedSortProvider` (new/hot/top), `blockedKeywordsProvider`, `hideNsfwProvider`,
    `mutedSourcesProvider`, per-subscription `selectedFeed`.
  - `_buildFeed()` — per-feed filtering; `'nostr:global'` matches
    `feedSource?.startsWith('nostr')` (`explore_view.dart:1361-1364`); `'web'` matches by
    subscription URI / domain / `web:`-prefixed feedSource.
- `lib/ui/explore/filter_bar.dart` — All / Nostr / per-subscription chips. **Tapping a chip
  only filters cached articles; it never triggers a fetch for that feed.**
- `lib/ui/explore/feed_management_sheet.dart` + `lib/ui/settings/feed_sources_page.dart` —
  list/edit/delete subscriptions; add dialog offers Reddit / RSS / Nostr / 4chan types.

### 2.5 Browse / web surface

- `lib/ui/explore/browse_session.dart` — temporary in-memory browse (not persisted) of a
  source before subscribing; `browseItemToArticle()` uses `browse://` URIs.
- `lib/ui/explore/web_channel_view.dart` — native channel for parsed web pages
  (single article → reader inline, multi-article → cards). Follow button creates a `web`
  subscription. **Used by `omnibar` and `WebChannelLoader`.**
- `lib/ui/explore/omnibar.dart` — URL bar + search; plugin `resolveUrl()` →
  `ResolvedContentItem` (opens viewer) or `ResolvedChannel` (**opens `WebChannelView`, not
  `ChannelPage`** — `omnibar.dart:931-946`); non-plugin URLs → `readerModeService.processUrl()`
  → `WebChannelView`.

### 2.6 Channel views

- `lib/ui/explore/channel_view.dart` — `ChannelView` ("unified author/channel view").
  - `_authorFeedUrl` / `_channelFeedUrl` **only return non-null for Reddit**
    (`channel_view.dart:31-46`).
  - Channel mode loads store content by tag `r/<name>` (a Reddit-only convention,
    `channel_view.dart:178-181`).
  - `_storeAndDedup()` stores fetched items with `feedSource: widget.sourceType.name`
    (e.g. the literal string `"reddit"`) — **not** the subscription URI
    (`channel_view.dart:303`).
  - Only ever invoked with `FeedSourceType.reddit` from `article_card.dart:679,692` and
    `article_detail_page.dart:62,77`.
- `lib/ui/explore/channel_page.dart` — `ChannelPage` ("unified channel page", collapsing
  header + filter tabs + grid). Fetches via plugin `fetchChannel()`; **for non-plugin
  channels returns `const []`** (`channel_page.dart:171-179`). **Never navigated to**
  anywhere in the app — dead code.
- `lib/ui/explore/agent_channel_surface.dart` — `AgentChannelPage` (a *different* widget)
  driven by observation events; reachable from `lib/ui/shell.dart:221`.

### 2.7 Plugins (channel capability)

- `lib/plugins/plugin.dart` — `ContentPlugin` interface; capabilities: search / channel /
  urlResolve / trending.
- Bundled plugins (`lib/plugins/bundled/`): reddit, fourchan, hackernews, media, soundcloud,
  wikipedia, youtube, bandcamp.
- `lib/ui/explore/omnibar.dart` is the **only** surface that reaches plugin content.

### 2.8 Agent surfaces

- `lib/agents/domains/feed_agent.dart` — `subscribe_feed`, `list_feeds`, `unsubscribe_feed`,
  `refresh_feed`, `list_articles`, `search_articles`, `mark_read`, Usenet indexer/provider tools.
- `lib/agents/domains/discovery_agent.dart` — `search_nostr_hashtag` / `search_nostr_content`
  return `ToolResult.channel(...)`; `subscribe_topic` creates a `nostr:t/...` feed
  subscription and immediately fetches initial content (`discovery_agent.dart:763-840`).
- `lib/ui/explore/topic_following.dart` — follow/unfollow hashtags as SavedSearch +
  `feedType: 'nostr'` FeedSubscription.

---

## 3. Data Flow (as designed)

**Feed refresh (`refreshAllFeeds`, `explore_view.dart:231`):**
1. `listFeedSubscriptions()` → for each sub with a URL and `feedType != 'web'`:
2. `feedService.fetchItems(url, type: ...)` (Reddit gets sort-injected URL)
3. dedup against `listArticles(limit: 2000)` by URL
4. `createArticle(...)` with `feedSource = sub.uri`
5. `updateFeedLastFetched(sub.uri)`
6. Explore invalidates `articlesProvider` → feed re-renders.

**Browse → subscribe (`_subscribeToBrowseSession`, `explore_view.dart:1246`):**
- browse a URL → `createFeedSubscription(feedType: derived)` → `refreshAllFeeds()` →
  new articles appear in the All feed and under the new chip.

**Reddit channel (`ChannelView`):**
- open `r/<name>` / `u/<user>` → load cached articles from store (tag `r/<name>` /
  `schema:author`), then `fetchItemsPage` on `_channelFeedUrl`/`_authorFeedUrl` → store new
  items → merge → render.

**Plugin channel (`ChannelPage` — intended, unused):**
- resolve channel via plugin → `plugin.fetchChannel(entityId)` → `ContentItem` grid.

---

## 4. What Works (verified in code)

| # | Capability | Where | Notes |
|---|---|---|---|
| W1 | RSS/Atom subscriptions fetch + parse | `rss_source.dart` | RSS 2.0 + Atom, images, dates |
| W2 | Reddit subreddit subscriptions fetch + parse | `reddit_source.dart`, `explore_view.dart:289-293` | Galleries, HLS video, crossposts, sort injection |
| W3 | 4chan board subscriptions fetch + parse | `fourchan_source.dart` | Catalog API |
| W4 | Usenet indexer subscriptions fetch + parse | `usenet_feed_source.dart` | Newznab |
| W5 | Nostr hashtag/topic subscriptions fetch as articles | `nostr_feed_source.dart`, `discovery_agent.dart:763` | `nostr:t/...` URL → `schema:Article` |
| W6 | Pull-to-refresh + auto-refresh (30 min timer + foreground recheck) | `explore_view.dart:437-468, 644-687` | `force: true` bypasses intervals |
| W7 | Sort modes New / Hot / Top | `explore_view.dart:1679-1703` | Reddit sort also server-side |
| W8 | Content filters (keywords, NSFW, muted sources) | `explore_view.dart:119-201, 1656-1676` | Client-side |
| W9 | Per-feed filter chips + feed management (rename/category/interval/delete) | `filter_bar.dart`, `feed_management_sheet.dart`, `feed_sources_page.dart` | Chip tap = filter only, no fetch |
| W10 | URL dedup on ingest | `explore_view.dart:296-316` | vs. newest 2000 |
| W11 | Read-tracking extends expiry to 7 d; bookmarks never pruned | `article.dart:473-485, 516` | |
| W12 | Reddit "load more" cursor pagination | `explore_view.dart:491-568`, `reddit_source.dart:45-91` | Appends in-memory only |
| W13 | Reddit subreddit/user native ChannelView | `article_card.dart:673-698`, `article_detail_page.dart:56-83` | Works for Reddit |
| W14 | Web page browse → `WebChannelView` + follow as `web` subscription | `omnibar.dart`, `web_channel_view.dart` | One-time parse |
| W15 | Agent feed tools (subscribe/list/refresh/unsubscribe/articles/mark-read) | `feed_agent.dart`, `discovery_agent.dart` | Covered by tests |

---

## 5. What Doesn't Work (gaps, verified with file:line)

### F1 — Explore feed hard-capped at 200 articles
`articlesProvider` reads `listArticles(limit: 200)` (`explore_view.dart:72`).
`_loadMore` can append Reddit items to the in-memory `_displayedArticles`, but any
filter change / provider invalidate resets the list from the 200-article provider
(`explore_view.dart:1471-1505`). Older content is unreachable; non-Reddit feeds have no
load-more at all (see F4).

### F2 — Unread articles auto-deleted after 48 h
`createArticle` stamps `kabuk:expiresAt = published + 48h` (`article.dart:364`);
`pruneStaleArticles` runs on startup and after every refresh and deletes expired unread
articles (`article.dart:496`, called at `explore_view.dart:675`). Content the user didn't
open within 48 h is silently destroyed. Read extends to 7 d; bookmarks are exempt.

### F3 — `web` subscriptions never refresh
`refreshAllFeeds` explicitly skips `feedType == 'web'` (`explore_view.dart:250`), because
web pages are one-time AI-parsed. A followed website (via `WebChannelView`) shows the
parse-time snapshot forever — there is no periodic re-fetch path for web feeds.

### F4 — Pagination is Reddit-only
- `fetchItemsPage()` returns `nextCursor: null` for every non-Reddit source
  (`feed_service_impl.dart:70-75`).
- `_loadMore` only paginates Reddit subs (`explore_view.dart:503-509`); RSS/Nostr/4chan/
  Usenet feeds can never load beyond the store cap (see F1).

### F5 — Reddit unauthenticated API + swallowed errors
`RedditFeedSource` uses a browser User-Agent + `over18=1` cookie but no OAuth
(`reddit_source.dart:28-30, 55-62`). Reddit aggressively 429s/403s such requests, and
`_fetchFeed` catches *all* exceptions and returns `[]` (`explore_view.dart:347-353`), so
feeds silently go stale with zero user feedback (the refresh UI shows no per-feed error).

### F6 — "Nostr" feed chip effectively shows nothing; global Nostr feed is unrendered
Two compounding bugs:
1. `refreshNostrFeed` stores global notes as `kabuk:NostrNote` entities via
   `createNostrNote` (`nostr_providers.dart:595`, `nostr_social.dart:193`) — **not**
   `schema:Article`. They never enter `articlesProvider`.
2. The `'nostr:global'` filter matches `a.feedSource?.startsWith('nostr')`
   (`explore_view.dart:1361-1364`), but articles from Nostr-topic subscriptions are stored
   with `feedSource = sub.uri` (a `kabuk:FeedSubscription/...` URI), which does **not**
   start with `nostr`.
3. `nostrNotesProvider` — the only consumer of `NostrNoteData` — is **never watched by any
   widget** (`nostr_providers.dart:545`; only invalidated at `explore_view.dart:686`).

Net result: the global Nostr feed is invisible, and the Nostr chip matches ~nothing.

### F7 — ChannelView is effectively Reddit-only
`_authorFeedUrl` / `_channelFeedUrl` return `null` for every source except Reddit
(`channel_view.dart:31-46`), so `_fetchAuthorContent`/`_fetchChannelContent` stop
immediately for Nostr/RSS/4chan/USenet. The store query for channel mode filters by tag
`r/<name>` (`channel_view.dart:178-181`) — a tag only Reddit produces. Non-Reddit channels
show "No posts found".

### F8 — Following from ChannelView mangles `feedSource`
`_storeAndDedup` stores fetched items with `feedSource: widget.sourceType.name`
(the literal string `"reddit"`) instead of the subscription URI (`channel_view.dart:303`).
If the user then taps **Follow**, a subscription is created, but the already-cached articles
keep `feedSource = "reddit"` — `_fetchFeed` dedups them and `continue`s without re-tagging
(`explore_view.dart:304-315`). The new subscription chip therefore shows zero articles
until genuinely new posts arrive. Also pollutes the "All" feed with `feedSource="reddit"`
articles that belong to no subscription.

### F9 — ChannelPage is dead code
`ChannelPage` is never pushed by any navigation path (`rg ChannelPage` → only its own file
and `AgentChannelPage`, which is a different widget). Its non-plugin branch returns `const []`
(`channel_page.dart:171-179`), so even if wired up it would render nothing for non-plugin
channels. The intended "unified" channel view does not exist in the navigation graph.

### F10 — Plugin content has no Explore/channel surface
YouTube / HackerNews / Wikipedia / SoundCloud / Bandcamp / Media plugins are reachable only
via omnibar search or URL resolution. `ChannelPage` (which could render `fetchChannel`
results) is unused, and plugins never feed into `articlesProvider`. "YouTube feed source"
and similar advertised capabilities don't surface in Explore.

### F11 — `ResolvedChannel` routes to WebChannelView, not ChannelPage
When the omnibar resolves a URL to a channel it opens `WebChannelView`
(`omnibar.dart:931-946`), bypassing the plugin-channel path entirely.

### F12 — Feed filter chips never fetch
Tapping a chip only filters already-cached articles (`filter_bar.dart` → `onSelected`
sets `selectedFeed`; `explore_view.dart:862-869`). The selected feed is not refreshed on
selection, so a fresh subscription's chip can be empty until a global refresh happens.

### F13 — Ingest dedup window is capped at 2000
`_fetchFeed` dedups against `listArticles(limit: 2000)` (`explore_view.dart:296`). Anything
older than the newest 2000 is considered new and re-created → duplicate articles accumulate
for high-volume sources.

### F14 — Nostr-profile "channel" has no Article representation
Nostr authors route to `ProfileView` (separate), but `ChannelView` with `sourceType: nostr`
is a silent no-op (author feed URL is null). There is no article-card surface for a Nostr
author's posts in the unified channel pipeline.

---

## 6. Root Causes (thematic)

1. **No per-source pagination abstraction** — `FeedSource` has `fetch()`/`validate()` only;
   cursor support is bolted onto `RedditFeedSource` and `fetchItemsPage()` special-cases it.
   F1/F4.
2. **Two competing channel models** — `ChannelView` (feed-source based, Reddit-only) and
   `ChannelPage` (plugin-based, unused) were built for the same job and neither was finished
   or wired up. F7/F9/F10/F11.
3. **Inconsistent `feedSource` semantics** — the rest of the app uses subscription URI as
   `feedSource`; ChannelView uses the enum name. F8, and the `nostr:` prefix convention in
   the Nostr filter matches neither. F6.
4. **Nostr notes modeled separately from articles** — global Nostr notes live in
   `kabuk:NostrNote`, outside the article feed; the "Nostr" chip's prefix matcher was
   written for a model that doesn't exist. F6.
5. **Content TTL is a foot-gun** — 48 h default expiry with prune-on-every-refresh is the
   single biggest data-loss risk. F2.
6. **Errors are swallowed everywhere** — `_fetchFeed`, the 4chan source, and the Nostr
   stream all degrade to empty results silently, so failures are indistinguishable from
   "no new content". F5.
7. **`web` feeds are one-shot by design** — the browse flow parses once and never refreshes.
   F3.

---

## 7. Recommended Fixes (priority order)

| # | Fix | Effort | Related gaps |
|---|---|---|---|
| 1 | Remove/raise the 48 h expiry default (configurable TTL, prune only ancient content) | S | F2 |
| 2 | Paginate `articlesProvider` (offset/cursor) so the feed isn't capped at 200 | M | F1 |
| 3 | Route channel fetches through feed sources per source type in `ChannelView` (build author/channel URL builders for RSS/4chan/Nostr, or reuse the plugin `fetchChannel`) | M | F7 |
| 4 | Store `feedSource = sub.uri` in `ChannelView._storeAndDedup` and re-tag existing articles on subscribe | S | F8 |
| 5 | Surface per-feed fetch errors in the UI; back off on Reddit 429/403; consider OAuth | M | F5 |
| 6 | Model Nostr global notes as `schema:Article` (or render `nostrNotesProvider`), and fix the `nostr:global` filter to match subscription URIs / a `nostr` feedSource | M | F6 |
| 7 | Wire `ChannelPage` into navigation (omnibar `ResolvedChannel`, plugin results) and implement its knowledge-store branch | M | F9/F10/F11 |
| 8 | Refresh `web` subscriptions periodically (re-parse with cached snapshot as fallback) | M | F3 |
| 9 | Add `refreshOnSelect` to filter chips; widen dedup window or use URL index | S | F12/F13 |

## 8. Test Coverage

There are **no** widget/service tests for the feed or channel pipeline. Existing coverage
is agent-level only:

- `test/agents/feed_agent_test.dart` — subscribe/list/refresh/unsubscribe article tools ✅
- `test/agents/discovery_agent_test.dart` — hashtag search, subscribe_topic ✅
- `test/agents/channel_tool_test.dart`, `channel_tools_test.dart`-style coverage via
  discovery ✅
- Missing: `feed_service_impl`, `rss_source`, `reddit_source`, `fourchan_source`,
  `nostr_feed_source`, `explore_view`, `channel_view`, `channel_page` tests — none exist.

`flutter analyze`: 0 errors, 6 warnings (all in `usenet`/`entity_player`, unrelated).