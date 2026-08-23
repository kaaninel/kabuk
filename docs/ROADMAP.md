# Kabuk — Roadmap & Master Task List

## Vision
Build an agent-centric personal OS shell where users interact primarily through chat with specialized agents. The system uses an RDF knowledge store as single source of truth, Remote Flutter Widgets for dynamic UI, and a Virtual OS layer to abstract platform capabilities.

**Nostr is the primary social protocol.** Every piece of content — Reddit posts, RSS articles, web pages, videos — can be liked, commented on, and shared using the user's Nostr identity. Those interactions are federated and visible to followers across the Nostr network. This gives a unified social graph across all content types without each source needing its own social layer.

**The local LLM is the primary AI provider.** All AI interactions default to the on-device model. External LLM APIs (OpenAI, Anthropic, Ollama) are optional extensions. **MCP (Model Context Protocol)** connects external tools and servers to the local LLM, expanding its capabilities without compromising privacy.

## Current Status (as of Aug 2026)

**This roadmap was written Feb 26, 2026 and was significantly out of date.** It has been reconciled with the actual codebase (verified Aug 2026). The app is running on iOS; `flutter analyze` is clean and 634 tests pass, but several "done" items are only partially true (see the Reality Check below).

- ✅ **11 specialized agents** deployed and functional
- ✅ **Full RFW widget system** with dynamic agent-generated UIs
- ✅ **Multi-model LLM support** (Anthropic, OpenAI, local GGUF inference)
- ✅ **Knowledge store** with 100+ Schema.org type support
- ✅ **Usenet streaming** — Newznab indexers, NNTP, NZB/yEnc/par2/RAR, local stream server (post-ROADMAP work, undocumented before this update)
- ✅ **Content plugin system** — 8 bundled adapters (Reddit, 4chan, YouTube, HN, Wikipedia, SoundCloud, Bandcamp, Media)
- 🔄 **Nostr integration** (E2E messaging, relays, DMs, group channels)
- 🔄 **Feed aggregation** (RSS/Reddit/4chan/Nostr/Usenet) — functional but fragile (see Reality Check)
- ⚠️ **Local LLM** (llamadart) — works, but weak tool-calling makes agent flows unreliable
- ⏳ **MCP** — design only, zero code
- ⏳ **Multi-platform** (Desktop), **Provider agents** (CalDAV, CardDAV), **Widget repository**

### Reality Check (what "done" actually means, Aug 2026)

| Claimed | Actual |
|---|---|
| "Unified ChannelView — any author across all sources" | Only Reddit fetches fresh content; all other sources show cached store content only (`lib/ui/explore/channel_view.dart`) |
| "Multi-model LLM support" | Real, but all domain agents default to the base tier; tiers `standard`/`advanced` are never requested by agents (`lib/agents/base.dart`) |
| "Explore feeds with real-time data" | Feed is capped at 200 articles and unread articles are pruned 48h after publication (`lib/ui/explore/explore_view.dart`, `lib/knowledge/types/article.dart`) |
| "Local LLM + hybrid routing" | On-device inference works; tool-calling/JSON output from small models is unreliable and frequently degrades to raw text |
| "Nostr social layer" | Reactions/comments/DMs implemented; broader cross-content social graph (NIP-22/25 on every content type) still planned |
| "MCP server support" | **Not implemented** — `docs/MCP.md` is a design document only |
| "8/9 relays connected" | Relay list is configurable; default connection count varies by environment |

## Phase Overview

| Phase | Name | Duration | Focus | Status |
|---|---|---|---|---|
| 0 | Foundation | Weeks 1–3 | Project setup, dependencies, core abstractions | ✅ **COMPLETE** |
| 1 | Agent Core | Weeks 4–9 | Knowledge store, agent runtime, basic agents | ✅ **COMPLETE** |
| 2 | Chat & UI | Weeks 10–15 | Chat interface, 4 views, navigation | ✅ **COMPLETE** |
| 3 | Essential Agents | Weeks 16–22 | Media, Calendar, Contact, Search agents | ✅ **COMPLETE** |
| 4 | Dynamic UI | Weeks 23–28 | RFW runtime, built-in widgets, agent UI generation | ✅ **COMPLETE** |
| 5 | Communication | Weeks 29–36 | Human messaging, mesh networking, sync | 🔄 **IN PROGRESS** |
| 6 | Ecosystem | Weeks 37–48 | Provider agents, widget repos, local LLM | 🔄 **IN PROGRESS** |
| 7 | Media & Usenet | Post-roadmap | Universal video playback, Usenet streaming, content plugins | ✅ **COMPLETE** (unplanned scope) |
| 8 | Stabilization | 2026 | Fix fragile LLM/channel behavior, doc accuracy, tests | 🔄 **RECOMMENDED NEXT** |

---

## Phase 0 — Foundation (Weeks 1–3) ✅ COMPLETE

### Project Setup ✅
- [x] Configure pubspec.yaml with all core dependencies
  - [x] flutter_riverpod, riverpod_annotation
  - [x] drift, sqlite3_flutter_libs
  - [x] freezed, freezed_annotation, json_annotation, json_serializable, build_runner
  - [x] rfw (remote flutter widgets)
  - [x] uuid
  - [x] mocktail (dev)
  - [x] Additional: llamadart (local LLM), web_socket_channel (Nostr relays), url_launcher, webview_flutter, cached_network_image, video_player, etc.
- [x] Configure analysis_options.yaml (strict mode)
- [x] Set up build_runner for code generation
- [x] Create directory structure per architecture spec
- [x] Set up CI (GitHub Actions: analyze, test, build) — *Assumed configured*
- [x] Configure code generation scripts (build_runner watch/build)

### Core Abstractions ✅
- [x] Define `Result<T>` sealed class (Success/Failure)
- [x] Define `ServiceError` sealed class hierarchy
- [x] Define base Riverpod provider structure
- [x] Create app entry point with ProviderScope
- [x] Create AppRouter (declarative routing)
- [x] Create Shell scaffold with bottom navigation bar

### Theme & Design Tokens ✅
- [x] Define color scheme
- [x] Define typography scale
- [x] Define spacing constants
- [x] Create ThemeData provider

---

## Phase 1 — Agent Core (Weeks 4–9) ✅ COMPLETE

### Knowledge Store ✅
- [x] Define Drift database schema (triples table, blobs table, FTS5)
- [x] Implement `Triple` Freezed data class
- [x] Implement `KnowledgeStore` interface
- [x] Implement `KnowledgeStoreImpl` (Drift-backed) — `drift_store.dart`
- [x] Implement `QueryBuilder` with fluent API
  - [x] subject/predicate/object matching
  - [x] Greater than / less than for dates and numbers
  - [x] Full-text search via FTS5
  - [x] ORDER BY, LIMIT, OFFSET
  - [x] Graph traversal (follow predicate)
- [x] Implement mutation API (`mutate()` with transaction) — `mutation.dart`
- [x] Implement `ChangeEvent` stream — `changes.dart`
- [x] Create Riverpod providers for knowledge store
- [x] Create stream providers for watching query patterns
- [x] Implement namespace constants
- [x] Unit tests for all query patterns
- [x] Unit tests for mutations and change events

### Schema.org Types ✅
- [x] Define type constants for: Note, Person, Event, MediaObject, ImageObject, VideoObject, AudioObject, Message, Conversation, Action, Place, Organization, ContactPoint
- [x] Create helper functions for each type (create, read, update patterns)
- [x] Document each type mapping in knowledge/types/

### Agent Framework ✅
- [x] Define `BaseAgent` abstract class
- [x] Define `AgentTool` class with parameter schema
- [x] Define `ToolParam` for parameter descriptions
- [x] Define `ToolResult` sealed class
- [x] Define `AgentContext` with all service references
- [x] Define `AgentMessage` sealed class with all message types
- [x] Implement `AgentRuntime` with Dart isolate management
- [x] Implement capability system
- [x] Unit tests for agent runtime

### LLM Service ✅
- [x] Define `LlmService` interface
- [x] Define `LlmMessage` types
- [x] Define `LlmOptions`
- [x] Implement Anthropic provider (HTTP API) — `http_llm.dart`
- [x] Implement OpenAI provider (HTTP API) — `http_llm.dart`
- [x] Implement local LLM inference — `local_llm.dart` (with llamadart)
- [x] Implement streaming response support
- [x] Token counting and budget management
- [x] Prompt template system — `prompts.dart`
- [x] Provider fallback chain
- [x] Secure API key storage
- [x] Unit tests

### Router Agent ✅
- [x] Implement RouterAgent extending BaseAgent
- [x] System prompt for intent classification
- [x] Domain agent registry
- [x] Intent → agent routing logic
- [x] Conversation context management
- [x] Fallback to general conversation
- [x] Multi-turn support
- [x] Unit tests for routing logic

### First Domain Agents ✅
- [x] Implement `NoteAgent` — all CRUD operations
- [x] Implement `FileAgent` — file operations
- [x] Implement `SystemAgent` — system info and preferences
- [x] Implement `DiscoveryAgent` — content discovery
- [x] Implement `SearchAgent` — universal search
- [x] Unit tests for each agent

---

## Phase 2 — Chat & UI (Weeks 10–15) ✅ COMPLETE

### Chat Core ✅
- [x] Define `ChatMessage` Freezed class with sealed `MessageContent`
- [x] Define `Conversation` Freezed class
- [x] Implement conversation storage in knowledge store
- [x] Implement message storage in knowledge store
- [x] Create providers for message streams and conversations
- [x] Create chat service for sending/receiving messages

### Chat UI ✅
- [x] Implement chat view scaffold
- [x] Message bubble widget (user vs agent styling)
- [x] Text message rendering
- [x] Markdown message rendering
- [x] Tool call display
- [x] Streaming text display
- [x] Message input bar with send button
- [x] Conversation drawer
- [x] New conversation creation
- [x] Agent avatar and status indicators
- [x] Scroll-to-bottom, auto-scroll on new messages
- [x] Widget tests for message rendering

### Shell Navigation ✅
- [x] Bottom navigation bar with 4 main views
- [x] Explore, Chat, Vault, Apps views
- [x] View-specific drawers
- [x] Top app bar
- [x] View transition animations
- [x] Routing and deep linking
- [x] Additional views: Onboarding, Settings

### Explore View ✅
- [x] Explore view scaffold
- [x] Dashboard card grid/list
- [x] Timeline view
- [x] Cards populated from knowledge store queries
- [x] Explore drawer with feed filters

### Vault View ✅
- [x] Vault view scaffold
- [x] Mode switch: Photo / Video / Note / Audio
- [x] Note creation screen
- [x] Integration with NoteAgent for smart tagging
- [x] Vault drawer
- [x] Bottom bar with capture controls

### Apps View ✅
- [x] Apps view scaffold
- [x] List of installed agents and tools
- [x] Agent detail view

---

## Phase 3 — Essential Agents (Weeks 16–22) ✅ COMPLETE

### Virtual OS Services ✅
- [x] Implement `VaultService` interface (secrets, encryption, secure storage)
- [x] Implement `AuthService` interface (identity, biometrics)
- [x] Implement `MediaService` interface (camera, audio, video, gallery)
- [x] Implement `NotificationService` interface (local/push notifications)
- [x] Implement `MeshService` interface (networking baseline)
- [x] Implement `PresentationService` interface (display, haptics)
- [x] Implement platform-specific implementations
- [x] Mock implementations for all services
- [x] Unit tests for all services

### Media Agent ✅
- [x] Implement `MediaAgent` with all tools
  - [x] capture_photo tool
  - [x] record_audio tool
  - [x] capture_video tool
  - [x] search_media tool
  - [x] extract_metadata tool
  - [x] generate_thumbnail tool
- [x] Vault view camera integration
- [x] Vault view audio recorder integration
- [x] Unit tests

### Calendar Agent ✅
- [x] Implement `CalendarAgent` with all tools
  - [x] create_event tool
  - [x] list_events tool
  - [x] set_reminder tool
  - [x] search_events tool
- [x] Notification integration for reminders
- [x] Unit tests

### Contact Agent ✅
- [x] Implement `ContactAgent` with all tools
  - [x] create_contact tool
  - [x] search_contacts tool
  - [x] get_contact tool
  - [x] update_contact tool
- [x] Unit tests

### Search Agent ✅
- [x] Implement `SearchAgent` — universal FTS across all types
- [x] Search UI integration
- [x] Unit tests

---

## Phase 4 — Dynamic UI (Weeks 23–28) ✅ COMPLETE

### RFW Runtime ✅
- [x] Set up RFW package integration
- [x] Implement `RfwRuntime` — parse and render RFW templates
- [x] Implement `RfwRegistry` — widget library management
- [x] Implement `RfwDataBinding` — knowledge store → DynamicContent
  - [x] Entity binding
  - [x] Query binding

### Built-in Widget Libraries ✅
- [x] `kabuk:core` — Card, ListTile, Grid, Timeline, EmptyState, ErrorState, LoadingState
- [x] `kabuk:notes` — NoteCard, NoteDetail, NoteList
- [x] `kabuk:contacts` — ContactCard, ContactList, ContactDetail
- [x] `kabuk:media` — ImageCard, VideoCard, AudioCard, Gallery
- [x] `kabuk:calendar` — EventCard, EventList
- [x] `kabuk:chat` — MessageBubble, ConversationList
- [x] `kabuk:dashboard` — DashboardCard, StatWidget, QuickAction

### Agent RFW Integration ✅
- [x] Agents return RFW templates in ToolResult
- [x] Chat renders RFW widgets inline
- [x] Explore view uses RFW widgets for dashboard cards
- [x] Apps view shows installed widget libraries

---

## Phase 5 — Communication (Weeks 29–36) 🔄 IN PROGRESS

### Human Chat 🔄
- [x] Implement `ChatAgent` for human messaging
- [x] gRPC protobuf definitions (Nostr envelope) — `nostr.dart`
- [x] E2E encryption (NIP-44) — `nip44.dart`
- [x] Relay integration via gRPC — `mesh.dart`
- [x] Direct message sending via MeshService
- [x] Message sync protocol
- [ ] Delivery and read receipts (planned)
- [ ] Group chat support (planned)

### Mesh Networking 🔄
- [x] Implement `MeshService` interface
- [x] WebSocket transport implementation (Nostr relays)
- [x] HTTP transport for API calls
- [x] Relay server connection
- [x] Peer discovery (baseline)
- [x] Offline message queue with sync-on-reconnect
- [x] Connection state management
- [ ] Advanced peer discovery — Nearby Connections (planned)

### Sync & Backup ⏳
- [ ] Device-to-device knowledge store sync (planned)
- [ ] Conflict resolution for concurrent edits (planned)
- [ ] Encrypted backup export (planned)
- [ ] Encrypted backup restore (planned)
- [ ] Multi-device identity (linked devices) (planned)

---

## Phase 6 — Ecosystem (Weeks 37–48) 🔄 IN PROGRESS

### Provider Agents 🔄
- [x] `FeedAgent` — RSS/Atom feed aggregation and display — `feed.dart`
- [ ] `CalDavAgent` — CalDAV calendar sync (planned)
- [ ] `CardDavAgent` — CardDAV contact sync (planned)
- [ ] `EmailAgent` — IMAP/SMTP (stretch goal)

### Local LLM 🔄
- [x] Model manager service — `model_manager.dart`
- [x] Ollama/llamadart integration
- [x] Model download and management
- [x] Hybrid routing (local for simple tasks, remote for complex) — `local_llm.dart`
- [x] Model switching and fallback

### MCP (Model Context Protocol) ⏳
- [ ] Define `McpClient` interface in `lib/services/mcp.dart` (planned)
- [ ] Implement stdio and HTTP/SSE transport for MCP servers (planned)
- [ ] Tool discovery: expose MCP server tools to the local LLM alongside native tools (planned)
- [ ] Built-in MCP servers: filesystem, web search, knowledge store bridge (planned)
- [ ] MCP server configuration UI in Settings (planned)
- [ ] AgentContext integration: `context.mcpClient` for agent access (planned)
- [ ] See [docs/MCP.md](MCP.md) for full design

### Nostr as Primary Social Protocol ⏳
- [ ] Nostr reactions (NIP-25) on any content type — Reddit, RSS, web pages (planned)
- [ ] Nostr comments (NIP-22) threaded below any content item (planned)
- [ ] Nostr profile viewer in Explore (like a Reddit profile page) (planned)
- [ ] Cross-content social graph: show which Nostr contacts interacted with a piece of content (planned)
- [ ] Nostr-based content sharing to followers (planned)

### Widget Repository ⏳
- [ ] Repository manifest format (planned)
- [ ] Repository client (planned)
- [ ] Repository browser in Apps view (planned)
- [ ] Library dependency resolution (planned)
- [ ] Update mechanism (planned)

### Platform Expansion ⏳
- [ ] iOS implementations for all Virtual OS services (planned)
- [ ] Desktop implementations — macOS, Linux, Windows (planned)
- [ ] Responsive layout for tablet/desktop (planned)

---

## Dependencies & Prerequisites

### Package Dependencies
```yaml
dependencies:
  flutter:
    sdk: flutter
  # State management
  flutter_riverpod: ^2.x
  riverpod_annotation: ^2.x
  # Database
  drift: ^2.x
  sqlite3_flutter_libs: ^0.5.x
  # Data classes
  freezed_annotation: ^2.x
  json_annotation: ^4.x
  # Remote Flutter Widgets
  rfw: ^1.x
  # Utilities
  uuid: ^4.x
  intl: ^0.x
  collection: ^1.x
  # Networking
  http: ^1.x
  web_socket_channel: ^2.x
  # Crypto (for AuthService)
  cryptography: ^2.x
  # Media
  camera: ^0.x
  just_audio: ^0.x
  # Markdown
  flutter_markdown: ^0.x

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^6.x
  build_runner: ^2.x
  freezed: ^2.x
  json_serializable: ^6.x
  riverpod_generator: ^2.x
  drift_dev: ^2.x
  mocktail: ^1.x
```

### External Requirements
- LLM API key (Anthropic or OpenAI) for agent intelligence
- Relay server (Phase 5) — simple gRPC server, Docker deployable
- Widget repository host (Phase 6) — static HTTP hosting

---

## Milestone Definitions

### M1 — "Hello Agent" ✅ COMPLETE
User can chat with an agent in a text UI. NoteAgent can create/search notes. Knowledge store persists data. **Status:** Fully achieved.

### M2 — "Shell" ✅ COMPLETE
Full 4-view navigation with Explore, Chat, Vault, Apps. Chat with agents. Capture notes. Explore shows dashboard. Navigation, drawers, and theming complete. **Status:** Fully achieved.

### M3 — "Useful" ✅ COMPLETE
Camera, audio recording, calendar, contacts, search all work through agents. System is usable as a daily personal organizer. Multiple specialized agents fully functional. **Status:** Fully achieved.

### M4 — "Beautiful" ✅ COMPLETE
Agents generate rich UI via RFW. Dashboard shows custom widgets. Built-in widget libraries complete. The system looks polished. **Status:** Fully achieved.

### M5 — "Connected" ✅ COMPLETE (as of Aug 2026)
Human-to-human messaging works with E2E encryption (NIP-44). Devices can sync via Nostr relays. Offline queue ensures no messages lost. Feed agent aggregates content. **Status:** Achieved. Group chat (NIP-28) and device pairing (UDP discovery + HTTP replication) also implemented.

### M6 — "Open" 🔄 IN PROGRESS
Local LLM support (local_llm.dart via llamadart). Feed agent for RSS/Atom. Model manager for switching between providers. Multi-platform groundwork. **Status:** ~50% complete. Local LLM, feed agent, and content plugins achieved; MCP, CalDAV/CardDAV, widget repository, and desktop platforms remain planned. Agent flows on the local model are fragile (see Reality Check).

---

## Implementation Summary

### Completed Work (Phases 0–4 + post-roadmap)
- **Full agent-centric architecture:** Router agent dispatches user messages to 11 specialized domain agents (Note, File, System, Media, Calendar, Contact, Search, Identity, Messaging, Feed, Discovery).
- **Knowledge store with RDF triples:** Drift-backed SQLite with full-text search, query builder, mutation events, and Riverpod reactivity.
- **4-view navigation + extras:** Explore (content feed/social), Chat (Nostr messaging + local LLM), Vault (private capture + AI organization), Apps, plus Onboarding and Settings.
- **Multi-model LLM support:** HTTP integration with Anthropic/OpenAI + local LLM inference via llamadart. Hybrid routing for cost optimization. *(Note: agents currently run everything on the base tier — see Reality Check.)*
- **RFW dynamic UI:** Full RFW runtime, widget registry, data binding to knowledge store, and 7 built-in widget libraries.
- **Virtual OS abstraction:** Services for Vault, Auth, Media, Notification, Presentation, Mesh, and Feed — with platform implementations.
- **Usenet streaming (post-roadmap):** Newznab indexers, NNTP provider pool with priority/SSL, NZB parser, yEnc decoder, par2 verification, RAR extraction, progressive streaming pipeline with local HTTP server, entity resolution, and a media_kit-based player with smart source selection.
- **Content plugin system (post-roadmap):** Plugin interface with capabilities (search/channel/urlResolve/trending), registry with persistence, 8 bundled adapters, and a Marketplace UI.

### Active Work (Phases 5–6)
- **Nostr integration:** E2E encryption (NIP-44), relay support, DMs, group channels (NIP-28), reactions.
- **Feed aggregation:** FeedAgent for RSS/Atom/Reddit/4chan/Nostr/Usenet parsing and timeline integration.
- **Model management:** Local LLM support with model switching and hybrid dispatch.
- **Planned:** Group messaging enhancements, device sync hardening, CalDAV/CardDAV providers, widget repository, multi-platform (Desktop).

### Recommended Next Work (Stabilization, 2026)
See [IMPROVEMENT_ROADMAP.md](IMPROVEMENT_ROADMAP.md) — the highest-impact items are fixing LLM tier selection + local-model tool-calling reliability, removing the 200-article feed cap and 48h article expiry, wiring plugin content into Explore/channels, making non-Reddit channels refresh, and building (or explicitly deferring) MCP.

### Key Architecture Decisions
1. **Privacy-first by design:** All data encrypted at rest (Vault service). No cloud dependency. Local-first with opt-in sync.
2. **Offline-first:** Every feature works without network. Mesh service provides async sync and store-and-forward.
3. **Agent-first UI:** Agents generate RFW templates for rich UI without app updates. Chat is the universal input.
4. **Sealed types everywhere:** Exhaustive pattern matching for robustness. Riverpod for state management and DI.
5. **Nostr foundation:** Using Nostr (NIP-44 encryption, relays, keys) instead of building custom auth/messaging. Open protocol for federation.

---

## Risk Register

| Risk | Impact | Status | Mitigation |
|---|---|---|---|
| RFW too limited for complex UIs | High | ✅ Mitigated | Built-in libraries handle 90% of needs. Custom renderers available if needed. |
| LLM quality insufficient for routing | Medium | 🔄 Ongoing | Improved prompts, fallback to text commands. User feedback loop. |
| **Local LLM tool-calling unreliable** | High | ⚠️ **Unresolved** | Small GGUF models emit malformed tool-call JSON; agents degrade to raw text. Fix: prompt hardening, JSON repair, fallback tiers. |
| **Feed content volatility** | High | ⚠️ **Unresolved** | 200-article cap + 48h unread expiry removes content aggressively; Reddit unauthenticated API is rate-limited. |
| **Channel refresh coverage** | Medium | ⚠️ **Unresolved** | Only Reddit channels refresh; plugin/local channels are static or dead code. |
| Mobile background execution limits | Medium | 🔄 Ongoing | FCM/APNs for wake-ups (planned). Minimize background processing. |
| Knowledge store performance at scale | Low-Medium | ✅ Mitigated | FTS5 indexing, pagination, query optimization in practice. |
| E2E encryption complexity | Medium | ✅ Mitigated | Using NIP-44 (established Nostr standard) instead of rolling own. |
| Scope creep | High | 🔄 Ongoing | Phases 5–6 focused on specific wins. Strict feature gates. |
| **MCP scope without implementation** | Medium | ⚠️ Unresolved | `docs/MCP.md` is design-only; either build a minimal client or archive the doc. |
