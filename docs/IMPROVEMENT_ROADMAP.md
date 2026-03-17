# Kabuk — Improvement Roadmap

*Addressing: Nostr social gaps, agent system issues, test coverage, complexity risk, and community features.*

> Generated from codebase audit on Feb 28, 2026. Prioritized by user impact and dependency order.

---

## Executive Summary

Five workstreams, 4 phases, ~16 weeks estimated:

| Phase | Focus | Duration | Impact |
|-------|-------|----------|--------|
| **A** | Agent System Fixes (Critical Bugs) | Weeks 1–2 | Correct broken core behavior |
| **B** | Test Foundation + Nostr Social Core | Weeks 3–6 | Reliability + feature parity |
| **C** | Community Features + Content | Weeks 7–11 | User-facing social layer |
| **D** | Hardening + Ecosystem | Weeks 12–16 | Production readiness |

---

## Phase A — Agent System Fixes (Weeks 1–2)

*These are architectural bugs that undermine the core agent loop. Fix before building anything else.*

### A.1 Router Text-Fallback (Priority: Critical)

**Problem:** When the LLM returns `TextLlmResponse` instead of calling `route_to_agent`, the router returns that text verbatim. The user's request never reaches a specialized agent.

**File:** `lib/agents/domains/router.dart` line 311

**Fix:**
1. When `TextLlmResponse` is received, attempt keyword-based re-matching on the original message content
2. If keyword match found → dispatch to matched agent
3. If no keyword match → forward to `SystemAgent` as catch-all (it has `search_knowledge` and `create_note`)
4. Only return raw text if `SystemAgent` also returns text (double-fallback)

**Acceptance criteria:**
- [ ] Router never returns raw LLM text without attempting dispatch
- [ ] Test: ambiguous query → system agent handles it
- [ ] Test: LLM text fallback → keyword re-match succeeds

---

### A.2 Isolate Runtime Safety (Priority: Critical)

**Problem:** `_IsolateProxyContext` proxies only `LlmService` across isolate boundary. `KnowledgeStore` (Drift/SQLite) cannot safely cross isolate boundaries. Agents running in isolates will crash when accessing the knowledge store.

**File:** `lib/agents/isolate_runtime.dart` lines 121–140, 209–213

**Fix options (choose one):**
- **Option 1 (Recommended):** Open a secondary Drift database connection inside the isolate using `DriftIsolate` (Drift's built-in isolate support). Proxy mutations back to the main isolate for change event emission.
- **Option 2:** Serialize all `KnowledgeStore` calls as messages across the isolate boundary (like LLM proxy). Higher latency but simpler.
- **Option 3:** Run agents in-process (current fallback behavior) and defer isolate sandboxing to a later phase.

**Acceptance criteria:**
- [ ] Agent executing in isolate can read/write knowledge store without crash
- [ ] Change events from isolate operations propagate to main isolate watchers
- [ ] Test: agent in isolate creates a note → triple appears in main isolate query

---

### A.3 Streaming Tool-Call Handling (Priority: High)

**Problem:** `HttpLlmService.stream()` correctly accumulates tool call deltas in `_ToolCallBuffer`, but `ChatService` only processes `TextDeltaEvent` from the stream — tool calls are silently dropped.

**File:** `lib/ui/chat/chat_service.dart` line 159

**Fix:**
1. After stream completes, check if accumulated content includes tool calls
2. If tool calls present, invoke `completeToolCallLoop()` with the accumulated tool calls
3. Yield final synthesized response after tool execution

**Acceptance criteria:**
- [ ] Streaming response with tool calls → tools execute → final answer rendered
- [ ] Test: stream yields tool call deltas → correct tool result

---

### A.4 Agent Memory Pruning (Priority: Medium)

**Problem:** `AgentMemoryMixin` stores memories as RDF triples with no eviction. `buildMemoryContext()` will eventually exceed context windows.

**File:** `lib/agents/memory.dart`

**Fix:**
1. Add `maxMemories` constant (default: 50 per agent)
2. On `saveMemory()`, count existing entries. If at limit, delete oldest.
3. In `buildMemoryContext()`, summarize memories if count exceeds threshold (e.g., 20) by injecting a summarization LLM call.
4. Add `relevanceScore` predicate — boost recent + frequently-accessed memories.

**Acceptance criteria:**
- [ ] Memory count never exceeds limit
- [ ] Old memories are pruned on save
- [ ] Test: save 55 memories → only 50 remain, oldest deleted

---

### A.5 LLM Tier Selection in processLlmRequest (Priority: Low)

**Problem:** `processLlmRequest()` always uses the default tier. Complex multi-step operations should use higher tiers.

**File:** `lib/agents/base.dart` line 339

**Fix:**
1. Add optional `tier` parameter to `processLlmRequest()`
2. Each domain agent declares a default tier based on task complexity
3. Router can pass detected complexity as metadata

---

## Phase B — Test Foundation + Nostr Social Core (Weeks 3–6)

### B.1 Critical Test Coverage (Weeks 3–4)

*Prioritized by blast radius — what breaks worst when untested.*

#### B.1.1 DriftKnowledgeStore Tests (Priority: Critical)

**Current state:** Zero tests for the real knowledge store implementation.

**Tests to write** (`test/knowledge/drift_store_test.dart`):
- `mutate()` transaction semantics (commit, rollback on error)
- `query()` with all filter combinations (subject, predicate, object, graph, FTS)
- `watch()` reactive streams — mutation emits change event → stream yields
- `getEntity()` / `getEntities()` triple aggregation
- `search()` FTS5 integration
- Blob storage roundtrip (`storeBlob` / `retrieveBlob`)
- Concurrent mutation safety

#### B.1.2 NIP-44 Encryption Tests (Priority: Critical)

**Current state:** Zero tests for cryptographic code.

**Tests to write** (`test/services/nip44_test.dart`):
- Encrypt/decrypt roundtrip with known test vectors (from NIP-44 spec)
- Cross-key-pair encrypt → decrypt
- Invalid ciphertext handling (corrupted HMAC, wrong version)
- Padding validation
- Edge cases: empty content, max-length content

#### B.1.3 MessagingAgent Tests (Priority: High)

**Current state:** The only untested domain agent.

**Tests to write** (`test/agents/messaging_agent_test.dart`):
- Metadata and tool declarations
- `send_message` tool execution
- `list_conversations` / `get_conversation` tools
- DM history flow
- Error handling (no identity, relay failure)

#### B.1.4 VaultService Tests (Priority: High)

**Tests to write** (`test/platform/shared/vault_service_test.dart`):
- Key derivation (Argon2id)
- Master key encrypt/decrypt roundtrip
- Per-file data key wrapping
- Error handling (wrong password, corrupted vault)

#### B.1.5 Knowledge Change Events Tests (Priority: High)

**Tests to write** (`test/knowledge/changes_test.dart`):
- Mutation → correct `ChangeEvent` type emitted
- Multiple watchers receive same events
- Filtered watches (by predicate, by subject)
- Stream cancellation cleanup

#### B.1.6 ChatService Tests (Priority: High)

**Tests to write** (`test/ui/chat/chat_service_test.dart`):
- Conversation CRUD (create, list, delete)
- Message sending → agent invocation → response persistence
- Conversation history building (capped at 20)
- Nostr DM conversation bridging
- Error handling (agent failure, DB failure)

#### B.1.7 Missing Knowledge Types

**Tests to write** (`test/knowledge/types_test.dart` — extend existing):
- `ArticleData.fromTriples()` — field extraction, missing fields
- `BookmarkData.fromTriples()` — field extraction
- `NostrSocialData.fromTriples()` — stats parsing, user-state flags
- `SavedSearchData.fromTriples()` — query preservation
- `SavedViewData.fromTriples()` — view config roundtrip

---

### B.2 Nostr Social Core (Weeks 5–6)

*Features that bring Kabuk close to YakiHonne's social baseline.*

#### B.2.1 NIP-09 Event Deletion (Priority: High, Effort: Low)

**Current state:** Kind 5 defined but no publish/handling logic.

**Implementation:**
1. Add `deleteEvent(String eventId)` to `NostrService` interface
2. Implement: publish kind 5 event with `["e", eventId]` tag
3. Handle incoming kind 5 events: remove referenced events from knowledge store
4. Add `delete_note` tool to `IdentityAgent`
5. UI: add delete action to user's own posts

**Files to modify:**
- `lib/services/nostr.dart` — interface method
- `lib/platform/shared/nostr_service_impl.dart` — implementation
- `lib/agents/domains/identity_agent.dart` — tool
- `lib/ui/explore/nostr_providers.dart` — UI action

#### B.2.2 NIP-51 Lists (Bookmarks & Mute) (Priority: High, Effort: Medium)

**Current state:** Bookmarks are local-only; no mute lists.

**Implementation:**
1. Define kinds: 10000 (mute list), 10001 (pin list), 30001 (curation set)
2. Add `publishList()` / `fetchList()` to `NostrService`
3. Sync local bookmarks → kind 30001 replaceable event
4. Implement mute list: muted pubkeys filtered from feeds
5. Add `mute_user` / `unmute_user` tools to `IdentityAgent`
6. Bidirectional sync: local bookmark ↔ Nostr list

**Files to create/modify:**
- `lib/services/nostr.dart` — interface additions
- `lib/platform/shared/nostr_service_impl.dart` — implementation
- `lib/knowledge/types/bookmark.dart` — add Nostr sync fields
- `lib/agents/domains/identity_agent.dart` — mute tools
- `lib/agents/domains/discovery_agent.dart` — bookmark sync tools

#### B.2.3 NIP-05 DNS Verification (Priority: Medium, Effort: Low)

**Current state:** Field stored and displayed but never verified.

**Implementation:**
1. Add `verifyNip05(String identifier)` → `Future<bool>` to `NostrService`
2. HTTP GET `https://{domain}/.well-known/nostr.json?name={local}`
3. Compare returned pubkey against profile's pubkey
4. Cache verification result with TTL (24h)
5. Display verification badge on profile cards

**Files to modify:**
- `lib/services/nostr.dart` — interface method
- `lib/platform/shared/nostr_service_impl.dart` — HTTP call + cache
- `lib/ui/explore/explore_widgets.dart` — badge display

#### B.2.4 Relay Auto-Reconnect with Backoff (Priority: High, Effort: Low)

**Current state:** WebSocket connections exist but no auto-reconnect on failure.

**Implementation:**
1. Add exponential backoff reconnection (1s, 2s, 4s, 8s, max 60s)
2. Track relay health state (connected / connecting / disconnected / failed)
3. Surface relay health in settings UI
4. Reset backoff on successful connection
5. Handle NOTICE messages beyond just logging

**Files to modify:**
- `lib/platform/shared/nostr_service_impl.dart` — reconnect logic
- `lib/ui/settings/relay_settings_page.dart` — health indicators

---

## Phase C — Community Features + Content (Weeks 7–11)

### C.1 NIP-23 Long-Form Content (Weeks 7–8)

**Current state:** Not implemented. No kind 30023 support.

**Implementation plan:**

#### C.1.1 Protocol Layer
1. Add `NostrKind.longFormContent = 30023` to kind enum
2. Define `LongFormArticle` model: title, summary, content (markdown), published_at, tags, image, `d` tag (identifier)
3. Add `publishArticle()` / `fetchArticles()` / `fetchArticle(naddr)` to `NostrService`
4. Long-form is a **replaceable event** (kind 30000–39999) — use `d` tag for deduplication

#### C.1.2 Knowledge Store
1. Extend `ArticleData` type to support NIP-23 fields
2. Add `nostrArticleIdentifier` predicate to namespaces
3. Cache fetched articles as triples for offline reading

#### C.1.3 Agent Layer
1. Add `publish_article` / `list_articles` / `fetch_article` tools to `IdentityAgent`
2. Or: create a dedicated `ContentAgent` for long-form

#### C.1.4 UI Layer
1. Extend `NoteComposer` (Vault view) with article mode — title, summary, tag, and full markdown editor
2. Article card component for Explore view (distinct from short note cards)
3. Article reader view with rendered markdown, author info, and social bar
4. Draft support: save locally before publishing to relays

**Files to create:**
- `lib/knowledge/types/long_form.dart` — model
- `lib/ui/vault/article_composer.dart` — editor UI
- `lib/ui/explore/article_card.dart` — card widget
- `lib/ui/explore/article_reader.dart` — reader view

**Files to modify:**
- `lib/services/nostr.dart`, `lib/platform/shared/nostr_service_impl.dart` — protocol
- `lib/config/namespaces.dart` — predicates
- `lib/agents/domains/identity_agent.dart` — tools

---

### C.2 Thread View UI (Weeks 8–9)

**Current state:** Reply data is stored (NIP-10 markers parsed) but no threaded view exists.

**Implementation:**
1. Thread view widget: shows root note + nested replies with depth indicators
2. Fetch reply chain: follow `e` tags with `reply`/`root` markers
3. Inline reply composer at bottom of thread
4. Navigate to thread from any note card's reply count button

**Files to create:**
- `lib/ui/explore/thread_view.dart`
- `lib/ui/explore/thread_providers.dart`

---

### C.3 User Profile Page (Weeks 9–10)

**Current state:** Profiles are fetched/cached, but no dedicated profile view.

**Implementation:**
1. Profile header: avatar, name, about, NIP-05 badge, follow/unfollow button
2. Profile tabs: Notes, Articles, Reactions, Relays
3. Follow list display
4. Navigate from any author name/avatar
5. Own-profile editing (reuses `update_profile` tool)

**Files to create:**
- `lib/ui/explore/profile_page.dart`
- `lib/ui/explore/profile_providers.dart`

---

### C.4 Interests & Topic Following (Weeks 10–11)

**Current state:** Hashtag search exists but no persistent topic following.

**Implementation:**
1. "Follow topic" action on hashtag search results
2. Followed topics stored as knowledge store triples (`kabuk:followedTopic`)
3. Explore feed mixes: Following (people) + Topics (hashtags) + Global
4. Topic suggestions based on interaction history (agent-curated)
5. Optional: NIP-51 interest list (kind 30015) for cross-client sync

**Files to create:**
- `lib/knowledge/types/interest.dart`
- `lib/ui/explore/topic_feed.dart`

**Files to modify:**
- `lib/agents/domains/discovery_agent.dart` — `follow_topic` / `unfollow_topic` tools
- `lib/ui/explore/explore_view.dart` — feed tab for topics

---

### C.5 Enhanced Search (Week 11)

**Current state:** FTS5 local search + NIP-50 relay search + hashtag search exist but are fragmented.

**Implementation:**
1. Unified search UI with tabs: All, People, Notes, Articles, Hashtags
2. People search: NIP-50 + NIP-05 identifier lookup
3. Search history persistence (already have `SavedSearchData` type)
4. Search suggestions from trending topics + recent searches
5. Inline search results with social actions

**Files to modify:**
- `lib/ui/explore/explore_view.dart` — enhanced search bar
- `lib/agents/domains/discovery_agent.dart` — `search_users` tool
- `lib/platform/shared/nostr_service_impl.dart` — NIP-50 user search

---

## Phase D — Hardening + Ecosystem (Weeks 12–16)

### D.1 Test Coverage Expansion (Weeks 12–13)

Target: >70% coverage on all non-UI code.

#### D.1.1 Service Implementation Tests

| Test File | Covers | Priority |
|-----------|--------|----------|
| `test/platform/shared/feed_service_test.dart` | Feed parsing, source management, error handling | High |
| `test/platform/shared/nostr_social_test.dart` | Full social flow: react, repost, reply, delete — with mock relays | High |
| `test/platform/shared/nostr_dm_test.dart` | Gift-wrap DM flow: send, receive, decrypt, self-copy | High |
| `test/platform/shared/nostr_feed_source_test.dart` | Nostr → FeedItem conversion, URL schemes | Medium |
| `test/platform/shared/rss_source_test.dart` | RSS/Atom XML parsing | Medium |
| `test/platform/shared/reddit_source_test.dart` | Reddit JSON parsing | Medium |
| `test/platform/shared/mesh_service_test.dart` | Network connectivity, peer discovery | Medium |

#### D.1.2 UI Widget Tests

| Test File | Covers | Priority |
|-----------|--------|----------|
| `test/ui/chat/message_bubble_test.dart` | Render text, markdown, media, tool-call, RFW messages | High |
| `test/ui/chat/chat_input_test.dart` | Text entry, send action, media attachment | High |
| `test/ui/explore/note_card_test.dart` | Social bar (react, reply, repost), author info, content | Medium |
| `test/ui/explore/article_card_test.dart` | Article preview rendering | Medium |
| `test/ui/settings/relay_settings_test.dart` | Add/remove relay, health display | Low |

#### D.1.3 Integration Tests

| Test File | Covers | Priority |
|-----------|--------|----------|
| `test/integration/agent_to_knowledge_test.dart` | Agent creates entity → knowledge store has it → UI provider yields it | High |
| `test/integration/nostr_social_flow_test.dart` | Publish note → react → reply → thread builds correctly | Medium |
| `test/integration/dm_flow_test.dart` | Send DM → encrypt → relay → receive → decrypt → display | Medium |

---

### D.2 Complexity Reduction (Weeks 13–14)

*Address the "high surface area" risk.*

#### D.2.1 Architecture Documentation

1. Add inline `///` doc comments to all public APIs (currently ~40% coverage)
2. Create `docs/ARCHITECTURE_DECISION_RECORDS/` with ADRs for key decisions:
   - ADR-001: Why RDF triples over relational tables
   - ADR-002: Why RFW over WebView widgets
   - ADR-003: Why Nostr over Matrix
   - ADR-004: Why isolate-based agent sandboxing
3. Add Mermaid diagrams for data flow in README

#### D.2.2 Error Handling Audit

1. Audit all `try/catch` blocks — ensure they use `ServiceError` sealed class
2. Replace bare exceptions with typed errors
3. Add error boundaries in UI (per-view error state)
4. Add `ErrorReporter` service for centralized error logging

#### D.2.3 Simplify Agent Registration

1. Auto-discover agents via code generation instead of manual `_registerAll()`
2. Reduce boilerplate in domain agents (extract common `process()` pattern to base class mixin)

---

### D.3 NIP-57 Zaps / Lightning (Weeks 14–15)

**Current state:** `lud16` field exists on `NostrProfile` but is unused.

**Implementation plan:**

#### D.3.1 Protocol Layer
1. Define kind 9734 (zap request) and 9735 (zap receipt)
2. Add `sendZap()` to `NostrService` — creates zap request, sends to recipient's LNURL
3. Parse zap receipts from relays for display

#### D.3.2 Wallet Integration
1. **NWC (Nostr Wallet Connect, NIP-47)** — connect external Lightning wallet via event-based protocol
2. Alternatively: integrate Cashu ecash for in-app balance
3. UI: wallet setup in settings, balance display

#### D.3.3 UI
1. Zap button on note/article cards
2. Zap amount selector (preset amounts + custom)
3. Zap receipt display (who zapped, how much)
4. Creator dashboard: total zaps received

**Files to create:**
- `lib/services/lightning.dart` — wallet interface
- `lib/platform/shared/nwc_service_impl.dart` — NWC implementation
- `lib/ui/shared/zap_button.dart` — zap UI component
- `lib/ui/settings/wallet_page.dart` — wallet setup

**Complexity note:** This is the highest-effort item. Consider NWC-only first (external wallet), defer built-in wallet to later.

---

### D.4 Production Hardening (Week 16)

#### D.4.1 Performance
- [ ] Add in-memory caching layer for hot knowledge store queries (like YakiHonne does)
- [ ] Profile and optimize RFW rendering pipeline
- [ ] Add lazy loading for feed items (pagination)
- [ ] Benchmark isolate agent startup time

#### D.4.2 Reliability
- [ ] Relay connection pool with health monitoring
- [ ] Graceful degradation when all relays fail
- [ ] Offline queue for outbound events (publish when reconnected)
- [ ] Database migration strategy for schema changes

#### D.4.3 Update GAP_ANALYSIS.md
- [ ] Mark fixed gaps (tool-call loop, multi-turn context) as resolved
- [ ] Add newly discovered gaps (isolate safety, streaming tool calls, memory pruning)
- [ ] Update completion percentages

---

## Dependency Graph

```
Phase A (Agent Fixes)
├── A.1 Router text-fallback ──────────────────────┐
├── A.2 Isolate runtime safety                     │
├── A.3 Streaming tool-call handling               │
├── A.4 Memory pruning                             │
└── A.5 Tier selection                             │
                                                   │
Phase B (Tests + Social Core)                      │
├── B.1 Critical tests ◀──── depends on A fixes ───┘
│   ├── B.1.1 DriftKnowledgeStore tests
│   ├── B.1.2 NIP-44 tests
│   ├── B.1.3 MessagingAgent tests
│   ├── B.1.4 VaultService tests
│   ├── B.1.5 Change events tests
│   ├── B.1.6 ChatService tests
│   └── B.1.7 Missing type tests
└── B.2 Nostr social core (independent)
    ├── B.2.1 NIP-09 deletion
    ├── B.2.2 NIP-51 lists/bookmarks
    ├── B.2.3 NIP-05 verification
    └── B.2.4 Relay auto-reconnect

Phase C (Community Features)
├── C.1 NIP-23 long-form ◀──── depends on B.2
├── C.2 Thread view ◀──── depends on B.2.1
├── C.3 User profile page (independent)
├── C.4 Topic following ◀──── depends on B.2.2
└── C.5 Enhanced search (independent)

Phase D (Hardening)
├── D.1 Test expansion ◀──── depends on C features
├── D.2 Complexity reduction (independent)
├── D.3 Zaps/Lightning (independent)
└── D.4 Production hardening ◀──── depends on all
```

---

## Phase E — Vision Alignment: Local LLM Primary + MCP (Weeks 17–20)

These items align the implementation with the core product vision established in the architecture documents.

### E.1 Local LLM as Default Provider (Week 17, Priority: Critical)

**Goal:** Ensure no data leaves the device unless the user explicitly opts in to cloud providers.

1. Reorder the `LlmService` provider chain: local (llama.cpp) → Ollama → cloud
2. Gate cloud provider activation behind a settings toggle (default: off)
3. Update onboarding to download/configure the local model before offering cloud keys
4. Add UI indicator showing which LLM is currently responding
5. Ensure the RouterAgent uses the local model for classification by default

**Files to modify:**
- `lib/agents/llm/` — provider chain initialization
- `lib/ui/settings/llm_settings_page.dart` — cloud opt-in toggle
- `lib/ui/onboarding/` — model setup step

---

### E.2 MCP Integration (Weeks 17–20, Priority: High)

**Goal:** Let the local LLM connect to external tools via the Model Context Protocol.

#### E.2.1 McpClient Interface (Week 17)
1. Define `McpClient` abstract interface in `lib/services/mcp.dart`
2. Define `McpTool`, `McpToolResult`, `McpServerInfo` Freezed models
3. Add `McpClient mcpClient` to `AgentContext`

#### E.2.2 Transport Implementations (Weeks 17–18)
1. Implement stdio transport (`StdioMcpTransport`) — spawn local MCP server processes
2. Implement HTTP/SSE transport (`HttpMcpTransport`) — connect to remote MCP servers
3. Provider: `mcpClientProvider` with list of configured servers

#### E.2.3 Tool Discovery & LLM Integration (Week 18)
1. `McpToolDiscovery` — fetch tool schemas from all connected servers at startup
2. Inject discovered MCP tools into the LLM tool list alongside native `AgentTool` objects
3. Route LLM tool calls prefixed with `mcp:` to the correct server

#### E.2.4 Settings & Configuration UI (Weeks 18–19)
1. MCP server configuration page in Settings
2. Add/remove MCP servers (name, transport, command/URL)
3. Per-server permission model (which agents can access which servers)

#### E.2.5 Bundled Starter Servers (Weeks 19–20)
1. Bundle `filesystem` MCP server for accessing files outside the vault
2. Bundle `fetch` MCP server for reading web pages
3. Document how to connect community MCP servers (GitHub, calendar, etc.)

**Files to create:**
- `lib/services/mcp.dart` — interface + models
- `lib/platform/shared/mcp_client_impl.dart` — stdio + HTTP transports
- `lib/ui/settings/mcp_settings_page.dart` — configuration UI
- `docs/MCP.md` — full design document (already created)

**Files to modify:**
- `lib/agents/runtime.dart` — add McpClient to AgentContext
- `lib/agents/llm/` — inject MCP tools into LLM requests

---

| Metric | Current | Target (Post-Phase D) |
|--------|---------|----------------------|
| Test files | 29 | 55+ |
| Code coverage (non-UI) | ~25% est. | >70% |
| NIPs implemented | 14 | 20+ |
| Social features | 12 | 20+ |
| Agent bugs (open) | 4 | 0 |
| Nostr event kinds handled | 15 | 22+ |
| Mean relay reconnect time | ∞ (no reconnect) | <5s |
| Max agent memory entries | ∞ (unbounded) | 50 |

---

## Quick Wins (Can start immediately, no dependencies)

1. **NIP-09 deletion** — 2–3 hours. Kind defined, just needs publish + handler.
2. **NIP-05 verification** — 2–3 hours. Single HTTP call + cache.
3. **Relay auto-reconnect** — 3–4 hours. Exponential backoff in existing WebSocket code.
4. **Router text-fallback** — 2–3 hours. Add `SystemAgent` fallback at line 311.
5. **Memory pruning** — 2–3 hours. Add count check + delete oldest in `saveMemory()`.
6. **MessagingAgent tests** — 3–4 hours. Follow existing agent test pattern.
7. **Update GAP_ANALYSIS.md** — 1 hour. Mark fixed gaps, add new ones.
