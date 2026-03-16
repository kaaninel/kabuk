# Kabuk — Copilot Instructions

## Project Overview

Kabuk is an agent-centric personal OS shell built in Flutter/Dart. It replaces the traditional app-grid paradigm with a conversational, data-driven interface where small, specialized AI agents act on the user's behalf. Users interact primarily through chat — agents understand intent, query a unified knowledge store, and render rich UI on the fly using Remote Flutter Widgets (RFW).

**Core philosophy:**

- **Agent-first** — Chat is the universal input. Every user action can be expressed as a conversation with a specialized agent.
- **Data-driven** — A single RDF knowledge store (Schema.org vocabulary, SQLite/Drift-backed) is the source of truth. UI reacts to data, not the other way around.
- **Privacy-focused** — All data is encrypted at rest, stored locally, and never leaves the device without explicit consent.
- **Offline-first** — Every feature works without network connectivity. Cloud sync is additive, never required.
- **Virtual OS abstraction** — Platform capabilities are abstracted behind Dart interfaces ("the Flutter way"), enabling true cross-platform behavior without platform-specific business logic.

## Architecture

Kabuk follows a strict layered architecture. Dependencies flow downward only.

```
┌─────────────────────────────────────────────┐
│           Presentation Layer                │
│  Flutter UI · RFW Runtime · 4 Main Views    │
│  (Explore / Chat / Create / Apps)           │
├─────────────────────────────────────────────┤
│             Agent Layer                     │
│  Router Agent · Domain Agents · LLM Service │
│  Tool-Calling Protocol (JSON)               │
├─────────────────────────────────────────────┤
│           Knowledge Layer                   │
│  RDF Triple Store · Schema.org Types        │
│  Drift/SQLite · Query Builder               │
├─────────────────────────────────────────────┤
│          Virtual OS Layer                   │
│  Vault · Mesh · Media · Auth                │
│  Notification · Presentation                │
├─────────────────────────────────────────────┤
│           Platform Layer                    │
│  Platform Channels · Native Implementations │
│  Android / iOS / Desktop                    │
└─────────────────────────────────────────────┘
```

- **Presentation Layer** — Flutter widgets and RFW runtime. Four main views: Explore (discovery feed), Chat (agent conversations), Create (content authoring), Apps (installed micro-apps). RFW allows agents to generate UI dynamically without app updates.
- **Agent Layer** — A router agent dispatches user messages to domain-specific agents. Each agent declares typed tools. Agents run in Dart isolates for sandboxing. LLM integration is abstracted behind `LlmService` so the provider can be swapped.
- **Knowledge Layer** — All persistent data lives as RDF triples (subject, predicate, object) using Schema.org as the default vocabulary. Backed by SQLite via Drift. Queries use a builder pattern. Mutations emit change events that Riverpod providers watch for reactive UI.
- **Virtual OS Layer** — Abstract service interfaces (Vault for secrets/encryption, Mesh for networking/sync, Media for camera/files/audio, Auth for identity, Notification for alerts, Presentation for display/haptics). Agents access these only through `AgentContext`.
- **Platform Layer** — Concrete implementations of Virtual OS services per platform. This is the only layer that may import `dart:io`, platform channels, or native plugin packages.

## Coding Conventions

- **Dart 3.x** with null safety, pattern matching, and sealed classes.
- **Riverpod** for all state management and dependency injection.
- **Drift** for SQLite persistence.
- **Freezed** for immutable data classes.
- **Sealed classes** for agent messages, tool results, and service errors — enabling exhaustive switch expressions.
- Abstract interfaces live in `lib/services/`; platform implementations in `lib/platform/`.
- Agents live in `lib/agents/` — each extends `BaseAgent` and declares tools as `AgentTool` objects.
- Knowledge types in `lib/knowledge/` map to Schema.org vocabulary.
- UI code in `lib/ui/`, organized by the four main views.
- RFW infrastructure in `lib/rfw/`.
- All services are injectable via Riverpod providers.
- Prefer **composition over inheritance**.
- Use **extension methods** for utility functions.
- All public APIs must have `///` doc comments.
- Tests in `test/` mirror the `lib/` directory structure.
- Use **mocktail** for mocking in tests.

## File Organization

```
lib/
  main.dart                    # Entry point, provider scope setup
  app.dart                     # MaterialApp / root widget configuration
  agents/
    router.dart                # Router agent — dispatches to domain agents
    base.dart                  # BaseAgent abstract class, AgentTool definition
    runtime.dart               # Isolate-based agent runtime, AgentContext
    tools/                     # Shared tool definitions and utilities
    domains/                   # Domain-specific agent implementations
  knowledge/
    store.dart                 # KnowledgeStore — triple CRUD, mutation events
    query.dart                 # Query builder for RDF triples
    types/                     # Schema.org type constants and helpers
  services/
    vault.dart                 # Secrets, encryption, secure storage
    mesh.dart                  # Networking, sync, peer discovery
    media.dart                 # Camera, files, audio, gallery
    notification.dart          # Local/push notifications
    auth.dart                  # Identity, biometrics, accounts
    presentation.dart          # Display, haptics, system UI
  platform/
    android/                   # Android-specific service implementations
    ios/                       # iOS-specific service implementations
    desktop/                   # macOS/Linux/Windows implementations
  rfw/
    runtime.dart               # RFW widget rendering engine
    registry.dart              # RfwRegistry — custom widget libraries
    bindings.dart              # DynamicContent bindings to knowledge store
  ui/
    shell.dart                 # App shell — navigation, bottom bar, scaffold
    explore/                   # Explore view (discovery feed)
    chat/                      # Chat view (agent conversations)
    create/                    # Create view (content authoring)
    apps/                      # Apps view (micro-app launcher)
    shared/                    # Shared widgets, themes, design tokens
  config/                      # App configuration, constants, feature flags
test/                          # Mirrors lib/ structure
```

## Agent Development Guidelines

- **Extend `BaseAgent`** and declare tools as `AgentTool` objects with name, description, JSON Schema parameters, and an execute function.
- **Agents are stateless** — all persistent state resides in the knowledge store. Between invocations, agents rely solely on `AgentContext` to access data and services.
- **Typed messages** — Use sealed classes for all message types (`AgentRequest`, `AgentResponse`, `ToolCall`, `ToolResult`). This enables exhaustive pattern matching.
- **Tool results must be JSON-serializable.** Agents can also return RFW templates for rich UI rendering as part of tool results.
- **`AgentContext`** provides access to `KnowledgeStore`, all Virtual OS services, and `LlmService`. Never access globals or singletons.
- **LLM calls go through `LlmService`** — this abstracts the underlying provider (OpenAI, Anthropic, local model, etc.) and handles rate limiting, retries, and cost tracking.
- **Isolate execution** — Agents run in Dart isolates for sandboxing and parallelism. Keep agent code free of UI dependencies.

## RFW Guidelines

- **All RFW widgets must be stateless** — this is a fundamental RFW constraint. No `StatefulWidget` equivalents exist.
- **Data binding** — Use `DynamicContent` populated from the knowledge store. Widgets declare what Schema.org types they need; the runtime resolves and binds the data.
- **Custom widget libraries** — Register custom widgets in `RfwRegistry`. Each library has a namespace to avoid collisions.
- **Agent-generated UI** — Agents can include RFW template text as part of tool results. The chat view renders these inline.
- **Schema.org type dependencies** — Every RFW widget should declare which Schema.org types it can render so the system can match data to widgets automatically.
- **LLM-generated RFW** — The LLM can generate novel RFW templates for data types that don't have pre-built widgets. Always validate these templates before rendering.

## Knowledge Store Guidelines

- **All data is stored as RDF triples** — `(subject, predicate, object)`. Subjects and predicates are URIs; objects can be URIs or literals.
- **Default vocabulary: Schema.org** — Use standard Schema.org types and properties wherever possible (e.g., `schema:Person`, `schema:name`, `schema:Event`).
- **Custom predicates** use the `kabuk:` prefix (e.g., `kabuk:agentMemory`, `kabuk:lastAccessed`).
- **Queries use the builder pattern** — never write raw SQL outside of Drift table definitions. Use `KnowledgeStore.query()` to construct type-safe queries.
- **All mutations go through `KnowledgeStore.mutate()`** — this ensures change events are emitted, enabling reactive UI updates through Riverpod providers.
- **Reactive binding** — Riverpod providers watch query patterns. When matching triples change, the UI rebuilds automatically.
- **Encryption at rest** — The `VaultService` handles encrypting the knowledge store's underlying SQLite database.

## Virtual OS Service Pattern

1. **Define an abstract interface** in `lib/services/` with pure Dart types (no platform imports).
2. **Create platform implementations** in `lib/platform/{android,ios,desktop}/`.
3. **Wire up via Riverpod** — a provider selects the correct implementation based on the current platform.
4. **Never import `dart:io` or platform channel packages** outside of `lib/platform/`. This is a hard rule.
5. **All methods return `Future` or `Stream`** — services are inherently asynchronous.
6. **Graceful degradation** — if a platform doesn't support a capability, return a meaningful error or no-op rather than crashing.
7. **Agent access** — Agents interact with services exclusively through `AgentContext`, never by importing service files directly.

## Testing

- **Unit tests for all agents** — mock `KnowledgeStore`, `LlmService`, and any Virtual OS services using mocktail. Verify tool execution logic and message routing.
- **Unit tests for knowledge store queries** — test the query builder against an in-memory SQLite database.
- **Widget tests for UI components** — test individual widgets and views with mocked providers.
- **Integration tests** — verify end-to-end flows: agent receives message → queries/mutates knowledge store → UI updates reactively.
- **Use mocktail** for all mocking. Declare mocks as `class MockKnowledgeStore extends Mock implements KnowledgeStore {}`.

## Key Principles

1. **Privacy first** — All data encrypted at rest, stored locally by default. No telemetry without consent. No cloud dependency.
2. **Offline first** — Every feature works without network connectivity. Sync is opportunistic and additive.
3. **Agent first** — Chat is the universal input. If a user can describe it, an agent should be able to do it.
4. **Data driven** — Widgets react to knowledge store changes. UI is a projection of data, not the source of it.
5. **Platform agnostic** — Virtual OS abstractions everywhere. Business logic never makes direct platform calls.

## Common Patterns

### Adding a New Agent

1. Create a new file in `lib/agents/domains/` with a class extending `BaseAgent`.
2. Define tools as `AgentTool` objects — each with a name, description, parameter JSON Schema, and an `execute` function that takes `AgentContext` and parameters.
3. Register the agent in `RouterAgent`'s agent registry with capability keywords so the router can dispatch appropriately.
4. Add capability declarations describing what intents the agent handles.
5. Write unit tests in `test/agents/domains/` with a mocked `AgentContext`.

```dart
class WeatherAgent extends BaseAgent {
  @override
  String get name => 'weather';

  @override
  String get description => 'Provides weather information and forecasts.';

  @override
  List<AgentTool> get tools => [
    AgentTool(
      name: 'get_forecast',
      description: 'Get weather forecast for a location.',
      parameters: { /* JSON Schema */ },
      execute: _getForecast,
    ),
  ];

  Future<ToolResult> _getForecast(AgentContext ctx, Map<String, dynamic> params) async {
    // Query knowledge store, call services, return result
  }
}
```

### Adding a New Schema Type

1. Define type constants in `lib/knowledge/types/` (URI, property names).
2. Map every property to its Schema.org equivalent where possible.
3. Create helper functions: `createX()`, `readX()`, `updateX()` that wrap `KnowledgeStore.mutate()` and `KnowledgeStore.query()`.
4. Add common query patterns (e.g., "all events this week") as reusable query builder extensions.
5. Create a default RFW widget in the appropriate widget library for rendering instances of this type.

### Adding a New Virtual OS Service

1. Define an abstract interface in `lib/services/` with only pure Dart types.
2. Create a Riverpod provider that switches implementation based on `Platform`:
   ```dart
   final myServiceProvider = Provider<MyService>((ref) {
     if (Platform.isAndroid) return AndroidMyService();
     if (Platform.isIOS) return IosMyService();
     return DesktopMyService();
   });
   ```
3. Implement per platform in `lib/platform/{android,ios,desktop}/`.
4. Add the service to `AgentContext` so agents can access it.
5. Create a mock implementation for use in tests.

## Do's and Don'ts

**DO:**
- Use sealed classes for type-safe unions and exhaustive pattern matching.
- Use Freezed for all data/model classes — immutability by default.
- Use Riverpod providers for all dependency injection and state management.
- Write `///` doc comments on every public class, method, and property.
- Keep agents stateless — persist everything through the knowledge store.
- Use the query builder for all knowledge store reads — never raw SQL outside Drift table definitions.
- Validate all RFW templates before rendering, especially those from LLM or external sources.
- Return meaningful errors using sealed error classes — no bare exceptions.
- Prefer `switch` expressions with exhaustive pattern matching over if/else chains.

**DON'T:**
- Import platform packages (`dart:io`, `path_provider`, platform channels, etc.) outside of `lib/platform/`.
- Put mutable state in agents — they must be stateless between invocations.
- Use mutable data classes — always Freezed or `@immutable`.
- Call LLM APIs directly — always go through `LlmService` for abstraction, cost tracking, and retry logic.
- Access `KnowledgeStore` from agents without going through `AgentContext`.
- Skip validation on RFW templates received from external or LLM-generated sources.
- Use raw SQL queries outside of Drift DAO/table definitions.
- Create singletons or global mutable state — use Riverpod providers instead.
