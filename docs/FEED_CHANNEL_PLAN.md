# Feed & Channel Restructuring Plan

*Status audit: `docs/FEED_CHANNEL_SYSTEM.md` (Aug 2026). This plan fixes the verified gaps and
restructures the fragmented feed/channel code into one unified mechanism.*

> **STATUS (Aug 23, 2026): All phases implemented.** `flutter analyze` clean (0 errors, 6
> pre-existing warnings), **717/717 tests passing** (34 new tests added for the store
> pagination/filters/preferences/retag, ContentSource adapters, Reddit URL builder + fallback,
> and DuckDuckGo helpers).

---

## 0. Root-Cause Diagnosis (the three symptoms you reported)

### A. "Filters don't do anything"
Verified causes (`docs/FEED_CHANNEL_SYSTEM.md` gaps F6, F12, F13 + F1):
1. **Chips filter cached data only** — tapping a chip sets `selectedFeed` but never fetches
   that source (`filter_bar.dart` → `explore_view.dart:862-869`). A freshly-added feed's chip
   is empty until an unrelated global refresh happens.
2. **`FeedSourcesPage._addFeed` doesn't refresh after subscribing** (`feed_sources_page.dart:605-609`)
   — it only persists the subscription and pops. The chip therefore shows "No articles from
   this feed yet".
3. **The `Nostr` chip matches ~nothing** — `'nostr:global'` filters by
   `feedSource?.startsWith('nostr')` (`explore_view.dart:1361-1364`), but articles use
   subscription URIs (`kabuk:FeedSubscription/...`) or `web:` prefixes, and global notes are
   stored as `kabuk:NostrNote`, not `schema:Article` (gap F6).
4. **Content filters are in-memory and capped** — `blockedKeywordsProvider` /
   `hideNsfwProvider` / `mutedSourcesProvider` are `StateProvider`s (reset on every restart,
   `explore_view.dart:110-116`) applied *after* the 200-article cap (F1). There is no filter
   on the knowledge-store query itself.

### B. "Refresh doesn't work"
Verified causes (F2, F3, F4, F5, F13):
1. **All fetch errors are swallowed** — `_fetchFeed` catches everything and returns `[]`
   (`explore_view.dart:347-353`). A Reddit 429/403, a dead RSS host, a bad TLS handshake —
   all look identical to "no new content". The UI shows "Updated just now" while nothing
   changed. (Reddit, the most likely source, aggressively blocks the unauthenticated JSON API —
   `reddit_source.dart:28-62`.)
2. **`web` subscriptions never refresh** — explicitly skipped in `refreshAllFeeds`
   (`explore_view.dart:250`).
3. **Refresh is blocked by the Nostr pass** — `_doRefresh` runs `refreshNostrFeed` inside the
   same `Future.wait`; `processNostrEvents` always waits its full 8 s timeout, and per-event
   `createNostrNote` I/O runs serially (`nostr_utils.dart:79-114`). Minimum refresh latency ≈ 8 s.
4. **48 h auto-delete** — `pruneStaleArticles` deletes unread articles 48 h after publication
   on every refresh (`article.dart:364,496`), so content the user expected to still be there is
   gone after two days.

### C. "Constantly fetching Nostr, feels broken"
Verified causes:
1. **A permanent DM subscription runs for the whole app lifetime** —
   `nostrDmBackgroundListenerProvider` (watched from `shell.dart:129`) subscribes to
   `watchDirectMessages` = a relay REQ for kind-1059 gift-wraps that is never cancelled
   (`providers.dart:1367-1381`, `nostr_service_impl.dart:1381-1431`).
2. **Every relay EVENT is debug-logged even when dropped** —
   `[Nostr] EVENT … hasListener=false` at `nostr_service_impl.dart:452-454` fires for
   *every* event on *every* connected relay, even when no consumer exists.
3. **Relays stay connected 24/7** — no idle close; reconnection churn adds
   `[Nostr] connected … replaying N subscriptions` logs (`nostr_service_impl.dart:369-374`).
4. **Unbounded 8 s fetch windows** — every Explore refresh, topic feed, profile view, and
   search spawns an 8 s relay subscription, so even idle navigation causes repeated
   connect/REQ/EVENT traffic (`nostr_utils.dart`).

---

## 1. Target Architecture (the "proper unified mechanism")

Replace the two competing pipelines (feed-source-based `ChannelView` vs plugin-based `ChannelPage`,
plus the disconnected Nostr note path) with **one abstraction**:

```
                     ┌───────────────────────────────────────────────┐
                     │              UNIFIED UI LAYER                 │
                     │  ExploreFeed (paged, filterable)              │
                     │  ChannelPage (one widget for ALL channels)    │
                     └───────────────┬───────────────────────────────┘
                                     │ uses only
                     ┌───────────────▼───────────────────────────────┐
                     │          ContentSource (interface)            │
                     │  fetchPage(query) → ContentPage(items,cursor) │
                     │                                               │
                     │  Adapters:                                    │
                     │   RssSource     RedditSource   FourchanSource │
                     │   NostrSource   UsenetSource   WebSource      │
                     │   PluginSource (wraps ContentPlugin)          │
                     └───────────────┬───────────────────────────────┘
                                     │
                     ┌───────────────▼───────────────────────────────┐
                     │        FeedRefreshService (single engine)     │
                     │  schedule(source) · refresh(source)           │
                     │  emits per-source result/error stream         │
                     └───────────────┬───────────────────────────────┘
                                     │ writes
                     ┌───────────────▼───────────────────────────────┐
                     │    Knowledge store (schema:Article ONLY)      │
                     │  feedSource = subscription URI (always)       │
                     │  kabuk:feedType tag · persisted filters       │
                     └───────────────────────────────────────────────┘
```

Design rules:
- **One item model** — every source returns `FeedItem`; every item persists as
  `schema:Article`. Delete the `kabuk:NostrNote` article path for the feed (keep it only for
  DMs/social), so the feed has exactly one entity type.
- **One `feedSource` convention** — always the subscription URI (`kabuk:FeedSubscription/…`)
  or a `web:`/`nostr:` pseudo-subscription. Never a bare enum name.
- **One channel widget** — `ChannelPage` dispatches by source type to the right adapter.
  `ChannelView`/`WebChannelView` become thin wrappers or are deleted.
- **One refresh engine** — no refresh logic inside widgets; per-source results/errors surfaced.
- **Universal pagination** — every source implements `fetchPage` with a cursor; the feed
  paginates against the store, not in-memory lists.

---

## 2. Work Plan (ordered: unblock correctness first, then unify)

> **Implementation status:** every item below is **done** as of Aug 23, 2026. See the
> `Where implemented` lines for the exact code.

### Phase 1 — Stop the bleeding (bug fixes, no redesign) ✅

**P1.1 Surface refresh errors instead of swallowing** ✅
- `_fetchFeed`: collect per-feed errors into a result object `(source, newCount, error?)`.
- `refreshAllFeeds` returns `FeedRefreshSummary` (per-source) and Explore shows a dismissible
  banner listing the feeds that failed (e.g. "Couldn't refresh: r/flutter, Nostr").
- Each network fetch is bounded by a 5 s timeout.
- Where implemented: `lib/services/feed_refresh.dart` (`FeedRefreshEngine`, `FeedRefreshResult`,
  `FeedRefreshSummary`), `lib/ui/explore/explore_view.dart` (`_buildRefreshErrorBanner`).

**P1.2 Fix the "add feed → chip empty" flow** ✅
- `FeedSourcesPage._addFeed` now creates the subscription then calls
  `refreshAllFeeds(force: true, onlyUri: feedUri)` and invalidates before returning.
- Where implemented: `feed_sources_page.dart`, `explore_view.dart:refreshAllFeeds(onlyUri:)`.

**P1.3 Make filter chips fetch-on-select** ✅
- On chip tap: `selectedFeed` is set *and* that subscription is refreshed, then providers
  invalidated.
- Where implemented: `explore_view.dart` (`onSelected` in the `FilterBar`).

**P1.4 Persist content filters** ✅
- `blockedKeywords` / `hideNsfw` / `mutedSources` are mirrored to `kabuk:Preference` entities
  (`setPreference`/`getPreference`) and hydrated on Explore mount, so filters survive restarts.
- Where implemented: `explore_view.dart` (`loadPersistedFeedFilters`, `persistFeedFilters`),
  `article.dart` (`KnowledgeStorePreferenceExtension`).

**P1.5 Fix the Nostr chip** ✅
- The `'nostr:global'` filter now matches `feedSource` starting with `nostr` *or* any
  subscription URI with `feedType == 'nostr'`.
- `refreshNostrFeed` now also persists each note as a `schema:Article` with
  `feedSource = 'nostr:global'` (via the shared `nostrEventsToFeedItems`), so global Nostr
  notes actually appear in the Explore feed.
- Where implemented: `explore_view.dart:_buildFeed`, `nostr_providers.dart:refreshNostrFeed`,
  `nostr_feed_source.dart:nostrEventsToFeedItems`.

**P1.6 Stop the 8 s refresh stall** ✅
- `processNostrEvents` gained a `limit` param and `refreshNostrFeed` passes it with a 4 s
  timeout; the Nostr pass runs after the feed pass (not in parallel).
- Where implemented: `nostr_utils.dart`, `nostr_providers.dart`, `explore_view.dart:_doRefresh`.

**P1.7 Reduce Nostr noise** ✅
- `[Nostr] EVENT` is logged only when a subscription actually has a listener (was logged for
  every relay push even when dropped).
- `[Nostr] watchDMs` logs only on delivered DMs, not every gift-wrap event.
- Where implemented: `nostr_service_impl.dart`.

**P1.8 Raise the 48 h TTL** ✅
- `kUnreadArticleTtl` = 14 days (`article.dart`), namespace doc updated; prune still skips
  read (7 d) and bookmarked content.

**P1.9 Widen dedup + fix channel `feedSource`** ✅
- Dedup now uses `listArticleUrlIndex()` (all `schema:url` triples) instead of the 2000-row
  window; `ChannelView._storeAndDedup` stores a stable pseudo `feedSource`
  (`reddit:r/flutter`, `reddit:u/name`, …) and `_FollowButton` re-tags those articles onto the
  real subscription URI via `retagArticles`.
- Where implemented: `article.dart` (`listArticleUrlIndex`, `retagArticles`), `channel_view.dart`.

### Phase 2 — Introduce the unified abstraction ✅

**P2.1 `ContentSource` + `ContentPage`** ✅
- New `lib/services/content_source.dart`: `ContentQuery`, `ContentPage`, `ContentSource`,
  `FeedSourceContentSource` (cursor-aware adapter over `FeedService.fetchItemsPage`).
- `FeedService.sourceFor(FeedSourceType)` added (`feed.dart`, `feed_service_impl.dart`).

**P2.2 `PluginContentSource` adapter** ✅
- Wraps any `ContentPlugin` (channel or search capability) behind `ContentSource` with
  `contentItemToFeedItem` conversion, so plugin channels paginate like feeds.
- Where implemented: `content_source.dart`.

**P2.3 `WebContentSource`** ✅
- Re-parses a `web:` subscription's URL on refresh (cheap link discovery via `WebExtractor`,
  no LLM); stored articles remain as the snapshot fallback on failure.
- The refresh engine now handles `web` subscriptions instead of skipping them.
- Where implemented: `content_source.dart`, `feed_refresh.dart`.

**P2.4 `FeedRefreshService`** ✅
- `FeedRefreshEngine` in `lib/services/feed_refresh.dart` owns the whole refresh pipeline
  (per-source intervals, force, 5 s timeouts, URL-index dedup, web re-parse, per-source
  results/errors). `refreshAllFeeds` is now a thin wrapper; callers share one engine.

### Phase 3 — Unify the channel UI ✅ (partial retirement)

**P3.1 One `ChannelPage`** ✅
- `ChannelPage` store branch implemented (`_fetchFromStore`): articles by entity feedSource →
  by tag (`r/…`, `/…/`, `#…`) → by author, converted via `_articleToContentItem`.
- `ResolvedChannel` now carries `sourcePluginId`/`externalEntityId`/`entityType`; the four
  bundled plugins populate them; the omnibar routes plugin-backed `ResolvedChannel`s to
  `ChannelPage` (non-plugin resolutions keep `WebChannelView`).
- `ChannelView`/`WebChannelView` are **not deleted** (still used for Reddit sub/user and web
  pages); the `ChannelView` `feedSource` bug is fixed (P1.9). Full retirement remains a
  follow-up: files are no longer dead code now that `ChannelPage` is functional.

**P3.2 Unified Nostr representation** ✅
- Global notes are stored as `schema:Article` (P1.5) so the feed's sort/filter/card machinery
  handles them; `kabuk:NostrNote` remains only for the DM/social layer.

### Phase 4 — Pagination, filters-at-query, cleanup ✅

**P4.1 Paginate `articlesProvider`** ✅
- `listArticles` gained a `before` date cursor; the provider cap raised 200 → 500; `_loadMore`
  now pages non-Reddit feeds from the store (before-cursor + keyword/NSFW/muted filters) in
  addition to Reddit's network cursor pagination.
- Where implemented: `article.dart`, `explore_view.dart:_loadMore`.

**P4.2 Filters at query level** ✅
- `listArticles` now accepts `feedSources` (OR set), `keyword`, `hideNsfw`, `mutedSources`,
  and applies them post-hydration; `_loadMore` passes them directly.
- **Bug fixed en route:** the triple-store executor AND-ed clause predicates on a single row,
  so `where(type).where(feedSource)` always returned empty — this was a root cause of
  "filters don't do anything" (e.g. `listArticles(feedSource:)`/`(author:)` returned `[]`).
  Clauses are now OR-ed at row level with subject-level intersection
  (`drift_store.dart:_enforceClauseIntersection`); `listArticles` sorts by `datePublished` in
  Dart (the old SQL `orderBy` on an unrelated predicate's row was silently a no-op).

**P4.3 Cleanup + tests** ✅
- Added `test/knowledge/feed_types_test.dart` (TTL, `before` cursor pagination, OR feedSources,
  keyword/NSFW/muted filters, preferences, `retagArticles`, prune) and
  `test/services/content_source_test.dart` (`contentItemToFeedItem`, `PluginContentSource`
  channel/search modes, `buildRedditSortUrl`). **701/701 tests passing.**

### Addendum (Aug 23, 2026) — Reddit 403 + DuckDuckGo search

**Reddit 403 (`lib/platform/shared/reddit_api.dart`)**
Reddit deprecated anonymous `.json` in May 2026 (403 + TLS fingerprint / IP blocking), so a
"browser User-Agent" no longer fixes it. The Reddit feed source and the Reddit plugin now share:
- a **descriptive User-Agent** `kabuk:1.0 (by /u/kabukapp)` (Reddit blocks browser-like UAs from scripts),
- a **host fallback chain** `api.reddit.com` → `old.reddit.com` → `www.reddit.com`,
- **429 back-off** before trying the next host, and
- non-transient errors (404 etc.) stop the chain instead of wasting requests.
`fetchRedditJson()` abstracts the HTTP client so both `RedditFeedSource` and `RedditPlugin` use it.
Tests: `test/platform/shared/reddit_api_test.dart`.

**DuckDuckGo search (`lib/platform/shared/duckduckgo_source.dart`)**
New `FeedSourceType.duckduckgo` — a DDG search is a first-class, subscribable feed:
- URL formats: `ddg://search?q=<query>` (canonical), `ddg:<query>`, `duckduckgo://…`.
- Uses the official **Instant Answer API** (`api.duckduckgo.com`) for the answer box, plus the
  HTML results page (`html.duckduckgo.com/html`) for full web results (there is no free
  full-results JSON API, so the HTML page is parsed into `FeedItem`s).
- Registered in `SharedFeedService` + `detectType`; subscribable from the Feed Sources page
  and browseable in the omnibar (`ddg:query`); the omnibar search page shows a **Web** results
  section with a "Subscribe as feed" action.
Tests: `test/platform/shared/duckduckgo_source_test.dart`.

**717/717 tests passing, 0 analyzer errors.**

### Addendum (Aug 23, 2026) — MCP-style channel layer + omnibar → agent

The channel system is now an **MCP-style tool layer** that agents, the omnibar, and the feed
engine all share:

- **`lib/services/channels.dart`** — `ChannelServer` / `ChannelTool` / `ChannelCallResult` /
  `ChannelRegistry`. Mirrors MCP's `tools/list` + `tools/call`: a server exposes named tools
  with JSON-Schema args; `ChannelRegistry.invoke(server, tool, args)` is the single entry
  point. External MCP servers can later plug in as another `ChannelServer` over stdio/HTTP.
- **`lib/services/channels/web_channel_server.dart`** — the built-in `web` server with
  `web_search(query, max_results)` (DuckDuckGo) and `web_fetch(url, max_length, start_index)`
  (readable page text) — Kabuk's version of the standard `fetch` + web-search MCP combo.
- **`lib/services/channels/feed_channel_servers.dart`** — Reddit (`reddit_list`,
  `reddit_search`), Nostr (`nostr_search`, `nostr_hashtag`), RSS (`rss_fetch`), and Usenet
  (`usenet_search`) as [ChannelServer]s. All thin adapters over the shared `FeedService`, so
  agents and the omnibar can invoke every channel through the same MCP-style registry.
- **`lib/agents/domains/web_agent.dart`** — the `web` (Web & Channels) agent: `web_search`,
  `web_fetch`, `reddit_search`, `reddit_list`, `nostr_search`, `nostr_hashtag`, `usenet_search`,
  `rss_fetch` — all wrapping `ChannelRegistry.invoke(server, tool, …)`. Channel-typed results
  become a `ToolResult.channel`, so the OS draws them as a channel. The router routes web /
  channel search intents to it.
- **`lib/agents/base.dart`** — channel tool results now serialize their actual items (titles /
  URLs / snippets) into the LLM context, enabling the search-then-read loop.
- **Omnibar → agent (Gap 1)** — the omnibar is now **agent-first**: a plain-text query is a
  *prompt* (enter or the "Ask" button) that runs the Web & Channels agent directly — no more
  parallel fan-out to nostr/usenet/media/plugins/DDG on every keystroke. The agent result
  (answer + populated channel) renders at the **top** of the results; per-source searches
  only fire for their explicit prefixes (`r/`, `ddg:`, `nzb:`, `#hashtag`, `nostr:`, `media:`)
  or an active scope chip. The old auto plugin-search UI was removed (plugins come back as
  agent channel servers).

**740/740 tests passing, 0 analyzer errors.**

Next steps (remaining halves of "channels as MCP"):
1. **External MCP transport** — the stdio/HTTP JSON-RPC wire layer (`docs/MCP.md`) so Kabuk
   can connect to third-party MCP servers as additional `ChannelServer`s.
2. **Plugin channel servers** — wrap `ContentPlugin`s (YouTube, Wikipedia, …) as
   `ChannelServer`s.
3. **Feed engine + omnibar unification** — route `FeedRefreshEngine` and the omnibar's
   nostr/usenet/plugin searches through `ChannelRegistry` so feeds and channels are literally
   the same invocation.

---

## 3. Effort & Sequencing

| Phase | Focus | Est. | Unblocks |
|---|---|---|---|
| 1 | Correctness: errors surfaced, chips fetch, filters persist & work, Nostr quiet, TTL sane | 3–4 d | User-reported symptoms A/B/C |
| 2 | Unified `ContentSource` + `FeedRefreshService` + plugin/web adapters | 4–5 d | Every source paginated/refreshable |
| 3 | One `ChannelPage` for all channels; Nostr as articles | 3–4 d | Channel fragmentation F7–F11 |
| 4 | Provider-level pagination + query-level filters + cleanup + tests | 3–4 d | 200-cap, stale in-memory lists |

Suggested first PR: **P1.1 + P1.2 + P1.3** (refresh works + chips fetch + errors visible) — this
directly resolves "filters don't do anything" and "refresh doesn't work" with no architectural
risk. **P1.7** independently resolves the continuous-Nostr noise.

## 4. Risks / Notes

- Changing `feedSource` conventions touches all consumers of `articlesProvider`; keep a
  migration that re-tags existing rows (`feedSource == 'reddit'|'rss'|...` enum names → their
  subscription URIs).
- Moving refresh out of the widget requires the Riverpod provider to outlive the Explore tab;
  watch it from `shell.dart` like the DM listener.
- iOS background refresh is best-effort; keep the in-app 30 min timer as the primary
  freshness driver and surface "last refreshed" per source in the feed header.