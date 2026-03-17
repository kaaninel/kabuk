# Explore Feeds — Improvements & Gap Analysis

*Last updated: Session 5*

---

## Session 1 — Fixes Implemented

### 1 · Scheduled Background Content Refresh (in-app timer)

**Problem:** `_autoRefresh` ran exactly once per session. Content only refreshed on manual pull.

**Changes — `explore_view.dart`:**
- `WidgetsBindingObserver` mixin added to `_ExploreViewState`.
- `Timer.periodic` fires every 30 minutes calling `_silentRefresh`.
- `didChangeAppLifecycleState` on resume: triggers silent refresh if stale (> 30 min).
- `_lastRefreshedAt` stamped on each successful refresh.

---

### 2 · Scroll Restoration After Back Navigation

**Problem:** Returning from `ArticleDetailPage` left the user at random scroll position.

**Changes — `explore_view.dart`, `article_card.dart`, `article_detail_page.dart`:**
- `Map<String, GlobalKey> _itemKeys` — stable key per article URI.
- `ArticleCard.onBeforeOpen` / `onReturnFromDetail` callbacks.
- `pushArticleDetail` returns `Future<void>`.
- `_scrollToLastOpened` uses `Scrollable.ensureVisible(alignment: 0.3)`.

---

### 3 · Full-Screen Media Centering

**Fixed in `fullscreen_image_viewer.dart`:** `extendBodyBehindAppBar` removed, `Image.network` gets `width: double.infinity`, wrapped in `Center`.

**Fixed in `video_thumbnail.dart`:** Same `extendBodyBehindAppBar` fix, `SizedBox.expand` → `Center` hierarchy for video player.

---

### 4 · Subreddit & User Link Navigation

**Changes — `article_card.dart`:** `r/xxx` names in orange, tappable to QuickPeekSheet. `u/author` in blue, tappable to profile.

**Changes — `article_detail_page.dart`:** Author row tappable, tag chips tappable, `_RedditLinkText` widget for inline `r/` and `u/` links in descriptions.

---

## Session 2 — New Features Implemented

### 5 · OS-Level Background Refresh (WorkManager / BGTask)

**Problem:** In-app 30-minute timer dies when the app is fully closed.

**Implementation:**
- Added `workmanager: ^0.5.2` to `pubspec.yaml`.
- Created `lib/services/background_refresh.dart` — abstract `BackgroundRefreshService` interface with `registerPeriodicFeedRefresh()` and `cancelFeedRefresh()`.
- Created `lib/platform/shared/background_refresh_impl.dart` — `WorkmanagerRefreshService` wrapping Android WorkManager + iOS BGAppRefreshTask.
  - Top-level `@pragma('vm:entry-point') void callbackDispatcher()` for the background isolate entry.
  - Constraints: `NetworkType.connected` + `requiresBatteryNotLow: true`.
  - `ExistingWorkPolicy.replace` so interval changes take effect immediately.
- Created `lib/platform/desktop/background_refresh_impl.dart` — no-op for desktop (relies on in-app timer).
- `main.dart` calls `WorkmanagerRefreshService().registerPeriodicFeedRefresh()` on startup.
- **Note:** The background isolate currently logs intent. Full feed refresh within the isolate requires Drift to be opened with a path-based constructor (tracked in roadmap) to share the SQLite file with the foreground isolate.

---

### 6 · Reddit Comments via Public JSON (No API Key)

**Implementation — `lib/ui/explore/reddit_comments.dart` (new file):**
- `RedditComment` immutable model (id, author, body, score, createdUtc, replies, depth).
- `redditCommentsProvider` — `FutureProvider.autoDispose.family` that fetches `{post_url}.json?limit=100&raw_json=1`. No API key; uses browser User-Agent.
- Parses `json[1]` (the comment listing) recursively up to depth 3. Skips `[deleted]` / `[removed]` entries and `"more"` kind nodes.
- `RedditCommentThread` widget — shown in `ArticleDetailPage` below the Nostr section, only for Reddit URLs.
- `_CommentTile` widget — shows author, time, score (⬆), body (truncated at 10 lines), collapsible replies (up to 5 nested).

**Integration — `article_detail_page.dart`:**
```dart
if (article.url != null && article.url!.contains('reddit.com'))
  RedditCommentThread(postUrl: article.url!),
```

**Privacy note:** Comments are fetched from Reddit's public JSON endpoint. No login, no cookies. The request goes directly from the device to `www.reddit.com`.

---

### 7 · Markdown / Selftext Rendering

**Problem:** Reddit text posts displayed nothing meaningful — the description only contained the upvote/comment count metadata string.

**Implementation — `article_detail_page.dart`:**
- `_hasMarkdown(String)` — detects markdown presence via signature patterns (`**`, `##`, `- `, `> `, `` ` ``, `[text](url)`, or double newline for paragraphs).
- `_stripStatsLine(String)` — removes the trailing `⬆ xxx · 💬 xxx` stats suffix before rendering.
- Description section now conditionally renders `MarkdownBody` (from `flutter_markdown`, already in pubspec) when markdown is detected.
- `MarkdownStyleSheet` matches `KabukTheme` colors: dark code blocks, italic blockquotes with left border, link color `KabukTheme.blueAccent`.
- Falls back to existing `_RedditLinkText` for non-markdown content (preserves `r/` and `u/` tap links).

---

### 8 · Feed Sort Toggle (Newest / Hot / Top)

**Implementation — `explore_view.dart`:**
- `FeedSort` enum: `newest`, `hot`, `top`.
- `feedSortProvider = StateProvider<FeedSort>((ref) => FeedSort.newest)`.
- `_buildSortBar` renders three compact chip buttons above the feed list.
- `_sortArticles` applies client-side sort:
  - `newest` → sort by `datePublished` descending (unchanged default).
  - `hot` → sort by `upvotes + (comments × 2)` — engagement score parsed from description `⬆` / `💬` metadata.
  - `top` → sort by raw upvote count descending.
- Parsed from the description field (no new network requests needed).

**Note:** This is a client-side sort of already-fetched articles. True Reddit "Hot" would require fetching from `/hot.json`, but that would change the stored subscription content. A future enhancement could add a per-subscription sort mode that modifies the fetch URL.

---

### 9 · Save / Bookmark Action

**Implementation — `article_card.dart` (`_ActionBar`):**
- Bookmark icon button (`Icons.bookmark_add_outlined`) added to the action bar.
- Tapping calls `store.createBookmark(name, url, description)` using the existing `KnowledgeStoreBookmarkExtension`.
- Shows a snack bar: "Saved to bookmarks".
- Bookmarks are stored as `kabuk:Bookmark` entities in the knowledge store (`schema:name`, `schema:url`, `schema:description`, `schema:dateCreated`).

---

### 10 · GIF / Animated Image Support

**Implementation — `article_card.dart`:**
- `_isGif(ArticleData)` detects `.gif` image URLs.
- `_isVideoContent` extended to include `.gifv` (Reddit's mp4-in-gifv wrapper — treated as video via `VideoThumbnail`).
- For `.gif` thumbnails: renders `Image.network` directly (Flutter's image codec animates GIFs natively at the frame level — no extra package needed).
- `_MediaBadge` widget shows a "GIF" overlay label in the bottom-right corner.

---

### 11 · Skeleton Loading Screens

**Problem:** Feed showed a `CircularProgressIndicator` while articles loaded.

**Implementation — `explore_view.dart`:**
- `_FeedSkeleton` stateful widget with `AnimationController` (1200 ms repeat reverse).
- `_SkeletonCard` renders a shimmer-pulsing version of the `ArticleCard` layout: source header row, two title lines, image placeholder, action bar.
- Shimmer uses `Color.lerp` between `cardColor` and `divider` driven by the animation.
- Replaced `loading: () => const Center(child: CircularProgressIndicator())` with `loading: () => const _FeedSkeleton()`.

---

### 12 · Feed List Simplification

Replaced `SliverAnimatedList` with `SliverList` + a sort bar header item. The `SliverAnimatedList` approach required managing `GlobalKey<SliverAnimatedListState>` and complex insert-animation bookkeeping that conflicted with the new sort feature (sort reorders the entire list, making item-level animation impractical). The new approach is simpler, more predictable, and makes sort changes instant.

---

## Current Gap Analysis

### Resolved ✅

| Item | Status |
|------|--------|
| No in-app timer-based refresh | ✅ 30-min timer + lifecycle observer (Session 1) |
| No OS-level background refresh | ✅ WorkManager / BGTask registered (Session 2) |
| Scroll restoration after back nav | ✅ `GlobalKey` + `ensureVisible` (Session 1) |
| Full-screen image/video centering | ✅ Fixed (Session 1) |
| Subreddit/user link navigation | ✅ Tappable `r/` and `u/` everywhere (Session 1) |
| No Reddit comment thread | ✅ Public JSON comments, no API key (Session 2) |
| No selftext/Markdown rendering | ✅ `flutter_markdown` conditional rendering (Session 2) |
| No feed sort toggle | ✅ Newest / Hot / Top client-side sort (Session 2) |
| No save/bookmark action | ✅ Bookmark icon → knowledge store (Session 2) |
| No GIF support | ✅ `.gif` native + `.gifv` as video (Session 2) |
| Spinner loading screen | ✅ Shimmer skeleton cards (Session 2) |
| **No multi-image gallery** | ✅ `_GalleryCarousel` `PageView` + `media_metadata` parsing (Session 3) |
| **Client-side sort only** | ✅ Server-side Reddit sort via `_buildRedditSortUrl` + `redditSort` param (Session 3) |
| **No per-feed refresh intervals** | ✅ `FeedSubscriptionData.refreshInterval` enforced in `_fetchFeed` (Session 3) |
| **No YouTube in-app player** | ✅ `_YoutubePlayerPage` using `webview_flutter` embed iframe (Session 3) |
| **Image pre-fetching** | ✅ `precacheImage` for next 2 items in `_buildItemCard` (Session 3) |
| **Stale `_newArticlesProvider`** | ✅ Removed (was populated but never consumed after `SliverList` migration) (Session 3) |
| **No media cache with TTL control** | ✅ `KabukCacheManager` (7-day TTL, 500-object max, LRU eviction) replacing `DefaultCacheManager` (Session 4) |
| **`Image.network` calls bypass cache** | ✅ GIF + gallery carousel replaced with `CachedNetworkImage` + `KabukCacheManager` (Session 4) |
| **No article expiry / prune** | ✅ `kabuk:expiresAt` stamped on create; `pruneStaleArticles()` on startup and after every refresh (Session 4) |
| **No connectivity awareness** | ✅ `connectivityProvider` stream; offline banner; skip pre-fetch on non-WiFi; skip network when offline (Session 4) |
| **Image pre-fetch wastes mobile data** | ✅ Pre-fetch gated on `onWifi()` check; uses `KabukCacheManager.downloadFile` (Session 4) |

### Remaining Gaps — High Priority

| Gap | Impact | Notes |
|-----|--------|-------|
| **Background isolate feed refresh is stub** | Medium | `callbackDispatcher` logs intent but doesn't actually refresh feeds. Blocked on Drift path-based open API to share SQLite across isolates. OS task schedule is registered and maintained correctly. |
| **No push notifications for new posts** | High | Local notification when background refresh finds new articles. Needs `flutter_local_notifications` integration in the background callback. |
| **No incremental pagination ("load more")** | Medium | Feed cap at 200 articles; no way to fetch older posts. Needs `after` / `before` cursor params in `RedditFeedSource.fetch` and a "Load more" trigger at the bottom of the list. |

### Remaining Gaps — Medium Priority

| Gap | Impact | Notes |
|-----|--------|-------|
| **No user follow graph** | High | User profiles open in QuickPeekSheet but no follow/mute action is wired. |
| **Dark mode for QuickPeekSheet** | Low | WebView does not inject `prefers-color-scheme`. YouTube embed player and subreddit pages appear in light mode. |
| **No swipe-to-dismiss / mark-read gesture** | Low | Common in Reddit/news apps. |
| **Knowledge store comment model** | Medium | `schema:Comment` with parent/child triples needed to persist Reddit/Nostr comments for offline reading. |

### Architecture Constraints

| Item | Notes |
|------|-------|
| **No Reddit OAuth2** | Read-only. Voting, native commenting, saved posts require PKCE OAuth2. Deliberately avoided to stay API-key-free. |
| **CDN image proxy absent** | Images load directly from origin — CORS on some RSS sources, device IP leak. |
| **Drift multi-isolate DB access** | Background isolate can't open the same Drift database as the foreground until a path-based constructor is added to `DriftKnowledgeStore`. This blocks full background feed refresh. |
| **YouTube embed restriction** | `_YoutubePlayerPage` uses the YouTube embed iframe. Some videos may have embed disabled by the uploader; those fall back to the external browser. |

---

## Architecture Overview (Session 4)

```
Explore UI
├── explore_view.dart         ← Feed list, sort bar, skeleton, refresh, interval check
│                                connectivityProvider watch → offline banner
│                                _doRefresh: skip network when offline, prune after refresh
│                                _buildItemCard: pre-fetch only on WiFi via onWifi()
├── article_card.dart         ← Feed card: GIF (CachedNetworkImage), bookmark, gallery carousel
│                                _GalleryCarousel now uses CachedNetworkImage + KabukCacheManager
├── article_detail_page.dart  ← Detail: Markdown selftext, Nostr + Reddit comments
├── reddit_comments.dart      ← Reddit public JSON comment fetcher + renderer
├── filter_bar.dart           ← Feed chip filter (no change)
└── nostr_providers.dart      ← Nostr social layer (no change)

Shared Widgets
├── lib/ui/shared/feed_image.dart       ← CachedNetworkImage with KabukCacheManager.instance
└── lib/ui/shared/video_thumbnail.dart  ← extractYoutubeVideoId, _YoutubePlayerPage (WebView embed)

Knowledge Layer
├── lib/knowledge/types/article.dart    ← ArticleData.expiresAt; markArticleRead extends expiry;
│                                          pruneStaleArticles(); createArticle stamps kabuk:expiresAt
├── lib/config/namespaces.dart          ← kabuk:expiresAt, kabuk:lastViewedAt predicates added
└── lib/services/feed.dart              ← FeedItem.galleryImages field

Platform Layer
└── lib/platform/shared/reddit_source.dart  ← media_metadata + gallery_data parsing

Services
├── lib/services/media_cache.dart              ← KabukCacheManager (7-day TTL, 500 objects)
│                                                  connectivityProvider StreamProvider
│                                                  hasNetwork() / onWifi() helpers
├── lib/services/background_refresh.dart       ← Abstract interface
├── lib/platform/shared/background_refresh_impl.dart ← WorkManager impl (stub refresh body)
└── lib/platform/desktop/background_refresh_impl.dart ← No-op desktop

App startup (lib/main.dart)
└── pruneStaleArticles() called on cold start (image cache eviction is automatic via stalePeriod)
```

---

## Session 4 — New Features Implemented

### 19 · Project-Scoped Image Cache (`KabukCacheManager`)

**Problem:** `FeedImage` used Flutter's `DefaultCacheManager` (30-day TTL, 200-object max) — too permissive, no project control. GIF images and the `_GalleryCarousel` used bare `Image.network`, bypassing `cached_network_image` entirely and leaving those images unavailable offline.

**Changes — `lib/services/media_cache.dart` (new file):**
- `KabukCacheManager` singleton extends `CacheManager with ImageCacheManager`.
- `Config`: key `kabuk_media_v1`, `stalePeriod: 7 days`, `maxNrOfCacheObjects: 500`.
- Oldest images auto-evicted by LRU when the 500-object ceiling is reached.
- `flutter_cache_manager: ^3.4.1` added as a direct `pubspec.yaml` dependency.

**Changes — `lib/ui/shared/feed_image.dart`:**
- `CachedNetworkImage` now passes `cacheManager: KabukCacheManager.instance`.

**Changes — `lib/ui/explore/article_card.dart`:**
- GIF image block: replaced `Image.network` with `CachedNetworkImage(..., cacheManager: KabukCacheManager.instance)`.
- `_GalleryCarousel.PageView.builder`: replaced `Image.network` with `CachedNetworkImage(..., cacheManager: KabukCacheManager.instance)`.
- All three image paths (regular, GIF, gallery) now share one cache with identical offline behaviour.

---

### 20 · Article Expiry & Automatic Pruning

**Problem:** The knowledge store accumulated articles indefinitely. Old, unread posts were never cleaned up, growing SQLite storage and slowing queries over time.

**Expiry rules:**
- **Unread articles:** expire 48 hours after `schema:datePublished`.
- **Read articles:** on `markArticleRead()`, expiry is extended to 7 days from the moment the user opens the post.
- **Bookmarked articles:** excluded from pruning entirely — bookmarks are permanent.

**Changes — `lib/config/namespaces.dart`:**
- Added `kabuk:expiresAt` — ISO-8601 timestamp after which the article should be pruned.
- Added `kabuk:lastViewedAt` — timestamp of the last user view.

**Changes — `lib/knowledge/types/article.dart`:**
- `ArticleData` gains `expiresAt: DateTime?` field, parsed from `kabuk:expiresAt` in `fromTriples`.
- `createArticle()` stamps `kabuk:expiresAt = datePublished + 48h` for every new article.
- `markArticleRead()` extended: sets `kabuk:read = true`, writes `kabuk:lastViewedAt = now`, extends `kabuk:expiresAt = now + 7d`.
- New `pruneStaleArticles()` extension: queries all articles, skips bookmarked and read ones, deletes those whose `expiresAt` is in the past. Returns the count of deleted articles.

**Changes — `lib/main.dart`:**
- `container.read(knowledgeStoreProvider).pruneStaleArticles().ignore()` called on every cold start after agents are registered.

---

### 21 · Connectivity Awareness

**Problem:** The app made network requests even when offline (generating silent failures). Image pre-fetching ran unconditionally, consuming mobile data for speculative fetches the user never asked for.

**Changes — `lib/services/media_cache.dart`:**
- `connectivityProvider = StreamProvider<List<ConnectivityResult>>` — streams OS connectivity changes via `connectivity_plus`.
- `hasNetwork(List<ConnectivityResult>) → bool` — true when any non-`none` result is present.
- `onWifi(List<ConnectivityResult>) → bool` — true when `wifi` is in the result list.

**Changes — `lib/ui/explore/explore_view.dart`:**
- `build()` watches `connectivityProvider`; derives `isOffline` and `isWifiConn`.
- **Offline banner:** `_OfflineBanner` widget (compact bar: "Offline — showing cached content") inserted as the first sliver in both the empty-feed and article-feed `CustomScrollView` when `isOffline`.
- **`_doRefresh`:** calls `Connectivity().checkConnectivity()` first. Skips `refreshAllFeeds` and `refreshNostrFeed` when offline. Always runs `pruneStaleArticles()` regardless of connectivity.
- **`_buildItemCard` pre-fetch:** replaced unconditional `precacheImage(NetworkImage(...))` with `KabukCacheManager.instance.downloadFile(img)` gated on `onWifi(connectivity)`. Mobile and offline users are no longer charged for speculative pre-fetching.

---

## Fixes Implemented in This Session

### 1 · Scheduled Background Content Refresh

**Problem:** `_autoRefresh` ran exactly once per session (guarded by a `_didAutoRefresh` boolean). After that, content only refreshed on manual pull-to-refresh. Feeds could sit stale for an entire day.

**Changes — `explore_view.dart`:**
- `_ExploreViewState` now mixes in `WidgetsBindingObserver`.
- A `Timer.periodic` fires every **30 minutes** while the view is alive, calling a new `_silentRefresh` that runs in the background without showing a spinner.
- `didChangeAppLifecycleState` detects `AppLifecycleState.resumed`. If more than 30 minutes have elapsed since the last successful refresh, a silent refresh is triggered immediately.
- `_lastRefreshedAt` is stamped inside `_doRefresh` on success.
- The 30-minute interval is consistent with the existing `trendingTopicsProvider` cache bust.

---

### 2 · Scroll Restoration After Back Navigation

**Problem:** Returning from `ArticleDetailPage` left the user at whatever scroll position the `RefreshIndicator` + `SliverAnimatedList` happened to be at — usually far from the post they had just read.

**Changes — `explore_view.dart`, `article_card.dart`, `article_detail_page.dart`:**
- `_ExploreViewState` maintains a `Map<String, GlobalKey> _itemKeys` — one stable key per article URI, assigned to the `Padding` wrapper of each card.
- `ArticleCard` receives two new optional callbacks:
  - `onBeforeOpen()` — called just before `pushArticleDetail`. The parent saves the opened article's URI.
  - `onReturnFromDetail()` — called when the nav pop future completes.
- `pushArticleDetail` now returns `Future<void>` (previously `void`) so the `.then` wires correctly.
- `_scrollToLastOpened` calls `Scrollable.ensureVisible` with `alignment: 0.3` (card appears 30 % from top, giving context of surrounding posts).

---

### 3 · Full-Screen Media Centering

**Problem (image viewer):** `InteractiveViewer` rendered its `Image.network` child at natural pixel size because no bounding `Center` or `width` constraint was provided. On wide images or after hero transitions this caused off-center placement.

**Problem (video player):** `_InlineVideoPlayer` used `extendBodyBehindAppBar: true`. With `extendBodyBehindAppBar: true` the `Scaffold.body` fills the full screen height (top-0 to bottom). A `Center` inside thus centres relative to the *full* screen, ~28 px too high when the app bar is visible. On smaller phones this offset is noticeable.

**Changes — `fullscreen_image_viewer.dart`:**
- `extendBodyBehindAppBar` removed (now false).
- `Image.network` gets `width: double.infinity` so `BoxFit.contain` has finite bounds to work against.
- `InteractiveViewer.child` wrapped in `Center(...)` — ensures the image is always visually centered inside the viewport regardless of image aspect ratio.
- `Scaffold.body` wrapped in `SizedBox.expand` for explicit full-size bounds.

**Changes — `video_thumbnail.dart` (`_InlineVideoPlayer`):**
- `extendBodyBehindAppBar` removed.
- `flutter/services.dart` imported for `SystemUiOverlayStyle`.
- `AppBar` sets `SystemUiOverlayStyle` so the status bar icons stay light on the black background.
- `Scaffold.body` uses `SizedBox.expand` → `Center` hierarchy so the `AspectRatio` + `VideoPlayer` is always centred in the available (non-app-bar) screen area.

---

### 4 · Subreddit & User Link Navigation

**Problem:** `r/subreddit` names in feed cards were plain unformatted text. Author fields showed raw usernames. Inline `r/xxx` and `u/xxx` references in post descriptions were not interactive. There was no way to "follow a thread" from a post to its subreddit or author.

**Changes — `article_card.dart` (`_SourceHeader`):**
- `_sourceName` renamed `_subredditName`.
- When the source is Reddit and the name starts with `r/`, the text is rendered in Reddit orange and wrapped in `GestureDetector` → `_openSubreddit` → `QuickPeekSheet`.
- Author line now shows `u/$author` for Reddit sources in `KabukTheme.blueAccent` and taps open `_openUserProfile` → `QuickPeekSheet` → `https://reddit.com/u/$name`.

**Changes — `article_detail_page.dart` (`_ArticleDetailContent`):**
- Author row: for Reddit articles the author is rendered in blue with the `u/` prefix; tapping calls `_openUserProfile`.
- Tags row: `r/xxx` tags rendered in Reddit orange with a light border; tapping opens the subreddit in the QuickPeekSheet.
- Description: replaced plain `Text` with the new `_RedditLinkText` widget.

**New widget `_RedditLinkText`:**
- Regex `/?([ru])/(\w+)` scans plain-text descriptions for inline subreddit and user references.
- Each match is rendered as a tappable `WidgetSpan` (orange for `r/`, blue for `u/`) with the surrounding text as normal `TextSpan`s.
- Callbacks `onSubredditTap` and `onUserTap` are forwarded to `QuickPeekSheet`.

---

## Gap Analysis vs Reddit / Instagram

> **Session 3 additions are listed immediately below.** See the Resolved table for the complete list.

---

## Session 3 — New Features Implemented

### 13 · Multi-Image Gallery (Reddit Gallery Posts)

**Problem:** Reddit gallery posts (`https://reddit.com/gallery/xxx`) have multiple images but only the first was shown.

**Changes — `lib/platform/shared/reddit_source.dart`:**
- `_parsePost` now reads `is_gallery`, `gallery_data.items` (ordered list of `media_id`s), and `media_metadata` (dict of `media_id → {s: {u, gif}}`).
- Iterates through the ordered items list and builds `galleryImages` (`List<String>`) from high-res source URLs, HTML-entity-decoded.
- Falls back to the first gallery image as `imageUrl` when no preview URL was found.

**Changes — `lib/services/feed.dart`:**
- Added `galleryImages: List<String>` field to `FeedItem` (defaults to `const []`).

**Changes — `lib/config/namespaces.dart`:**
- Added `kabuk:galleryImages` predicate constant.

**Changes — `lib/knowledge/types/article.dart`:**
- `ArticleData` gains a `galleryImages: List<String>` field.
- `ArticleData.fromTriples` reads the `kabuk:galleryImages` predicate and JSON-decodes the list.
- `createArticle` gains a `galleryImages` param, JSON-encodes non-empty lists into the `kabuk:galleryImages` triple.
- `_parseGalleryImages` static helper added.
- Added `dart:convert` import.

**Changes — `lib/ui/explore/explore_view.dart`:**
- `_fetchFeed` passes `galleryImages: item.galleryImages` to both `store.createArticle` and the in-memory `ArticleData` constructor.

**Changes — `lib/ui/explore/article_card.dart`:**
- Checks `article.galleryImages.length > 1` before showing the regular image widget.
- New `_GalleryCarousel` stateful widget: `PageView.builder` at height 220, `onPageChanged` updates `_current`, page counter pill (`current / total`) bottom-right, animated dot indicators at the bottom for ≤ 10 images.

---

### 14 · Server-Side Sort for Reddit Feeds

**Problem:** `RedditFeedSource._toJsonUrl` always fetched `/hot.json` regardless of the sort selection in the UI.

**Changes — `lib/ui/explore/explore_view.dart`:**
- New top-level `_buildRedditSortUrl(String baseUrl, String sort)` function: strips any existing `/XXX.json[?...]` suffix and replaces with `/$sort.json?limit=50&raw_json=1`.
- `refreshAllFeeds` reads the current `feedSortProvider` and maps it to the Reddit sort string (`new` / `hot` / `top`).
- `_fetchFeed` gains a `redditSort` named parameter and calls `_buildRedditSortUrl` when `sourceType == FeedSourceType.reddit`.
- When users pull-to-refresh while the "New" sort chip is selected, the next fetch uses Reddit's `/new.json` endpoint.

---

### 15 · Per-Feed Refresh Interval Enforcement

**Problem:** `FeedSubscriptionData.refreshInterval` was modeled and stored in the knowledge store but `_fetchFeed` never checked it — every sync fetched every feed regardless of age.

**Changes — `lib/ui/explore/explore_view.dart`:**
- At the top of `_fetchFeed`: if `sub.lastFetched != null` and the age is less than `sub.refreshInterval` minutes, return immediately with an empty list.
- This prevents redundant network requests on the silent 30-minute timer and when the user rapidly triggers multiple refreshes.
- The background task (`_BackgroundFeedRefresher`) will benefit from this check automatically once full isolate wiring is complete.

---

### 16 · YouTube In-App Player

**Problem:** YouTube links opened in the device's external browser, breaking the immersive reading flow.

**Approach:** Uses `webview_flutter` (already in `pubspec.yaml`) to render the YouTube embed iframe in a full-screen `Scaffold`. No new package dependency.

**Changes — `lib/ui/shared/video_thumbnail.dart`:**
- Added `import 'package:webview_flutter/webview_flutter.dart'`.
- New top-level `extractYoutubeVideoId(String url) → String?` function handling:
  - `youtube.com/watch?v=ID`
  - `youtu.be/ID`
  - `youtube.com/shorts/ID`
  - `m.youtube.com/watch?v=ID`
- `VideoThumbnail._openVideo` now checks `extractYoutubeVideoId` before falling back to the external browser. If a video ID is found, navigates to `_YoutubePlayerPage`.
- New `_YoutubePlayerPage` stateful widget: initialises a `WebViewController` with the embed URL (`https://www.youtube.com/embed/{id}?autoplay=1&rel=0&modestbranding=1&playsinline=1`) and renders it with `WebViewWidget` on a black background.
- Videos with embed disabled by the uploader still fall back to the external browser via the existing `launchUrl` path.

---

### 17 · Image Pre-Fetching

**Problem:** Scrolling through an image-heavy feed caused visible load-flicker as each image appeared for the first time.

**Changes — `lib/ui/explore/explore_view.dart`:**
- In `_buildItemCard`, before building the card widget: calls `precacheImage(NetworkImage(img), context)` for the next 2 items in `_displayedArticles` whose `image` URL starts with `http`.
- This piggybacks on Flutter's image cache — by the time the user scrolls to item `n+2`, its image is already decoded in memory.

---

### 18 · _newArticlesProvider Removal

**Problem:** `_newArticlesProvider` was populated on every refresh (accumulating new items) but its value was never read by any widget after `SliverAnimatedList` was replaced with a plain `SliverList` in Session 2.

**Changes — `lib/ui/explore/explore_view.dart`:**
- Removed `_newArticlesProvider` `StateProvider` declaration.
- Removed the sort-and-accumulate block from `refreshAllFeeds` (9 lines).
- `refreshAllFeeds` now returns `results.expand((list) => list).length` directly.
- Simplified the doc comment.

---

The features implemented bring the Explore view meaningfully closer to a full feed reader, but significant gaps remain before it can serve as a complete Reddit/Instagram replacement.

### Content Freshness & Delivery

| Gap | Impact |
|-----|--------|
| **RSS-only Reddit access** — reads Reddit's JSON feed endpoint, not the Reddit API. Maximum one post per page (25 items), no way to request Hot / Rising / Top sort. | High — the content the user sees is always "New", never curated by engagement. |
| **No push notifications** — new posts from followed subreddits are only discovered on the next timer tick or manual pull. | High — social apps rely on push to drive re-engagement. |
| **No per-feed configurable refresh interval** — all feeds share the 30-minute timer. High-frequency subreddits (r/news) are over-refreshed; slow blogs are unnecessarily polled. | Medium — wasted battery/network on some feeds. |
| **No incremental pagination** — the feed loads 200 articles on boot and discards older ones with no "load more". Long-term users will hit the ceiling. | Medium — UX degrades as the knowledge store grows. |
| **Feed deduplication is URL-based** — cross-posts and re-posts with the same URL are suppressed even when they are distinct Reddit posts. | Low–Medium |

### Content Richness

| Gap | Impact |
|-----|--------|
| **No Reddit selftext / body rendering** — post descriptions come from the RSS `<description>` field which is often just an upvote/comment count string. Self-posts (text posts) have no body displayed. | **Critical** — a large fraction of Reddit content is text posts. |
| **No comment thread** — social layer shows only Nostr comments, not Reddit's own comment tree. | **Critical** — comments are why most users open Reddit. |
| **No multi-image gallery** — posts with multiple images (Reddit galleries, Instagram carousels) show only the first image. | High — gallery posts are a primary format on both platforms. |
| **No GIF / animated image support** — `.gif` and `.gifv` URLs are not detected or played. | High — GIFs are endemic to Reddit. |
| **YouTube plays in external browser** — no in-app YouTube player or thumbnail preview for youtube.com links. | High — significant friction vs. native YouTube embeds. |
| **No polls** — Reddit and Instagram poll formats are not parsed or rendered. | Medium |
| **No post flair / link flair** — flair metadata is present in the RSS but not surfaced or filterable. | Medium |
| **No award / trophy display** — awards are metadata Reddit readers expect to see. | Low |
| **No crosspost chain** — crossposted articles show the destination post without indicating the source. | Low |

### Ranking & Discovery

| Gap | Impact |
|-----|--------|
| **Purely chronological feed** — no Hot / Best / Top / Rising sort. Reddit's "best" algorithm is the primary driver of content quality; the app shows raw "new". | **Critical** — chronological Reddit feeds are unusable for popular subreddits. |
| **No algorithmic ranking / personalisation** — no engagement signals (scroll depth, reaction rate, read time) are used to rank or weight content. | High — Instagram-style feeds rely entirely on ranking. |
| **Discovery is Nostr-only** — the Explore discovery section shows Nostr trending hashtags, not Reddit trending topics or cross-platform trending. | High |
| **No search with filters** — text search exists but has no time range, subreddit scope, media-type, or flair filter. | Medium |
| **No "similar posts" / "you might like"** — no recommendation engine beyond manual subscriptions. | Medium |

### Interaction Model

| Gap | Impact |
|-----|--------|
| **No Reddit authentication** — the app is read-only. Upvotes, downvotes, and native Reddit comments require OAuth2. | **Critical** for any Reddit replacement. |
| **No upvote / downvote** — Nostr reactions are shown but Reddit vote scores still read from the (often empty) RSS description field. | High |
| **No save / bookmark** — there is no "save post" or "read later" action visible in the feed card or detail page. | High |
| **No user follow graph** — the app can browse a user profile via QuickPeekSheet but cannot follow that user and surface their posts in the feed. | High |
| **No in-app DMs / chat** — no equivalent to Reddit DMs or Instagram Direct. | Medium |
| **No cross-post / share within app** — "share" only opens the system sheet; no internal repost to a subscribed feed or Nostr. | Medium |
| **No read-later / offline queue** — articles open in a WebView but are not cached for offline reading. | Medium |
| **No multireddit / feed collections** — subreddits are subscribed to individually; there is no way to group them into a named multi-feed (e.g. "Tech" = r/programming + r/tech + r/science). | Medium |

### UX Polish

| Gap | Impact |
|-----|--------|
| **No Stories / Reels / vertical video** — ephemeral and vertical-video formats pioneered by Instagram and adopted by Reddit are absent. | High — younger audiences expect this format. |
| **No haptic feedback on interactions** — likes, reposts, and navigation lack haptics. | Low–Medium |
| **No skeleton loading screens** — feed shows a `CircularProgressIndicator` while articles load instead of skeleton placeholders matching card sizes. | Low–Medium — polish gap vs Instagram. |
| **Images are loaded lazily but not pre-cached** — scrolling through image-heavy feeds can produce noticeable load flicker. | Low–Medium |
| **No swipe-to-dismiss / mark-read gesture** — Reddit and news apps commonly let users swipe cards left/right to mark read or bookmark. | Low |
| **No compact / card view toggle** — feed only supports the card layout; Reddit users expect list, compact, and card modes. | Low |
| **No dark/light mode for QuickPeekSheet WebView** — the in-app browser does not inject `prefers-color-scheme` matching the app theme. | Low |

### Architecture Gaps Blocking Feature Parity

| Gap | Notes |
|-----|-------|
| **Reddit API integration not implemented** — `FeedAgent` uses Reddit's RSS feeds which are public but limited (plain JSON, no auth, no sort, no vote data). A full Reddit experience requires official API keys + OAuth2 PKCE. | Foundational blocker for comments, voting, and "Hot" feeds. |
| **No media transcoding / HLS support** — `v.redd.it` DASH streams require HLS parsing that `video_player` can handle (`m3u8`) but the URL resolution from Reddit's API (not RSS) is needed first. | Needed for in-app video. |
| **Knowledge store does not model comment trees** — `schema:Article` stores top-level posts only. A `schema:Comment` with parent/child triples needs to be added before native comment threads can be rendered. | Structural prerequisite. |
| **No CDN image proxy** — images are loaded directly from origin which causes CORS failures on some RSS sources and is a privacy leak (origin sees the user's IP). | Privacy & reliability gap. |

---

## Prioritised Next Steps

1. **Reddit OAuth2 + official API** — unblocks Hot/Best feeds, upvoting, native comments, and NSFW filtering in one go.
2. **`schema:Comment` model + Reddit comment tree renderer** — the single biggest content gap.
3. **Background isolate full wiring** — open a path-based `DriftKnowledgeStore` in the WorkManager callback so the background task actually refreshes feeds and emits local notifications.
4. **Push notifications on new articles** — `flutter_local_notifications` in the background callback; badge count on the Explore tab.
5. **Incremental pagination ("load more")** — `after`/`before` cursors in `RedditFeedSource.fetch`; "Load more" trigger sliver at feed bottom.
6. **User follow graph** — follow action in `QuickPeekSheet`; store as `schema:FollowAction` triples; surface followed-user posts in Explore.
7. **Multireddit / feed groups** — group subscriptions behind a new `schema:DataFeedMulti` entity type.
8. **Knowledge store comment model** — `schema:Comment` with parent/child triples needed for offline comment reading.
9. **CDN image proxy** — route image requests through an on-device or self-hosted proxy to prevent origin IP leak and handle CORS failures on some RSS sources.
10. **Swipe-to-dismiss / mark-read gesture** — swipe left → mark read (extends expiry to 7 days); swipe right → bookmark.

---

## Session 5 — Remaining Gaps Closed

Items 3–10 from the prioritised next-steps list above were implemented. Reddit OAuth2 (item 1) and the comment tree renderer (item 2) remain blocked on the official API.

---

### 19 · Swipe-to-Dismiss / Mark-Read Gesture

**Gap addressed:** "No swipe-to-dismiss / mark-read gesture" (UX Polish table).

**Changes — `lib/ui/explore/article_card.dart`:**
- `ArticleCard.build()` now returns a `Dismissible` wrapping the existing `GestureDetector`.
- `startToEnd` (swipe right): green background + bookmark icon → calls `store.createBookmark()` then shows snackbar "Saved to bookmarks".
- `endToStart` (swipe left): orange background + check icon → calls `store.markArticleRead(article.uri)` then shows snackbar "Marked as read".
- `confirmDismiss` always returns `false` — the card stays in the list; the gesture is a non-destructive side-effect action.

---

### 20 · Incremental Pagination with Reddit Cursor

**Gap addressed:** "No incremental pagination" (Content Freshness table).

**Changes — `lib/platform/shared/reddit_source.dart`:**
- **Bug fix:** `_toJsonUrl` changed `endsWith('.json')` → `contains('.json')` so sort URLs with query parameters are not double-transformed.
- New `fetchPage(url, {String? afterCursor})` method: appends `&after={cursor}` when cursor is supplied; extracts `data['after']` from the Reddit JSON response and returns `({List<FeedItem> items, String? nextCursor})`.
- `fetch(url)` is now a thin wrapper over `fetchPage`.

**Changes — `lib/services/feed.dart`:**
- Added `fetchItemsPage(url, {FeedSourceType? type, String? cursor})` returning `({List<FeedItem> items, String? nextCursor})` to the `FeedService` interface.

**Changes — `lib/platform/shared/feed_service_impl.dart`:**
- Implemented `fetchItemsPage` — casts the resolved source to `RedditFeedSource` for cursor support; non-Reddit sources get `nextCursor: null`.

**Changes — `lib/ui/explore/explore_view.dart`:**
- New state: `Map<String, String?> _afterTokens`, `bool _isLoadingMore`.
- `initState` adds `_onScroll` listener to `_scrollController`.
- `_onScroll` triggers `_loadMore()` when the scroll position is within 400 px of the bottom.
- `_loadMore()` fetches current subreddits with stored cursor, persists new articles, updates `_afterTokens`.
- `SliverToBoxAdapter` load-more spinner (`CircularProgressIndicator`, color `KabukTheme.accentGreen`) appended at the bottom of the feed sliver.

---

### 21 · Dark Mode WebView CSS Injection

**Gap addressed:** "No dark/light mode for QuickPeekSheet WebView" (UX Polish table).

**Changes — `lib/ui/explore/quick_peek_sheet.dart`:**
- In `onPageFinished`, `_controller.runJavaScript(...)` injects an IIFE that:
  1. Creates or updates `<meta name="color-scheme" content="dark">`.
  2. Inserts `<style id="__kabuk_dark">` with `:root { color-scheme: dark; }` if not already present.
  - Both wrapped in try/catch to silently handle pages that block script execution.

---

### 22 · Background Isolate Full Wiring

**Gap addressed:** "Background isolate full wiring" (Next Steps list, formerly a stub).

**Changes — `lib/platform/shared/background_refresh_impl.dart`:**
- Completely replaced the no-op `_BackgroundFeedRefresher` stub with a fully functional `_runFeedRefresh()`:
  1. Opens Drift DB: `KabukDatabase(driftDatabase(name: 'kabuk_default'))`.
  2. Constructs `DriftKnowledgeStore`, `SharedMeshService`, `SharedFeedService`.
  3. Lists all feed subscriptions; skips any whose `refreshInterval` has not elapsed.
  4. Fetches new articles per subscription, deduplicates via existing URIs, persists via `store.createArticle()`.
  5. Updates `lastFetched` per subscription.
  6. Counts newly-persisted articles and triggers push notification if `count > 0`.
  7. Closes DB in a `finally` block.

---

### 23 · Push Notifications for New Articles

**Gap addressed:** "No push notifications" (Content Freshness table).

**Changes — `lib/platform/shared/background_refresh_impl.dart`:**
- New `_showNewArticlesNotification(int count)` helper:
  - Instantiates `FlutterLocalNotificationsPlugin` directly (no Riverpod — isolate context).
  - Android init: `AndroidInitializationSettings('@mipmap/ic_launcher')`.
  - Creates notification channel `kabuk_feed_refresh` with `defaultImportance`.
  - Shows notification ID `1001`, title "Kabuk Feed Updated", body "N new articles are ready to read".
- Called from `_runFeedRefresh()` after persisting all new articles.

---

### 24 · User Follow Graph

**Gap addressed:** "No user follow graph" (Interaction Model table).

**New file — `lib/knowledge/types/follow.dart`:**
- `FollowedUserData` — immutable data class with `uri`, `name`, `profileUrl`, `followedAt`; `fromTriples()` factory.
- `KnowledgeStoreFollowExtension` on `KnowledgeStore`:
  - `createFollowedUser({name, profileUrl})` — stores `rdf:type kabuk:FollowedUser`, `schema:name`, `kabuk:profileUrl`, `kabuk:followedAt` triples.
  - `listFollowedUsers()` — queries by `rdf:type`.
  - `isFollowing(profileUrl)` — returns `true` if a matching `kabuk:profileUrl` triple exists.
  - `followedUriFor(profileUrl)` — returns the entity URI for the given profile URL.
  - `unfollowUser(uri)` — removes all triples for the entity.

**Changes — `lib/config/namespaces.dart`:**
- Added `kabukFollowedUser`, `kabukProfileUrl`, `kabukFollowedAt`.

**Changes — `lib/ui/explore/quick_peek_sheet.dart`:**
- `_SubredditPeekSheetState` gains `bool _isFollowed`, `String? _followUri`.
- `initState` calls `_checkFollowState()` to load current follow state.
- `_toggleFollow()` creates or deletes the `FollowedUser` entity and shows a snackbar.
- Follow/Unfollow `OutlinedButton.icon` rendered between `_PeekHeader` and `Divider`.

---

### 25 · Knowledge Store Comment Model

**Gap addressed:** "Knowledge store does not model comment trees" (Architecture Gaps table).

**New file — `lib/knowledge/types/comment.dart`:**
- `CommentData` — immutable data class with `uri`, `text`, `author`, `parentArticleUri`, `parentCommentUri`, `datePublished`, `score`, `depth`; `isTopLevel` getter; `fromTriples()` factory.
- `KnowledgeStoreCommentExtension` on `KnowledgeStore`:
  - `createComment({text, parentArticleUri, author?, parentCommentUri?, datePublished?, score?, depth})` — stores `schema:Comment` entity with full triple set.
  - `listCommentsForArticle(articleUri, {limit})` — returns comments sorted by `depth` ascending, then `score` descending.
  - `listReplies(commentUri)` — returns direct replies sorted by `score` descending.
  - `deleteCommentsForArticle(articleUri)` — bulk-deletes all comment entities for an article.

**Changes — `lib/config/namespaces.dart`:**
- Added `schemaCommentEntity`, `kabukParentArticle`, `kabukParentComment`, `kabukScore`, `kabukCommentDepth`.

---

### Session 5 — Remaining Gaps

| Gap | Status |
|-----|--------|
| Reddit OAuth2 + official API | **Blocked** — requires app registration and OAuth2 PKCE flow |
| Reddit comment tree renderer (UI) | **Pending** — comment model is now in place; renderer not yet built |
| Multireddit / feed groups | **Pending** |
| CDN image proxy | **Pending** |
| No compact / card view toggle | **Pending** |
| Stories / Reels / vertical video | **Pending** |
| No Reddit authentication (upvote/downvote) | **Blocked** — requires OAuth2 |
| No in-app DMs / chat | **Pending** |
