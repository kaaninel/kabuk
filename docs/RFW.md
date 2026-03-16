# Remote Flutter Widgets & Dynamic UI

## Overview

Remote Flutter Widgets (RFW) is one of the most critical features of Kabuk. It enables agents to generate and serve UI dynamically without deploying new code. Instead of pre-building screens for every possible interaction, agents can compose widget trees on the fly and return them as part of tool results. Users and third-party developers can install widget packs from repositories, extending the system's visual capabilities.

This is what makes Kabuk truly extensible — any new data type, any new agent capability, can immediately get a rich visual representation.

---

## How RFW Works in Kabuk

### The Flow

```
1. User asks question or triggers action
2. Agent processes request, reads knowledge store
3. Agent generates response with optional RFW template
4. RFW Runtime receives template + data bindings
5. Runtime resolves widget library references
6. Runtime binds DynamicContent from knowledge store
7. Flutter renders the widget tree in the chat/view
```

### Example: Agent Returns a Contact Card

```dart
// In ContactAgent.getContact tool implementation:
return ToolResult.widget(
  RfwTemplate(
    library: 'kabuk:contacts',
    widget: 'ContactCard',
    dependencies: ['schema:Person'],
    bindings: {
      'personUri': 'kabuk:person/$contactId',
    },
  ),
);
```

The RFW runtime looks up `ContactCard` in the `kabuk:contacts` library, injects data from the knowledge store for the given person URI, and renders it.

---

## Architecture

### RFW Runtime (`lib/rfw/runtime.dart`)

- Initializes the RFW rendering environment
- Maintains widget library cache
- Resolves library references when rendering templates
- Manages `DynamicContent` lifecycle
- Handles user interactions (callbacks from RFW widgets back to agents)

### Widget Registry (`lib/rfw/registry.dart`)

- Stores installed widget libraries
- Each library is a collection of related widgets (e.g., `kabuk:contacts` has `ContactCard`, `ContactList`, `ContactDetail`)
- Libraries stored in knowledge store as `kabuk:widget_library` triples
- Supports install, uninstall, update from repositories
- Built-in libraries ship with the app; additional ones installed by agents or users

### Data Bindings (`lib/rfw/bindings.dart`)

- Bridges knowledge store data into RFW's `DynamicContent` model
- Reactive: when knowledge store changes, bindings update, widgets rebuild
- Supports:
  - Single entity binding (one subject URI → all its predicates as a map)
  - Query binding (query pattern → list of results)
  - Computed binding (derived values from multiple triples)

### Library Format

```dart
/// A widget library definition.
class RfwLibrary {
  /// Namespaced identifier, e.g. 'kabuk:contacts'.
  final String name;

  /// Semver version string.
  final String version;

  /// Author or organization name.
  final String author;

  /// Human-readable description of the library.
  final String description;

  /// Widget name → definition map.
  final Map<String, RfwWidgetDef> widgets;

  /// Other libraries this library depends on.
  final List<String> dependencies;

  /// Schema.org types this library is designed to display.
  final List<String> schemaTypes;
}

/// A single widget definition within a library.
class RfwWidgetDef {
  /// Widget name, unique within the library.
  final String name;

  /// The RFW template source text.
  final String rfwSource;

  /// Expected data bindings and their types.
  final Map<String, String> dataContract;

  /// Events this widget can emit (e.g., 'onTap', 'onEdit').
  final List<String> events;
}
```

---

## Built-in Widget Libraries

### `kabuk:core`

Base widgets and layouts:

| Widget         | Description                                        |
|----------------|----------------------------------------------------|
| `Card`         | Material card with title, subtitle, body, actions  |
| `ListTile`     | Standard list tile with leading, title, subtitle, trailing |
| `Grid`         | Responsive grid layout                             |
| `Timeline`     | Vertical timeline with items                       |
| `EmptyState`   | Placeholder when no data                           |
| `ErrorState`   | Error display with retry action                    |
| `LoadingState`  | Loading indicator with message                     |

### `kabuk:notes`

Note-related widgets:

| Widget        | Description                                              |
|---------------|----------------------------------------------------------|
| `NoteCard`    | Compact preview card for a note                          |
| `NoteDetail`  | Full note view with edit capability                      |
| `NoteList`    | List of note cards                                       |
| `NoteEditor`  | Note creation/editing form (as much as RFW allows)       |

### `kabuk:contacts`

Contact-related widgets:

| Widget          | Description                                      |
|-----------------|--------------------------------------------------|
| `ContactCard`   | Contact info card with avatar, name, details     |
| `ContactList`   | Scrollable contact directory                     |
| `ContactDetail` | Full contact view                                |
| `ContactAvatar` | Circle avatar with initials fallback             |

### `kabuk:media`

Media display widgets:

| Widget        | Description                          |
|---------------|--------------------------------------|
| `ImageCard`   | Photo with metadata overlay          |
| `VideoCard`   | Video thumbnail with duration        |
| `AudioCard`   | Audio waveform with play button      |
| `Gallery`     | Grid of media items                  |
| `MediaPlayer` | Inline media player                  |

### `kabuk:calendar`

Calendar widgets:

| Widget      | Description              |
|-------------|--------------------------|
| `EventCard` | Event summary card       |
| `EventList` | Upcoming events list     |
| `DayView`   | Single day schedule      |
| `WeekView`  | Week overview            |
| `MonthView` | Month calendar grid      |

### `kabuk:chat`

Chat UI widgets:

| Widget             | Description                             |
|--------------------|-----------------------------------------|
| `MessageBubble`    | Chat message (text, media, compound)    |
| `ConversationList` | List of conversations                   |
| `TypingIndicator`  | Agent/user typing state                 |
| `ReplyPreview`     | Reply-to preview                        |

### `kabuk:dashboard`

Explore view widgets:

| Widget          | Description                             |
|-----------------|-----------------------------------------|
| `DashboardCard` | Generic dashboard info card             |
| `StatWidget`    | Number/stat display                     |
| `ChartWidget`   | Simple charts (bar, line, pie)          |
| `QuickAction`   | Action button with icon and label       |
| `WeatherWidget` | Weather display                         |
| `ClockWidget`   | Time/date display                       |

---

## Agent-Generated RFW

### How Agents Create Widgets

Agents can generate RFW in two ways:

#### 1. Reference Existing Library Widgets (Preferred)

```dart
return ToolResult.widget(
  RfwTemplate(
    library: 'kabuk:notes',
    widget: 'NoteCard',
    bindings: {'noteUri': 'kabuk:note/$id'},
  ),
);
```

This is the most common path. The agent simply refers to a widget that already exists in an installed library and provides the data bindings. The runtime handles resolution, data fetching, and rendering.

#### 2. Generate Raw RFW Template (Dynamic / Custom UIs)

```dart
return ToolResult.widget(
  RfwTemplate.raw(
    source: '''
      import core;
      widget ResultView = Column(
        children: [
          Text(text: data.title, style: { fontSize: 20 }),
          Text(text: data.summary),
          ...for item in data.items:
            ListTile(
              title: Text(text: item.name),
              subtitle: Text(text: item.description),
            ),
        ],
      );
    ''',
    data: {
      'title': 'Search Results',
      'summary': 'Found ${results.length} items',
      'items': results
          .map((r) => {'name': r.name, 'description': r.desc})
          .toList(),
    },
  ),
);
```

This path is used when no existing widget fits the data shape, or the agent needs to compose a one-off layout. The raw RFW source is parsed, validated, and rendered inline.

### LLM-Generated Widgets

A key capability: agents can ask the LLM to generate RFW templates dynamically.

```
1. Agent determines what data needs to be displayed
2. Agent sends data schema to LLM with instruction to produce RFW
3. LLM generates RFW template
4. Agent validates template (syntax check, security check)
5. Template rendered to user
```

This means the system can create UIs it was never explicitly programmed to show. For example, if an agent fetches structured data from an API the system has never seen before, the LLM can inspect the data shape and produce a reasonable card or list layout on the spot.

#### LLM Prompt Strategy

The LLM is provided with:

- The RFW syntax reference (subset of Flutter widget tree DSL).
- The available `kabuk:core` widgets it can compose with.
- The data schema (field names, types, cardinality).
- Design guidelines (spacing, typography scale, color tokens).

The prompt constrains the LLM to produce valid RFW source only — no Dart code, no imports beyond registered libraries, no unbounded recursion.

#### Caching Generated Templates

Generated templates are cached in the knowledge store keyed by a hash of the data schema + prompt. If the same agent encounters the same data shape again, it reuses the cached template instead of calling the LLM.

```dart
// Pseudocode for LLM-generated widget flow
Future<ToolResult> _displayUnknownData(
  AgentContext ctx,
  Map<String, dynamic> data,
) async {
  final schemaHash = computeSchemaHash(data);
  final cached = await ctx.knowledge.query()
      .subject(type: 'kabuk:GeneratedTemplate')
      .where('kabuk:schemaHash', equals: schemaHash)
      .first();

  final String rfwSource;
  if (cached != null) {
    rfwSource = cached['kabuk:rfwSource'];
  } else {
    rfwSource = await ctx.llm.generate(
      prompt: buildRfwPrompt(dataSchema: describeSchema(data)),
    );
    // Validate before storing
    RfwValidator.validate(rfwSource);
    await ctx.knowledge.mutate((store) {
      store.insert(
        subject: Uri.parse('kabuk:template/${generateId()}'),
        predicates: {
          'rdf:type': 'kabuk:GeneratedTemplate',
          'kabuk:schemaHash': schemaHash,
          'kabuk:rfwSource': rfwSource,
          'schema:dateCreated': DateTime.now().toIso8601String(),
        },
      );
    });
  }

  return ToolResult.widget(
    RfwTemplate.raw(source: rfwSource, data: data),
  );
}
```

---

## Widget Repository System

### Repository Structure

```
widget-repo/
  index.json              — Catalog of available libraries
  kabuk-notes/
    manifest.json         — Library metadata, version, dependencies
    widgets.rfw           — RFW source for all widgets
    preview.png           — Preview image
  kabuk-weather/
    manifest.json
    widgets.rfw
    preview.png
```

### `index.json` Format

```json
{
  "version": 1,
  "libraries": [
    {
      "name": "kabuk:notes",
      "version": "1.2.0",
      "description": "Note display widgets",
      "author": "Kabuk Project",
      "sha256": "abc123...",
      "path": "kabuk-notes/"
    }
  ]
}
```

### `manifest.json` Format

```json
{
  "name": "kabuk:notes",
  "version": "1.2.0",
  "author": "Kabuk Project",
  "description": "Widgets for displaying and editing notes.",
  "dependencies": ["kabuk:core >= 1.0.0"],
  "schemaTypes": ["schema:NoteDigitalDocument", "schema:Note"],
  "widgets": {
    "NoteCard": {
      "description": "Compact preview card for a note",
      "dataContract": {
        "noteUri": { "type": "uri", "schemaType": "schema:Note", "required": true },
        "maxLines": { "type": "integer", "default": 3 }
      },
      "events": ["onTap", "onDelete"]
    },
    "NoteList": {
      "description": "Scrollable list of note cards",
      "dataContract": {
        "query": { "type": "query", "schemaType": "schema:Note", "required": true },
        "emptyMessage": { "type": "string", "default": "No notes found" }
      },
      "events": ["onTap", "onLoadMore"]
    }
  }
}
```

### Distribution

- Repositories can be hosted as static files (HTTP) — no server logic required.
- Default repository hosted by the Kabuk project.
- Users can add custom repository URLs via settings.
- Libraries are versioned using semver.
- Dependency resolution between libraries (e.g., `kabuk:notes` depends on `kabuk:core >= 1.0.0`).
- Integrity verification via SHA-256 hash in `index.json`.

### Installation Flow

```
1. User browses Apps view → Widget Repository section
   OR agent suggests: "I can show your calendar better with the
   Calendar Widget Pack. Install it?"
2. Download library manifest + RFW source
3. Verify SHA-256 hash matches index
4. Parse and validate RFW source (syntax, security)
5. Resolve dependencies (install missing ones first)
6. Store in knowledge store:
   - Library metadata as RDF triples (kabuk:widget_library)
   - RFW source in blob storage via VaultService
7. Register in RfwRegistry — widgets become available immediately
```

### Uninstall & Update

- **Uninstall:** Remove triples and blob. Widgets referencing the library fall back to a placeholder.
- **Update:** Download new version, validate, replace blob and update version triple. Existing rendered widgets refresh automatically via reactive bindings.

---

## Data Binding Contract

### How `DynamicContent` Connects to Knowledge Store

```dart
/// Bridges knowledge store data into RFW's DynamicContent.
class RfwDataBinding {
  /// Bind a single entity's properties.
  ///
  /// Queries all triples where subject == [subjectUri].
  /// Returns as a flat map:
  ///   { 'schema:name': 'John', 'schema:email': 'john@...' }
  /// Reactively updates when any of those triples change.
  static DynamicContent entityBinding(
    KnowledgeStore store,
    String subjectUri,
  ) {
    // ...
  }

  /// Bind a query result (list of entities).
  ///
  /// Executes query, returns list of entity maps.
  /// Reactively updates when query results change.
  static DynamicContent queryBinding(
    KnowledgeStore store,
    QueryBuilder query,
  ) {
    // ...
  }

  /// Bind computed values.
  ///
  /// Runs [fn] over store data.
  /// Updates when dependent triples change.
  static DynamicContent computedBinding(
    KnowledgeStore store,
    ComputeFunction fn,
  ) {
    // ...
  }
}
```

### Riverpod Integration

Data bindings are exposed as Riverpod providers so the widget tree stays reactive:

```dart
/// Provider that creates a DynamicContent for a single entity.
final rfwEntityProvider = StreamProvider.family<DynamicContent, String>(
  (ref, subjectUri) {
    final store = ref.watch(knowledgeStoreProvider);
    return RfwDataBinding.entityStream(store, subjectUri);
  },
);

/// Provider that creates a DynamicContent for a query.
final rfwQueryProvider = StreamProvider.family<DynamicContent, QueryBuilder>(
  (ref, query) {
    final store = ref.watch(knowledgeStoreProvider);
    return RfwDataBinding.queryStream(store, query);
  },
);
```

### Data Contract

Each widget declares what data it expects:

```json
{
  "noteUri": {
    "type": "uri",
    "schemaType": "schema:Note",
    "required": true
  },
  "showActions": {
    "type": "boolean",
    "default": true
  },
  "maxLines": {
    "type": "integer",
    "default": 3
  }
}
```

The runtime validates that bindings satisfy the contract before rendering. If a required binding is missing or the wrong type, the widget is replaced with an `ErrorState` showing what went wrong.

### Supported Binding Types

| Type       | Description                                  | Example                    |
|------------|----------------------------------------------|----------------------------|
| `uri`      | Knowledge store subject URI                  | `kabuk:note/42`            |
| `string`   | Plain text value                             | `"Hello"`                  |
| `integer`  | Integer number                               | `3`                        |
| `double`   | Floating point number                        | `3.14`                     |
| `boolean`  | True/false                                   | `true`                     |
| `query`    | Query builder pattern for lists              | `{ type: 'schema:Note' }` |
| `map`      | Arbitrary key-value map                      | `{ 'key': 'value' }`      |
| `list`     | Ordered list of values                       | `['a', 'b', 'c']`         |

---

## Event Handling

RFW widgets are stateless, but they can emit events:

```
Widget tap → RFW callback → RfwRuntime → Agent notification
```

### Event Types

| Event                          | Description                          |
|--------------------------------|--------------------------------------|
| `onTap(entityUri)`             | User tapped an item                  |
| `onAction(actionName, params)` | User triggered an action button      |
| `onNavigate(destination)`      | User wants to navigate               |
| `onInput(field, value)`        | User entered data in a field         |
| `onLongPress(entityUri)`       | User long-pressed an item            |
| `onDismiss(entityUri)`         | User dismissed/swiped away an item   |

### Event Routing

```dart
/// Handles events emitted by RFW widgets.
class RfwEventRouter {
  /// Routes an event to the appropriate agent.
  ///
  /// Events carry the source widget's library name, allowing
  /// the router to dispatch to the domain agent that owns that
  /// library (e.g., events from kabuk:notes → NoteAgent).
  Future<void> handleEvent(RfwEvent event) async {
    final agent = _resolveAgent(event.library);
    await agent.handleWidgetEvent(
      widgetName: event.widget,
      eventName: event.name,
      params: event.params,
    );
  }
}
```

### Event Flow Example

```
User taps "Edit" on a NoteCard
  → RFW emits onAction('edit', { 'noteUri': 'kabuk:note/42' })
  → RfwRuntime receives callback
  → RfwEventRouter resolves kabuk:notes → NoteAgent
  → NoteAgent.handleWidgetEvent('NoteCard', 'edit', { noteUri: ... })
  → NoteAgent opens NoteEditor with the note data
  → NoteEditor rendered as new RFW widget in chat
```

---

## Security & Sandboxing

### Constraints

- RFW widgets **cannot** execute arbitrary Dart code.
- **No access** to services, agents, or network directly.
- Can **only read** data through declared bindings.
- Can **only emit** events through declared event contracts.
- Template source is validated before execution.
- No infinite loops or recursive widget trees (depth limit enforced).
- Memory budget per widget tree.

### Validation Pipeline

```
1. Parse RFW source → catch syntax errors
2. Check structure → verify widget tree is well-formed
3. Verify all referenced libraries are installed
4. Verify data contract is satisfiable from provided bindings
5. Check for prohibited patterns:
   - Excessive nesting (depth > 30)
   - Unbounded loops (list builders without limits)
   - Excessively large literal data
6. Sandbox execution with resource limits:
   - Max widget count per tree: 500
   - Max render time budget: 100ms
   - Max memory allocation: 10MB
```

### Third-Party Library Trust

Libraries from external repositories go through additional checks:

- Author verification (signed manifests in future versions).
- Community rating and review system.
- Automated scanning for suspicious patterns.
- Users can restrict which repositories are trusted.

---

## RFW Syntax Reference (Kabuk Subset)

Kabuk uses the standard RFW text format. Key constructs:

```
// Import a library
import core;
import contacts;

// Define a widget
widget MyWidget = Container(
  padding: [16.0],
  child: Column(
    crossAxisAlignment: "start",
    children: [
      // Use data bindings
      Text(text: data.title, style: { fontSize: 18.0, fontWeight: "bold" }),
      Text(text: data.subtitle),
      
      // Conditional rendering
      switch data.hasImage {
        true: Image(source: data.imageUrl),
      },
      
      // List iteration
      ...for item in data.items:
        ListTile(
          title: Text(text: item.name),
          onTap: event "onTap" { entityUri: item.uri },
        ),
      
      // Action buttons
      Row(
        children: [
          Button(
            label: "Edit",
            onPressed: event "onAction" { action: "edit" },
          ),
          Button(
            label: "Delete",
            onPressed: event "onAction" { action: "delete" },
          ),
        ],
      ),
    ],
  ),
);
```

### Available Base Widgets (from Flutter Material via RFW)

The RFW runtime registers standard Flutter widgets:

- Layout: `Container`, `Row`, `Column`, `Stack`, `Wrap`, `Expanded`, `Flexible`, `Padding`, `SizedBox`, `Center`, `Align`
- Content: `Text`, `Icon`, `Image`, `Placeholder`
- Material: `Card`, `ListTile`, `Divider`, `Chip`, `AppBar`, `Scaffold`
- Input: `ElevatedButton`, `TextButton`, `IconButton`, `TextField`
- Scroll: `ListView`, `GridView`, `SingleChildScrollView`

---

## Implementation Task List

### Phase 1 — Core Runtime

- [ ] Set up `rfw` package dependency in `pubspec.yaml`
- [ ] Implement `RfwRuntime` — basic rendering of RFW templates
- [ ] Implement `RfwRegistry` — store/retrieve widget libraries
- [ ] Implement `RfwDataBinding` — entity binding from knowledge store
- [ ] Create `kabuk:core` built-in library (`Card`, `ListTile`, `Grid`, `EmptyState`)
- [ ] Agent → RFW integration (`ToolResult.widget` support)
- [ ] Render RFW widgets in chat view
- [ ] Basic validation pipeline (syntax + structure checks)

### Phase 2 — Built-in Libraries

- [ ] Create `kabuk:notes` library
- [ ] Create `kabuk:contacts` library
- [ ] Create `kabuk:media` library
- [ ] Create `kabuk:chat` library
- [ ] Create `kabuk:calendar` library
- [ ] Create `kabuk:dashboard` library
- [ ] Query binding support (list of entities)
- [ ] Computed binding support
- [ ] Event handling (`onTap`, `onAction`, `onNavigate`)
- [ ] Event routing to domain agents

### Phase 3 — Repository & Distribution

- [ ] Define repository manifest format (`index.json`, `manifest.json`)
- [ ] Implement repository client (fetch, verify integrity, install)
- [ ] Widget repository browser in Apps view
- [ ] Library dependency resolution
- [ ] Library versioning and update mechanism
- [ ] Uninstall support with graceful fallback
- [ ] Repository URL management in settings

### Phase 4 — LLM-Generated Widgets

- [ ] LLM prompt templates for RFW generation
- [ ] Template validation and security checking
- [ ] Agent integration for dynamic widget creation
- [ ] Schema hash–based caching of generated templates
- [ ] Feedback loop (user rates generated UIs, improves prompts)
- [ ] Prompt refinement based on feedback data

### Phase 5 — Hardening

- [ ] Full security validation pipeline
- [ ] Resource limits enforcement (widget count, render time, memory)
- [ ] Third-party library trust model
- [ ] Performance profiling and optimization of RFW rendering
- [ ] Accessibility support in RFW widgets
- [ ] RTL and localization support in templates
