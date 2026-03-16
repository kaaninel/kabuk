# MCP Integration Plan for Kabuk

> Model Context Protocol (MCP) support for extending the local LLM with external tools and data sources.

## What is MCP?

[Model Context Protocol](https://modelcontextprotocol.io) is an open standard that defines how AI models (LLMs) communicate with external tools, data sources, and services. An MCP server exposes a set of **tools** (functions the LLM can call) and optionally **resources** (data the LLM can read) over a standard JSON-RPC protocol transported via stdio or HTTP/SSE.

The LLM client (Kabuk) discovers available tools from each connected server, injects them into its prompt alongside native tools, and routes the LLM's tool calls to the correct server. Results flow back to the LLM for synthesis into a final response.

---

## Why MCP Matters for Kabuk

Kabuk's local LLM is the primary AI. Its capabilities are bounded by what can fit on-device. MCP resolves this without compromising privacy:

- **Extensible without code changes.** New tools arrive by connecting a new MCP server, not by updating the app.
- **Privacy-preserving.** MCP servers run locally by default. External data never goes to a cloud LLM unless the user explicitly connects a remote server.
- **Ecosystem leverage.** A growing community of MCP servers covers filesystem, web search, calendars, code, databases, and more — all usable immediately.
- **Agent augmentation.** Domain agents (NoteAgent, CalendarAgent, etc.) gain access to tools beyond their built-in set, letting the local LLM fill gaps organically.

---

## Architecture

### How MCP Fits into the Agent Layer

```
User message
    │
    ▼
RouterAgent → DomainAgent.process(message, context)
                          │
                          ▼
              AgentContext.llm.complete(LlmRequest {
                tools: [
                  ...agent.tools,           // native AgentTool objects
                  ...context.mcp.tools(),   // discovered MCP tools
                ]
              })
                          │
              LLM selects tool, returns ToolCall
                          │
              ┌───────────┴────────────┐
              │                        │
      Native tool call         MCP tool call (prefix: "mcp:")
      executed in isolate              │
                                       ▼
                          AgentContext.mcp.invoke(
                            server: "filesystem",
                            tool: "read_file",
                            args: { path: "~/notes.txt" }
                          )
                                       │
                                MCP server responds
                                       │
                            Tool result returned to LLM
                            for final synthesis
```

### McpClient Interface

`McpClient` lives in `lib/services/mcp.dart` and is exposed on `AgentContext`:

```dart
/// Connects the local LLM to external MCP servers.
abstract class McpClient {
  /// Discover all tools from all connected, available servers.
  Future<List<McpTool>> discoverTools();

  /// Invoke a tool on a specific server.
  Future<McpToolResult> invoke(
    String serverName,
    String toolName,
    Map<String, dynamic> args,
  );

  /// List configured servers and their connection status.
  Future<List<McpServerInfo>> listServers();

  /// Stream of server connection/disconnection events.
  Stream<McpServerEvent> get serverEvents;
}
```

### Key Data Models (Freezed)

```dart
@freezed
class McpTool with _$McpTool {
  const factory McpTool({
    required String serverName,
    required String name,
    required String description,
    required Map<String, dynamic> inputSchema, // JSON Schema
  }) = _McpTool;
}

@freezed
class McpServerInfo with _$McpServerInfo {
  const factory McpServerInfo({
    required String name,
    required McpTransportType transport,
    required McpConnectionStatus status,
    required List<McpTool> tools,
  }) = _McpServerInfo;
}

sealed class McpToolResult {
  factory McpToolResult.text(String content);
  factory McpToolResult.json(Map<String, dynamic> data);
  factory McpToolResult.error(String message);
}
```

### Transport Types

| Transport | Use Case | Implementation |
|-----------|----------|----------------|
| **stdio** | Local MCP server processes (spawned by Kabuk) | `dart:io` process spawn |
| **HTTP/SSE** | Remote MCP servers or local servers with HTTP interface | `http` + `web_socket_channel` |

Stdio transport is preferred for local servers — zero network overhead, fully offline, process lifecycle tied to the app session.

---

## Tool Discovery and LLM Integration

When building an `LlmRequest`, the `LlmService` implementation merges native tools and MCP tools:

```dart
final nativeTools = agent.tools.map((t) => t.toLlmTool());
final mcpTools = await context.mcp.discoverTools()
    .then((tools) => tools.map((t) => t.toLlmTool(prefix: 'mcp:')));

final request = LlmRequest(
  messages: history,
  tools: [...nativeTools, ...mcpTools],
  systemPrompt: agent.systemPrompt,
);
```

MCP tool names are prefixed with `mcp:<server_name>:` in the LLM context to avoid collisions with native tools. When the LLM returns a tool call with this prefix, the `AgentRuntime` routes it to `McpClient.invoke()` instead of the native tool executor.

---

## Example MCP Servers for Kabuk

### Local Servers (bundled or easy to install)

| Server | Tools | Use Case |
|--------|-------|----------|
| **filesystem** | `read_file`, `write_file`, `list_directory`, `search_files` | Access documents, config files, project folders |
| **fetch** | `fetch_url` | Read web pages, APIs, RSS feeds natively |
| **sqlite** | `query`, `describe_table` | Query local databases (e.g., app data, exported data) |
| **memory** | `save_memory`, `recall`, `list_memories` | Extended key-value memory beyond the RDF store |

### Community Servers (user-installed)

| Server | Tools | Use Case |
|--------|-------|----------|
| **github** | `search_repos`, `list_issues`, `create_pr` | Developer workflows |
| **google-calendar** | `list_events`, `create_event` | CalDAV alternative |
| **slack** | `list_channels`, `send_message` | Workspace messaging |
| **brave-search** | `web_search` | Live web search results |
| **postgres** | SQL query execution | Access production databases |

### Integration with Existing Kabuk Agents

MCP servers complement, they don't replace, built-in agents:

- **CalendarAgent** + a CalDAV MCP server → bidirectional sync with external calendars
- **FileAgent** + filesystem MCP server → read files anywhere on disk, not just the vault
- **SearchAgent** + web-search MCP server → blend local FTS results with live web results
- **NoteAgent** + memory MCP server → persist agent reasoning across invocations

---

## Implementation Phases

### Phase 1 — Foundation (Week 1)

**Goal:** Define the interface and wire it into `AgentContext`. No functional servers yet.

- [ ] `lib/services/mcp.dart` — `McpClient` abstract interface
- [ ] `lib/knowledge/types/mcp.dart` — `McpTool`, `McpServerInfo`, `McpToolResult` Freezed models
- [ ] `lib/agents/runtime.dart` — add `McpClient mcpClient` to `AgentContext`
- [ ] `lib/platform/shared/mcp_noop.dart` — no-op implementation for tests
- [ ] Unit tests for interface contracts

### Phase 2 — Transports (Weeks 2–3)

**Goal:** Implement stdio and HTTP transports, make tool discovery functional.

- [ ] `lib/platform/shared/stdio_mcp_transport.dart` — spawn + communicate with local MCP processes
- [ ] `lib/platform/shared/http_mcp_transport.dart` — JSON-RPC over HTTP/SSE
- [ ] `lib/platform/shared/mcp_client_impl.dart` — `McpClientImpl` backed by transports
- [ ] `mcpClientProvider` Riverpod provider, reads server list from config store
- [ ] Tool discovery: fetch schemas at connection time, cache until reconnect
- [ ] Integration test: connect to a real filesystem MCP server (stdio)

### Phase 3 — LLM Integration (Week 4)

**Goal:** MCP tools appear in every LLM request alongside native tools.

- [ ] Merge native + MCP tools in `LlmRequest` construction
- [ ] `AgentRuntime` routes `mcp:`-prefixed tool calls to `McpClient.invoke()`
- [ ] Error handling: MCP server unavailable → graceful degradation (tool marked unavailable)
- [ ] Integration test: end-to-end LLM → MCP tool call → result synthesis

### Phase 4 — Configuration UI (Week 5)

**Goal:** Users can add/remove/manage MCP servers from Settings.

- [ ] `lib/ui/settings/mcp_settings_page.dart` — server list, add/remove, connection status
- [ ] Server config stored as triples in the knowledge store (`kabuk:mcpServer`)
- [ ] Per-server enable/disable toggle
- [ ] Connection status indicator (connected, error, offline)

### Phase 5 — Bundled Servers (Weeks 5–6)

**Goal:** Kabuk ships with useful MCP servers enabled by default.

- [ ] Bundle the `filesystem` MCP server (read access to user-selected directories)
- [ ] Bundle the `fetch` MCP server for URL reading
- [ ] Onboarding step: "Allow AI to read your files?" (opt-in, not forced)
- [ ] Document community server installation in `docs/MCP_SERVERS.md`

---

## Security Model

MCP servers run as separate processes (stdio) or remote services (HTTP). Kabuk enforces:

1. **User consent** — servers are only connected if the user explicitly adds them in Settings.
2. **Tool-level permissions** — agents can be restricted to specific MCP servers or tool names via the capability proxy in `AgentContext`.
3. **No automatic cloud calls** — HTTP MCP servers require the user to add them with a URL; Kabuk never connects to an MCP server automatically.
4. **Stdio sandboxing** — local server processes inherit minimal environment variables and run with the app's file permissions, not root.
5. **Result validation** — `McpToolResult` values are validated against the tool's output schema before being passed to the LLM.

---

## Configuration Format

MCP server configurations are stored as RDF triples:

```
<kabuk:mcp/server/filesystem>
    rdf:type           kabuk:McpServer ;
    schema:name        "filesystem" ;
    kabuk:transport    "stdio" ;
    kabuk:command      "npx @modelcontextprotocol/server-filesystem ~/Documents" ;
    kabuk:enabled      "true"^^xsd:boolean ;
    kabuk:addedAt      "2026-03-01T00:00:00Z"^^xsd:dateTime .
```

This integrates naturally with the knowledge store reactive system — when a server config triple changes, the `mcpClientProvider` rebuilds and reconnects.

---

## References

- [Model Context Protocol specification](https://modelcontextprotocol.io/specification)
- [MCP server registry](https://github.com/modelcontextprotocol/servers)
- [docs/AGENTS.md](AGENTS.md) — MCP integration overview in the agent system design
- [docs/ARCHITECTURE.md](ARCHITECTURE.md) — MCP in the Agent Layer architecture diagram
- [docs/IMPROVEMENT_ROADMAP.md](IMPROVEMENT_ROADMAP.md) — Phase E implementation plan
