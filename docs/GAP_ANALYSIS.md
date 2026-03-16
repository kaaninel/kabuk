# Kabuk — Comprehensive Gap Analysis

> Generated from a full audit of all documentation, source files, tests, and configuration.
> Goal: identify everything needed to make the app functional end-to-end — open the app, chat with an agent, create notes, search data, and see dynamic widgets.
>
> **Last updated:** All Tier 1–3 gaps audited and resolved (except 5 low-priority items).

---

## Resolved / Improved Since Initial Audit

The following gaps have been fully or partially resolved through the
[IMPROVEMENT_ROADMAP.md](IMPROVEMENT_ROADMAP.md) implementation (phases A–D):

| # | Gap | Status | What Changed |
|---|-----|--------|--------------|
| 1.1 | No LLM Config UI | **RESOLVED** | Full `lib/ui/settings/` with 7 files: settings_view, llm_settings_page, local_models_page, service_providers_page, identity_page, relay_settings_page, settings_shared. `llmConfigProvider` persists via knowledge store triples. |
| 1.2 | Tool-call loop incomplete | **RESOLVED** | `BaseAgent.completeToolCallLoop()` implements full execute→re-prompt→recurse (up to depth 3). All 10 agents delegate to `processLlmRequest()`. |
| 1.3 | No conversation context | **RESOLVED** | `_buildConversationHistory()` loads last 20 messages, passed via `AgentMessage.user(history: history)`. Every agent uses `if (message case UserMessage(:final history?)) ...history`. |
| 1.4 | Router fallback missing | **RESOLVED** | `_handleTextFallback()` added: keyword re-match → system agent forward → raw text fallback chain (`lib/agents/domains/router.dart`). |
| 1.5 | System Agent wrong URI | **RESOLVED** | Uses `NS.schemaNote`, `NS.rdfType`, proper date serialization. |
| 1.6 | Vault view wrong agent | **RESOLVED** | `NoteComposer._saveNote()` calls `store.createNote()` directly — no longer routes through system agent. |
| 2.1 | No platform services | **RESOLVED** | 22 files across `lib/platform/{android,ios,desktop,shared}/` — all Virtual OS services implemented. |
| 2.3 | No FTS5 search | **RESOLVED** | FTS5 virtual table + sync triggers + `rebuildFtsIndex()` in Drift schema. |
| 2.5 | N+1 query problem | **RESOLVED** | `getEntities(List<String>)` batch method exists in KnowledgeStore. |
| 2.6 | RFW not wired to agents | **RESOLVED** | `ToolResult.widget()` returned by note/contact/calendar agents. |
| 2.7 | Conversation resume | **RESOLVED** | `resumeLastConversationProvider` auto-loads most recent conversation; watched in `shell.dart` on startup. |
| 2.8 | No error handling | **RESOLVED** | `_sendRequestWithRetry` with exponential backoff, status code mapping to structured errors. |
| 2.9 | Streaming tool calls | **RESOLVED** | `_handleStream` now returns `({String text, List<LlmToolCall> toolCalls})` record; caller executes via `completeToolCallLoop()` (`lib/ui/chat/chat_service.dart`). |
| 3.1 | No isolate sandboxing | **RESOLVED** | Full rewrite of `lib/agents/isolate_runtime.dart` (~780 lines) — proxies all service calls across isolate boundary with `_ProxyKnowledgeStore`, `_ProxyQueryBuilder`, `_RecordingMutationContext`. |
| 3.2 | Minimal tests | **IMPROVED** | 28 new tests added: `test/agents/memory_pruning_test.dart`, `test/services/nostr_nips_test.dart`, `test/agents/tier_selection_test.dart`. Still needs UI widget tests and integration tests. |
| 3.3 | No CI/CD | **RESOLVED** | `.github/workflows/ci.yml` — analyze, test, build Android/iOS. Runs on push/PR to main. |
| 3.5 | No onboarding | **RESOLVED** | `lib/ui/onboarding/` with full onboarding flow, gated by `onboardingCompleteProvider`. |
| 3.6 | RFW validation missing | **RESOLVED** | `validate()` with depth/count limits in RFW runtime. |
| 3.7 | count() stub | **RESOLVED** | Base class `count()` throws `UnimplementedError` instead of returning 0. |
| 3.8 | No DB migrations | **RESOLVED** | `schemaVersion = 2` with `MigrationStrategy` and `onUpgrade` callback. |
| 3.9 | Anthropic tool format | **RESOLVED** | Anthropic-specific tool formatting in `_buildBody()`. |

### New Capabilities Added (not in original gap list)

| Feature | Files |
|---------|-------|
| **Agent memory pruning** | `lib/agents/memory.dart` — `maxMemories=50`, `_pruneMemories()` removes oldest in batch. |
| **LLM tier selection** | `lib/agents/base.dart` — `processLlmRequest(tier:)` with `model: 'tier:{name}'`. `TieredLlmService` routes base/standard/advanced. |
| **NIP-09 event deletion** | `lib/services/nostr.dart`, `lib/platform/shared/nostr_service_impl.dart` |
| **NIP-23 long-form content** | `NostrLongFormContent` data class, full CRUD on knowledge store |
| **NIP-51 bookmark/mute/pin lists** | `NostrBookmarkList`, `NostrMuteList` with create/read/update |
| **NIP-05 verification** | `verifyNip05()` with HTTP lookup + `_nip05Cache` |
| **Thread view** | `lib/ui/explore/thread_view.dart` — reply tree with `collectNostrEvents` |
| **Profile view** | `lib/ui/explore/profile_view.dart` — user notes, follow button, NIP-05 badge |
| **Topic following** | `lib/ui/explore/topic_following.dart` — hashtag feed with `TopicChip` |
| **Enhanced search** | `lib/ui/explore/search_view.dart` — `SearchResult` sealed class, combined local + Nostr |
| **Shared NostrAuthorRow** | `lib/ui/shared/nostr_author_row.dart` — consolidated author display widget |
| **Shared time formatting** | `lib/ui/shared/time_format.dart` — `timeAgo()`, `formatDate()` |
| **Complexity reduction** | `explore_widgets.dart` (1945 lines) → barrel export of 5 focused modules: `filter_bar.dart`, `article_card.dart`, `article_detail_sheet.dart`, `empty_feed_state.dart`, `search_dialog.dart` |
| **Deduplicated utilities** | `collectNostrEvents` canonical in `nostr_utils.dart`; `profileForPubkeyProvider` canonical in `nostr_providers.dart` |

---

## Executive Summary

The project has a solid architectural skeleton. The knowledge store (Drift/SQLite-backed RDF triple store), agent framework (10 domain agents with tool-calling), RFW infrastructure (7 built-in widget libraries), and UI shell (4 views) are all implemented and compile cleanly.

**Nearly all gaps have been resolved.** Through the IMPROVEMENT_ROADMAP phases A–D and subsequent audits, the following are now fully functional:

- **All Tier 1 items (1.1–1.6):** LLM config UI, tool-call loop, conversation history, router fallback, correct URIs, direct note creation.
- **All Tier 2 items (2.1–2.9):** Platform services (22 files), FTS5 search, batch queries, RFW agent widgets, conversation resume, error handling, streaming tool calls.
- **Most Tier 3 items:** Isolate sandboxing (3.1), CI/CD (3.3), onboarding (3.5), RFW validation (3.6), count() fix (3.7), DB migrations (3.8), Anthropic format (3.9), plus 28 new tests (3.2).

The app is now a **working end-to-end demo**: open → configure LLM → chat → agent routes → note created → appears in Explore → RFW widgets render inline.

**Remaining open items** (low priority):
- 2.2 Chat protocol Freezed migration (spec divergence, not a bug)
- 2.4 Freezed data classes (manual sealed classes work well)
- 3.2 Additional test coverage (UI widgets, integration tests)
- 3.4 Filtered watch streams (performance optimization)
- 3.10 Presentation service (multi-display, nice-to-have)

---

## Tier 1 — Critical Path (Must-fix for basic functionality)

### 1.1 No LLM Configuration UI

| Field | Detail |
|-------|--------|
| **What** | `llmConfigProvider` defaults to `null`, so `_StubLlmService` is always used. There is no settings screen, onboarding flow, or environment variable reader to set an API key. |
| **Where** | `lib/config/providers.dart` L97–L109, missing `lib/ui/settings/` |
| **Why** | Without a real LLM, every agent returns *"LLM service not configured"*. Chat is dead. |
| **Effort** | ~2–3 days. Build a Settings view with provider/model selector and API key field. Persist config in the knowledge store (encrypted via a basic local storage approach until Vault is real). Add a `lib/ui/settings/settings_view.dart` and wire it into the shell's navigation or a gear icon. |
| **Dependencies** | None — self-contained. |

### 1.2 Agent Tool-Call Loop Does Not Complete

| Field | Detail |
|-------|--------|
| **What** | When the LLM returns `ToolCallsLlmResponse`, every domain agent (Note, Contact, Calendar, File, Search) executes the tools and concatenates the text results — but **never sends the tool results back to the LLM for a final summarised response**. The user sees raw tool output instead of a natural-language answer. The Router agent has the same problem: after routing and getting a sub-agent response, it doesn't synthesize. |
| **Where** | `_handleToolCalls()` in every file under `lib/agents/domains/`. |
| **Why** | The OpenAI/Anthropic tool-calling protocol requires a second LLM call with the tool results appended to the conversation so the model can produce a user-facing answer. Skipping this breaks the conversational UX. |
| **Effort** | ~1–2 days. Add a follow-up `context.llm.complete()` call that includes the original user message, the assistant's tool-call message, and the tool results. Refactor the shared pattern into a helper in `BaseAgent` to avoid duplication across 6 agents. |
| **Dependencies** | 1.1 (needs a real LLM to test). |

### 1.3 Multi-Turn Conversation Context Not Passed to Agents

| Field | Detail |
|-------|--------|
| **What** | `ChatService.sendMessage()` builds a `history` list from stored messages, but only the *current* user message is forwarded to the router/domain agent as `AgentMessage.user(content)`. Prior turns are discarded. |
| **Where** | `lib/ui/chat/chat_service.dart` — the `sendMessage()` method builds history but doesn't use it when invoking the agent. |
| **Why** | Agents have no memory of the conversation. "Edit the note I just created" fails because the agent has no context about the previous turn. |
| **Effort** | ~1 day. Pass the full `List<LlmMessage>` conversation history through `AgentContext` or as part of the `AgentMessage`, and have each domain agent include it in the `LlmRequest.messages` list. |
| **Dependencies** | 1.2 (same LLM request path). |

### 1.4 Router Agent Routing Failures

| Field | Detail |
|-------|--------|
| **What** | The Router agent asks the LLM to call `route_to_agent` with the correct agent name. If the LLM returns a plain text response instead of a tool call (common with weaker models or ambiguous queries), the router returns that text verbatim — the user's request is silently dropped without reaching any domain agent. There is no fallback to the system agent. |
| **Where** | `lib/agents/domains/router.dart` — `process()` method. |
| **Why** | Unreliable routing means messages randomly fail to reach the right agent. |
| **Effort** | ~0.5 day. Add a fallback: if `TextLlmResponse` is returned, either forward to the system agent or attempt a keyword-based match against agent capabilities. |
| **Dependencies** | 1.1. |

### 1.5 System Agent Uses Wrong Note Type URI

| Field | Detail |
|-------|--------|
| **What** | `SystemAgent._createNote()` writes `rdf:type` as `http://schema.org/NoteDigitalDocument`, but every other agent and the UI use `https://schema.org/Note` (`NS.schemaNote`). Notes created via the system agent are invisible to all other queries. |
| **Where** | `lib/agents/domains/system_agent.dart` L205–L210. Also uses raw URI strings instead of `NS.*` constants, and uses `DateTime.now()` (a `DateTime` object) instead of `DateTime.now().toIso8601String()` for `dateCreated`. |
| **Why** | Data inconsistency — notes created through the system agent can't be found by the note agent or Explore view. |
| **Effort** | ~15 minutes. Replace raw strings with `NS.*` constants and fix the date serialization. |
| **Dependencies** | None. |

### 1.6 Vault View Routes Note Through Wrong Agent

| Field | Detail |
|-------|--------|
| **What** | `VaultView._NoteCreator` saves notes by sending a chat message through the *system* agent ("Please create a note…"), not the *note* agent. This is fragile (depends on LLM parsing free-text) and uses the system agent's broken `_createNote` (see 1.5). |
| **Where** | `lib/ui/vault/vault_view.dart` — `_saveNote()`. |
| **Why** | Creates notes with wrong type URI and depends on LLM being configured. Direct knowledge store mutation would be more reliable. |
| **Effort** | ~0.5 day. Either call `NoteAgent` directly via the runtime, or (better) create a `NoteService` that wraps knowledge store mutations and call that from both the UI and the agent. |
| **Dependencies** | 1.5 (if keeping agent route). |

---

## Tier 2 — Important Features (Required for a usable product)

### 2.1 No Platform Implementations for Virtual OS Services

| Field | Detail |
|-------|--------|
| **What** | All 5 Virtual OS services (Vault, Mesh, Media, Auth, Notification) use `_NoOp*` stubs that throw `UnimplementedError`. There is no `lib/platform/` directory at all. |
| **Where** | `lib/config/providers.dart` L230–L347 (stubs). Missing: `lib/platform/{android,ios,desktop}/`. |
| **Why** | File import, image capture, biometrics, push notifications, and encrypted storage are all dead. The File agent's `import_file` tool crashes immediately. |
| **Effort** | ~2–3 weeks for initial implementations. Start with **MediaService** (file picker via `file_picker` package) and **VaultService** (encrypted blob storage via `flutter_secure_storage` + local files). Mesh can use the existing `http` package. Auth and Notification can remain stubs initially. |
| **Dependencies** | None — independent of Tier 1. |

### 2.2 Chat Protocol Diverges from Spec

| Field | Detail |
|-------|--------|
| **What** | `docs/CHAT_PROTOCOL.md` specifies Freezed-based sealed hierarchies (`ChatMessage`, `MessageSender`, `MessageContent` with text/widget/compound/action variants), a `Conversation` model with participant list, and `ConversationState`. None of this exists. The implementation uses plain Drift table rows with string `role` fields. |
| **Where** | `lib/knowledge/database.dart` (Messages/Conversations tables), `lib/ui/chat/chat_service.dart`, `lib/ui/chat/message_bubble.dart`. |
| **Why** | The current string-based approach works but loses type safety, makes tool-call/result messages awkward to render, and blocks features like compound messages (text + widget), conversation state tracking, and participant management. |
| **Effort** | ~3–4 days. Create Freezed models matching the spec, migrate `ChatService` to use them, update `MessageBubble` to pattern-match on sealed types. |
| **Dependencies** | Requires adding `freezed` + `freezed_annotation` + `build_runner` to pubspec (they're not there yet). |

### 2.3 No Full-Text Search (FTS5)

| Field | Detail |
|-------|--------|
| **What** | `docs/KNOWLEDGE_STORE.md` specifies FTS5 virtual tables for full-text search with automatic sync triggers. The implementation uses `LIKE '%query%'` which is O(n), case-sensitive, and doesn't support ranking or stemming. |
| **Where** | `lib/knowledge/database.dart` — `search()` method. |
| **Why** | Search quality degrades rapidly as data grows. The Search agent and Explore view search both suffer. |
| **Effort** | ~2 days. Add FTS5 virtual table in the Drift schema, create triggers to keep it in sync with the Triples table, and update `search()` to use `MATCH`. |
| **Dependencies** | SQLite must support FTS5 (it does via `sqlite3_flutter_libs`). |

### 2.4 No Freezed Data Classes Anywhere

| Field | Detail |
|-------|--------|
| **What** | The copilot instructions and architecture docs mandate Freezed for all data/model classes. Zero Freezed classes exist — everything uses manual sealed classes or plain classes. `freezed` is not even in `pubspec.yaml`. |
| **Where** | All model classes in `lib/agents/messages.dart`, `lib/agents/llm.dart`, `lib/knowledge/triple.dart`, `lib/config/errors.dart`. |
| **Why** | The manual sealed classes actually work well and are idiomatic Dart 3. This is a spec-vs-implementation divergence, not a bug. Consider whether migrating to Freezed adds enough value (auto-generated `==`, `hashCode`, `copyWith`, `toJson`) to justify the `build_runner` dependency. |
| **Effort** | ~3–5 days if pursued. Alternatively, update the spec to accept manual sealed classes. |
| **Dependencies** | `freezed`, `freezed_annotation`, `json_serializable`, `build_runner` packages. |

### 2.5 Explore View N+1 Query Problem

| Field | Detail |
|-------|--------|
| **What** | `ExploreView` fetches all `rdf:type` triples, then for each entity calls `getEntity()` individually — classic N+1 query. With 100 entities this means 101 database queries on every rebuild. |
| **Where** | `lib/ui/explore/explore_view.dart` — `_buildBody()`. |
| **Why** | UI freezes and battery drain as data grows. |
| **Effort** | ~1 day. Add a batch `getEntities(List<String> subjects)` method to `KnowledgeStore` that fetches all triples for multiple subjects in one query. Same N+1 pattern exists in every agent's `_list*` and `_search*` tool — fix those too. |
| **Dependencies** | None. |

### 2.6 RFW Data Binding Not Wired to Agents

| Field | Detail |
|-------|--------|
| **What** | `RfwDataBindings` supports `entity:` and `query:` binding prefixes, and agents can return `ToolResult.widget()` or `ToolResult.rawWidget()`. But the actual domain agents **never return widget results** — they always return `ToolResult.text()`. The chat MessageBubble checks for widget metadata but no agent produces it. |
| **Where** | `lib/agents/domains/*.dart` (no widget returns), `lib/ui/chat/message_bubble.dart` (unused widget rendering path), `lib/rfw/bindings.dart` (unused entity bindings). |
| **Why** | The entire RFW dynamic widget pipeline — a core differentiator — is dormant. A note creation should return an inline NoteCard widget, not plain text. |
| **Effort** | ~2–3 days. Have agents return `ToolResult.rawWidget()` with RFW template strings referencing the built-in libraries (e.g., `kabuk:notes`'s `NoteCard`). Feed entity URIs through `DynamicContent` bindings. |
| **Dependencies** | 1.2 (tool results must reach the user). |

### 2.7 No Conversation Persistence Between App Restarts (Partial)

| Field | Detail |
|-------|--------|
| **What** | Conversations and messages are persisted in Drift tables and loaded reactively. However `activeConversationProvider` is a simple `StateProvider` that resets to `null` on app restart. The Explore view's "conversations" section doesn't exist — there's no way to resume a past conversation from the UI. |
| **Where** | `lib/config/providers.dart` L115, missing conversation list UI in chat view. |
| **Why** | Users lose conversation context on every app restart. The bottom-sheet conversation list in `ChatView` exists but only for switching — doesn't handle empty states well. |
| **Effort** | ~1 day. Auto-load the most recent conversation on startup, or show a conversation list as the default chat view when no conversation is active. |
| **Dependencies** | None. |

### 2.8 No Error Handling / User Feedback for Agent Failures

| Field | Detail |
|-------|--------|
| **What** | `ChatService.sendMessage()` catches exceptions and inserts an `agent_error` message, but common failures (network timeout, malformed tool arguments, LLM rate limiting) aren't surfaced with actionable messages. The `HttpLlmService` throws raw exceptions on HTTP errors without structured error handling. |
| **Where** | `lib/agents/http_llm.dart` L170–L202, `lib/ui/chat/chat_service.dart`. |
| **Why** | Users see cryptic error messages or silent failures. |
| **Effort** | ~1–2 days. Wrap HTTP calls in try/catch, map status codes to `LlmResponse.error()` with user-friendly messages, add retry logic for transient failures. |
| **Dependencies** | 1.1 (needs real LLM calls to trigger). |

### 2.9 HttpLlmService Doesn't Handle Tool Calls in Streaming

| Field | Detail |
|-------|--------|
| **What** | `HttpLlmService.stream()` handles SSE text chunks but doesn't parse tool call deltas. If the LLM returns a tool call during streaming, it's silently dropped. |
| **Where** | `lib/agents/http_llm.dart` — `stream()` method. |
| **Why** | Streaming mode is used for all chat responses. If the LLM decides to call a tool mid-stream, the user sees incomplete text and the tool never executes. |
| **Effort** | ~1–2 days. Accumulate function_call/tool_calls chunks during streaming, emit a complete tool call at stream end. |
| **Dependencies** | 1.1, 1.2. |

---

## Tier 3 — Polish & Platform

### 3.1 No Isolate-Based Agent Sandboxing

| Field | Detail |
|-------|--------|
| **What** | The architecture doc and copilot instructions specify agents run in Dart isolates for sandboxing and parallelism. `_SimpleAgentRuntime` runs all agents in the main isolate. |
| **Where** | `lib/config/providers.dart` — `_SimpleAgentRuntime`. |
| **Why** | Long-running agent operations block the UI. Not critical for MVP since agents are currently fast (just DB + HTTP calls). |
| **Effort** | ~3–5 days. Requires making `AgentContext` serializable for isolate SendPorts, or using `Isolate.run()` with closures. Complex because Drift database handles can't cross isolate boundaries easily — may need a database proxy. |
| **Dependencies** | 2.1 (heavy services need isolate safety). |

### 3.2 Minimal Test Coverage

| Field | Detail |
|-------|--------|
| **What** | 8 test files exist covering agents (3), knowledge (3), rfw (2), config (1), plus a mock helper. No tests for: UI widgets, ChatService, any Virtual OS service, HttpLlmService, DriftKnowledgeStore, providers. |
| **Where** | `test/` — missing `test/ui/`, `test/services/`. |
| **Why** | Regressions will slip through. The existing tests verify query building and triple creation — good foundation but insufficient. |
| **Effort** | ~1 week for meaningful coverage. Priority: ChatService integration test, DriftKnowledgeStore test against in-memory DB, agent tool execution tests. |
| **Dependencies** | None. |

### 3.3 No CI/CD Configuration

| Field | Detail |
|-------|--------|
| **What** | No GitHub Actions, no Codemagic, no Fastlane configuration. |
| **Where** | Missing: `.github/workflows/`, `codemagic.yaml`, `fastlane/`. |
| **Why** | Tests don't run automatically, no automated builds or releases. |
| **Effort** | ~0.5 day for a basic `flutter analyze && flutter test` GitHub Action. |
| **Dependencies** | 3.2 (tests should exist before CI runs them). |

### 3.4 Knowledge Store `watch()` Returns Unfiltered Stream

| Field | Detail |
|-------|--------|
| **What** | `DriftKnowledgeStore.watch()` takes `subject`/`predicate`/`graph` filters but the current implementation watches *all* triple changes and filters in Dart. For high-frequency mutations this creates unnecessary overhead. |
| **Where** | `lib/knowledge/drift_store.dart` — `watch()` method. |
| **Why** | Performance — every knowledge store write triggers every watcher. Acceptable for MVP, problematic at scale. |
| **Effort** | ~1–2 days. Use Drift's `.watch()` on filtered queries to push filtering to SQLite. |
| **Dependencies** | None. |

### 3.5 No Onboarding / Empty State UX

| Field | Detail |
|-------|--------|
| **What** | When the app opens for the first time, the Explore view shows "Your knowledge store is empty", Chat shows an empty message list, and there's no hint about what to do. No walkthrough, no sample data, no prompt suggestions. |
| **Where** | All 4 views — `explore_view.dart`, `chat_view.dart`, `create_view.dart`, `apps_view.dart`. |
| **Why** | New users have no idea how to start or what the app does. |
| **Effort** | ~2 days. Add suggested prompts in the empty chat state, seed example data, or show an onboarding carousel. |
| **Dependencies** | 1.1 (users need working chat to follow prompts). |

### 3.6 RFW Template Validation Missing

| Field | Detail |
|-------|--------|
| **What** | The copilot instructions and RFW doc mandate validating all RFW templates before rendering (especially LLM-generated ones). `KabukRfwRuntime.renderRaw()` parses templates directly with no validation, sanitization, or depth/count limits. `AppConstants.maxRfwWidgetDepth` and `maxRfwWidgetCount` are defined but never checked. |
| **Where** | `lib/rfw/runtime.dart` — `renderRaw()`, `lib/config/constants.dart` L33–L37. |
| **Why** | Malicious or malformed RFW templates could crash the app or cause infinite widget trees. |
| **Effort** | ~1 day. Add a validation pass that checks depth and widget count before rendering. Wrap the parse call in try/catch and return an error widget on failure. |
| **Dependencies** | 2.6 (RFW must be actively used first). |

### 3.7 `QueryBuilder.count()` Not Implemented

| Field | Detail |
|-------|--------|
| **What** | `QueryBuilder.count()` is declared in `query.dart` but returns `0` in the base class — it's a stub. `_ConnectedQueryBuilder` in `drift_store.dart` does override it, so it works for the real store. But any test doubles or alternate implementations will silently return 0. |
| **Where** | `lib/knowledge/query.dart` — `count()` method. |
| **Why** | Minor — tests using mock stores will get wrong count results. |
| **Effort** | ~15 minutes. Make the base class throw `UnimplementedError` instead of returning 0. |
| **Dependencies** | None. |

### 3.8 Database Migration Strategy Missing

| Field | Detail |
|-------|--------|
| **What** | `KabukDatabase` declares `schemaVersion = 1` with no migration strategy. When the schema changes (and it will — FTS5 tables, new columns, etc.), existing user databases will fail to open. |
| **Where** | `lib/knowledge/database.dart` — `KabukDatabase` class, no `migration` getter. |
| **Why** | Any schema change will corrupt or lose existing user data. |
| **Effort** | ~1 day. Implement Drift's `MigrationStrategy` with `onUpgrade` callbacks. Consider using Drift's schema versioning tools. |
| **Dependencies** | 2.3 (FTS5 will be the first migration). |

### 3.9 HttpLlmService Anthropic Tool Format Incomplete

| Field | Detail |
|-------|--------|
| **What** | `HttpLlmService._buildBody()` formats tools for OpenAI's API shape. Anthropic uses a different tool format (tools at top level, not as `functions` wrapper). The code checks `isAnthropic` for headers and response parsing but **not for request body tool formatting**. |
| **Where** | `lib/agents/http_llm.dart` — `_buildBody()` method. |
| **Why** | Tool calling will fail when using Anthropic's Claude API. |
| **Effort** | ~0.5 day. Add Anthropic-specific tool schema formatting in `_buildBody()`. |
| **Dependencies** | 1.1. |

### 3.10 No Presentation Service Integration

| Field | Detail |
|-------|--------|
| **What** | `PresentationService` defines display discovery, brightness control, and screen info. There's no platform implementation and no UI that uses it. |
| **Where** | `lib/services/presentation.dart`, not used anywhere. |
| **Why** | Low priority — nice-to-have for multi-display support and system UI control. |
| **Effort** | ~3–5 days per platform. |
| **Dependencies** | 2.1 (platform layer foundation). |

---

## Tier 4 — Vision Alignment (Required to match product vision)

### 4.1 MCP Support Not Yet Implemented

| Field | Detail |
|-------|--------|
| **What** | Kabuk's vision calls for MCP (Model Context Protocol) support so the local LLM can connect to external tools and data sources. No `McpClient` interface exists, no MCP servers are configured, and `AgentContext` has no MCP access point. |
| **Where** | Missing: `lib/services/mcp.dart`, `lib/agents/runtime.dart` (AgentContext). |
| **Why** | MCP is the extensibility mechanism that lets the local LLM reach beyond its built-in capabilities without requiring new native code. Without it, users cannot connect tools like filesystem access, web search, or calendar bridges. |
| **Effort** | ~1–2 weeks. Define `McpClient` interface, implement stdio and HTTP/SSE transports, wire into `AgentContext`, add tool discovery to LLM request construction. See [docs/MCP.md](MCP.md). |
| **Dependencies** | Local LLM must be active (4.2). |

---

### 4.2 Local LLM Not Set as Default Provider

| Field | Detail |
|-------|--------|
| **What** | The `LlmService` fallback chain currently tries Anthropic/OpenAI first. Per the product vision, the **local LLM (llama.cpp / Ollama) is the primary provider**. Cloud providers should only activate when the user explicitly configures them as extensions or fallbacks. |
| **Where** | `lib/agents/llm/http_llm.dart`, `lib/agents/llm/local_llm.dart`, provider initialization in `lib/config/`. |
| **Why** | Privacy-first design requires that data never leaves the device by default. Having cloud providers as the primary LLM silently violates this principle. |
| **Effort** | ~0.5–1 day. Reorder the provider chain so local → Ollama → cloud. Add a settings toggle for cloud fallback opt-in. Ensure onboarding sets up the local model before any cloud key is requested. |
| **Dependencies** | Local LLM model must be downloaded (model manager already exists). |

---

## Remaining Items (Low Priority)

```
2.2  Chat protocol Freezed models    (3–4d)  — Spec divergence, current string-based approach works
2.4  Freezed data classes everywhere  (3–5d)  — Manual sealed classes are idiomatic Dart 3
3.2  Expand test coverage             (1w)    — UI widget tests, integration tests needed
3.4  Filtered watch streams           (1–2d)  — Performance optimization for scale
3.10 Presentation service impl        (3–5d)  — Multi-display support, nice-to-have
4.1  MCP support                      (1–2w)  — Local LLM tool extension, planned Phase 6
4.2  Local LLM as default             (0.5d)  — Reorder provider chain, cloud opt-in
```

None of items 2.x/3.x block basic functionality. The app is a working end-to-end demo. Items 4.x are required to fully realize the product vision.

---

## Summary Matrix

| # | Gap | Tier | Status |
|---|-----|------|--------|
| ~~1.1~~ | ~~No LLM config UI~~ | ~~1~~ | **RESOLVED** |
| ~~1.2~~ | ~~Tool-call loop incomplete~~ | ~~1~~ | **RESOLVED** |
| ~~1.3~~ | ~~No conversation context~~ | ~~1~~ | **RESOLVED** |
| ~~1.4~~ | ~~Router fallback missing~~ | ~~1~~ | **RESOLVED** |
| ~~1.5~~ | ~~System agent wrong URI~~ | ~~1~~ | **RESOLVED** |
| ~~1.6~~ | ~~Vault view wrong agent~~ | ~~1~~ | **RESOLVED** |
| ~~2.1~~ | ~~No platform services~~ | ~~2~~ | **RESOLVED** |
| 2.2 | Chat protocol diverged | 2 | OPEN (spec divergence, not a bug) |
| ~~2.3~~ | ~~No FTS5 search~~ | ~~2~~ | **RESOLVED** |
| 2.4 | No Freezed classes | 2 | OPEN (manual sealed classes work well) |
| ~~2.5~~ | ~~N+1 query problem~~ | ~~2~~ | **RESOLVED** |
| ~~2.6~~ | ~~RFW not wired to agents~~ | ~~2~~ | **RESOLVED** |
| ~~2.7~~ | ~~Conversation resume~~ | ~~2~~ | **RESOLVED** |
| ~~2.8~~ | ~~No error handling~~ | ~~2~~ | **RESOLVED** |
| ~~2.9~~ | ~~Streaming tool calls~~ | ~~2~~ | **RESOLVED** |
| ~~3.1~~ | ~~No isolate sandboxing~~ | ~~3~~ | **RESOLVED** |
| 3.2 | Minimal tests | 3 | **IMPROVED** (28 new tests, needs more) |
| ~~3.3~~ | ~~No CI/CD~~ | ~~3~~ | **RESOLVED** |
| 3.4 | Unfiltered watch stream | 3 | OPEN (perf optimization) |
| ~~3.5~~ | ~~No onboarding~~ | ~~3~~ | **RESOLVED** |
| ~~3.6~~ | ~~RFW validation missing~~ | ~~3~~ | **RESOLVED** |
| ~~3.7~~ | ~~count() stub~~ | ~~3~~ | **RESOLVED** |
| ~~3.8~~ | ~~No DB migrations~~ | ~~3~~ | **RESOLVED** |
| ~~3.9~~ | ~~Anthropic tool format~~ | ~~3~~ | **RESOLVED** |
| 3.10 | No Presentation impl | 3 | OPEN (nice-to-have) |
| 4.1 | MCP support not yet implemented | 4 | OPEN — planned in Phase 6 |
| 4.2 | Local LLM not set as default provider | 4 | OPEN — cloud providers still default |
