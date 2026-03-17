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
| **Explore** | Reddit + Instagram + browser hybrid. Follow Reddit, 4chan, YouTube, RSS, and more. View web content natively. Nostr is the social layer — like/comment on any content using your Nostr identity. Nostr profiles viewable inline. |
| **Chat** | Primary messaging via Nostr (text, media, contacts). AI chat defaults to the local on-device LLM. External LLM APIs are optional extensions. MCP (Model Context Protocol) connects external tools to the local LLM. |
| **Vault** | Private data storage with quick capture. Easy camera/recorder/notes access so you can capture anything and let the local LLM sort, organize, and tag it. A private inbox to yourself. |
| **Apps** | Everything else — app launcher, bookmarks, settings, and anything the other three views don't cover. |

## Tech Stack

- **Flutter/Dart 3.x** — Cross-platform UI
- **Riverpod** — State management
- **Drift** — SQLite ORM for knowledge store
- **Freezed** — Immutable data classes
- **RFW** — Remote Flutter Widgets for dynamic UI
- **gRPC** — Inter-device communication
- **Nostr** — Decentralized social protocol (NIP-01, NIP-04, NIP-44, NIP-23, NIP-51)
- **MCP** — Model Context Protocol for connecting external tools to the local LLM

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

**Phase 5 / 6 — Communication & Ecosystem (Active Development)**

Core foundation is complete and the app is running on iOS. Current working features:

- ✅ Explore view — Reddit, RSS, Nostr (#hashtag) feeds with real-time data
- ✅ Nostr social layer — Like/comment/repost any content via Nostr identity
- ✅ Chat view — Nostr DMs + Kabuk AI (local LLM) as primary assistant
- ✅ Vault view — Notes, camera/audio capture, document library
- ✅ Apps view — Tools (Notes, Calendar, Contacts, Search, Settings), Developer panel
- ✅ Identity system — Nostr key management, generate/import nsec
- ✅ Relay management — 8/9 relays connected by default
- ✅ RFW widget system — 7 widget libraries (core, notes, contacts, dashboard, media, etc.)
- ✅ Agent system — 11 specialized agents (identity, messaging, feeds, discover, router, etc.)
- ✅ Settings — LLM config, local models, service providers, encryption at rest
- 🔄 Local LLM on-device inference (GGUF model support)
- 🔄 External LLM API integration (OpenAI, Ollama)
- 🔄 MCP (Model Context Protocol) server support
- ⏳ App Marketplace
- ⏳ 4chan / YouTube / Nostr profile feed sources

## License

TBD
