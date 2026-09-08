# Kabuk

An agent-centric personal OS shell built in Flutter.

## Vision

Kabuk is a super app that unifies your digital life through small, specialized AI agents. Instead of switching between dozens of apps with inconsistent UIs, you interact with agents through a consistent chat interface. Agents read and write a local RDF knowledge store, and can generate rich UI on the fly using Remote Flutter Widgets.

Think of it as a shell for your digital life — like Android launchers or Windows Explorer, but for all your services and data.

**Nostr is the primary social protocol.** Every piece of content — Reddit posts, RSS articles, web pages, videos — can be liked, commented on, and shared using the user's Nostr identity. Other Nostr followers see those interactions. This gives a unified social graph across all content sources without requiring each source to implement its own social layer.

**The local LLM is the primary AI.** All AI interactions default to the on-device model. External LLM APIs (OpenAI, Ollama) are available as extensions — the local model can delegate complex tasks to them or use them for specialized capabilities. Privacy is preserved by default.

## Core Concepts

- **Agent-First**: Users interact through chat with specialized agents (NoteAgent, FileAgent, MediaAgent, CalendarAgent, etc.). Chat is the universal input.
- **Knowledge Store**: All data stored as RDF triples (Schema.org vocabulary) in a local SQLite database. Single source of truth, reactive via Riverpod.
- **Dynamic UI (RFW)**: Agents generate UI using Remote Flutter Widgets. The system can create interfaces it was never explicitly programmed to show.
- **Virtual OS Layer**: Platform capabilities (filesystem, networking, media, crypto, notifications) abstracted behind clean Dart interfaces — the Flutter way.
- **Privacy-First**: All data encrypted locally. Offline-first. No cloud dependency.

## Architecture

```
┌─────────────────────────────────────────────────┐
│              Presentation Layer                  │
│   Explore │ Chat │ Vault  │ Apps │ RFW Runtime   │
├─────────────────────────────────────────────────┤
│                Agent Layer                       │
│   Router Agent → Domain Agents → LLM Service     │
├─────────────────────────────────────────────────┤
│              Knowledge Layer                     │
│        RDF Triple Store (SQLite/Drift)           │
├─────────────────────────────────────────────────┤
│             Virtual OS Layer                     │
│   Vault │ Mesh │ Media │ Auth │ Notify │ Present │
├─────────────────────────────────────────────────┤
│              Platform Layer                      │
│        Android │ iOS │ Desktop                   │
└─────────────────────────────────────────────────┘
```

## 4 Main Views

| View | Purpose |
|---|---|
| **Explore** | Reddit + Instagram + browser hybrid. Follow Reddit, 4chan, YouTube, RSS, and more. View web content natively. Nostr is the social layer — like/comment on any content using your Nostr identity. Nostr profiles viewable inline. Unified **ChannelView** displays any author's content natively across all sources. |
| **Chat** | Primary messaging via Nostr (text, media, contacts). AI chat defaults to the local on-device LLM. External LLM APIs are optional extensions. MCP (Model Context Protocol) connects external tools to the local LLM. |
| **Vault** | Private data storage with quick capture. Easy camera/recorder/notes access so you can capture anything and let the local LLM sort, organize, and tag it. A private inbox to yourself. |
| **Apps** | Everything else — app launcher, bookmarks, settings, and anything the other three views don't cover. |

## Tech Stack

- **Flutter/Dart 3.x** — Cross-platform UI (iOS is the active target)
- **Riverpod** — State management
- **Drift** — SQLite ORM for knowledge store
- **Freezed** — Immutable data classes
- **RFW** — Remote Flutter Widgets for dynamic UI
- **Nostr** — Decentralized social protocol (NIP-01, NIP-19, NIP-44, NIP-25, NIP-28)
- **media_kit** — Universal video playback (MKV/MP4/HLS)
- **llamadart** — On-device GGUF inference via Dart Native Assets
- **MCP** *(design only — no implementation yet)* — Model Context Protocol for connecting external tools to the local LLM

## Documentation

| Document | Description |
|---|---|
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | System architecture and layer design |
| [docs/AGENTS.md](docs/AGENTS.md) | Agent system design and protocol |
| [docs/KNOWLEDGE_STORE.md](docs/KNOWLEDGE_STORE.md) | RDF knowledge store design |
| [docs/VIRTUAL_OS.md](docs/VIRTUAL_OS.md) | Virtual OS service layer |
| [docs/RFW.md](docs/RFW.md) | Remote Flutter Widgets and dynamic UI |
| [docs/CHAT_PROTOCOL.md](docs/CHAT_PROTOCOL.md) | Chat and communication protocol |
| [docs/MCP.md](docs/MCP.md) | Model Context Protocol integration plan |
| [docs/ROADMAP.md](docs/ROADMAP.md) | Roadmap and master task list |
| [docs/IMPROVEMENT_ROADMAP.md](docs/IMPROVEMENT_ROADMAP.md) | Improvement workstreams and phases |
| [docs/UX_AUDIT_REPORT.md](docs/UX_AUDIT_REPORT.md) | UX findings and recommendations |
| [docs/TOOL_DISTILLATION.md](docs/TOOL_DISTILLATION.md) | In-house tools vs. best open-source counterparts (build vs. adopt) |

## Getting Started

```bash
# Install dependencies
flutter pub get

# Run code generation
dart run build_runner build

# Run the app
flutter run
```

## Project Status

**Last verified: Aug 2026** — iOS simulator build passing, `flutter analyze` clean (0 errors, 6 warnings), 634/634 tests passing.

The app runs on iOS (iPhone 17 Pro simulator) and the codebase is healthy, but the docs below previously overstated several features. The accurate picture:

### Working (verified)

- ✅ 4-view shell — Explore, Chat, Vault, Apps — plus Onboarding, Settings (12 sub-pages), Marketplace
- ✅ Explore feed — RSS, Reddit, 4chan, Nostr, Usenet, and **DuckDuckGo search** articles stored as `schema:Article` and rendered as native cards; pull-to-refresh, sort modes, filters, 30-min background refresh. DDG is searchable in the omnibar ("Web" results) and subscribable as a feed (`ddg://search?q=…`). Plain-text omnibar queries route **prompt → agent → tools → channels → UI** (answer + optional channel surface).
- ✅ Nostr social layer — NIP-01/19/44/25, relays, DMs, group channels, reactions
- ✅ Agent system — 12 domain agents (router, system, note, contact, calendar, file, search, identity, messaging, feeds, discover, **web & channels**); isolate runtime; tiered LLM (local GGUF + OpenAI/Anthropic HTTP); privacy filter; memory; cost tracking. The **web & channels agent** exposes `web_search`/`web_fetch`/`reddit_search`/`nostr_search`/`usenet_search`/`rss_fetch` through an in-process MCP-style channel registry (`lib/services/channels.dart`) — agents, the omnibar, and the feed engine all invoke channels through the same interface.
- ✅ Knowledge store — Drift/SQLite RDF triple store (schemaVersion 4), FTS5, change events, device-sync columns
- ✅ Usenet stack — Newznab indexers, NNTP provider pool, NZB/yEnc/par2/RAR, streaming pipeline + local HTTP server, "Find on Usenet", media_kit video player
- ✅ Content plugins — Reddit, 4chan, Media, YouTube, HackerNews, Wikipedia, SoundCloud, Bandcamp (searchable/usable via omnibar + marketplace)
- ✅ RFW widget system — 7 built-in widget libraries with knowledge-store bindings
- ✅ Vault — AES-256-GCM encrypted files, notes, camera/audio capture, collections
- ✅ Identity system — secp256k1 keypairs, nsec import/generate, biometrics
- ✅ 634 passing tests (agent, knowledge, service, and platform layers; no UI widget tests)

### Partially working / fragile (see docs/IMPROVEMENT_ROADMAP.md)

- 🔄 LLM behavior is the weakest area — see "Known Gaps" below. Local GGUF tool-calling is unreliable, all domain agents run on the base tier, and unconfigured setups show a misleading "AI model is being prepared" stub.
- 🔄 Feed/channel system was fragmented — **reworked Aug 2026** (see `docs/FEED_CHANNEL_PLAN.md`). Feed refresh now surfaces per-source errors, chips fetch-on-select, filters persist and work, the "Nostr" chip shows real content, web subscriptions refresh, and `ChannelPage` is functional and wired for plugin channels.

### Known Gaps (verified in code, Aug 2026)

1. ~~**Explore feed hard-capped at 200 articles**~~ → **Fixed**: `articlesProvider` raised to 500 and `_loadMore` pages non-Reddit feeds from the store via a `before` cursor (`lib/knowledge/types/article.dart`, `lib/ui/explore/explore_view.dart`).
2. ~~**Articles auto-delete after 48h**~~ → **Fixed**: default unread TTL raised to 14 days (`kUnreadArticleTtl`); read → 7 days; bookmarks never pruned.
3. ~~**ChannelView only refreshes Reddit**~~ → **Partial**: `ChannelView` remains Reddit-only, but the unified `ChannelPage` now has a working store branch + plugin branch and is wired for plugin channels via the omnibar. (`docs/FEED_CHANNEL_PLAN.md` §Phase 3.)
4. ~~**Unified ChannelPage is dead code**~~ → **Fixed**: store branch implemented; `ResolvedChannel` carries plugin refs and plugin channels open in `ChannelPage`.
5. ~~**Plugin content has no Explore/channel surface**~~ → **Partial**: plugin channels now open in `ChannelPage` via URL resolution; a full plugin-backed Explore feed source remains future work.
6. ~~**Reddit unauthenticated API rate-limited**~~ → **Improved**: Reddit deprecated anonymous `.json` in May 2026 (403 + TLS fingerprinting). The Reddit source now uses the recommended descriptive User-Agent plus a host fallback chain (`api.reddit.com` → `old.reddit.com` → `www.reddit.com`) with 429 back-off (`lib/platform/shared/reddit_api.dart`); per-feed errors are surfaced in the refresh banner. OAuth remains future work.
7. **All domain agents run on the base LLM tier** — unchanged.
8. **MCP and wallet/Lightning are design-only** — unchanged.
9. **Remote-only LLM config makes two API calls per message** — unchanged.
10. **iOS build artifacts are uncommitted** — unchanged.

See [docs/IMPROVEMENT_ROADMAP.md](docs/IMPROVEMENT_ROADMAP.md) for the full status and remediation plan.

## License

TBD
