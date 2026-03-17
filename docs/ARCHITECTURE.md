# Kabuk — Architecture

> The primary architecture reference for Kabuk, an agent-centric personal OS shell built with Flutter.

---

## Table of Contents

- [1. System Overview](#1-system-overview)
- [2. Core Architecture Diagram](#2-core-architecture-diagram)
- [3. Layer Details](#3-layer-details)
  - [3.1 Presentation Layer](#31-presentation-layer)
  - [3.2 Agent Layer](#32-agent-layer)
  - [3.3 Knowledge Layer](#33-knowledge-layer)
  - [3.4 Virtual OS Layer](#34-virtual-os-layer)
  - [3.5 Platform Layer](#35-platform-layer)
- [4. Data Flow Examples](#4-data-flow-examples)
- [5. Key Design Decisions](#5-key-design-decisions)
- [6. Security Model](#6-security-model)
- [7. Technology Stack](#7-technology-stack)
- [8. File Organization](#8-file-organization)

---

## 1. System Overview

Kabuk is an **agent-centric personal OS shell**. Instead of navigating menus and tapping through screens, users interact primarily through **chat with small, specialized agents**. Each agent is an expert in a single domain — notes, files, media, calendar, contacts — and exposes typed tools that the system can invoke on the user's behalf.

The system is built on five pillars:

1. **Agent-first.** Chat is not a secondary interface — it *is* the interface. Every capability in the system is reachable through natural language. Agents are stateless; all persistent state lives in the knowledge store.

2. **Virtual OS.** Platform capabilities (filesystem, networking, camera, crypto, notifications) are abstracted behind clean Dart interfaces. Business logic and agents never touch platform APIs directly. Implementations use platform channels to bridge to native code — the "Flutter way."

3. **RDF Knowledge Store.** A single source of truth for all structured data. Everything — notes, contacts, media metadata, conversations, preferences — is stored as RDF triples backed by SQLite/Drift. Schema.org provides the default vocabulary. Riverpod streams make the store reactive.

4. **RFW Dynamic UI.** Agents generate UI on the fly using Remote Flutter Widgets. Instead of pre-building screens for every possible data shape, agents compose widget trees at runtime. Widget libraries are installable and extensible.

5. **Privacy-first, Offline-first, Data-driven.** All data lives on-device, encrypted at rest. Agents can run with local LLMs (Ollama, llama.cpp via dart:ffi). The mesh networking layer enables peer-to-peer sync without centralized servers. No data leaves the device unless the user explicitly enables it.

---

## 2. Core Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│                       PRESENTATION LAYER                            │
│                                                                     │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐           │
│  │ Explore  │  │   Chat   │  │  Vault   │  │   Apps   │           │
│  │  View    │  │   View   │  │   View   │  │   View   │           │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘  └────┬─────┘           │
│       │              │              │              │                 │
│  ┌────▼──────────────▼──────────────▼──────────────▼─────────────┐  │
│  │            Shell Navigation (Bottom Nav + Drawers)            │  │
│  └──────────────────────────┬────────────────────────────────────┘  │
│                             │                                       │
│  ┌──────────────────────────▼────────────────────────────────────┐  │
│  │                RFW Runtime (Widget Resolution + Data Binding) │  │
│  └──────────────────────────┬────────────────────────────────────┘  │
├─────────────────────────────┼───────────────────────────────────────┤
│                       AGENT LAYER                                   │
│                             │                                       │
│  ┌──────────────────────────▼────────────────────────────────────┐  │
│  │                     Router Agent                              │  │
│  │         (Intent Classification · Context Management)          │  │
│  └───┬──────┬──────┬──────┬──────┬──────┬──────┬──────┬─────────┘  │
│      │      │      │      │      │      │      │      │            │
│      ▼      ▼      ▼      ▼      ▼      ▼      ▼      ▼            │
│   ┌─────┐┌─────┐┌─────┐┌─────┐┌─────┐┌─────┐┌─────┐┌──────┐      │
│   │Note ││File ││Media││Cal. ││Cont.││Srch ││Chat ││System│      │
│   │Agent││Agent││Agent││Agent││Agent││Agent││Agent││Agent │      │
│   └──┬──┘└──┬──┘└──┬──┘└──┬──┘└──┬──┘└──┬──┘└──┬──┘└──┬───┘      │
│      └──────┴──────┴──────┴──────┴──────┴──────┴──────┘            │
│                             │                                       │
│  ┌──────────────────────────▼────────────────────────────────────┐  │
│  │  LLM Service (OpenAI · Anthropic · Ollama · llama.cpp/FFI)   │  │
│  └──────────────────────────┬────────────────────────────────────┘  │
│                             │                                       │
│  ┌──────────────────────────▼────────────────────────────────────┐  │
│  │  Tool Protocol (JSON Schema · Function Calling · Results)     │  │
│  └──────────────────────────┬────────────────────────────────────┘  │
├─────────────────────────────┼───────────────────────────────────────┤
│                     KNOWLEDGE LAYER                                 │
│                             │                                       │
│  ┌──────────────────────────▼────────────────────────────────────┐  │
│  │              RDF Triple Store (Drift / SQLite)                │  │
│  │                                                               │  │
│  │   ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐  │  │
│  │   │ Schema.org  │  │   kabuk:    │  │   FTS5 Search Index │  │  │
│  │   │  Vocabulary │  │  Namespace  │  │                     │  │  │
│  │   └─────────────┘  └─────────────┘  └─────────────────────┘  │  │
│  │                                                               │  │
│  │   ┌─────────────────┐  ┌──────────────────────────────────┐   │  │
│  │   │  Query Builder  │  │  Change Events (→ Riverpod)      │   │  │
│  │   └─────────────────┘  └──────────────────────────────────┘   │  │
│  └──────────────────────────┬────────────────────────────────────┘  │
├─────────────────────────────┼───────────────────────────────────────┤
│                    VIRTUAL OS LAYER                                  │
│                             │                                       │
│  ┌────────────┐ ┌──────────┴──┐ ┌────────────┐ ┌──────────────┐   │
│  │  Vault     │ │   Mesh      │ │   Media    │ │    Auth      │   │
│  │  Service   │ │   Service   │ │   Service  │ │    Service   │   │
│  └──────┬─────┘ └──────┬──────┘ └─────┬──────┘ └──────┬───────┘   │
│         │              │               │               │           │
│  ┌──────┴──────┐ ┌─────┴───────┐                                   │
│  │Notification │ │Presentation │                                   │
│  │  Service    │ │  Service    │                                   │
│  └──────┬──────┘ └──────┬──────┘                                   │
│         └───────┬───────┘                                          │
├─────────────────┼──────────────────────────────────────────────────┤
│                 │          PLATFORM LAYER                           │
│                 │                                                   │
│  ┌──────────────▼───────────────────────────────────────────────┐  │
│  │              Platform Channels / FFI                          │  │
│  └──┬───────────────┬────────────────────┬──────────────────────┘  │
│     │               │                    │                         │
│     ▼               ▼                    ▼                         │
│  ┌──────┐     ┌──────────┐        ┌───────────┐                   │
│  │Android│     │   iOS    │        │  Desktop  │                   │
│  │Kotlin │     │  Swift   │        │ Dart FFI  │                   │
│  └──────┘     └──────────┘        └───────────┘                   │
└─────────────────────────────────────────────────────────────────────┘
```

**Data flows downward** (user → presentation → agent → knowledge → services → platform). **Reactive updates flow upward** (knowledge store change → Riverpod stream → widget rebuild). Agents never access the platform layer directly — they go through Virtual OS service interfaces provided via `AgentContext`.

---

## 3. Layer Details

### 3.1 Presentation Layer

The presentation layer is what the user sees and touches. It is built entirely in Flutter with Material 3 design tokens, and it supports both statically defined views and dynamically generated RFW widgets.

#### 3.1.1 Four Main Views

| View | Purpose | Key Features |
|---|---|---|
| **Explore** | Content consumption and social feed | Reddit + Instagram + browser hybrid. Follow Reddit, 4chan, YouTube, RSS, and more. View web content natively. Nostr is the social layer — like/comment on any content using your Nostr identity. Other Nostr followers see those interactions. Nostr profiles viewable inline. |
| **Chat** | Primary messaging and AI assistant | Nostr-based messaging (text, media, contacts). AI chat defaults to the local on-device LLM. External LLM APIs (OpenAI, Ollama) are optional extensions that the local LLM can delegate to. MCP connects external tools to the local LLM. |
| **Vault** | Private data storage and quick capture | Camera/recorder/notes for fast data input. The local LLM auto-organizes and tags captured content. A private inbox to yourself — capture anything, AI handles organization. |
| **Apps** | Everything else | App launcher, bookmarks, settings, and any OS-level capabilities that the other three views don't cover. |

**Explore View** is the front page of the user's digital life — a Reddit + Instagram + Chrome hybrid. Users follow content sources (Reddit communities, 4chan boards, YouTube channels, RSS feeds, Nostr relays) and view them in a unified feed. Content can be viewed natively like a browser. Nostr is the social backbone: any content item — a Reddit post, an RSS article, a web page — can be liked, commented on, and shared through the user's Nostr identity. Those interactions are visible to Nostr followers. Nostr profiles are viewable inline just like Reddit profiles.

**Chat View** is the primary messaging app and AI assistant. Human messaging runs over Nostr (NIP-04/NIP-44 E2E encryption). The AI assistant defaults to the **local on-device LLM** — this is the primary AI, not a fallback. External LLM providers (OpenAI, Ollama, Anthropic) are optional extensions that the local model can delegate to for tasks beyond its capabilities. MCP (Model Context Protocol) servers connect external tools (filesystem, web search, calendar, etc.) to the local LLM, expanding its capabilities without replacing it.

**Vault View** is the user's private data store with a quick-capture front door. Camera, audio recorder, and note input are immediately accessible so the user can capture anything quickly. The local LLM then sorts, organizes, and tags the captured content automatically. Think of it as a private inbox to yourself — you throw things in, the AI makes sense of them later.

**Apps View** is the catch-all for everything the OS/super-app needs that the other three views don't cover: app launcher, bookmarks, settings entry points, installed agent tools, and widget repositories.

#### 3.1.2 Navigation

- **Bottom Navigation Bar:** Material 3 bar with four destinations (Explore, Chat, Vault, Apps). Two variants from Figma: default (labeled icons) and minimal (icons only).
- **View-specific Drawers:** Each view has its own drawer. Explore has feed selection. Chat has conversation list. Vault has recent captures. Apps has categories.
- **Top App Bar:** Contextual top bar with title, actions, and optional search. Adapts per view.
- **Pull-up Chat Sheet:** A persistent bottom sheet that can be swiped up from any view to access the chat quickly without navigating away. Enables "ask a quick question while browsing Explore."

#### 3.1.3 RFW Runtime

The RFW Runtime is the bridge between agent-generated widget descriptions and live Flutter widgets on screen.

```
Agent generates RfwTemplate
         │
         ▼
┌─────────────────────────────────┐
│          RFW Runtime            │
│                                 │
│  1. Resolve library reference   │──── Widget Registry (installed libraries)
│  2. Load widget definition      │
│  3. Bind DynamicContent         │──── Knowledge Store (reactive data)
│  4. Render widget tree          │──── Flutter widget tree
│  5. Route user interactions     │──── Back to agent via callbacks
│                                 │
└─────────────────────────────────┘
```

- **Widget Registry:** Stores installed widget libraries. Each library is a named collection (e.g., `kabuk:contacts`, `kabuk:notes`, `kabuk:calendar`). Built-in libraries ship with the app. Additional libraries can be installed from repositories.
- **Data Bindings:** Bridge knowledge store data into RFW's `DynamicContent`. Bindings are reactive — when a triple changes in the knowledge store, the Riverpod stream fires, `DynamicContent` updates, and the RFW widget rebuilds.
- **Interaction Routing:** User taps, form submissions, and other interactions inside RFW widgets are routed back to the originating agent as events.

---

### 3.2 Agent Layer

The agent layer is the brain of Kabuk. It receives user intent, reasons about it, and orchestrates actions across the knowledge store and services.

#### 3.2.1 Router Agent

The Router Agent is the single entry point for all user messages. It runs in the **main isolate** (not sandboxed) and performs:

1. **Input parsing** — Normalize the user message, extract attachments.
2. **Context loading** — Retrieve the last N messages from the conversation for continuity.
3. **Intent classification** — LLM call with descriptions of all registered agents. The model selects the best agent and optionally extracts parameters.
4. **Routing** — Dispatch the message to the selected domain agent via the Agent Runtime (isolate).
5. **Multi-turn tracking** — Maintain which agent is "active" in a conversation so follow-up messages route to the same agent without re-classification.

```
"remind me to buy milk tomorrow"
         │
         ▼
   Router Agent
         │
    LLM classifies → NoteAgent (intent: create_note)
         │
         ▼
   NoteAgent.process()
         │
    Tool: create_note(title: "Buy milk", due: tomorrow)
         │
         ▼
   ToolResult.compound([
     ToolResult.mutation(add reminder triples),
     ToolResult.widget(reminderCardTemplate, data),
   ])
```

#### 3.2.2 Domain Agents

Small, focused agents — each an expert in one domain:

| Agent | Domain | Key Tools |
|---|---|---|
| **NoteAgent** | Text notes, reminders | `create_note`, `edit_note`, `search_notes`, `list_notes`, `delete_note` |
| **FileAgent** | File management | `list_files`, `tag_file`, `get_metadata`, `create_smart_folder` |
| **MediaAgent** | Photos, video, audio | `capture_photo`, `record_video`, `transcode`, `extract_metadata`, `generate_thumbnail` |
| **CalendarAgent** | Events, scheduling | `create_event`, `list_events`, `find_free_time`, `set_reminder` |
| **ContactAgent** | People, relationships | `create_contact`, `search_contacts`, `get_contact`, `merge_duplicates` |
| **SearchAgent** | Cross-domain search | `search_all`, `search_by_type`, `semantic_search` |
| **ChatAgent** | Human messaging | `send_message`, `list_conversations`, `create_group`, `search_messages` |
| **SystemAgent** | Settings, status | `get_status`, `set_preference`, `list_agents`, `get_capabilities` |

**Agent properties:**
- **Stateless.** Agents hold no memory between invocations. All state lives in the knowledge store.
- **Isolated.** Each agent runs in a Dart isolate. No shared mutable state. Message passing via `SendPort`/`ReceivePort` with JSON serialization.
- **Least privilege.** Agents declare required capabilities. The runtime provides a scoped `AgentContext` — if an agent doesn't have `vault:write`, calling `vault.write()` throws `CapabilityDeniedException`.
- **Resource-limited.** 30s execution timeout, 64MB memory per isolate, max 10 LLM calls and 20 tool calls per invocation, max recursion depth of 3 for agent-to-agent calls.

#### 3.2.3 Tool Protocol

Agents expose strongly-typed tools via JSON Schema. The protocol is compatible with OpenAI and Anthropic function calling conventions.

```dart
class AgentTool {
  final String name;            // e.g., "create_note"
  final String description;     // Injected into LLM context
  final JsonSchema parameters;  // JSON Schema for validation
  final Future<ToolResult> Function(
    Map<String, dynamic> args,
    AgentContext ctx,
  ) execute;
}
```

**Tool Result types:**

| Variant | Use Case |
|---|---|
| `ToolResult.text(content)` | Plain text response displayed as chat message |
| `ToolResult.widget(template, data)` | RFW widget rendered inline in chat |
| `ToolResult.mutation(added, removed)` | Knowledge store triples to add/remove atomically |
| `ToolResult.compound(results)` | Combine multiple results (e.g., mutation + widget) |
| `ToolResult.error(message)` | Error displayed to user, does not crash agent |

The runtime validates parameters against the JSON Schema before calling `execute`. Results are type-safe via Dart sealed classes with exhaustive pattern matching.

#### 3.2.4 LLM Service

Abstracts LLM providers behind a uniform interface:

```dart
abstract class LlmService {
  Future<LlmResponse> complete(LlmRequest request);
  Stream<LlmToken> stream(LlmRequest request);
  Future<List<double>> embed(String text);
}
```

**Supported providers:**

| Provider | Transport | Use Case |
|---|---|---|
| OpenAI | HTTP API | Cloud, high capability |
| Anthropic | HTTP API | Cloud, high capability |
| Ollama | HTTP (local) | On-device, privacy-first |
| llama.cpp | `dart:ffi` | Fully embedded, offline |

The service handles prompt construction, token counting, budget enforcement, streaming, and provider fallback chains. API keys are stored securely via AuthService.

**Local LLM is the primary provider.** Kabuk defaults to the on-device model (llama.cpp via `dart:ffi` or Ollama). External cloud providers are optional extensions — the local model may delegate specific tasks to them, but privacy is preserved by default. The provider priority order is: local → Ollama → cloud (Anthropic/OpenAI).

#### 3.2.5 MCP (Model Context Protocol)

MCP connects the local LLM to external tools and data sources via a standardized protocol. The `AgentContext` exposes an `McpClient` that discovers and forwards tool calls to configured MCP servers:

```
Local LLM ──► AgentContext.mcpClient ──► MCP Server (filesystem, web, calendar…)
                                                │
                                         Tool results returned
                                         to LLM for synthesis
```

MCP servers run locally or over HTTP. The local LLM sees their tools alongside native agent tools, enabling open-ended capability extension without modifying Kabuk's agent code. See [docs/MCP.md](MCP.md) for the full integration plan.

#### 3.2.6 Agent-to-Agent Communication

Agents can invoke other agents' tools through the `AgentRuntime` reference in `AgentContext`. This enables composition:

- CalendarAgent calls ContactAgent to resolve attendee names.
- SearchAgent dispatches sub-queries to NoteAgent and FileAgent.
- ChatAgent calls ContactAgent to resolve person URIs.

Communication is via typed sealed classes (`AgentMessage` / `AgentResponse`). Recursion is depth-limited to 3 levels.

#### 3.2.6 RFW Generation

Agents return RFW templates as part of `ToolResult.widget()`. Two modes:

1. **Static templates.** Agent selects a pre-defined template from an installed widget library (e.g., `kabuk:contacts/ContactCard`) and provides data bindings.
2. **Dynamic generation.** The LLM generates a novel RFW template for data shapes that don't have a pre-built widget. The template is validated, sandboxed, and rendered. This enables the system to visualize *any* data type without deploying new code.

---

### 3.3 Knowledge Layer

The knowledge layer is the single source of truth for all structured data in Kabuk.

#### 3.3.1 RDF Triple Store

All data is stored as RDF triples:

```
(subject, predicate, object)
```

With an optional fourth component for graph/context:

```
(subject, predicate, object, graph)
```

**Examples:**

```
(kabuk:note/abc123,  rdf:type,           schema:NoteDigitalDocument)
(kabuk:note/abc123,  schema:name,        "Buy milk")
(kabuk:note/abc123,  schema:dateCreated, "2026-02-25T10:00:00Z")
(kabuk:note/abc123,  kabuk:tags,         "shopping")
(kabuk:person/def456, rdf:type,          schema:Person)
(kabuk:person/def456, schema:name,       "Alice")
(kabuk:person/def456, schema:email,      "alice@example.com")
```

#### 3.3.2 SQLite Backend via Drift

The triple store is backed by SQLite through Drift ORM. The core table:

```sql
CREATE TABLE triples (
  id        INTEGER PRIMARY KEY AUTOINCREMENT,
  subject   TEXT NOT NULL,
  predicate TEXT NOT NULL,
  object    TEXT NOT NULL,
  graph     TEXT DEFAULT 'default',
  datatype  TEXT,           -- xsd:string, xsd:dateTime, xsd:integer, etc.
  created   INTEGER NOT NULL, -- Unix timestamp
  modified  INTEGER NOT NULL
);

CREATE INDEX idx_spo ON triples(subject, predicate, object);
CREATE INDEX idx_pos ON triples(predicate, object, subject);
CREATE INDEX idx_osp ON triples(object, subject, predicate);
CREATE INDEX idx_graph ON triples(graph);
```

Three indexes (SPO, POS, OSP) ensure efficient lookups in any direction — by subject, by predicate+object, or by object.

#### 3.3.3 Vocabulary

**Schema.org** is the default vocabulary. Core types used:

| Type | Maps To |
|---|---|
| `schema:NoteDigitalDocument` | Notes, reminders |
| `schema:Person` | Contacts |
| `schema:Event` | Calendar events |
| `schema:MediaObject` | Generic media |
| `schema:ImageObject` | Photos, images |
| `schema:VideoObject` | Videos |
| `schema:AudioObject` | Audio recordings |
| `schema:Message` | Chat messages |
| `schema:Conversation` | Chat threads |
| `schema:Action` | Agent actions, tool calls |
| `schema:Place` | Locations |
| `schema:Organization` | Organizations |
| `schema:ContactPoint` | Phone, email, social handles |

**Custom `kabuk:` namespace** for system predicates:

| Predicate | Purpose |
|---|---|
| `kabuk:tags` | User-assigned tags |
| `kabuk:vaultHash` | Link to VaultService content hash |
| `kabuk:agentSource` | Which agent created this entity |
| `kabuk:capability` | Granted capabilities |
| `kabuk:preference` | User preferences |
| `kabuk:widgetLibrary` | Installed RFW widget library |
| `kabuk:encryptedWith` | Encryption key reference |
| `kabuk:syncStatus` | Sync state for mesh networking |

#### 3.3.4 Reactive via Riverpod

Every knowledge store mutation emits a `ChangeEvent`. Riverpod stream providers watch for changes matching specific patterns:

```dart
// Watch all notes — rebuilds when any note triple changes
final notesProvider = StreamProvider<List<Triple>>((ref) {
  return ref.read(knowledgeStoreProvider).watch(
    predicate: 'rdf:type',
    object: 'schema:NoteDigitalDocument',
  );
});

// Watch a specific entity — rebuilds when any of its triples change
final entityProvider = StreamProvider.family<List<Triple>, String>((ref, uri) {
  return ref.read(knowledgeStoreProvider).watchSubject(uri);
});
```

This connects the knowledge store directly to the UI: write a triple → stream fires → provider updates → widget rebuilds. No manual state synchronization.

#### 3.3.5 Full-Text Search (FTS5)

A companion FTS5 virtual table indexes text content for fast keyword search:

```sql
CREATE VIRTUAL TABLE triples_fts USING fts5(
  subject,
  object,
  content='triples',
  content_rowid='id'
);
```

The query builder exposes FTS via a `fullText()` method that joins against the FTS index.

#### 3.3.6 Query Builder

A fluent Dart API for constructing SPARQL-like queries without writing raw SQL:

```dart
final results = await knowledge.query()
  .where(predicate: 'rdf:type', object: 'schema:Person')
  .and(predicate: 'schema:name', matchesText: 'Ali*')
  .orderBy('schema:name')
  .limit(20)
  .execute();
```

Supports: subject/predicate/object matching, comparison operators for dates and numbers, full-text search, `ORDER BY`, `LIMIT`, `OFFSET`, and graph traversal (follow a predicate to discover connected entities).

#### 3.3.7 Import / Export

The knowledge store supports serialization in standard RDF formats:

- **Turtle** (`.ttl`) — human-readable, good for debugging
- **N-Triples** (`.nt`) — line-oriented, good for streaming
- **JSON-LD** (`.jsonld`) — web-compatible, good for interop

This enables backups, data portability, and interoperability with external tools.

#### 3.3.8 Encryption at Rest

All data in the SQLite database is encrypted via SQLCipher (or equivalent). The encryption key is derived from the user's auth credentials and stored in the platform secure storage (Android Keystore / Secure Enclave / OS keychain) via AuthService.

---

### 3.4 Virtual OS Layer

The Virtual OS layer abstracts every platform capability behind clean Dart interfaces. Business logic and agents never touch platform APIs directly. Each service is defined as an abstract interface in `lib/services/` with platform-specific implementations in `lib/platform/`.

**Design principles:**
- Interface in `lib/services/`, implementation in `lib/platform/`.
- Every service exposed as a Riverpod provider (swappable for testing).
- No platform imports (`dart:io`, `dart:html`, `dart:ffi`) outside `lib/platform/`.
- Async by default — all methods return `Future` or `Stream`.
- Graceful degradation — unsupported capabilities return `ServiceError.notSupported`.
- Feature detection via `isSupported` flags and `capabilities` getters.
- Agents access services only through `AgentContext` — never import providers directly.

#### 3.4.1 VaultService — Encrypted File Storage

Secure, tag-based, content-addressed file storage. Every piece of user data (notes, photos, audio, documents) flows through VaultService.

| Feature | Description |
|---|---|
| Content-addressing | SHA-256 hashing provides deduplication and integrity |
| Encryption | AES-256-GCM by default, key managed by AuthService |
| Tag-based organization | Tags map naturally to RDF triples |
| Streaming | Support for large files without full memory load |
| Metadata extraction | EXIF, ID3, document properties |
| Smart folders | Virtual folders defined by tag/metadata queries |

**Platform mapping:**

| | Android | iOS | Desktop |
|---|---|---|---|
| Storage | App internal storage | App sandbox Documents | `~/.kabuk/vault/` |
| Encryption | Android Keystore + Tink | CryptoKit | libsodium |
| File access | Storage Access Framework | UIDocumentPicker | Native file dialog |

#### 3.4.2 MeshService — Connection-Agnostic Networking

Peer-to-peer networking abstracted over multiple transports.

| Feature | Description |
|---|---|
| Transport-agnostic | BLE, WiFi Direct, WebSocket, relay server |
| Stream API | Bidirectional data streams between peers |
| Peer discovery | mDNS, BLE advertising, relay-assisted |
| Connection upgrade | Start on BLE, upgrade to WiFi Direct for throughput |
| Sync protocol | CRDT-based triple sync for knowledge store |

```
Device A                        Device B
   │                               │
   │──── Peer Discovery (BLE) ────►│
   │◄─── Handshake + Key Exchange ─│
   │                               │
   │──── Data Stream (WiFi Direct)─│
   │◄─── Triple Sync (CRDT) ──────│
   │                               │
```

#### 3.4.3 MediaService — Capture & Playback

Camera, microphone, video, and audio processing.

| Feature | Description |
|---|---|
| Camera | Photo, video capture via platform APIs |
| Audio | Recording, playback |
| Video | Playback, streaming |
| Processing | Thumbnail generation, transcoding |
| Metadata extraction | EXIF, duration, resolution |

#### 3.4.4 AuthService — Key Management & Crypto

Unified cryptographic operations and identity management.

| Feature | Description |
|---|---|
| Key management | Platform keystore (Keystore/Secure Enclave/OS keychain) |
| Encryption | AES-256-GCM, XChaCha20-Poly1305 |
| Signing | Ed25519 for identity and message signing |
| Key derivation | Argon2id from user credentials |
| JWT | Token generation and verification |
| Biometrics | Fingerprint/FaceID gate for sensitive operations |

#### 3.4.5 NotificationService — Unified Notification Pipeline

| Feature | Description |
|---|---|
| Local notifications | Scheduled, immediate, recurring |
| Push notifications | FCM (Android), APNs (iOS) |
| Agent-routed | Notifications can originate from any agent |
| Action buttons | Tapping routes back to the originating agent |
| Do-not-disturb | Respects platform DND settings |

#### 3.4.6 PresentationService — Display Management

| Feature | Description |
|---|---|
| Display info | Screen size, pixel ratio, safe areas |
| Casting | Chromecast, AirPlay support |
| Window management | Multi-window on desktop, split-screen |
| External display | Presentation API for secondary screens |

---

### 3.5 Platform Layer

The platform layer contains native code that implements Virtual OS service interfaces.

```
lib/platform/
├── android/     ← Kotlin implementations, MethodChannel handlers
├── ios/         ← Swift implementations, MethodChannel handlers
└── desktop/     ← Dart FFI bindings to native libraries
```

**Platform channels** bridge Dart to native code. Each Virtual OS service has a corresponding channel:

| Channel | Android (Kotlin) | iOS (Swift) | Desktop |
|---|---|---|---|
| `kabuk/vault` | Internal storage + Tink | App sandbox + CryptoKit | File system + libsodium |
| `kabuk/mesh` | Nearby Connections API | MultipeerConnectivity | WebSocket + mDNS |
| `kabuk/media` | CameraX + MediaCodec | AVFoundation | FFmpeg via FFI |
| `kabuk/auth` | Android Keystore | Secure Enclave | OS keychain + libsodium |
| `kabuk/notify` | NotificationManager + FCM | UNUserNotificationCenter + APNs | Desktop notifications |
| `kabuk/presentation` | MediaRouter | AVKit | Window manager |

**Feature detection:** Each implementation exposes capabilities so the Dart layer can adapt. An agent asking for BLE on a desktop without a Bluetooth adapter gets `ServiceError.notSupported` gracefully.

---

## 4. Data Flow Examples

### 4.1 "Remind me to buy milk tomorrow"

```
┌──────┐     ┌────────────┐     ┌────────────┐     ┌──────────────┐     ┌──────────┐
│ User │────►│   Chat UI  │────►│   Router   │────►│  NoteAgent   │────►│Knowledge │
│      │     │            │     │   Agent    │     │  (isolate)   │     │  Store   │
└──────┘     └────────────┘     └────────────┘     └──────────────┘     └──────────┘
                                                          │                   │
Step 1: User types message in Chat View                   │                   │
Step 2: Message sent to Router Agent                      │                   │
Step 3: Router calls LLM → classifies intent as           │                   │
        "note:create_note" → routes to NoteAgent          │                   │
Step 4: NoteAgent calls LLM to extract parameters:        │                   │
        title="Buy milk", due=2026-02-26                  │                   │
Step 5: NoteAgent returns ToolResult.compound([           │                   │
          ToolResult.mutation(add triples) ─────────────────────────────────►│
          ToolResult.widget(reminderCard, data)           │                   │
        ])                                                │                   │
Step 6: Knowledge store emits ChangeEvent ◄───────────────────────────────── │
Step 7: Explore View's notesProvider fires ─► reminder card appears on       │
        dashboard                                                            │
```

**Triples written:**
```
(kabuk:note/n1,  rdf:type,            schema:NoteDigitalDocument)
(kabuk:note/n1,  schema:name,         "Buy milk")
(kabuk:note/n1,  schema:dateCreated,  "2026-02-25T14:00:00Z")
(kabuk:note/n1,  kabuk:dueDate,       "2026-02-26T00:00:00Z")
(kabuk:note/n1,  kabuk:agentSource,   "note")
(kabuk:note/n1,  kabuk:tags,          "reminder")
```

### 4.2 User Captures Photo in Vault View

```
┌──────┐     ┌────────────┐     ┌────────────┐     ┌──────────────┐     ┌──────────┐
│ User │────►│  Vault UI  │────►│  Media     │────►│  MediaAgent  │────►│Knowledge │
│      │     │ (Camera)   │     │  Service   │     │  (isolate)   │     │  Store   │
└──────┘     └────────────┘     └────────────┘     └──────────────┘     └──────────┘
                                      │                   │                   │
                                      ▼                   │                   │
                                ┌────────────┐            │                   │
                                │   Vault    │◄───────────┘                   │
                                │  Service   │                                │
                                └────────────┘                                │
                                                                              │
Step 1: User taps capture in Vault View (Photo mode)                          │
Step 2: MediaService captures photo via platform camera API                   │
Step 3: MediaAgent receives the raw image bytes                               │
Step 4: MediaAgent extracts EXIF metadata (date, location, camera)            │
Step 5: MediaAgent generates thumbnail                                        │
Step 6: VaultService stores encrypted original + thumbnail                    │
Step 7: MediaAgent writes metadata triples to knowledge store ──────────────►│
Step 8: Knowledge store emits ChangeEvent                                     │
Step 9: Explore timeline shows photo card via ImageObject query               │
```

**Triples written:**
```
(kabuk:media/m1,  rdf:type,              schema:ImageObject)
(kabuk:media/m1,  schema:name,           "IMG_20260225.jpg")
(kabuk:media/m1,  schema:dateCreated,    "2026-02-25T14:30:00Z")
(kabuk:media/m1,  schema:contentSize,    "4200000")
(kabuk:media/m1,  schema:encodingFormat, "image/jpeg")
(kabuk:media/m1,  schema:width,          "4032")
(kabuk:media/m1,  schema:height,         "3024")
(kabuk:media/m1,  kabuk:vaultHash,       "sha256:abc123...")
(kabuk:media/m1,  kabuk:thumbnailHash,   "sha256:def456...")
(kabuk:media/m1,  schema:contentLocation, kabuk:place/p1)
```

### 4.3 Agent Generates Custom RFW Widget

```
┌──────┐     ┌────────────┐     ┌──────────────┐     ┌────────────┐     ┌──────────┐
│ User │────►│   Chat UI  │────►│  SearchAgent │────►│ LLM Service│     │Knowledge │
│      │     │            │     │  (isolate)   │     │            │     │  Store   │
└──────┘     └────────────┘     └──────────────┘     └────────────┘     └──────────┘
   │                                   │                    │                 │
   │  "Show me a summary of my        │                    │                 │
   │   week with exercise stats"       │                    │                 │
   │                                   │                    │                 │
   │  Step 1:  SearchAgent queries ────────────────────────────────────────► │
   │           knowledge store for                          │                 │
   │           events, activities, exercise data            │                 │
   │                                   │                    │                 │
   │  Step 2:  No built-in widget for  │                    │                 │
   │           "weekly exercise         │                    │                 │
   │           summary" exists          │                    │                 │
   │                                   │                    │                 │
   │  Step 3:  SearchAgent asks LLM ──────────────────────►│                 │
   │           to generate an RFW       │                    │                 │
   │           template for this       │                    │                 │
   │           data shape              │                    │                 │
   │                                   │                    │                 │
   │  Step 4:  LLM returns RFW template (validated)         │                 │
   │                                   │                    │                 │
   │  Step 5:  ToolResult.widget(      │                    │                 │
   │             generatedTemplate,    │                    │                 │
   │             weeklyExerciseData    │                    │                 │
   │           )                       │                    │                 │
   │                                   │                    │                 │
   │  ◄──── RFW Runtime renders the ───┘                    │                 │
   │         custom weekly summary                          │                 │
   │         widget inline in chat                          │                 │
```

The key insight: the LLM generated a **novel widget template** that didn't exist before. The RFW Runtime validates it (no code execution, only declared widgets and data bindings), then renders it. This makes the UI infinitely extensible without deploying new code.

---

## 5. Key Design Decisions

### Why RDF over Relational?

A relational database requires a fixed schema. Every new entity type means a new table, new migrations, new queries. Kabuk doesn't know ahead of time what data types it will need — agents can introduce new concepts at any time.

RDF's triple model is schema-flexible. A `(subject, predicate, object)` triple can represent any relationship. Adding a new property to an entity is just adding a row — no migration needed. Schema.org provides a shared vocabulary so entities remain interoperable. Cross-entity queries ("find all things tagged 'work' that were created this week") are natural in a triple store but require complex JOINs in a relational model.

The tradeoff: lower query performance for structured aggregations. This is mitigated by SQLite indexes (SPO, POS, OSP) and materialized views for common patterns.

### Why RFW for Dynamic UI?

Traditional approaches (WebView, server-driven UI with JSON) either sacrifice performance (WebView) or require code deployment for new layouts (native JSON-to-widget mappers).

RFW is Flutter-native — widgets rendered by RFW are real Flutter widgets with full performance. RFW templates are declarative and sandboxed — they cannot execute arbitrary code, only reference declared widgets and data bindings. This makes them safe to receive from LLMs or external sources.

The combination of RFW + LLM generation means the UI can adapt to any data shape without human intervention. A new data type appears in the knowledge store? The agent asks the LLM to generate an appropriate widget template.

### Why Isolates for Agents?

Agents execute LLM-generated tool calls. Even with validation, running untrusted logic in the main isolate risks hangs, memory leaks, and security violations. Dart isolates provide:

- **Memory isolation.** An agent cannot read or corrupt main-isolate state.
- **Timeout enforcement.** A hung isolate can be killed without affecting the app.
- **Concurrency.** Multiple agents run in parallel.
- **Resource limits.** Each isolate has bounded memory (64MB).

The cost is serialization overhead for message passing. This is acceptable — `AgentMessage` and `AgentResponse` are small JSON payloads, and the LLM call dominates latency.

### Why Chat-First UX?

Traditional apps require users to learn navigation hierarchies, button layouts, and mental models for each feature. Chat inverts this — the user states intent in natural language, and the system figures out how to fulfill it.

Chat-first doesn't mean chat-only. The four views (Explore, Chat, Vault, Apps) provide visual interfaces for browsing, capturing, and extending. But the chat is always one swipe away, and it's always the fastest path to any capability.

### Why a Virtual OS Layer?

Flutter already abstracts rendering. Kabuk extends this principle to *all* platform capabilities. Without the Virtual OS layer:

- Agent code would be littered with `if (Platform.isAndroid)` checks.
- Testing would require platform-specific mocks for every test.
- Adding a new platform (e.g., web) would require touching agent logic.

With the Virtual OS layer, agents code against stable interfaces. Platform specifics are isolated behind Riverpod providers. Testing uses mock implementations. New platforms require only new `lib/platform/` implementations.

---

## 6. Security Model

### 6.1 Data at Rest

All user data is encrypted:

- **Knowledge store:** SQLite database encrypted via SQLCipher. Key derived from user credentials via Argon2id, stored in platform secure storage.
- **Vault files:** AES-256-GCM encryption by default. Each file encrypted with a unique data key. Data keys wrapped with a master key from platform keystore.

### 6.2 Agent Sandboxing

Agents run in Dart isolates with a scoped `AgentContext`:

```
┌─────────────────────────────────────────────┐
│                Main Isolate                  │
│                                              │
│   ┌──────────────────────────────────────┐   │
│   │ AgentRuntime (manages isolate pool)  │   │
│   └──────────┬───────────────────────────┘   │
│              │                               │
│   ┌──────────▼───────────────────────────┐   │
│   │  Capability Enforcement Proxy        │   │
│   │  (filters AgentContext per agent)    │   │
│   └──────────┬───────────────────────────┘   │
│              │ SendPort (serialized JSON)     │
├──────────────┼───────────────────────────────┤
│              ▼                               │
│   ┌────────────────────────┐                 │
│   │    Agent Isolate       │                 │
│   │  64MB memory limit     │                 │
│   │  30s execution timeout │                 │
│   │  No direct I/O         │                 │
│   │  No platform imports   │                 │
│   └────────────────────────┘                 │
└─────────────────────────────────────────────┘
```

- Agents **cannot** access platform APIs directly — only through `AgentContext`.
- The `AgentContext` is **scoped** per agent based on declared capabilities.
- Unauthorized operations throw `CapabilityDeniedException` at the proxy level.

### 6.3 Capability-Based Authorization

```
Agent declares: requiredCapabilities = ['knowledge:read', 'knowledge:write', 'vault:read']
User grants: [all requested]
Runtime provides: AgentContext with only those services
Agent calls vault.write() → CapabilityDeniedException (not granted)
```

Capabilities are stored in the knowledge store as triples. Users can review and revoke at any time via SystemAgent.

### 6.4 Inter-Device Communication

- **E2E encryption** for all mesh communication using X25519 key exchange + XChaCha20-Poly1305.
- **Identity verification** via Ed25519 key pairs. Public keys exchanged out-of-band (QR code, NFC).
- **Forward secrecy** via ephemeral session keys.

### 6.5 RFW Widget Sandboxing

RFW widgets are **declarative only**:

- No Dart code execution — only reference to declared widget types and data bindings.
- Data flow is explicit: `DynamicContent` provides data in, callbacks provide events out.
- Widget libraries declare their interaction contracts (what data they read, what events they emit).
- Templates received from LLMs or external sources are validated before rendering.

---

## 7. Technology Stack

| Layer | Technology | Purpose |
|---|---|---|
| UI Framework | Flutter 3.x + Material 3 | Cross-platform UI |
| State Management | Riverpod | Reactive state, dependency injection, provider scoping |
| Database | Drift (SQLite) + SQLCipher | RDF triple store with encryption at rest |
| Data Classes | Freezed + json_serializable | Immutable models, sealed classes, JSON serialization |
| Dynamic UI | Remote Flutter Widgets (RFW) | Agent-generated widgets at runtime |
| Networking | gRPC-Dart, HTTP, WebSocket | LLM APIs, mesh relay, sync |
| P2P | Nearby Connections, MultipeerConnectivity, BLE | Local mesh networking |
| Crypto | libsodium / platform keystore | AES-256-GCM, Ed25519, X25519, Argon2id |
| IDs | UUID v7 | Time-sortable unique identifiers |
| Code Generation | build_runner | Freezed, Drift, json_serializable, Riverpod codegen |
| Testing | mocktail | Mock-based testing with null safety |
| CI | GitHub Actions | Analyze, test, build |

---

## 8. File Organization

```
lib/
├── main.dart                       # App entry point, ProviderScope
├── app.dart                        # MaterialApp, theme, routing
│
├── agents/                         # Agent layer
│   ├── base.dart                   # BaseAgent abstract class
│   ├── router.dart                 # Router Agent (intent → domain agent)
│   ├── runtime.dart                # AgentRuntime (isolate pool, lifecycle)
│   ├── context.dart                # AgentContext (scoped service bundle)
│   ├── tools/                      # Tool protocol
│   │   ├── tool.dart               # AgentTool class, JsonSchema, ToolParam
│   │   └── result.dart             # ToolResult sealed class hierarchy
│   └── domains/                    # Domain agents
│       ├── note_agent.dart         # NoteAgent — notes, reminders
│       ├── file_agent.dart         # FileAgent — file management
│       ├── media_agent.dart        # MediaAgent — photos, video, audio
│       ├── calendar_agent.dart     # CalendarAgent — events, scheduling
│       ├── contact_agent.dart      # ContactAgent — people, relationships
│       ├── search_agent.dart       # SearchAgent — cross-domain search
│       ├── chat_agent.dart         # ChatAgent — human messaging
│       └── system_agent.dart       # SystemAgent — settings, status
│
├── knowledge/                      # Knowledge layer
│   ├── store.dart                  # KnowledgeStore interface + Drift impl
│   ├── query.dart                  # QueryBuilder fluent API
│   ├── triple.dart                 # Triple Freezed data class
│   ├── change.dart                 # ChangeEvent stream types
│   ├── namespaces.dart             # Namespace constants (rdf:, schema:, kabuk:)
│   ├── serialization.dart          # Turtle, N-Triples, JSON-LD import/export
│   └── types/                      # Schema.org type helpers
│       ├── note.dart               # NoteDigitalDocument helpers
│       ├── person.dart             # Person helpers
│       ├── event.dart              # Event helpers
│       ├── media.dart              # MediaObject/Image/Video/Audio helpers
│       ├── message.dart            # Message helpers
│       ├── conversation.dart       # Conversation helpers
│       ├── action.dart             # Action helpers
│       └── place.dart              # Place helpers
│
├── services/                       # Virtual OS interfaces
│   ├── vault.dart                  # VaultService — encrypted file storage
│   ├── mesh.dart                   # MeshService — P2P networking
│   ├── media.dart                  # MediaService — capture & playback
│   ├── auth.dart                   # AuthService — keys, crypto, identity
│   ├── notification.dart           # NotificationService — unified alerts
│   └── presentation.dart           # PresentationService — display management
│
├── platform/                       # Platform implementations
│   ├── android/                    # Kotlin-backed implementations
│   │   ├── android_vault.dart
│   │   ├── android_mesh.dart
│   │   ├── android_media.dart
│   │   ├── android_auth.dart
│   │   ├── android_notification.dart
│   │   └── android_presentation.dart
│   ├── ios/                        # Swift-backed implementations
│   │   ├── ios_vault.dart
│   │   ├── ios_mesh.dart
│   │   ├── ios_media.dart
│   │   ├── ios_auth.dart
│   │   ├── ios_notification.dart
│   │   └── ios_presentation.dart
│   └── desktop/                    # FFI-backed implementations
│       ├── desktop_vault.dart
│       ├── desktop_mesh.dart
│       ├── desktop_media.dart
│       ├── desktop_auth.dart
│       ├── desktop_notification.dart
│       └── desktop_presentation.dart
│
├── rfw/                            # RFW dynamic UI
│   ├── runtime.dart                # RFW rendering environment
│   ├── registry.dart               # Widget library registry
│   ├── bindings.dart               # Knowledge store → DynamicContent bridge
│   └── libraries/                  # Built-in widget libraries
│       ├── core.dart               # Core widgets (cards, lists, forms)
│       ├── contacts.dart           # Contact card, contact list
│       ├── notes.dart              # Note card, note editor
│       ├── media.dart              # Image card, video player, audio player
│       ├── calendar.dart           # Event card, week view, month view
│       └── chat.dart               # Message bubble, conversation list
│
├── ui/                             # Presentation layer
│   ├── shell.dart                  # App shell — bottom nav, drawers, top bar
│   ├── theme.dart                  # ThemeData, color scheme, typography
│   ├── explore/                    # Explore view
│   │   ├── explore_view.dart       # Main Explore scaffold
│   │   ├── explore_drawer.dart     # Feed selector (Timeline, News, etc.)
│   │   ├── timeline.dart           # Timeline scroll view
│   │   └── dashboard_card.dart     # Individual dashboard cards
│   ├── chat/                       # Chat view
│   │   ├── chat_view.dart          # Main Chat scaffold
│   │   ├── chat_drawer.dart        # Conversation list drawer
│   │   ├── chat_sheet.dart         # Pull-up bottom sheet (from any view)
│   │   ├── message_bubble.dart     # Message rendering (text, markdown, media)
│   │   ├── message_input.dart      # Input bar with actions
│   │   └── tool_call_display.dart  # Tool call progress/results
│   ├── vault/                      # Vault view (private data storage + quick capture)
│   │   ├── vault_view.dart         # Main Vault scaffold
│   │   ├── camera_capture.dart     # Photo/Video capture
│   │   ├── audio_capture.dart      # Audio recording
│   │   └── note_editor.dart        # Quick note creation
│   ├── apps/                       # Apps view
│   │   ├── apps_view.dart          # Widget catalog scaffold
│   │   └── app_card.dart           # Mini-app card
│   └── shared/                     # Shared widgets
│       ├── rfw_host.dart           # RFW rendering host widget
│       ├── entity_card.dart        # Generic knowledge store entity card
│       ├── loading.dart            # Loading indicators
│       └── error.dart              # Error display widgets
│
├── config/                         # App configuration
│   ├── result.dart                 # Result<T> sealed class (Success/Failure)
│   ├── errors.dart                 # ServiceError sealed class hierarchy
│   ├── constants.dart              # App-wide constants
│   └── providers.dart              # Top-level Riverpod providers
│
└── llm/                            # LLM service
    ├── service.dart                # LlmService interface
    ├── models.dart                 # LlmMessage, LlmOptions, LlmResponse
    ├── providers/                  # Provider implementations
    │   ├── openai.dart             # OpenAI API
    │   ├── anthropic.dart          # Anthropic API
    │   ├── ollama.dart             # Ollama (local HTTP)
    │   └── llamacpp.dart           # llama.cpp via dart:ffi
    └── prompt.dart                 # Prompt templates, token counting
```

```
test/
├── agents/                         # Agent unit tests
│   ├── router_test.dart
│   ├── runtime_test.dart
│   └── domains/
│       ├── note_agent_test.dart
│       ├── file_agent_test.dart
│       └── ...
├── knowledge/                      # Knowledge store tests
│   ├── store_test.dart
│   ├── query_test.dart
│   └── serialization_test.dart
├── services/                       # Service interface tests (mock impls)
│   ├── vault_test.dart
│   ├── mesh_test.dart
│   └── ...
├── rfw/                            # RFW runtime tests
│   ├── runtime_test.dart
│   ├── registry_test.dart
│   └── bindings_test.dart
└── ui/                             # Widget tests
    ├── shell_test.dart
    ├── chat/
    │   ├── message_bubble_test.dart
    │   └── ...
    └── ...
```

---

*This document is the primary architecture reference for Kabuk. For detailed design of individual subsystems, see:*

- [AGENTS.md](AGENTS.md) — Agent system design, tool protocol, router, isolate runtime
- [CHAT_PROTOCOL.md](CHAT_PROTOCOL.md) — Message format, conversation management, human messaging
- [VIRTUAL_OS.md](VIRTUAL_OS.md) — Service interfaces, platform mapping, lifecycle
- [RFW.md](RFW.md) — RFW runtime, widget libraries, data bindings, LLM generation
- [ROADMAP.md](ROADMAP.md) — Phased implementation plan with task lists
