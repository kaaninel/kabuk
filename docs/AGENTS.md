# Agent System Design

> Core design document for the Kabuk agent architecture — the primary interaction layer of the personal OS shell.

## Philosophy

Users interact with the system primarily through small, specialized agents via chat. Each agent is an expert in one domain. Agents are stateless — all persistent state lives in the RDF knowledge store. Agents can generate UI on the fly using Remote Flutter Widgets (RFW). The system should feel like talking to a knowledgeable assistant that can show you things, not just tell you.

**Core principles:**

- **Chat-first**: Every capability is reachable through natural language. The chat is not a secondary interface — it *is* the interface.
- **Stateless agents**: An agent receives a message, does work, returns a result. It holds no memory between invocations. All persistence is delegated to the knowledge store (RDF triples). This makes agents trivially restartable, replaceable, and testable.
- **Composable tools**: Agents expose typed tools with JSON Schema parameters. Tools are the atomic unit of capability. An agent's power comes from the tools it wires together.
- **Visual responses**: Agents don't just return text. They return RFW widget templates bound to live data. A note agent shows you a formatted note card. A calendar agent shows you a week view. The UI is generated, not hardcoded.
- **Least privilege**: Agents declare the capabilities they need. The system grants only what is necessary. A note agent cannot access the camera. A media agent cannot send network requests (unless explicitly granted).

---

## Agent Architecture

### Base Agent

```dart
// Conceptual — not actual code, guide for implementation
abstract class BaseAgent {
  /// Unique identifier for this agent (e.g., "note", "file", "system")
  String get name;

  /// Human-readable description shown in agent listing
  String get description;

  /// System prompt injected into every LLM call this agent makes.
  /// Defines the agent's personality, constraints, and domain expertise.
  String get systemPrompt;

  /// Tools this agent exposes. Declared statically so the router
  /// can inspect capabilities without instantiating the agent.
  List<AgentTool> get tools;

  /// Required capabilities. The runtime will refuse to invoke the agent
  /// if the user hasn't granted these.
  List<String> get requiredCapabilities;

  /// Process a single message. The agent may make multiple LLM calls
  /// and tool invocations within a single process() call.
  Future<AgentResponse> process(AgentMessage message, AgentContext context);
}
```

**Design notes:**
- `process()` is the single entry point. The agent receives everything it needs via `message` (what the user said, conversation history) and `context` (services it can call).
- Agents should *not* store instance state between `process()` calls. If an agent needs to "remember" something, it writes it to the knowledge store.
- The `systemPrompt` is critical — it shapes the agent's LLM reasoning. Each agent has a carefully crafted prompt that constrains it to its domain and instructs it on when/how to use its tools.

### Agent Tool Protocol

```dart
class AgentTool {
  /// Tool name, used in LLM function calling (e.g., "create_note")
  final String name;

  /// Human-readable description. Also injected into LLM context so the
  /// model understands when to invoke this tool.
  final String description;

  /// JSON Schema defining the tool's parameters. Used for:
  /// 1. LLM function calling schema
  /// 2. Runtime parameter validation before execution
  /// 3. Auto-generating documentation
  final JsonSchema parameters;

  /// The tool implementation. Receives validated parameters and a context
  /// providing access to system services.
  final Future<ToolResult> Function(Map<String, dynamic> args, AgentContext ctx) execute;
}
```

**Tool results are a sealed type hierarchy:**

```dart
sealed class ToolResult {
  /// Plain text response — displayed as chat message
  factory ToolResult.text(String content);

  /// RFW widget to render inline in the chat.
  /// `template` is the RFW template string (compiled to binary on send).
  /// `data` is the dynamic data bound into the template.
  factory ToolResult.widget(RfwTemplate template, Map<String, dynamic> data);

  /// Knowledge store mutation — triples to add and/or remove.
  /// Applied atomically after the tool returns.
  factory ToolResult.mutation(List<Triple> added, List<Triple> removed);

  /// Compound result — combine multiple results in one response.
  /// Common pattern: mutation + widget (update state, then show UI).
  factory ToolResult.compound(List<ToolResult> results);

  /// Error — displayed to user and logged. Does not crash the agent.
  factory ToolResult.error(String message);
}
```

**Why `sealed`?** The sealed type ensures exhaustive matching. Every consumer of `ToolResult` must handle all variants. This prevents silent failures where a new result type is added but not rendered.

**Common patterns:**

```dart
// Create a note and show it
ToolResult.compound([
  ToolResult.mutation(
    added: [Triple(noteUri, rdf.type, schema.NoteDigitalDocument), ...],
    removed: [],
  ),
  ToolResult.widget(noteCardTemplate, {'title': title, 'content': content}),
]);

// Search and display results
ToolResult.widget(searchResultsTemplate, {'results': matchingNotes});

// Simple confirmation
ToolResult.text('Note deleted.');
```

### Agent Context

```dart
class AgentContext {
  /// Read/write RDF triples in the knowledge store.
  /// This is the primary persistence layer for all structured data.
  final KnowledgeStore knowledge;

  /// File operations — read, write, list, tag files in the vault.
  /// The vault is the user's encrypted file storage.
  final VaultService vault;

  /// Network operations — peer discovery, data sync, mesh messaging.
  final MeshService mesh;

  /// Camera, microphone, media playback.
  final MediaService media;

  /// Push notifications and reminders.
  final NotificationService notify;

  /// Make LLM calls — chat completion, embedding, etc.
  /// Abstracts provider details (OpenAI, Anthropic, local).
  final LlmService llm;

  /// Invoke other agents. Enables agent-to-agent collaboration.
  /// Recursion-limited (max depth 3).
  final AgentRuntime runtime;

  /// Auth and encryption services.
  final AuthService auth;

  /// Current user identity and granted capabilities.
  final UserSession session;
}
```

**Capability enforcement:** The `AgentContext` provided to an agent is *scoped*. If an agent doesn't have `vault:write` capability, calling `vault.write()` throws a `CapabilityDeniedException`. This is enforced at the service proxy layer, not by trusting the agent.

### Agent Runtime

The runtime is responsible for agent lifecycle management, isolation, and resource control.

**Isolation model:**

- Agents run in **Dart isolates** for sandboxing. Each agent invocation gets its own isolate (or a reused one from the pool).
- `AgentRuntime` manages the lifecycle: spawn, message, terminate.
- Message passing via `SendPort`/`ReceivePort` with JSON serialization. All messages crossing the isolate boundary are serializable — no shared mutable state.
- Concurrent agent execution: multiple isolates can run simultaneously for parallel agent invocations (e.g., router dispatches to two agents).

**Agent pool:**

```
┌──────────────────────────────────────────────────────┐
│                   AgentRuntime                        │
│                                                      │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  │
│  │  Isolate 1  │  │  Isolate 2  │  │  Isolate 3  │  │
│  │  NoteAgent   │  │  FileAgent   │  │  (idle)     │  │
│  │  [active]    │  │  [active]    │  │  [pooled]   │  │
│  └──────┬───────┘  └──────┬───────┘  └─────────────┘  │
│         │                 │                            │
│  ┌──────▼─────────────────▼──────────────────────┐    │
│  │           Message Router (main isolate)        │    │
│  └────────────────────┬──────────────────────────┘    │
│                       │                               │
└───────────────────────┼───────────────────────────────┘
                        │
                   User Messages
```

**Resource limits:**

| Resource      | Limit         | Enforcement                     |
|---------------|---------------|---------------------------------|
| Execution time | 30s default   | Timer-based kill                |
| Memory         | 64MB per isolate | Isolate memory limit (Dart VM) |
| LLM calls      | 10 per invocation | Counter in context proxy       |
| Tool calls     | 20 per invocation | Counter in runtime             |
| Recursion depth | 3 levels      | Depth counter in context        |
| Concurrent isolates | 4 max    | Semaphore in runtime            |

**Lifecycle:**

1. **Spawn**: Runtime selects an idle isolate from the pool or creates a new one. Agent class is instantiated inside the isolate.
2. **Message**: Serialized `AgentMessage` is sent via `SendPort`. Agent processes it and returns serialized `AgentResponse`.
3. **Recycle**: After response, the isolate is returned to the pool (agent instance is dropped, isolate is reused).
4. **Terminate**: If the agent exceeds resource limits, the isolate is killed immediately via `Isolate.kill()`.

### Router Agent

The router is special — it runs in the **main isolate** (not sandboxed) and is the entry point for all user messages.

**Routing flow:**

```
User Message
     │
     ▼
┌─────────────────┐
│   RouterAgent    │
│                  │
│  1. Parse input  │
│  2. Load context │──── Conversation history (last N messages)
│  3. Classify     │──── LLM call with agent descriptions
│  4. Route        │
│                  │
└────────┬─────────┘
         │
    ┌────┴────┐
    │         │
    ▼         ▼
 Direct    Domain Agent
 Answer    (via runtime)
```

**Classification prompt structure:**

```
You are a message router for a personal OS. Given the user's message
and conversation history, determine which agent should handle it.

Available agents:
- note: Create, edit, search, organize text notes
- file: Manage files, tag-based organization
- system: System settings, preferences, status
- ...

Respond with a JSON object: {"agent": "name", "confidence": 0.0-1.0}
If confidence < 0.7, respond with {"agent": "clarify", "question": "..."}
If the message is simple chitchat or a direct question you can answer,
respond with {"agent": "self", "response": "..."}
```

**Multi-turn awareness:**

The router maintains a **conversation context window** (last N messages, configurable, default 20). This enables:

- Follow-up questions: "What about the second one?" → Router knows we were talking about notes.
- Implicit agent selection: If the last 3 messages went to NoteAgent, a vague "delete it" routes to NoteAgent.
- Context switching: "Actually, show me my files instead" → Router detects intent change.

**Router capabilities:**

- Handles simple greetings/chitchat directly (no agent dispatch needed)
- Asks clarifying questions when intent is ambiguous
- Supports explicit agent targeting: "@note create a new note" bypasses classification
- Logs routing decisions for debugging and improvement
- Maintains per-conversation agent affinity (sticky routing for multi-turn)

---

## Domain Agents (Planned)

### Phase 1 Agents

Phase 1 delivers the minimum viable agent set: notes, files, and system management. These three agents cover the core personal OS use cases and exercise the full agent pipeline (LLM reasoning → tool execution → knowledge store mutation → RFW rendering).

---

#### 1. NoteAgent

**Purpose:** Create, edit, search, and organize text notes. The primary "quick capture" agent — designed for fast note-taking via chat.

**System prompt essence:**
> You are a note-taking assistant. Help the user capture, organize, and find their notes. Be concise. When creating notes, infer a good title if the user doesn't provide one. When searching, show the most relevant results first. Always offer to tag notes for better organization.

**Tools:**

| Tool | Parameters | Returns | Description |
|------|-----------|---------|-------------|
| `create_note` | `title: string, content: string, tags: string[]?` | `ToolResult.compound([mutation, widget])` | Creates a Note triple in the knowledge store. Returns the rendered note card. |
| `edit_note` | `id: string, content: string?, title: string?, tags: string[]?` | `ToolResult.compound([mutation, widget])` | Updates an existing note. Partial updates supported. |
| `search_notes` | `query: string, tags: string[]?, limit: int?` | `ToolResult.widget(searchResults)` | Full-text search over notes. Uses knowledge store SPARQL query + optional LLM re-ranking. |
| `list_notes` | `tags: string[]?, limit: int?, sort: string?` | `ToolResult.widget(noteList)` | List notes, optionally filtered by tags. Sort by created, modified, or title. |
| `delete_note` | `id: string` | `ToolResult.compound([mutation, text])` | Removes note triples from knowledge store. Asks for confirmation first. |
| `generate_note_view` | `notes: string[]` | `ToolResult.widget(noteGrid)` | Returns an RFW widget displaying a grid/list of notes. Used by other tools internally. |

**Knowledge store schema:**

```turtle
@prefix schema: <https://schema.org/> .
@prefix kabuk: <https://kabuk.dev/ns/> .

<note/uuid> a schema:NoteDigitalDocument ;
    schema:name "Title" ;
    schema:text "Content body" ;
    schema:dateCreated "2026-02-25T10:30:00Z"^^xsd:dateTime ;
    schema:dateModified "2026-02-25T10:30:00Z"^^xsd:dateTime ;
    kabuk:tag "personal", "ideas" ;
    schema:author <user/self> .
```

**Schema.org types:** `Note`, `NoteDigitalDocument`

**Required capabilities:** `knowledge:read`, `knowledge:write`

**RFW templates:**
- `note_card.rfwt` — Single note display (title, content preview, tags, dates)
- `note_list.rfwt` — Scrollable list of notes with search bar
- `note_editor.rfwt` — Inline editor for quick edits

**Example interactions:**

```
User: "jot down: meeting with Alex tomorrow 3pm to discuss project timeline"
→ NoteAgent creates note with title "Meeting with Alex" and full content,
  tags: ["meeting", "alex"]. Returns note card widget.

User: "find my notes about project timeline"
→ NoteAgent runs search_notes("project timeline"), returns results widget.

User: "tag it as urgent"
→ NoteAgent (multi-turn context) edits the last referenced note, adds "urgent" tag.
```

---

#### 2. FileAgent

**Purpose:** Manage files in the vault with tag-based organization. Think of it as a smart file manager that understands natural language queries and organizes by meaning, not just folders.

**System prompt essence:**
> You are a file management assistant. Help the user find, organize, and manage their files. Prefer tag-based organization over deep folder hierarchies. When listing files, show relevant metadata. Suggest tags based on file content when possible.

**Tools:**

| Tool | Parameters | Returns | Description |
|------|-----------|---------|-------------|
| `list_files` | `tags: string[]?, type: string?, folder: string?, limit: int?` | `ToolResult.widget(fileList)` | List files in vault. Filter by tags, MIME type, or folder. |
| `tag_file` | `id: string, add: string[]?, remove: string[]?` | `ToolResult.compound([mutation, text])` | Add or remove tags from a file. Tags are stored as knowledge store triples. |
| `move_file` | `id: string, folder: string` | `ToolResult.compound([mutation, text])` | Move file to a different folder in the vault. |
| `get_metadata` | `id: string` | `ToolResult.widget(metadataCard)` | Extract and display file metadata (size, type, dates, EXIF for images, etc.). |
| `create_smart_folder` | `name: string, query: string, tags: string[]?` | `ToolResult.mutation(...)` | Create a saved search that acts as a virtual folder. Stored as a knowledge triple. |
| `preview_file` | `id: string` | `ToolResult.widget(filePreview)` | Returns RFW widget with file preview. Images rendered inline, text shown, PDFs get first page, etc. |

**Knowledge store schema:**

```turtle
<file/uuid> a schema:DigitalDocument ;
    schema:name "report.pdf" ;
    schema:encodingFormat "application/pdf" ;
    schema:contentSize "2048000"^^xsd:integer ;
    schema:dateCreated "2026-02-25T10:30:00Z"^^xsd:dateTime ;
    kabuk:tag "work", "reports" ;
    kabuk:vaultPath "/documents/report.pdf" ;
    schema:author <user/self> .

<smart-folder/uuid> a kabuk:SmartFolder ;
    schema:name "Recent Photos" ;
    kabuk:query "type:image modified:>7d" ;
    kabuk:tag "photos" .
```

**Schema.org types:** `DigitalDocument`, `MediaObject`, `DataDownload`

**Required capabilities:** `vault:read`, `vault:write`, `knowledge:read`, `knowledge:write`

**RFW templates:**
- `file_list.rfwt` — Grid/list view of files with thumbnails
- `file_preview.rfwt` — File preview with metadata sidebar
- `metadata_card.rfwt` — Detailed metadata display

---

#### 3. SystemAgent

**Purpose:** System settings, preferences, status monitoring, and agent management. The "control panel" agent.

**System prompt essence:**
> You are the system management assistant. Help the user configure their personal OS, check system status, and manage installed agents. Be direct and technical when appropriate. For destructive operations (clearing data, uninstalling agents), always confirm first.

**Tools:**

| Tool | Parameters | Returns | Description |
|------|-----------|---------|-------------|
| `get_status` | none | `ToolResult.widget(statusDashboard)` | System status: storage usage, battery level, network state, active agents, knowledge store stats. |
| `set_preference` | `key: string, value: any` | `ToolResult.compound([mutation, text])` | Set a user preference. Stored in knowledge store under user profile. |
| `get_preference` | `key: string` | `ToolResult.text(value)` | Read a preference value. |
| `list_agents` | none | `ToolResult.widget(agentList)` | Show all available agents with status, description, and capabilities. |
| `install_widget` | `repo: string, id: string` | `ToolResult.text(status)` | Install an RFW widget template from a repository. Validates and stores in vault. |

**Special properties:**
- Has **elevated capabilities** — can modify system config, manage other agents
- Runs with `system:admin` capability in addition to standard ones
- Can restart the agent runtime, clear caches, and perform maintenance tasks

**Knowledge store schema for preferences:**

```turtle
<user/self> kabuk:preference [
    kabuk:key "theme" ;
    kabuk:value "dark" ;
] .

<user/self> kabuk:preference [
    kabuk:key "llm.provider" ;
    kabuk:value "anthropic" ;
] .

<user/self> kabuk:preference [
    kabuk:key "llm.model" ;
    kabuk:value "claude-sonnet-4-20250514" ;
] .
```

**Required capabilities:** `knowledge:read`, `knowledge:write`, `system:admin`

---

### Phase 2 Agents

Phase 2 expands into PIM (Personal Information Management) territory: media, calendar, contacts, and universal search.

---

#### 4. MediaAgent

**Purpose:** Camera, audio recording, media playback, and media library management. The eyes and ears of the OS.

**System prompt essence:**
> You are a media assistant. Help the user capture photos, record audio/video, manage their media library, and find specific media. When showing media, use gallery views. Suggest organizing media by event, date, or people when appropriate.

**Tools:**

| Tool | Parameters | Returns | Description |
|------|-----------|---------|-------------|
| `capture_photo` | `options: {quality?, flash?, camera?}?` | `ToolResult.compound([mutation, widget])` | Opens camera UI, captures photo, stores in vault, creates knowledge triple. |
| `record_video` | `options: {quality?, maxDuration?}?` | `ToolResult.compound([mutation, widget])` | Video recording with configurable quality and duration limit. |
| `record_audio` | `options: {format?, maxDuration?}?` | `ToolResult.compound([mutation, widget])` | Audio recording. Returns waveform visualization widget. |
| `play_media` | `id: string` | `ToolResult.widget(mediaPlayer)` | Play audio or video. Returns embedded player widget. |
| `generate_thumbnail` | `id: string` | `ToolResult.mutation(...)` | Generate and store thumbnail for a media file. |
| `extract_metadata` | `id: string` | `ToolResult.widget(metadataCard)` | Extract EXIF data, duration, resolution, codec info, GPS coordinates, etc. |
| `search_media` | `query: string, type: string?` | `ToolResult.widget(gallery)` | Search photos/videos/audio by metadata, tags, dates, or description. |
| `create_gallery_view` | `items: string[], layout: string?` | `ToolResult.widget(gallery)` | RFW gallery widget. Supports grid, carousel, and timeline layouts. |

**Knowledge store schema:**

```turtle
<media/uuid> a schema:ImageObject ;
    schema:name "IMG_20260225.jpg" ;
    schema:encodingFormat "image/jpeg" ;
    schema:width "4032"^^xsd:integer ;
    schema:height "3024"^^xsd:integer ;
    schema:contentSize "3500000"^^xsd:integer ;
    schema:dateCreated "2026-02-25T14:30:00Z"^^xsd:dateTime ;
    schema:contentLocation [
        a schema:Place ;
        schema:latitude "41.0082" ;
        schema:longitude "28.9784" ;
    ] ;
    kabuk:vaultPath "/media/photos/2026/02/IMG_20260225.jpg" ;
    kabuk:thumbnail "/media/thumbs/uuid.jpg" ;
    kabuk:tag "istanbul", "travel" .
```

**Schema.org types:** `ImageObject`, `VideoObject`, `AudioObject`, `MediaObject`

**Required capabilities:** `media:capture`, `media:playback`, `vault:write`, `knowledge:write`

---

#### 5. CalendarAgent

**Purpose:** Manage events, reminders, and scheduling. Time-aware agent that integrates with the notification system.

**System prompt essence:**
> You are a calendar and scheduling assistant. Help the user manage events, set reminders, and plan their time. When creating events, infer reasonable defaults (e.g., 1-hour duration). Show upcoming events proactively. Use natural language time parsing ("next Tuesday", "in 2 hours").

**Tools:**

| Tool | Parameters | Returns | Description |
|------|-----------|---------|-------------|
| `create_event` | `title: string, start: datetime, end: datetime?, location: string?, description: string?, reminders: string[]?` | `ToolResult.compound([mutation, widget])` | Create a new calendar event. Supports recurring events via RRULE. |
| `list_events` | `from: datetime, to: datetime` | `ToolResult.widget(calendarView)` | Events in a date range. Returns day/week/month view based on range size. |
| `set_reminder` | `text: string, datetime: datetime, repeat: string?` | `ToolResult.compound([mutation, text])` | Set a reminder. Schedules a notification via NotificationService. |
| `search_events` | `query: string` | `ToolResult.widget(eventList)` | Search events by title, description, location, or attendees. |
| `generate_calendar_view` | `events: string[], view: string?` | `ToolResult.widget(calendar)` | RFW calendar widget. Supports day, week, month, and agenda views. |

**Knowledge store schema:**

```turtle
<event/uuid> a schema:Event ;
    schema:name "Team Standup" ;
    schema:startDate "2026-02-25T09:00:00Z"^^xsd:dateTime ;
    schema:endDate "2026-02-25T09:30:00Z"^^xsd:dateTime ;
    schema:location "Conference Room A" ;
    schema:description "Daily standup meeting" ;
    kabuk:reminder "15m" ;
    kabuk:recurrence "RRULE:FREQ=DAILY;BYDAY=MO,TU,WE,TH,FR" .
```

**Schema.org types:** `Event`, `Schedule`

**Required capabilities:** `knowledge:read`, `knowledge:write`, `notify:send`

---

#### 6. ContactAgent

**Purpose:** Manage contacts and relationships. Integrates with other agents (CalendarAgent for event attendees, ChatAgent for messaging).

**System prompt essence:**
> You are a contact management assistant. Help the user manage their contacts and relationships. When creating contacts, capture all provided information. Suggest linking contacts to events and notes when relevant.

**Tools:**

| Tool | Parameters | Returns | Description |
|------|-----------|---------|-------------|
| `create_contact` | `name: string, email: string?, phone: string?, organization: string?, ...` | `ToolResult.compound([mutation, widget])` | Create a new contact. Flexible schema — stores whatever info is provided. |
| `search_contacts` | `query: string` | `ToolResult.widget(contactList)` | Search contacts by name, email, phone, organization, or tags. |
| `get_contact` | `id: string` | `ToolResult.widget(contactCard)` | Full contact details with linked notes, events, and messages. |
| `update_contact` | `id: string, fields: map` | `ToolResult.compound([mutation, widget])` | Update contact fields. Partial updates supported. |
| `generate_contact_card` | `id: string` | `ToolResult.widget(contactCard)` | RFW contact card with photo, details, and quick actions (call, email, message). |

**Knowledge store schema:**

```turtle
<contact/uuid> a schema:Person ;
    schema:name "Alex Johnson" ;
    schema:email "alex@example.com" ;
    schema:telephone "+1-555-0123" ;
    schema:worksFor [
        a schema:Organization ;
        schema:name "Acme Corp" ;
    ] ;
    schema:image <media/uuid-avatar> ;
    kabuk:tag "work", "engineering" ;
    schema:dateCreated "2026-02-25T10:00:00Z"^^xsd:dateTime .
```

**Schema.org types:** `Person`, `Organization`, `ContactPoint`

**Required capabilities:** `knowledge:read`, `knowledge:write`

---

#### 7. SearchAgent

**Purpose:** Universal search across the entire knowledge store. The "find anything" agent.

**System prompt essence:**
> You are a search assistant. Help the user find anything in their personal OS — notes, files, contacts, events, media, or any other data. Use semantic understanding to find relevant results even when exact keywords don't match. Show results grouped by type.

**Tools:**

| Tool | Parameters | Returns | Description |
|------|-----------|---------|-------------|
| `search` | `query: string, types: string[]?, limit: int?` | `ToolResult.widget(searchResults)` | Search across all types in the knowledge store. SPARQL full-text query. |
| `semantic_search` | `query: string, limit: int?` | `ToolResult.widget(searchResults)` | LLM-enhanced semantic search. Embeds the query, finds similar content by vector similarity. Falls back to keyword search if embedding service is unavailable. |
| `generate_results_view` | `results: map[]` | `ToolResult.widget(searchResults)` | RFW search results widget with type-specific rendering (note cards, file icons, contact avatars, etc.). |

**How semantic search works:**

1. User query is embedded via `LlmService.embed(query)`.
2. Knowledge store triples with text content are pre-embedded (on write) and stored with their vectors.
3. Cosine similarity search finds the top-K most similar triples.
4. Results are optionally re-ranked by the LLM for relevance.
5. Results are grouped by Schema.org type and rendered with type-appropriate widgets.

**Required capabilities:** `knowledge:read`

---

### Phase 3 Agents

Phase 3 extends into communication, external services, and development tools.

---

#### 8. ChatAgent (Human-to-Human Messaging)

**Purpose:** Send and receive messages with other Kabuk users. This is not AI chat — it's person-to-person communication.

**Architecture:**
- Uses `MeshService` for transport (peer-to-peer when possible, relay when not)
- Protocol: Matrix (preferred for federation) or custom gRPC (for mesh-native transport)
- End-to-end encryption via `AuthService` (Double Ratchet / Olm)
- Message history stored in local knowledge store
- Push notifications for incoming messages via `NotificationService`

**Knowledge store schema:**

```turtle
<conversation/uuid> a schema:Conversation ;
    schema:name "Chat with Alex" ;
    schema:participant <contact/uuid-alex>, <user/self> ;
    schema:dateCreated "2026-02-25T10:00:00Z"^^xsd:dateTime .

<message/uuid> a schema:Message ;
    schema:text "Hey, are we still meeting tomorrow?" ;
    schema:sender <contact/uuid-alex> ;
    schema:dateCreated "2026-02-25T14:30:00Z"^^xsd:dateTime ;
    schema:isPartOf <conversation/uuid> ;
    kabuk:encrypted "true"^^xsd:boolean .
```

**Schema.org types:** `Message`, `Conversation`

**Required capabilities:** `mesh:connect`, `mesh:send`, `knowledge:read`, `knowledge:write`, `notify:send`, `auth:sign`

---

#### 9. Provider Agents (External Service Adapters)

Provider agents bridge external protocols into the Kabuk knowledge store. Each one wraps a specific protocol and maps external data to Schema.org types.

**RssAgent:**
- Fetches RSS/Atom feeds on a schedule
- Maps entries to `schema:Article` triples
- Tool: `add_feed(url)`, `list_feeds()`, `refresh(feed_id?)`, `search_articles(query)`
- Capabilities: `mesh:connect`, `knowledge:read`, `knowledge:write`

**EmailAgent:**
- IMAP/SMTP email management
- Maps emails to `schema:EmailMessage` triples
- Tools: `fetch_mail(folder?, limit?)`, `send_email(to, subject, body)`, `search_email(query)`, `move_to_folder(id, folder)`
- Capabilities: `mesh:connect`, `mesh:send`, `knowledge:read`, `knowledge:write`, `auth:sign`

**CalDavAgent:**
- Bidirectional sync with CalDAV servers (Google Calendar, iCloud, Nextcloud)
- Maps to same `schema:Event` triples as CalendarAgent
- Tools: `add_server(url, credentials)`, `sync(server_id?)`, `push_event(event_id, server_id)`
- Capabilities: `mesh:connect`, `knowledge:read`, `knowledge:write`

**CardDavAgent:**
- Bidirectional sync with CardDAV servers for contacts
- Maps to same `schema:Person` triples as ContactAgent
- Tools: `add_server(url, credentials)`, `sync(server_id?)`, `push_contact(contact_id, server_id)`
- Capabilities: `mesh:connect`, `knowledge:read`, `knowledge:write`

**Provider agent design principles:**
- Each provider agent is optional — the system works fully offline without them
- External credentials are stored encrypted in the vault (never in knowledge store)
- Sync is always user-initiated or explicitly scheduled (no background polling without consent)
- Conflicts resolved by "last write wins" with full history for manual resolution

---

#### 10. CodeAgent

**Purpose:** Code editing, running scripts, and development assistance. A lightweight development environment accessible through chat.

**Tools:**
- `run_script(code: string, language: string)` — Execute a script in a sandboxed isolate
- `edit_file(path: string, edits: Edit[])` — Apply edits to a file in the vault
- `explain_code(code: string)` — LLM-powered code explanation
- `generate_code(prompt: string, language: string)` — Generate code from natural language

**Sandboxing:**
- Scripts run in dedicated Dart isolates with no filesystem access
- Only Dart is natively supported; other languages require explicit runtime installation
- Execution timeout: 10 seconds
- Memory limit: 32MB
- No network access from scripts

**Required capabilities:** `vault:read`, `vault:write`, `llm:call`

---

## Agent Communication Protocol

### Message Format

All messages between system components (UI ↔ Router, Router ↔ Agent, Agent ↔ Agent) use a unified JSON format:

```json
{
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "type": "user_message | agent_response | tool_call | tool_result | system",
  "from": "user | agent_name",
  "to": "router | agent_name",
  "content": "text content",
  "tool_calls": [
    {
      "id": "call_550e8400-e29b-41d4-a716-446655440001",
      "name": "create_note",
      "arguments": {
        "title": "Meeting Notes",
        "content": "Discussed project timeline...",
        "tags": ["meeting", "project"]
      }
    }
  ],
  "tool_results": [
    {
      "call_id": "call_550e8400-e29b-41d4-a716-446655440001",
      "result": {
        "type": "compound",
        "results": [
          {
            "type": "mutation",
            "added": [
              { "s": "note/uuid", "p": "rdf:type", "o": "schema:NoteDigitalDocument" }
            ],
            "removed": []
          },
          {
            "type": "widget",
            "template": "note_card",
            "data": { "title": "Meeting Notes", "content": "Discussed project timeline..." }
          }
        ]
      }
    }
  ],
  "rfw_template": "optional pre-compiled RFW template (base64 binary)",
  "rfw_data": {
    "title": "Meeting Notes",
    "tags": ["meeting", "project"]
  },
  "metadata": {
    "timestamp": "2026-02-25T10:30:00Z",
    "conversation_id": "conv-550e8400-e29b-41d4-a716-446655440002",
    "capabilities_used": ["knowledge:read", "knowledge:write"],
    "agent_duration_ms": 1250,
    "llm_tokens_used": 450,
    "routing_confidence": 0.95
  }
}
```

**Message types:**

| Type | Direction | Description |
|------|-----------|-------------|
| `user_message` | User → Router | User's natural language input |
| `agent_response` | Agent → User | Agent's final response (text + optional widget) |
| `tool_call` | Agent → Runtime | Agent invokes a tool |
| `tool_result` | Runtime → Agent | Tool execution result |
| `system` | Runtime → Agent | System events (timeout warning, capability grant, error) |

### Conversation Flow

```
┌──────┐     ┌────────┐     ┌─────────┐     ┌────────────┐     ┌──────────────┐
│ User │     │   UI   │     │ Router  │     │  Runtime   │     │ Domain Agent │
└──┬───┘     └───┬────┘     └────┬────┘     └─────┬──────┘     └──────┬───────┘
   │             │               │                │                   │
   │  Message    │               │                │                   │
   ├────────────►│  user_message │                │                   │
   │             ├──────────────►│                │                   │
   │             │               │ LLM classify   │                   │
   │             │               ├──┐             │                   │
   │             │               │  │ intent      │                   │
   │             │               │◄─┘             │                   │
   │             │               │                │                   │
   │             │               │ spawn/reuse    │                   │
   │             │               ├───────────────►│                   │
   │             │               │                │  forward message  │
   │             │               │                ├──────────────────►│
   │             │               │                │                   │
   │             │               │                │                   ├──┐ LLM
   │             │               │                │                   │  │ reason
   │             │               │                │                   │◄─┘
   │             │               │                │                   │
   │             │               │                │  tool_call        │
   │             │               │                │◄─────────────────┤
   │             │               │                │                   │
   │             │               │                │  tool_result      │
   │             │               │                ├──────────────────►│
   │             │               │                │                   │
   │             │               │                │  agent_response   │
   │             │               │                │◄─────────────────┤
   │             │               │◄───────────────┤                   │
   │             │◄──────────────┤                │                   │
   │◄────────────┤ render chat + │                │                   │
   │   display   │ RFW widget    │                │                   │
```

**Step-by-step:**

1. **User sends message** — text input from chat UI
2. **Router classifies intent** — LLM call with conversation history and agent descriptions
3. **Router selects agent** — or handles directly if simple chitchat
4. **Runtime dispatches** — spawns/reuses isolate, sends serialized message
5. **Agent reasons** — makes LLM calls for understanding and planning
6. **Agent calls tools** — may call multiple tools, sequentially or in parallel
7. **Agent returns response** — text content + optional RFW widget + optional knowledge mutations
8. **UI renders** — chat bubble for text, embedded widget for RFW, reactive update if knowledge changed

### Multi-Agent Collaboration

Agents can invoke other agents through `AgentRuntime` in their context. This enables composition:

```dart
// Inside NoteAgent.process()
Future<AgentResponse> process(AgentMessage message, AgentContext context) async {
  // Ask SearchAgent to find related notes
  final searchResult = await context.runtime.invoke(
    agent: 'search',
    message: AgentMessage(content: 'notes about ${topic}'),
  );
  
  // Use results to provide context
  // ...
}
```

**Rules for multi-agent collaboration:**

- **Recursion depth limit:** Maximum 3 levels of agent invocation. Prevents infinite loops.
- **Circular invocation detection:** If Agent A invokes Agent B which invokes Agent A, the second invocation is rejected with an error.
- **Capability union:** The invoking agent cannot grant capabilities it doesn't have. The invoked agent runs with the intersection of its required capabilities and the invoker's granted capabilities.
- **Timeout inheritance:** The invoked agent's timeout is subtracted from the invoker's remaining timeout. No agent can extend its time by invoking another.
- **Result passthrough:** The invoking agent receives the full `ToolResult` from the invoked agent and can incorporate it into its own response.

**Common collaboration patterns:**

| Pattern | Example |
|---------|---------|
| Search delegation | NoteAgent → SearchAgent (find related notes) |
| Enrichment | CalendarAgent → ContactAgent (resolve attendee names) |
| Cross-reference | FileAgent → NoteAgent (find notes mentioning a file) |
| Notification | CalendarAgent → SystemAgent (schedule a reminder) |

---

## Agent Capability System

### Capability Model

Every agent declares the capabilities it requires. The runtime enforces these at the service proxy layer — agents physically cannot access services they haven't been granted.

**Defined capabilities:**

| Capability | Grants | Risk Level |
|------------|--------|------------|
| `knowledge:read` | Read triples from knowledge store | Low |
| `knowledge:write` | Write/delete triples in knowledge store | Medium |
| `vault:read` | Read files from the vault | Low |
| `vault:write` | Write/delete files in the vault | Medium |
| `media:capture` | Access camera and microphone | High |
| `media:playback` | Play audio/video | Low |
| `mesh:connect` | Establish network connections | Medium |
| `mesh:send` | Send data over network | Medium |
| `notify:send` | Send push notifications | Low |
| `auth:sign` | Sign data with user's keys | High |
| `llm:call` | Make LLM API calls (costs money/resources) | Medium |
| `agent:invoke` | Invoke other agents | Medium |
| `system:admin` | System configuration, agent management | Critical |

### Grant Flow

1. **First use:** When an agent is first invoked, the UI shows a capability grant dialog listing what the agent needs and why.
2. **User approves:** Grant is stored in the knowledge store. Subsequent invocations skip the dialog.
3. **Revocation:** User can revoke grants at any time via SystemAgent.
4. **Audit log:** All capability uses are logged for transparency.

**Knowledge store schema for grants:**

```turtle
<grant/uuid> a kabuk:CapabilityGrant ;
    kabuk:agent "note" ;
    kabuk:capability "knowledge:read", "knowledge:write" ;
    kabuk:grantedBy <user/self> ;
    kabuk:grantedAt "2026-02-25T10:00:00Z"^^xsd:dateTime ;
    kabuk:status "active" .
```

### Enforcement Architecture

```
Agent Isolate                    Main Isolate
┌───────────┐                   ┌──────────────────────┐
│           │  vault.write(f)   │  CapabilityProxy     │
│  Agent    ├──────────────────►│  ┌────────────────┐  │
│  Code     │                   │  │ Check grant     │  │
│           │                   │  │ "vault:write"   │  │
│           │  CapabilityDenied │  │ for "note"      │  │
│           │◄──────────────────│  └───────┬────────┘  │
│           │                   │          │ granted?   │
└───────────┘                   │          ▼            │
                                │  ┌────────────────┐  │
                                │  │ Real VaultSvc   │  │
                                │  │ .write(f)       │  │
                                │  └────────────────┘  │
                                └──────────────────────┘
```

The proxy pattern ensures that even if an agent somehow gains a reference to a service, the capability check is performed on every call. There is no way to bypass it from inside the isolate.

---

## LLM Integration

### LlmService

`LlmService` is the abstraction layer that lets agents make LLM calls without caring about the underlying provider.

```dart
abstract class LlmService {
  /// Chat completion with tool support
  Future<LlmResponse> complete(LlmRequest request);

  /// Streaming chat completion
  Stream<LlmChunk> completeStream(LlmRequest request);

  /// Generate embedding for text (for semantic search)
  Future<List<double>> embed(String text);

  /// Check if a model/provider is available
  Future<bool> isAvailable(String? model);
}
```

### Supported Backends

**Local providers are primary.** Kabuk defaults to the on-device model — the user's privacy is preserved from the first interaction. External cloud providers are optional extensions that the local model can delegate to when it lacks capability or capacity.

**Provider priority order (default): local → Ollama → Anthropic → OpenAI**

**1. Local Providers (Primary):**

| Provider | Integration | Use Case |
|----------|-------------|----------|
| llama.cpp | dart:ffi binding | Fully embedded, no server needed — **default** |
| Ollama | HTTP API (localhost:11434) | On-device server, model management UI |

- llama.cpp: Model files stored in vault, loaded on demand
- Ollama: User installs separately, Kabuk auto-detects running instance
- Smaller models for routing/classification, larger for reasoning
- Local model can forward specific sub-tasks to cloud providers when the user permits

**2. Remote Providers (Optional Extensions):**

| Provider | Models | Use Case |
|----------|--------|----------|
| Anthropic | Claude Sonnet, Haiku | Complex reasoning, tool use |
| OpenAI | GPT-4o, GPT-4o-mini | Alternative, embeddings |

- API keys stored in secure storage (platform keychain, not knowledge store)
- Rate limiting and cost tracking per-agent
- Automatic retry with exponential backoff
- Cloud calls only happen when: (a) user explicitly initiates, (b) local model delegates, or (c) user configures as default

### Prompt Construction

Every LLM call follows a structured prompt template:

```
┌─────────────────────────────────────┐
│ System Prompt (agent-specific)      │
│ "You are a note-taking assistant.." │
├─────────────────────────────────────┤
│ Knowledge Context (injected)        │
│ "User has 47 notes, 12 tagged       │
│  'work'. Last created: 2h ago."     │
├─────────────────────────────────────┤
│ Available Tools (JSON Schema)       │
│ [create_note, edit_note, ...]       │
├─────────────────────────────────────┤
│ Conversation History (last N msgs)  │
│ User: "make a note about..."        │
│ Assistant: "Created note..."        │
│ User: "tag it as urgent"            │
├─────────────────────────────────────┤
│ Current Message                     │
│ "tag it as urgent"                  │
└─────────────────────────────────────┘
```

**Knowledge context injection:** Before each LLM call, the agent queries the knowledge store for relevant context and injects a summary into the prompt. This gives the LLM awareness of the user's data without sending the entire knowledge store.

### Token Budget Management

LLM context windows are finite. The system manages token budgets:

1. **System prompt:** Fixed cost, always included (measured once per agent)
2. **Tools:** Fixed cost, always included (measured once per agent)
3. **Knowledge context:** Variable, capped at 20% of remaining budget
4. **Conversation history:** Variable, fills remaining space (oldest messages truncated first)
5. **Current message:** Always included in full

```
Total budget: 128K tokens (model-dependent)
─ System prompt:       ~500 tokens
─ Tools schema:        ~1000 tokens
─ Knowledge context:   ≤25,000 tokens
─ Conversation history: ≤100,000 tokens (truncated FIFO)
─ Current message:     variable
─ Response reserve:    ~4000 tokens
```

### Streaming

LLM responses are streamed to the UI in real-time:

1. Agent calls `llm.completeStream(request)`
2. Each `LlmChunk` is forwarded to the UI via the agent response stream
3. UI renders text incrementally (typewriter effect)
4. If a tool call is detected in the stream, execution begins immediately (parallel to continued streaming)
5. Final aggregated response is stored in conversation history

### Fallback Chain

The **local LLM is the primary provider**. If it fails or is unavailable:

1. **Retry** — same provider, exponential backoff (3 attempts)
2. **Ollama** — try local Ollama instance if available
3. **Cloud fallback** — try configured cloud provider (Anthropic → OpenAI) only if user has opted in to cloud fallback
4. **Degrade** — return error message to agent, agent returns graceful failure to user

Note: Cloud fallback only activates if the user has explicitly enabled it in settings. Privacy is never silently compromised.

---

## MCP Integration

MCP (Model Context Protocol) extends the local LLM's capabilities by connecting it to external tools and data sources through a standardized protocol. Rather than building every integration into Kabuk directly, MCP allows any compliant server to expose tools that the local LLM can discover and invoke.

### How MCP Fits the Agent Architecture

```
User message
    │
    ▼
RouterAgent → DomainAgent
                  │
                  ▼
           AgentContext.llm (local LLM)
                  │  ◄── Available tools = native AgentTools + MCP server tools
                  ▼
           LLM selects and calls a tool
                  │
           ┌──────┴──────┐
           │             │
    Native tool     McpClient.invoke(server, tool, args)
    executed              │
    locally               ▼
                   MCP Server responds
                          │
                          ▼
                   Result returned to LLM
                   for synthesis
```

### McpClient in AgentContext

`AgentContext` exposes an `McpClient` that agents (and the LLM service) can use:

```dart
abstract class McpClient {
  /// Discover tools from all configured MCP servers
  Future<List<McpTool>> discoverTools();

  /// Invoke a specific tool on a specific server
  Future<McpToolResult> invoke(String serverName, String toolName, Map<String, dynamic> args);

  /// List configured servers and their connection status
  Future<List<McpServerInfo>> listServers();
}
```

MCP tools are surfaced alongside native `AgentTool` objects in every LLM prompt. The LLM doesn't distinguish between a native Kabuk tool and an MCP tool — it simply sees a unified list of available capabilities.

### Useful MCP Servers for Kabuk

| Server | Capability | Use Case |
|--------|-----------|----------|
| `filesystem` | Read/write files | Access documents outside the vault |
| `web-search` | Search the web | Answer questions with fresh data |
| `fetch` | Fetch URLs | Read web pages, APIs |
| `calendar` (CalDAV) | Calendar access | Complement CalendarAgent |
| `memory` | Long-term notes | External memory beyond knowledge store |
| `github` | Code/repo access | Developer workflows |
| `sqlite` | Query databases | Access external databases |

See [docs/MCP.md](MCP.md) for the full integration plan and implementation phases.

---

## Implementation Task List

### Phase 1 Tasks

Core agent infrastructure and three initial agents.

- [ ] Define `BaseAgent` abstract class with tool protocol
- [ ] Define `AgentTool`, `ToolResult` sealed classes
- [ ] Define `AgentMessage`, `AgentResponse` message types
- [ ] Define `AgentContext` with service dependencies
- [ ] Implement capability proxy wrappers for all services
- [ ] Implement `AgentRuntime` with isolate management
  - [ ] Isolate pool (spawn, reuse, terminate)
  - [ ] Message serialization/deserialization
  - [ ] Timeout enforcement
  - [ ] Resource limit tracking
- [ ] Implement `RouterAgent` with LLM-based intent classification
  - [ ] Classification prompt template
  - [ ] Conversation context window management
  - [ ] Explicit agent targeting (`@agent` syntax)
  - [ ] Direct-answer path for simple queries
- [ ] Implement `NoteAgent` with all tools
  - [ ] `create_note` tool
  - [ ] `edit_note` tool
  - [ ] `search_notes` tool
  - [ ] `list_notes` tool
  - [ ] `delete_note` tool
  - [ ] `generate_note_view` tool
  - [ ] RFW templates: note_card, note_list, note_editor
- [ ] Implement `FileAgent` with all tools
  - [ ] `list_files` tool
  - [ ] `tag_file` tool
  - [ ] `move_file` tool
  - [ ] `get_metadata` tool
  - [ ] `create_smart_folder` tool
  - [ ] `preview_file` tool
  - [ ] RFW templates: file_list, file_preview, metadata_card
- [ ] Implement `SystemAgent` with all tools
  - [ ] `get_status` tool
  - [ ] `set_preference` tool
  - [ ] `get_preference` tool
  - [ ] `list_agents` tool
  - [ ] `install_widget` tool
  - [ ] RFW templates: status_dashboard, agent_list
- [ ] Define capability system and grant storage
  - [ ] Capability enum and grant model
  - [ ] Grant dialog UI
  - [ ] Grant persistence in knowledge store
  - [ ] Revocation flow
- [ ] Implement `LlmService` with remote API support
  - [ ] llama.cpp (dart:ffi) integration (primary — local, default)
  - [ ] Ollama integration (local server, auto-detected)
  - [ ] Anthropic Claude integration (cloud extension)
  - [ ] OpenAI integration (secondary)
  - [ ] Prompt construction pipeline
  - [ ] Token budget management
  - [ ] Streaming support
  - [ ] Fallback chain
- [ ] Agent → RFW integration
  - [ ] `ToolResult.widget` rendering pipeline
  - [ ] Template compilation and caching
  - [ ] Data binding for dynamic content
- [ ] Unit tests for all Phase 1 agents
  - [ ] Mock AgentContext for isolated testing
  - [ ] Tool execution tests per agent
  - [ ] Routing classification tests
- [ ] Integration test: user message → router → agent → knowledge store → UI update

### Phase 2 Tasks

PIM agents and enhanced infrastructure.

- [ ] Implement `MediaAgent` with all tools
- [ ] Implement `CalendarAgent` with all tools
- [ ] Implement `ContactAgent` with all tools
- [ ] Implement `SearchAgent` with all tools
  - [ ] SPARQL full-text search
  - [ ] Embedding generation and storage
  - [ ] Vector similarity search
  - [ ] LLM re-ranking
- [ ] Multi-agent collaboration
  - [ ] Agent-to-agent invocation via runtime
  - [ ] Recursion depth limiting
  - [ ] Circular invocation detection
  - [ ] Capability intersection for delegated calls
- [ ] Conversation context management
  - [ ] Multi-turn conversation tracking
  - [ ] Context window sliding
  - [ ] Agent affinity (sticky routing)
  - [ ] Conversation summarization for long sessions
- [ ] Local LLM support
  - [ ] Ollama HTTP client integration
  - [ ] Model discovery and selection
  - [ ] Performance benchmarking vs. remote

### Phase 3 Tasks

Communication, external services, and advanced features.

- [ ] Implement `ChatAgent` (human-to-human messaging)
  - [ ] Matrix protocol integration
  - [ ] E2E encryption (Double Ratchet / Olm)
  - [ ] Message sync and offline queuing
- [ ] Implement provider agents
  - [ ] `RssAgent` — RSS/Atom feed management
  - [ ] `EmailAgent` — IMAP/SMTP email
  - [ ] `CalDavAgent` — Calendar sync
  - [ ] `CardDavAgent` — Contact sync
- [ ] Agent marketplace / sideloading
  - [ ] Agent package format definition
  - [ ] Signature verification for third-party agents
  - [ ] Sandboxed installation and capability review
- [ ] Local LLM support (embedded)
  - [ ] llama.cpp dart:ffi binding
  - [ ] Model management (download, store, load)
  - [ ] Quantization selection (Q4, Q5, Q8)
- [ ] Agent memory (long-term context)
  - [ ] Conversation summarization to knowledge store
  - [ ] User preference learning
  - [ ] Cross-session context retrieval via semantic search

---

## Appendix: Design Decisions

### Why Dart isolates and not WASM?
Dart isolates give us: native speed, full Dart standard library access, easy message passing via SendPort/ReceivePort, and trivial integration with the rest of the Flutter app. WASM would add complexity (need a WASM runtime, serialization bridge, limited Dart subset) for marginal sandboxing benefit. Isolates already provide memory isolation.

### Why stateless agents?
Stateful agents are harder to reason about, harder to test, harder to scale, and create coupling between the agent and its runtime context. By making agents stateless and putting all state in the knowledge store, we get: deterministic behavior (same input + same knowledge state = same output), trivial agent restart/replacement, natural audit trail (all mutations are triples), and multi-device sync for free (sync the knowledge store, agents work identically everywhere).

### Why Schema.org types?
Schema.org provides a well-known, extensible vocabulary for common data types (Person, Event, Note, etc.). By mapping agent data to Schema.org types, we get: interoperability with web standards, shared vocabulary across agents (NoteAgent and SearchAgent agree on what a "Note" looks like), and potential future integration with web-based systems (ActivityPub, Solid, etc.).

### Why sealed ToolResult?
The sealed type forces exhaustive handling. Every piece of code that consumes a `ToolResult` must handle every variant (text, widget, mutation, compound, error). This prevents bugs where a new result type is added but not handled in the UI renderer or the conversation logger.

### Why a Router Agent (not hardcoded routing)?
LLM-based routing gives us: natural language understanding of intent (no keyword matching), graceful handling of ambiguous queries, ability to improve routing by updating the prompt (no code changes), and support for multi-turn context (the router can use conversation history to infer which agent the user is talking to).
