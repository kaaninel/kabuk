# Kabuk OS — Bug & Issue Tracker

## Open Issues

_Audit date: Aug 17, 2026. All items verified against current code. Detailed analysis in [docs/IMPROVEMENT_ROADMAP.md](docs/IMPROVEMENT_ROADMAP.md)._

### LLM / Agent

- [ ] **1. All domain agents run on the base LLM tier** — `processLlmRequest()` never sets a tier; only the router passes `tier:base`. `standard`/`advanced` tiers are unused. With a local model everything runs through the small base model; with remote-only config every message costs two API calls. — `lib/agents/base.dart:338`, `lib/agents/domains/*.dart`
- [ ] **2. Local model tool-calling is unreliable** — `LocalLlmService` only parses ```` ```json {"tool_calls": [...]} ``` ```` blocks; small models emit raw/malformed JSON and requests silently degrade to plain text. — `lib/agents/local_llm.dart:444`
- [ ] **3. Isolate sandboxing is effectively unused** — isolate spawn falls back to in-process execution; no `DriftIsolate` connection for the knowledge store. — `lib/agents/isolate_runtime.dart:1060`
- [ ] **4. Unconfigured LLM shows misleading message** — `_StubLlmService` returns "AI model is being prepared…" even when no model is configured or downloadable. — `lib/config/providers.dart:1665`
- [ ] **5. Privacy filter doubles latency** — remote-tier requests first run an on-device anonymization pass when a local model exists; remote-only configs disable filtering entirely. — `lib/agents/privacy_filter.dart`, `lib/config/providers.dart:764`

### Content / Channels

- [ ] **6. Explore feed hard-capped at 200 articles** — `articlesProvider` reads `listArticles(limit: 200)`; older content never displays. — `lib/ui/explore/explore_view.dart:72`
- [ ] **7. Unread articles auto-delete after 48h** — `kabuk:expiresAt = published + 48h`; `pruneStaleArticles()` deletes them on startup/refresh. — `lib/knowledge/types/article.dart:364`
- [ ] **8. Only Reddit channels refresh** — `_authorFeedUrl`/`_channelFeedUrl` return `null` for all non-Reddit sources; Nostr/RSS/4chan/USenet channels show cached content only. — `lib/ui/explore/channel_view.dart:31`
- [ ] **9. Unified ChannelPage is dead code** — never navigated to; returns `const []` for non-plugin channels. — `lib/ui/explore/channel_page.dart:171`
- [ ] **10. Plugin content has no Explore/channel surface** — YouTube, HN, Wikipedia, SoundCloud, Bandcamp, Media items only reachable via omnibar search/URL resolution. — `lib/plugins/bundled/*`
- [ ] **11. Reddit unauthenticated API rate-limited** — 429/403 failures are silently swallowed; feeds go stale without user feedback. — `lib/platform/shared/reddit_source.dart`, `lib/ui/explore/explore_view.dart:347`

### Hygiene / Docs

- [ ] **12. iOS build artifacts uncommitted** — SPM dirs, Xcode scheme pre-action, `Podfile.lock`, `pubspec.lock` diffs in working tree.
- [ ] **13. 6 analyzer warnings** — unused imports/fields in `lib/platform/shared/usenet/usenet_service_impl.dart:15`, `lib/ui/explore/entity_player.dart:18,104,130,292`, `lib/platform/shared/usenet/stream_pipeline.dart:894`.
- [ ] **14. No UI widget tests** — only agent/knowledge/service/platform layers covered.
- [ ] **15. MCP is design-only** — `docs/MCP.md` exists, zero implementation. Build it or archive the doc.
- [ ] **16. `rework` git branch is dead** — disconnected history, last commit "Deadend." — safe to delete.

---

## Previously Resolved (archived)

<details>
<summary>18 issues resolved as of Mar 17, 2026 (click to expand)</summary>

### CRITICAL

- [x] **1. Isolate runtime always fails silently** — `_AgentIsolateMessage` passes non-transferable objects across isolate boundaries. The entire isolate architecture is dead code. **Fix**: Added logging, explanatory comments, `storeBlob()` now throws `StateError`.

### HIGH

- [x] **2. Agent name always "router"** — Added `agentName` field to `AgentResponse`. Router tags all dispatched responses.
- [x] **3. `LlmProvider.local` missing from selector** — Added 4th `ButtonSegment` for local provider.

### MEDIUM

- [x] **4. Identity shows "?"** — 3-way fallback: displayName → pubkey hex prefix → '?'.
- [x] **5. Explore avatar no accessibility label** — Wrapped in `Semantics`.
- [x] **6-8. Multiple accessibility fixes** — `IconButton` replacements, `Semantics` wrappers.
- [x] **9. `storeBlob()` silent failure** — Now throws `StateError`.
- [x] **10. `watch()`/`stream()` empty** — Documented as known limitation.
- [x] **11. Conversation delete no undo** — Added SnackBar feedback.
- [x] **12. Raw GestureDetectors lack accessibility** — Wrapped in `Semantics`.
- [x] **13. Disabled buttons no visual state** — Covered by `TextButton.icon`.

### LOW

- [x] **14. "1 widgets" grammar** — Conditional singular/plural.
- [x] **15. `_colorFromHex` unsafe parsing** — Added try-catch with fallback.
- [x] **16. Empty displayName** — Shows "Unnamed Identity".
- [x] **17. Title generation race condition** — Added `_pendingTitles` guard.
- [x] **18. Reddit image URL validation** — Added `FeedImage.isValidImageUrl()`.

</details>