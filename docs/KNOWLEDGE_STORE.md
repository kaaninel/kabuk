# Knowledge Store Design

> The single source of truth in Kabuk — an RDF triple store backed by SQLite via Drift ORM.

> **⚠️ STATUS (Aug 2026):** Implemented as Drift schemaVersion 4 (`lib/knowledge/database.dart`) with FTS5, change events, and device-sync columns. Two behavioral notes: article entities are stamped with `kabuk:expiresAt` (published + 48h) and pruned when unread — see `lib/knowledge/types/article.dart` and `TODO.md` #7. The `QueryBuilder` throws `UnimplementedError` unless connected to a store (by design).

---

## Table of Contents

1. [Overview](#1-overview)
2. [Data Model](#2-data-model)
   - [Triple Structure](#triple-structure)
   - [SQLite Schema (Drift)](#sqlite-schema-drift)
   - [URI Scheme](#uri-scheme)
3. [Schema.org Type Mappings](#3-schemaorg-type-mappings)
4. [Query API](#4-query-api)
5. [Mutation API](#5-mutation-api)
6. [Change Events & Reactivity](#6-change-events--reactivity)
7. [Encryption](#7-encryption)
8. [Named Graphs](#8-named-graphs)
9. [Import/Export](#9-importexport)
10. [Agent Integration](#10-agent-integration)
11. [Dart Data Classes](#11-dart-data-classes)
12. [Performance](#12-performance)
13. [Implementation Task List](#13-implementation-task-list)

---

## 1. Overview

### Why RDF?

Kabuk is not a traditional app with a fixed set of screens and tables. It is a personal OS shell where agents dynamically create, query, and visualize data across dozens of domains — notes, contacts, events, media, messages, tasks, preferences, agent state, widget definitions, and types that don't exist yet. A fixed relational schema would require migrations for every new data type, every new relationship, every new agent capability. RDF eliminates that friction entirely.

**RDF (Resource Description Framework)** models all data as a graph of triples: `(subject, predicate, object)`. Every fact, relationship, and piece of metadata is one triple. There are no tables to define, no schemas to migrate, no joins to compute — just triples that connect things.

### What it enables

| Capability | How RDF Delivers |
|---|---|
| **Flexible schema** | New data types require zero schema changes. An agent can invent a new entity type by writing triples with a new `rdf:type`. The store doesn't care. |
| **Graph queries** | "Find all people who attended events tagged 'work' in the last month" is a graph traversal, not a multi-table JOIN. |
| **Schema.org interop** | Using Schema.org predicates (`schema:name`, `schema:email`, `schema:startDate`) means data is inherently interoperable with the web, search engines, and other tools. |
| **Agent-friendly access** | Agents are stateless. They don't know what tables exist. They *do* know how to read and write triples. An agent can explore the store by following predicates — it's self-describing. |
| **Reactive UI** | Widgets bind to query patterns over triples. When a triple changes, any widget watching that pattern rebuilds. No manual invalidation. |
| **Linked data** | Entities reference each other by URI. A message links to a conversation links to participants links to contact details — all via URI references in triples. |
| **Future-proof** | When a new agent domain is added (e.g., health data, recipes, bookmarks), it simply starts writing triples. No database migration. No coordination with existing code. |

### How it fits the architecture

```
┌─────────────────────────────────────────────────────────────┐
│                         UI Layer                            │
│  Riverpod Providers → watch query patterns → rebuild        │
└────────────────────────────┬────────────────────────────────┘
                             │
                     Stream<ChangeSet>
                             │
┌────────────────────────────▼────────────────────────────────┐
│                     Knowledge Store                          │
│                                                              │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌────────────┐  │
│  │  Query   │  │  Mutate  │  │  Change  │  │  Encrypt   │  │
│  │  Builder │  │  API     │  │  Events  │  │  Layer     │  │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘  └─────┬──────┘  │
│       │              │             │               │         │
│  ┌────▼──────────────▼─────────────▼───────────────▼──────┐  │
│  │                   Drift ORM Layer                       │  │
│  │  triples table │ blobs table │ FTS5 index              │  │
│  └────────────────────────┬───────────────────────────────┘  │
│                           │                                  │
│  ┌────────────────────────▼───────────────────────────────┐  │
│  │                      SQLite                             │  │
│  └─────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────┘
                             ▲
                             │
                    AgentContext.knowledge
                             │
┌────────────────────────────┴────────────────────────────────┐
│                       Agent Layer                            │
│  NoteAgent │ ContactAgent │ CalendarAgent │ MediaAgent │ …  │
└─────────────────────────────────────────────────────────────┘
```

The knowledge store is:
- **The only persistence layer** — agents never write files or SQLite tables directly.
- **Accessed through `AgentContext.knowledge`** — capability-gated per agent.
- **Reactive** — every mutation emits a `ChangeSet` on a broadcast stream. Riverpod providers watch these streams and rebuild widgets when relevant data changes.
- **Encrypted at rest** — sensitive triples are individually encrypted with AES-256-GCM. The store handles transparent encryption/decryption.

---

## 2. Data Model

### Triple Structure

Every fact in Kabuk is a single quad (triple + optional named graph):

```
(subject: URI, predicate: URI, object: URI | Literal, graph?: URI)
```

| Component | Type | Description |
|---|---|---|
| `subject` | URI | The thing being described (`kabuk:note/abc123`) |
| `predicate` | URI | The relationship or property (`schema:name`) |
| `object` | URI or Literal | The value — either a reference to another entity (URI) or a literal value (string, int, float, datetime, boolean) |
| `graph` | URI (optional) | Named graph for provenance tracking. Defaults to `kabuk:graph/default` |

**Turtle examples:**

A Note:
```turtle
@prefix schema: <https://schema.org/> .
@prefix kabuk: <kabuk://> .
@prefix rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#> .

kabuk:note/a1b2c3d4 a schema:Note ;
    schema:name "Meeting Notes — Q1 Planning" ;
    schema:text "Discussed budget allocation for..." ;
    schema:dateCreated "2026-02-20T10:30:00Z"^^xsd:dateTime ;
    schema:dateModified "2026-02-20T11:15:00Z"^^xsd:dateTime ;
    kabuk:tag "work" ;
    kabuk:tag "planning" .
```

A Person:
```turtle
kabuk:person/e5f6g7h8 a schema:Person ;
    schema:givenName "Kaan" ;
    schema:familyName "Inel" ;
    schema:name "Kaan Inel" ;
    schema:email "kaan@example.com" ;
    schema:telephone "+1-555-0123" ;
    schema:image kabuk:media/avatar-k1 ;
    kabuk:tag "family" .
```

An Event:
```turtle
kabuk:event/i9j0k1l2 a schema:Event ;
    schema:name "Q1 Planning Meeting" ;
    schema:description "Quarterly planning session with the full team" ;
    schema:startDate "2026-03-01T14:00:00Z"^^xsd:dateTime ;
    schema:endDate "2026-03-01T16:00:00Z"^^xsd:dateTime ;
    schema:location "Conference Room A" ;
    schema:organizer kabuk:person/e5f6g7h8 ;
    schema:attendee kabuk:person/e5f6g7h8 ;
    schema:attendee kabuk:person/m3n4o5p6 ;
    kabuk:reminder "2026-03-01T13:45:00Z"^^xsd:dateTime .
```

### SQLite Schema (Drift)

#### `triples` table

```sql
CREATE TABLE triples (
  id            INTEGER PRIMARY KEY AUTOINCREMENT,
  subject       TEXT    NOT NULL,                     -- URI of the subject
  predicate     TEXT    NOT NULL,                     -- URI of the predicate
  object_value  TEXT    NOT NULL,                     -- String representation of the object
  object_type   TEXT    NOT NULL DEFAULT 'string'     -- 'uri' | 'string' | 'integer' | 'float' | 'datetime' | 'boolean' | 'blob_ref'
                CHECK (object_type IN ('uri', 'string', 'integer', 'float', 'datetime', 'boolean', 'blob_ref')),
  object_lang   TEXT,                                 -- Language tag (e.g., 'en', 'tr') for string literals
  object_datatype TEXT,                               -- XSD datatype URI (e.g., 'xsd:dateTime')
  graph         TEXT    NOT NULL DEFAULT 'kabuk:graph/default',  -- Named graph URI
  created_at    TEXT    NOT NULL,                     -- ISO 8601 UTC timestamp
  updated_at    TEXT    NOT NULL,                     -- ISO 8601 UTC timestamp
  encrypted     INTEGER NOT NULL DEFAULT 0            -- 0 = plaintext, 1 = AES-256-GCM encrypted
);

-- Primary lookup patterns
CREATE INDEX idx_triples_subject            ON triples(subject);
CREATE INDEX idx_triples_predicate          ON triples(predicate);
CREATE INDEX idx_triples_object_uri         ON triples(object_value) WHERE object_type = 'uri';
CREATE INDEX idx_triples_graph              ON triples(graph);
CREATE INDEX idx_triples_subject_predicate  ON triples(subject, predicate);

-- Type-based filtering (find all entities of a given rdf:type)
CREATE INDEX idx_triples_type ON triples(object_value)
  WHERE predicate = 'rdf:type';

-- Temporal ordering for date-typed objects
CREATE INDEX idx_triples_datetime ON triples(object_value)
  WHERE object_type = 'datetime';

-- Compound index for graph-scoped queries
CREATE INDEX idx_triples_graph_subject ON triples(graph, subject);

-- Uniqueness constraint: no duplicate quads
CREATE UNIQUE INDEX idx_triples_unique
  ON triples(subject, predicate, object_value, graph);
```

#### FTS5 Virtual Table

```sql
-- Full-text search index over subject URIs and string object values.
-- Tokenizer: unicode61 with remove_diacritics for accent-insensitive search.
CREATE VIRTUAL TABLE triples_fts USING fts5(
  subject,
  object_value,
  content='triples',
  content_rowid='id',
  tokenize='unicode61 remove_diacritics 2'
);

-- Triggers to keep FTS in sync with the triples table.
CREATE TRIGGER triples_ai AFTER INSERT ON triples BEGIN
  INSERT INTO triples_fts(rowid, subject, object_value)
    VALUES (new.id, new.subject, new.object_value);
END;

CREATE TRIGGER triples_ad AFTER DELETE ON triples BEGIN
  INSERT INTO triples_fts(triples_fts, rowid, subject, object_value)
    VALUES ('delete', old.id, old.subject, old.object_value);
END;

CREATE TRIGGER triples_au AFTER UPDATE ON triples BEGIN
  INSERT INTO triples_fts(triples_fts, rowid, subject, object_value)
    VALUES ('delete', old.id, old.subject, old.object_value);
  INSERT INTO triples_fts(rowid, subject, object_value)
    VALUES (new.id, new.subject, new.object_value);
END;
```

#### `blobs` table

```sql
CREATE TABLE blobs (
  hash       TEXT    PRIMARY KEY,                    -- SHA-256 hex digest (content-addressed)
  data       BLOB    NOT NULL,                       -- Raw binary data
  mime_type  TEXT    NOT NULL,                        -- MIME type (e.g., 'image/jpeg')
  size       INTEGER NOT NULL,                       -- Size in bytes
  created_at TEXT    NOT NULL                         -- ISO 8601 UTC timestamp
);
```

**Design notes:**

- **Content-addressing**: Blobs are stored by their SHA-256 hash. Storing the same file twice costs nothing extra — the hash deduplicates.
- **Blob references**: A triple with `object_type = 'blob_ref'` has its `object_value` set to the blob hash. This decouples metadata (triples) from binary data (blobs).
- **Large blob strategy**: For files > 10MB, consider storing only the path in the vault (via `VaultService`) and keeping the hash as a reference. The blob table is for content that benefits from content-addressing and deduplication (photos, thumbnails, audio clips).

### URI Scheme

All URIs in Kabuk follow a consistent namespacing scheme. URIs are short, human-readable identifiers — not full HTTP URLs.

#### Kabuk Entity URIs

| Prefix | Pattern | Example | Description |
|---|---|---|---|
| `kabuk:note/` | `kabuk:note/{uuid}` | `kabuk:note/a1b2c3d4` | A note/document |
| `kabuk:person/` | `kabuk:person/{uuid}` | `kabuk:person/e5f6g7h8` | A contact/person |
| `kabuk:event/` | `kabuk:event/{uuid}` | `kabuk:event/i9j0k1l2` | A calendar event |
| `kabuk:media/` | `kabuk:media/{uuid}` | `kabuk:media/m3n4o5p6` | A media object (image, video, audio) |
| `kabuk:file/` | `kabuk:file/{uuid}` | `kabuk:file/q7r8s9t0` | A generic file reference |
| `kabuk:message/` | `kabuk:message/{uuid}` | `kabuk:message/u1v2w3x4` | A chat message |
| `kabuk:conversation/` | `kabuk:conversation/{uuid}` | `kabuk:conversation/y5z6a7b8` | A conversation (agent or human) |
| `kabuk:preference/` | `kabuk:preference/{key}` | `kabuk:preference/theme` | A user preference |
| `kabuk:agent/` | `kabuk:agent/{name}` | `kabuk:agent/note` | An agent definition |
| `kabuk:widget/` | `kabuk:widget/{library}/{name}` | `kabuk:widget/contacts/ContactCard` | An RFW widget reference |
| `kabuk:capability/` | `kabuk:capability/{name}` | `kabuk:capability/knowledge:read` | A capability definition |
| `kabuk:task/` | `kabuk:task/{uuid}` | `kabuk:task/c9d0e1f2` | A task/action item |
| `kabuk:tag/` | `kabuk:tag/{name}` | `kabuk:tag/work` | A tag (can be used as subject for tag metadata) |

#### Kabuk Graph URIs

| Pattern | Example | Description |
|---|---|---|
| `kabuk:graph/default` | — | The default graph |
| `kabuk:graph/agent/{name}` | `kabuk:graph/agent/note` | Triples created by a specific agent |
| `kabuk:graph/import/{source}` | `kabuk:graph/import/google-contacts` | Triples from an external import |
| `kabuk:graph/device/{id}` | `kabuk:graph/device/pixel-9` | Triples originating from a specific device |
| `kabuk:graph/user` | — | Triples explicitly created by the user |

#### Standard Namespace Prefixes

| Prefix | Full URI | Usage |
|---|---|---|
| `schema:` | `https://schema.org/` | Type and property vocabulary (Person, Event, name, email, etc.) |
| `rdf:` | `http://www.w3.org/1999/02/22-rdf-syntax-ns#` | Core RDF (`rdf:type`) |
| `rdfs:` | `http://www.w3.org/2000/01/rdf-schema#` | RDF Schema (`rdfs:label`, `rdfs:comment`) |
| `xsd:` | `http://www.w3.org/2001/XMLSchema#` | Datatypes (`xsd:dateTime`, `xsd:integer`) |
| `kabuk:` | `kabuk://` | All Kabuk-specific URIs |

**Prefix expansion** is handled at the Dart layer. URIs are stored in their short form (`schema:name`, not `https://schema.org/name`) for compactness and readability. The `NS` constants class provides all prefix mappings.

---

## 3. Schema.org Type Mappings

Every entity type in Kabuk maps to a Schema.org type with well-defined predicates. This section is the canonical reference for how each type is modeled in triples.

### Note

| Predicate | Object Type | Required | Description |
|---|---|---|---|
| `rdf:type` | URI → `schema:Note` | ✓ | Entity type |
| `schema:name` | string | ✓ | Title/heading |
| `schema:text` | string | ✓ | Body content (Markdown) |
| `schema:dateCreated` | datetime | ✓ | Creation timestamp (UTC) |
| `schema:dateModified` | datetime | ✓ | Last modification timestamp (UTC) |
| `kabuk:tag` | string | | Tag label (multi-valued — one triple per tag) |
| `schema:author` | URI → `kabuk:person/*` | | Author reference |
| `kabuk:pinned` | boolean | | Whether the note is pinned |

**Example triples for a note:**

| subject | predicate | object_value | object_type |
|---|---|---|---|
| `kabuk:note/abc` | `rdf:type` | `schema:Note` | uri |
| `kabuk:note/abc` | `schema:name` | `Meeting Notes` | string |
| `kabuk:note/abc` | `schema:text` | `# Q1 Planning\n\n- Budget...` | string |
| `kabuk:note/abc` | `schema:dateCreated` | `2026-02-20T10:30:00Z` | datetime |
| `kabuk:note/abc` | `schema:dateModified` | `2026-02-20T11:15:00Z` | datetime |
| `kabuk:note/abc` | `kabuk:tag` | `work` | string |
| `kabuk:note/abc` | `kabuk:tag` | `planning` | string |

### Person

| Predicate | Object Type | Required | Description |
|---|---|---|---|
| `rdf:type` | URI → `schema:Person` | ✓ | Entity type |
| `schema:name` | string | ✓ | Full display name |
| `schema:givenName` | string | | First name |
| `schema:familyName` | string | | Last name |
| `schema:email` | string | | Email address (multi-valued) |
| `schema:telephone` | string | | Phone number (multi-valued) |
| `schema:image` | URI → `kabuk:media/*` | | Avatar/profile photo |
| `schema:url` | string | | Website/social URL (multi-valued) |
| `schema:jobTitle` | string | | Job title |
| `schema:worksFor` | string | | Organization name |
| `schema:address` | string | | Postal address |
| `schema:birthDate` | datetime | | Date of birth |
| `kabuk:tag` | string | | Tag label (multi-valued) |
| `kabuk:notes` | string | | Free-form notes about this person |

### Event

| Predicate | Object Type | Required | Description |
|---|---|---|---|
| `rdf:type` | URI → `schema:Event` | ✓ | Entity type |
| `schema:name` | string | ✓ | Event title |
| `schema:description` | string | | Event details |
| `schema:startDate` | datetime | ✓ | Start time (UTC) |
| `schema:endDate` | datetime | | End time (UTC) |
| `schema:location` | string | | Location name or address |
| `schema:organizer` | URI → `kabuk:person/*` | | Organizer reference |
| `schema:attendee` | URI → `kabuk:person/*` | | Attendee (multi-valued) |
| `kabuk:reminder` | datetime | | Reminder time (multi-valued) |
| `kabuk:recurrence` | string | | RRULE string (iCalendar format) |
| `kabuk:allDay` | boolean | | Whether the event is all-day |
| `kabuk:tag` | string | | Tag label (multi-valued) |

### MediaObject (ImageObject, VideoObject, AudioObject)

| Predicate | Object Type | Required | Description |
|---|---|---|---|
| `rdf:type` | URI → `schema:ImageObject` / `schema:VideoObject` / `schema:AudioObject` | ✓ | Specific media type |
| `schema:name` | string | | Display name / filename |
| `schema:contentUrl` | blob_ref | ✓ | SHA-256 hash reference to blob |
| `schema:encodingFormat` | string | ✓ | MIME type (`image/jpeg`, `video/mp4`, etc.) |
| `schema:contentSize` | integer | ✓ | Size in bytes |
| `schema:dateCreated` | datetime | ✓ | Capture/creation timestamp |
| `schema:width` | integer | | Width in pixels (images/video) |
| `schema:height` | integer | | Height in pixels (images/video) |
| `schema:duration` | string | | ISO 8601 duration (`PT3M45S`) for video/audio |
| `schema:thumbnail` | blob_ref | | Thumbnail blob hash |
| `kabuk:tag` | string | | Tag label (multi-valued) |
| `kabuk:exif/make` | string | | Camera make (from EXIF) |
| `kabuk:exif/model` | string | | Camera model (from EXIF) |
| `kabuk:exif/gpsLatitude` | float | | GPS latitude (from EXIF) |
| `kabuk:exif/gpsLongitude` | float | | GPS longitude (from EXIF) |
| `kabuk:exif/focalLength` | float | | Focal length in mm |
| `kabuk:exif/exposureTime` | string | | Exposure time (e.g., `1/250`) |
| `kabuk:exif/iso` | integer | | ISO sensitivity |
| `kabuk:exif/aperture` | float | | F-number |

### Message

| Predicate | Object Type | Required | Description |
|---|---|---|---|
| `rdf:type` | URI → `schema:Message` | ✓ | Entity type |
| `schema:text` | string | ✓ | Message body |
| `schema:sender` | URI → `kabuk:person/*` or `kabuk:agent/*` | ✓ | Who sent the message |
| `schema:recipient` | URI → `kabuk:person/*` or `kabuk:agent/*` | | Recipient (multi-valued for group) |
| `schema:dateCreated` | datetime | ✓ | When sent |
| `kabuk:conversation` | URI → `kabuk:conversation/*` | ✓ | Parent conversation |
| `kabuk:read` | boolean | | Read status |
| `kabuk:encrypted` | boolean | | Whether content is end-to-end encrypted |
| `schema:replyTo` | URI → `kabuk:message/*` | | Message being replied to |
| `kabuk:contentType` | string | | Content type hint (`text`, `markdown`, `media`, `widget`) |
| `kabuk:attachment` | URI → `kabuk:media/*` | | Media attachment (multi-valued) |

### Conversation

| Predicate | Object Type | Required | Description |
|---|---|---|---|
| `rdf:type` | URI → `kabuk:Conversation` | ✓ | Entity type |
| `schema:name` | string | | Conversation title/label |
| `kabuk:participant` | URI → `kabuk:person/*` or `kabuk:agent/*` | ✓ | Participant (multi-valued) |
| `kabuk:conversationType` | string | ✓ | `'agent'` or `'human'` or `'group'` |
| `schema:dateCreated` | datetime | ✓ | When created |
| `kabuk:lastMessageAt` | datetime | | Timestamp of most recent message |
| `kabuk:lastMessagePreview` | string | | Preview text of last message |
| `kabuk:muted` | boolean | | Whether notifications are muted |
| `kabuk:archived` | boolean | | Whether conversation is archived |

### Task

| Predicate | Object Type | Required | Description |
|---|---|---|---|
| `rdf:type` | URI → `schema:Action` | ✓ | Entity type |
| `schema:name` | string | ✓ | Task title |
| `schema:description` | string | | Task details |
| `kabuk:dueDate` | datetime | | Due date/time |
| `kabuk:completed` | boolean | | Completion status |
| `kabuk:completedAt` | datetime | | When completed |
| `kabuk:priority` | string | | `'low'` / `'medium'` / `'high'` / `'urgent'` |
| `kabuk:assignee` | URI → `kabuk:person/*` | | Assigned person |
| `kabuk:parentTask` | URI → `kabuk:task/*` | | Parent task for subtasks |
| `kabuk:tag` | string | | Tag label (multi-valued) |

---

## 4. Query API

The `QueryBuilder` provides a fluent, composable API for reading triples. All queries return `Future<List<Triple>>` or `Stream<List<Triple>>` for reactive watching.

### QueryBuilder Interface

```dart
/// Fluent query builder for the knowledge store.
/// Immutable — each method returns a new builder instance.
class QueryBuilder {
  /// Filter by subject URI (exact match).
  QueryBuilder subject(String uri);

  /// Filter by subject URI prefix (e.g., 'kabuk:note/' matches all notes).
  QueryBuilder subjectPrefix(String prefix);

  /// Filter by predicate URI (exact match).
  QueryBuilder predicate(String uri);

  /// Filter by object value (exact match).
  QueryBuilder object(String value);

  /// Filter by object type.
  QueryBuilder objectType(ObjectType type);

  /// Filter by named graph.
  QueryBuilder graph(String graphUri);

  /// Filter: object value > threshold (for datetime, integer, float).
  QueryBuilder objectGreaterThan(String value);

  /// Filter: object value < threshold (for datetime, integer, float).
  QueryBuilder objectLessThan(String value);

  /// Filter: object value BETWEEN low and high (inclusive).
  QueryBuilder objectBetween(String low, String high);

  /// Filter: object value IN a set of values.
  QueryBuilder objectIn(List<String> values);

  /// Full-text search across subject and object_value via FTS5.
  QueryBuilder fullText(String query);

  /// Order results by a column.
  QueryBuilder orderBy(TripleField field, {bool descending = false});

  /// Limit number of results.
  QueryBuilder limit(int count);

  /// Skip N results (for pagination).
  QueryBuilder offset(int count);

  /// Execute the query, returning matching triples.
  Future<List<Triple>> get();

  /// Execute the query as a reactive stream. Re-emits when
  /// matching triples change.
  Stream<List<Triple>> watch();

  /// Execute and return results grouped by subject URI.
  /// Useful for materializing entities from their triples.
  Future<Map<String, List<Triple>>> getGroupedBySubject();

  /// Count matching triples without fetching data.
  Future<int> count();
}

/// Fields available for ordering and filtering.
enum TripleField {
  subject,
  predicate,
  objectValue,
  createdAt,
  updatedAt,
}
```

### Query Examples

#### Find all notes tagged "work"

```dart
// Step 1: Find subjects that have tag "work"
final workTagged = await store.query()
    .predicate(NS.kabukTag)
    .object('work')
    .get();

final noteUris = workTagged.map((t) => t.subject).toSet();

// Step 2: Get all triples for those notes
final notes = await store.query()
    .subjectPrefix('kabuk:note/')
    .objectIn(noteUris.toList()) // could also filter in memory
    .get();

// Or, more concisely using the entity convenience:
final noteEntities = await store.findEntities(
  type: NS.schemaNote,
  where: (q) => q.predicate(NS.kabukTag).object('work'),
);
```

#### Find events in a date range

```dart
// Find all events starting between March 1-7, 2026
final events = await store.query()
    .predicate(NS.schemaStartDate)
    .objectBetween('2026-03-01T00:00:00Z', '2026-03-07T23:59:59Z')
    .objectType(ObjectType.datetime)
    .get();

// Get full entity data for each event
final eventUris = events.map((t) => t.subject).toSet();
final allTriples = await store.query()
    .subjectPrefix('kabuk:event/')
    .get();

final eventTriples = allTriples
    .where((t) => eventUris.contains(t.subject))
    .toList();
```

#### Graph traversal — follow a predicate

```dart
/// Follow a predicate from a subject, returning the linked entities.
/// Example: Find all attendees of an event, then get their contact details.
Future<List<Entity>> getEventAttendees(String eventUri) async {
  // Step 1: Get attendee URIs
  final attendeeTriples = await store.query()
      .subject(eventUri)
      .predicate(NS.schemaAttendee)
      .objectType(ObjectType.uri)
      .get();

  final personUris = attendeeTriples.map((t) => t.objectValue).toList();

  // Step 2: Fetch full person entities
  final entities = <Entity>[];
  for (final uri in personUris) {
    final triples = await store.query().subject(uri).get();
    entities.add(Entity.fromTriples(uri, triples));
  }
  return entities;
}
```

#### Full-text search

```dart
// Search for "quarterly budget" across all text content
final results = await store.query()
    .fullText('quarterly budget')
    .orderBy(TripleField.updatedAt, descending: true)
    .limit(20)
    .get();

// Group by subject to see which entities matched
final grouped = <String, List<Triple>>{};
for (final triple in results) {
  grouped.putIfAbsent(triple.subject, () => []).add(triple);
}
```

#### Combined filters with ORDER BY, LIMIT, OFFSET

```dart
// Paginated list of recent notes, 20 per page
final page2Notes = await store.query()
    .predicate(NS.rdfType)
    .object(NS.schemaNote)
    .orderBy(TripleField.updatedAt, descending: true)
    .limit(20)
    .offset(20) // Page 2
    .get();

// Get the subject URIs, then fetch all their triples
final uris = page2Notes.map((t) => t.subject).toSet();
final fullTriples = await Future.wait(
  uris.map((uri) => store.query().subject(uri).get()),
);
```

---

## 5. Mutation API

All writes go through the `mutate()` method, which executes atomically within a SQLite transaction. Every mutation emits a `ChangeSet` for reactive propagation.

### Interface

```dart
/// Transactional mutation API.
/// All operations within a single mutate() call are atomic.
abstract class KnowledgeStore {
  // ... query methods ...

  /// Execute a batch of mutations atomically.
  /// Returns the ChangeSet describing what changed.
  Future<ChangeSet> mutate(void Function(MutationBuilder m) mutations);
}

/// Builder for composing mutations within a transaction.
class MutationBuilder {
  /// Create a new entity with a generated UUID.
  /// Returns the generated URI.
  /// Sets rdf:type, schema:dateCreated, schema:dateModified automatically.
  String createEntity({
    required String prefix,    // e.g., 'kabuk:note/'
    required String type,      // e.g., 'schema:Note'
    String? graph,
  });

  /// Add a triple. If the exact quad already exists, this is a no-op.
  void add({
    required String subject,
    required String predicate,
    required String objectValue,
    ObjectType objectType = ObjectType.string,
    String? objectLang,
    String? objectDatatype,
    String? graph,
    bool encrypted = false,
  });

  /// Set a triple — upsert semantics. If a triple with the same
  /// (subject, predicate, graph) exists, its object is updated.
  /// For multi-valued predicates (like kabuk:tag), use add() instead.
  void set({
    required String subject,
    required String predicate,
    required String objectValue,
    ObjectType objectType = ObjectType.string,
    String? objectLang,
    String? objectDatatype,
    String? graph,
    bool encrypted = false,
  });

  /// Remove a specific triple by exact match.
  void remove({
    required String subject,
    required String predicate,
    required String objectValue,
    String? graph,
  });

  /// Remove all triples matching a pattern.
  /// At least one of subject/predicate must be specified.
  void removeWhere({
    String? subject,
    String? predicate,
    String? objectValue,
    String? graph,
  });

  /// Store a blob (content-addressed by SHA-256).
  /// Returns the hash. If a blob with the same hash exists, this is a no-op.
  Future<String> storeBlob({
    required Uint8List data,
    required String mimeType,
  });

  /// Remove a blob by hash. Only succeeds if no triples reference it.
  void removeBlob(String hash);
}
```

### Mutation Examples

#### Create a note

```dart
final changeSet = await store.mutate((m) {
  final noteUri = m.createEntity(
    prefix: 'kabuk:note/',
    type: NS.schemaNote,
  );

  m.set(
    subject: noteUri,
    predicate: NS.schemaName,
    objectValue: 'Weekly Standup Notes',
  );

  m.set(
    subject: noteUri,
    predicate: NS.schemaText,
    objectValue: '# Standup\n\n- Progress on feature X...',
  );

  m.add(
    subject: noteUri,
    predicate: NS.kabukTag,
    objectValue: 'work',
  );

  m.add(
    subject: noteUri,
    predicate: NS.kabukTag,
    objectValue: 'standup',
  );
});
// changeSet.added contains all 6 new triples (type, dateCreated, dateModified, name, text, 2x tag)
```

#### Update an existing entity

```dart
await store.mutate((m) {
  m.set(
    subject: 'kabuk:note/abc',
    predicate: NS.schemaText,
    objectValue: '# Updated content\n\nNew body text...',
  );

  // set() automatically updates schema:dateModified
  m.set(
    subject: 'kabuk:note/abc',
    predicate: NS.schemaDateModified,
    objectValue: DateTime.now().toUtc().toIso8601String(),
    objectType: ObjectType.datetime,
  );
});
```

#### Store a photo with blob

```dart
await store.mutate((m) async {
  // Store the image blob
  final hash = await m.storeBlob(
    data: imageBytes,
    mimeType: 'image/jpeg',
  );

  final mediaUri = m.createEntity(
    prefix: 'kabuk:media/',
    type: NS.schemaImageObject,
  );

  m.set(
    subject: mediaUri,
    predicate: NS.schemaContentUrl,
    objectValue: hash,
    objectType: ObjectType.blobRef,
  );

  m.set(
    subject: mediaUri,
    predicate: NS.schemaEncodingFormat,
    objectValue: 'image/jpeg',
  );

  m.set(
    subject: mediaUri,
    predicate: NS.schemaContentSize,
    objectValue: imageBytes.length.toString(),
    objectType: ObjectType.integer,
  );

  m.set(
    subject: mediaUri,
    predicate: NS.schemaWidth,
    objectValue: '4032',
    objectType: ObjectType.integer,
  );

  m.set(
    subject: mediaUri,
    predicate: NS.schemaHeight,
    objectValue: '3024',
    objectType: ObjectType.integer,
  );
});
```

#### Delete an entity

```dart
await store.mutate((m) {
  // Remove all triples with this subject
  m.removeWhere(subject: 'kabuk:note/abc');
});
```

---

## 6. Change Events & Reactivity

Every mutation emits a `ChangeSet` that describes exactly what changed. This is the backbone of Kabuk's reactive UI — Riverpod providers watch streams of changes and rebuild widgets when relevant data mutates.

### Change Types

```dart
/// A single change to the triple store.
@freezed
sealed class KnowledgeChange with _$KnowledgeChange {
  /// A new triple was added.
  const factory KnowledgeChange.added(Triple triple) = TripleAdded;

  /// An existing triple was removed.
  const factory KnowledgeChange.removed(Triple triple) = TripleRemoved;

  /// A triple was updated (set() replaced the old value).
  /// Contains both old and new triple for diffing.
  const factory KnowledgeChange.updated({
    required Triple oldTriple,
    required Triple newTriple,
  }) = TripleUpdated;
}
```

### ChangeSet

```dart
/// A batch of changes from a single mutate() call.
/// Emitted atomically — either all changes happened or none did.
@freezed
class ChangeSet with _$ChangeSet {
  const factory ChangeSet({
    /// Unique ID for this changeset (UUID v7).
    required String id,

    /// When this mutation was applied.
    required DateTime timestamp,

    /// The named graph these changes belong to (if uniform).
    String? graph,

    /// All individual changes in this mutation.
    required List<KnowledgeChange> changes,

    /// The source of the mutation (agent name, user action, sync).
    required String source,
  }) = _ChangeSet;

  /// Convenience: all added triples.
  List<Triple> get added => changes
      .whereType<TripleAdded>()
      .map((c) => c.triple)
      .toList();

  /// Convenience: all removed triples.
  List<Triple> get removed => changes
      .whereType<TripleRemoved>()
      .map((c) => c.triple)
      .toList();

  /// Convenience: all updated triples (new values).
  List<Triple> get updated => changes
      .whereType<TripleUpdated>()
      .map((c) => c.newTriple)
      .toList();

  /// All subject URIs affected by this changeset.
  Set<String> get affectedSubjects => changes.map((c) => switch (c) {
    TripleAdded(:final triple) => triple.subject,
    TripleRemoved(:final triple) => triple.subject,
    TripleUpdated(:final newTriple) => newTriple.subject,
  }).toSet();
}
```

### Stream Infrastructure

```dart
/// The knowledge store exposes a broadcast stream of all changes.
abstract class KnowledgeStore {
  /// Stream of all change sets. Each mutation emits exactly one ChangeSet.
  Stream<ChangeSet> get changes;

  /// Filtered stream: only change sets that affect the given subject.
  Stream<ChangeSet> watchSubject(String subjectUri);

  /// Filtered stream: only change sets that affect triples matching a pattern.
  Stream<ChangeSet> watchPattern({
    String? subject,
    String? predicate,
    String? objectValue,
    String? graph,
  });
}
```

### Riverpod Providers

```dart
/// Provider exposing the global change stream.
final knowledgeChangesProvider = StreamProvider<ChangeSet>((ref) {
  return ref.watch(knowledgeStoreProvider).changes;
});

/// Provider that watches a specific entity and rebuilds when it changes.
/// Returns all triples for the given subject URI.
final entityProvider = StreamProvider.family<List<Triple>, String>(
  (ref, subjectUri) {
    final store = ref.watch(knowledgeStoreProvider);

    // Initial fetch + re-fetch on relevant changes
    return store.query().subject(subjectUri).watch();
  },
);

/// Provider for a typed query result that auto-updates.
/// Example: all notes tagged "work", sorted by date.
final workNotesProvider = StreamProvider<List<Entity>>((ref) {
  final store = ref.watch(knowledgeStoreProvider);

  return store
      .query()
      .predicate(NS.rdfType)
      .object(NS.schemaNote)
      .watch()
      .asyncMap((typeTriples) async {
    final uris = typeTriples.map((t) => t.subject).toSet();

    // Filter to only those tagged "work"
    final tagTriples = await store
        .query()
        .predicate(NS.kabukTag)
        .object('work')
        .get();
    final workUris = tagTriples.map((t) => t.subject).toSet();
    final matchingUris = uris.intersection(workUris);

    // Materialize full entities
    final entities = <Entity>[];
    for (final uri in matchingUris) {
      final triples = await store.query().subject(uri).get();
      entities.add(Entity.fromTriples(uri, triples));
    }

    entities.sort((a, b) =>
        b.dateModified.compareTo(a.dateModified));
    return entities;
  });
});
```

### Propagation Flow

```
mutate() called
    │
    ▼
SQLite transaction executes
    │
    ▼
ChangeSet constructed from diff
    │
    ▼
ChangeSet emitted on broadcast stream ──────────────┐
    │                                                │
    ▼                                                ▼
watchPattern() filters match?              Agent subscriptions
    │ yes                                  filter + callback
    ▼
Riverpod StreamProvider receives new event
    │
    ▼
Provider re-evaluates / re-fetches query
    │
    ▼
Dependent widgets rebuild with new data
```

**Design principle:** The UI never polls. It never manually refreshes. Every widget that displays knowledge store data does so through a provider that watches the change stream. When data changes, the widget rebuilds. This is the same reactivity model as Firestore listeners but running entirely locally on SQLite.

---

## 7. Encryption

Kabuk supports per-triple encryption for sensitive data. Encryption is transparent — encrypted triples are decrypted in memory during queries and re-encrypted on write.

### Architecture

```
┌──────────────────────────────────────────────┐
│            Application Layer                  │
│  (reads/writes plaintext triples)            │
└─────────────────┬────────────────────────────┘
                  │
┌─────────────────▼────────────────────────────┐
│          Encryption Layer                     │
│                                               │
│  encrypt(plaintext) → ciphertext + nonce     │
│  decrypt(ciphertext, nonce) → plaintext      │
│                                               │
│  Algorithm: AES-256-GCM                      │
│  Key: derived from passphrase + platform key │
└─────────────────┬────────────────────────────┘
                  │
┌─────────────────▼────────────────────────────┐
│             SQLite Layer                      │
│  (stores ciphertext in object_value,         │
│   encrypted=1 flag set)                      │
└──────────────────────────────────────────────┘
```

### Key Derivation

```
User Passphrase
       │
       ▼
  Argon2id(passphrase, salt, t=3, m=65536, p=4)
       │
       ▼
  256-bit Master Key
       │
       ├──► Stored in platform keystore:
       │    - Android: Android Keystore
       │    - iOS: Secure Enclave / Keychain
       │    - Desktop: OS keychain (libsecret / Keychain Access)
       │
       └──► HKDF(masterKey, context="kabuk-triple-encryption")
                │
                ▼
          256-bit Encryption Key (used for AES-256-GCM)
```

### Per-Triple Encryption

When `encrypted = true` on a triple:

1. **Write path**: `object_value` is encrypted with AES-256-GCM before storage. The nonce (12 bytes) and auth tag (16 bytes) are prepended to the ciphertext. The `object_value` column stores base64-encoded `nonce || tag || ciphertext`.
2. **Read path**: On query, if `encrypted = 1`, `object_value` is decoded, split into nonce/tag/ciphertext, and decrypted. The plaintext triple is returned to the caller.
3. **FTS behavior**: Encrypted triples are **not** indexed in FTS5. Full-text search only covers unencrypted content. This is a deliberate trade-off — indexing encrypted content would leak information.
4. **Index behavior**: The `idx_triples_object_uri` index only covers unencrypted triples. Subject and predicate are always stored in plaintext (they are URIs, not user data). Only the object value is encrypted.

### Blob Encryption

Blobs with sensitive content are encrypted before storage:

```dart
// Blob encryption uses the same key with a different HKDF context
final blobKey = HKDF(masterKey, context: 'kabuk-blob-encryption');

// Entire blob is encrypted as one AES-256-GCM message
// Stored as: nonce (12B) || tag (16B) || ciphertext
final encryptedBlob = AesGcm.encrypt(
  plaintext: blobData,
  key: blobKey,
  nonce: generateNonce(),
);
```

### Key Rotation

Key rotation re-encrypts all encrypted triples and blobs with a new key:

1. User provides old passphrase + new passphrase.
2. Derive old key and new key.
3. In a single transaction:
   - Read all encrypted triples, decrypt with old key.
   - Re-encrypt with new key, update `object_value` and `updated_at`.
4. Re-encrypt all encrypted blobs (can be done in batches outside the triple transaction).
5. Wipe old key from keystore. Store new key.

**Key rotation is expensive** but infrequent. For a store with 10,000 encrypted triples, expect ~2-5 seconds on a modern mobile device.

### Encryption Scope

| Data | Encrypted by default? | Notes |
|---|---|---|
| Message content | Yes | All message `schema:text` triples |
| Contact phone/email | Yes | PII fields |
| Note content | No | User can opt-in per note |
| Event details | No | User can opt-in per event |
| Media blobs | Optional | User chooses at capture time |
| Preferences | No | Non-sensitive settings |
| Agent state | No | Internal operational data |

---

## 8. Named Graphs

Named graphs partition the triple store into logical collections without duplicating data. Every triple belongs to exactly one graph (default: `kabuk:graph/default`). Graphs enable provenance tracking, access control, and selective sync.

### Use Cases

#### Provenance Tracking

Track which agent created each piece of data:

```dart
await store.mutate((m) {
  m.add(
    subject: noteUri,
    predicate: NS.schemaName,
    objectValue: 'Auto-generated summary',
    graph: 'kabuk:graph/agent/note', // NoteAgent created this
  );
});

// Later: find all data created by the NoteAgent
final agentData = await store.query()
    .graph('kabuk:graph/agent/note')
    .get();
```

#### Import Source Tracking

When importing data from external sources, tag it with the source graph:

```dart
// Import Google Contacts
for (final contact in googleContacts) {
  await store.mutate((m) {
    final uri = m.createEntity(
      prefix: 'kabuk:person/',
      type: NS.schemaPerson,
      graph: 'kabuk:graph/import/google-contacts',
    );
    m.set(
      subject: uri,
      predicate: NS.schemaName,
      objectValue: contact.name,
      graph: 'kabuk:graph/import/google-contacts',
    );
    // ... more fields
  });
}

// Find all imported contacts for re-sync
final imported = await store.query()
    .graph('kabuk:graph/import/google-contacts')
    .predicate(NS.rdfType)
    .object(NS.schemaPerson)
    .get();
```

#### Sync Device Tracking

In multi-device scenarios, each device writes to its own graph:

```dart
// This device's graph
final deviceGraph = 'kabuk:graph/device/${deviceId}';

// Find triples from other devices (for conflict resolution)
final remoteTriples = await store.query()
    .graph('kabuk:graph/device/other-device-id')
    .get();
```

### Graph-Scoped Queries

All query builder methods can be combined with `.graph()`:

```dart
// All notes created by the user (not agents, not imports)
final userNotes = await store.query()
    .graph('kabuk:graph/user')
    .predicate(NS.rdfType)
    .object(NS.schemaNote)
    .get();

// Cross-graph: find all triples for a subject regardless of graph
final allTriples = await store.query()
    .subject('kabuk:person/abc')
    .get(); // No .graph() filter — returns from all graphs
```

### Graph Metadata

Graphs themselves can have metadata stored as triples:

```dart
// Describe the import graph
await store.mutate((m) {
  m.add(
    subject: 'kabuk:graph/import/google-contacts',
    predicate: NS.rdfsLabel,
    objectValue: 'Google Contacts Import',
  );
  m.add(
    subject: 'kabuk:graph/import/google-contacts',
    predicate: NS.schemaDateCreated,
    objectValue: '2026-02-25T10:00:00Z',
    objectType: ObjectType.datetime,
  );
  m.add(
    subject: 'kabuk:graph/import/google-contacts',
    predicate: 'kabuk:importSource',
    objectValue: 'google-people-api',
  );
});
```

---

## 9. Import/Export

The knowledge store supports multiple serialization formats for interoperability, backup, and migration.

### Formats

| Format | Extension | Use Case | Human Readable | Streaming |
|---|---|---|---|---|
| Turtle | `.ttl` | Human inspection, debugging, small exports | Yes | No |
| N-Triples | `.nt` | Machine processing, large bulk operations | Somewhat | Yes |
| JSON-LD | `.jsonld` | Web interop, API exchange, Schema.org tools | Yes | No |
| SQLite backup | `.db` | Full encrypted backup/restore | No | No |

### Turtle Export

```dart
/// Export all triples (or a subset) as Turtle.
Future<String> exportTurtle({
  String? graph,
  String? type,      // Filter by rdf:type
  List<String>? subjects,
}) async {
  final buffer = StringBuffer();

  // Write prefixes
  buffer.writeln('@prefix schema: <https://schema.org/> .');
  buffer.writeln('@prefix kabuk: <kabuk://> .');
  buffer.writeln('@prefix rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#> .');
  buffer.writeln('@prefix rdfs: <http://www.w3.org/2000/01/rdf-schema#> .');
  buffer.writeln('@prefix xsd: <http://www.w3.org/2001/XMLSchema#> .');
  buffer.writeln();

  // Query and serialize...
  final triples = await _buildQuery(graph, type, subjects).get();
  final grouped = _groupBySubject(triples);

  for (final entry in grouped.entries) {
    buffer.writeln('${entry.key}');
    final predicates = _groupByPredicate(entry.value);
    var first = true;
    for (final pred in predicates.entries) {
      final prefix = first ? '    ' : '    ; ';
      first = false;
      final objects = pred.value.map(_formatObject).join(' , ');
      buffer.writeln('$prefix${pred.key} $objects');
    }
    buffer.writeln('    .');
    buffer.writeln();
  }

  return buffer.toString();
}
```

### N-Triples Export

```dart
/// Export as N-Triples — one triple per line, suitable for streaming/piping.
Stream<String> exportNTriples({String? graph, String? type}) async* {
  final triples = await _buildQuery(graph, type, null).get();
  for (final t in triples) {
    yield '${_ntUri(t.subject)} ${_ntUri(t.predicate)} ${_ntObject(t)} .\n';
  }
}
```

### JSON-LD Export

```dart
/// Export as JSON-LD with Schema.org context.
Future<Map<String, dynamic>> exportJsonLd({
  String? graph,
  String? type,
}) async {
  return {
    '@context': {
      'schema': 'https://schema.org/',
      'kabuk': 'kabuk://',
      'rdf': 'http://www.w3.org/1999/02/22-rdf-syntax-ns#',
    },
    '@graph': await _buildJsonLdGraph(graph, type),
  };
}
```

### Selective Export

```dart
// Export only notes
final notesTtl = await store.exportTurtle(type: NS.schemaNote);

// Export only a specific graph
final importedTtl = await store.exportTurtle(
  graph: 'kabuk:graph/import/google-contacts',
);

// Export specific entities
final selectedTtl = await store.exportTurtle(
  subjects: ['kabuk:note/abc', 'kabuk:note/def'],
);
```

### Full Backup

```dart
/// Create an encrypted full backup of the SQLite database.
Future<File> createBackup({
  required String outputPath,
  required String passphrase,
}) async {
  // 1. Flush WAL to main database file
  await _db.customStatement('PRAGMA wal_checkpoint(TRUNCATE)');

  // 2. Copy database file
  final dbFile = File(_db.path);
  final backupFile = await dbFile.copy(outputPath);

  // 3. Encrypt the backup file with AES-256-GCM
  final key = await _deriveBackupKey(passphrase);
  await _encryptFile(backupFile, key);

  return backupFile;
}

/// Restore from an encrypted backup.
Future<void> restoreBackup({
  required String backupPath,
  required String passphrase,
}) async {
  // 1. Decrypt backup
  final key = await _deriveBackupKey(passphrase);
  final decrypted = await _decryptFile(File(backupPath), key);

  // 2. Close current database
  await _db.close();

  // 3. Replace database file
  await decrypted.copy(_db.path);

  // 4. Reopen and validate
  await _db.open();
  await _validateSchema();
}
```

### Import

```dart
/// Import triples from Turtle format.
Future<ChangeSet> importTurtle(
  String turtleContent, {
  String? targetGraph,
}) async {
  final parser = TurtleParser();
  final triples = parser.parse(turtleContent);

  return store.mutate((m) {
    for (final t in triples) {
      m.add(
        subject: t.subject,
        predicate: t.predicate,
        objectValue: t.objectValue,
        objectType: t.objectType,
        objectLang: t.objectLang,
        objectDatatype: t.objectDatatype,
        graph: targetGraph ?? t.graph ?? 'kabuk:graph/import/turtle',
      );
    }
  });
}
```

---

## 10. Agent Integration

Agents are the primary consumers and producers of knowledge store data. Every agent accesses the store through `AgentContext.knowledge`, which is a capability-scoped proxy.

### Access Pattern

```dart
class AgentContext {
  /// Capability-gated proxy to the knowledge store.
  /// Only allows operations matching the agent's declared capabilities.
  final KnowledgeStore knowledge;

  // ... other services ...
}
```

### Capability Gates

Agents declare the capabilities they need. The runtime enforces these at the proxy level:

| Capability | Allows |
|---|---|
| `knowledge:read` | Query triples (all types) |
| `knowledge:read:note` | Query only `schema:Note` triples |
| `knowledge:read:person` | Query only `schema:Person` triples |
| `knowledge:read:event` | Query only `schema:Event` triples |
| `knowledge:read:media` | Query only media-type triples |
| `knowledge:read:message` | Query only `schema:Message` triples |
| `knowledge:write` | Mutate triples (all types) |
| `knowledge:write:note` | Mutate only `schema:Note` triples |
| `knowledge:write:person` | Mutate only `schema:Person` triples |
| `knowledge:write:event` | Mutate only `schema:Event` triples |
| `knowledge:write:media` | Mutate only media-type triples |
| `knowledge:write:message` | Mutate only `schema:Message` triples |
| `knowledge:delete` | Remove triples |
| `knowledge:blob:read` | Read blob data |
| `knowledge:blob:write` | Store new blobs |

**Example: NoteAgent capabilities**

```dart
class NoteAgent extends BaseAgent {
  @override
  List<String> get requiredCapabilities => [
    'knowledge:read:note',
    'knowledge:write:note',
    'knowledge:delete',
    'knowledge:blob:read',    // For note attachments
  ];

  @override
  Future<AgentResponse> process(AgentMessage msg, AgentContext ctx) async {
    // ctx.knowledge is scoped — can only read/write notes
    final notes = await ctx.knowledge.query()
        .predicate(NS.rdfType)
        .object(NS.schemaNote)
        .get();

    // This would throw CapabilityDeniedException:
    // await ctx.knowledge.query()
    //     .predicate(NS.rdfType)
    //     .object(NS.schemaPerson)
    //     .get();
  }
}
```

### Agent Change Subscriptions

Agents can subscribe to change events for patterns they care about. This enables reactive agent behavior — an agent can respond to data changes, not just user messages.

```dart
// In agent tool implementation:
Future<ToolResult> setupReminders(Map<String, dynamic> args, AgentContext ctx) async {
  // Subscribe to new events being created
  ctx.knowledge.watchPattern(
    predicate: NS.rdfType,
    objectValue: NS.schemaEvent,
  ).listen((changeSet) {
    for (final change in changeSet.changes) {
      if (change is TripleAdded) {
        // A new event was created — check if it needs a reminder
        _scheduleReminderIfNeeded(change.triple.subject, ctx);
      }
    }
  });

  return ToolResult.text('Reminder watcher active.');
}
```

### Tool Results with Mutations

Agent tools can return mutations as part of their result. The runtime applies these atomically after the tool returns:

```dart
// NoteAgent: create_note tool
Future<ToolResult> createNote(Map<String, dynamic> args, AgentContext ctx) async {
  final title = args['title'] as String;
  final content = args['content'] as String;
  final tags = (args['tags'] as List?)?.cast<String>() ?? [];

  // Create the note via mutation
  final changeSet = await ctx.knowledge.mutate((m) {
    final uri = m.createEntity(
      prefix: 'kabuk:note/',
      type: NS.schemaNote,
      graph: 'kabuk:graph/agent/note',
    );

    m.set(subject: uri, predicate: NS.schemaName, objectValue: title);
    m.set(subject: uri, predicate: NS.schemaText, objectValue: content);

    for (final tag in tags) {
      m.add(subject: uri, predicate: NS.kabukTag, objectValue: tag);
    }
  });

  // Return a widget showing the created note
  final noteUri = changeSet.added
      .firstWhere((t) => t.predicate == NS.rdfType)
      .subject;

  return ToolResult.compound([
    ToolResult.text('Created note: $title'),
    ToolResult.widget(
      RfwTemplate(library: 'kabuk:notes', widget: 'NoteCard'),
      {'noteUri': noteUri},
    ),
  ]);
}
```

---

## 11. Dart Data Classes

All core types are defined as Freezed immutable data classes with JSON serialization.

### Triple

```dart
@freezed
class Triple with _$Triple {
  const factory Triple({
    /// Auto-incremented database ID. Null for unsaved triples.
    int? id,

    /// Subject URI (e.g., 'kabuk:note/abc').
    required String subject,

    /// Predicate URI (e.g., 'schema:name').
    required String predicate,

    /// String representation of the object value.
    required String objectValue,

    /// Type of the object value.
    @Default(ObjectType.string) ObjectType objectType,

    /// Language tag for string literals (e.g., 'en', 'tr').
    String? objectLang,

    /// XSD datatype URI (e.g., 'xsd:dateTime').
    String? objectDatatype,

    /// Named graph URI.
    @Default('kabuk:graph/default') String graph,

    /// When this triple was created.
    required DateTime createdAt,

    /// When this triple was last modified.
    required DateTime updatedAt,

    /// Whether the object value is encrypted at rest.
    @Default(false) bool encrypted,
  }) = _Triple;

  factory Triple.fromJson(Map<String, dynamic> json) =>
      _$TripleFromJson(json);
}
```

### ObjectType Enum

```dart
/// The type of an object value in a triple.
enum ObjectType {
  /// A URI reference to another entity.
  uri,

  /// A plain string literal.
  string,

  /// An integer value (stored as string, parsed on read).
  integer,

  /// A floating-point value (stored as string, parsed on read).
  float,

  /// An ISO 8601 datetime (stored as string, parsed on read).
  datetime,

  /// A boolean ('true' or 'false' as string).
  boolean,

  /// A SHA-256 hash referencing a blob in the blobs table.
  blobRef,
}
```

### Blob

```dart
@freezed
class Blob with _$Blob {
  const factory Blob({
    /// SHA-256 hex digest (content-addressed key).
    required String hash,

    /// MIME type (e.g., 'image/jpeg', 'audio/mp3').
    required String mimeType,

    /// Size in bytes.
    required int size,

    /// When the blob was stored.
    required DateTime createdAt,
  }) = _Blob;

  factory Blob.fromJson(Map<String, dynamic> json) =>
      _$BlobFromJson(json);
}
```

**Note:** The `Blob` class intentionally does not hold `data` — blob data is loaded lazily via `store.readBlob(hash)` to avoid holding large binary data in memory.

### Entity

```dart
/// Convenience wrapper: a subject URI + all its triples materialized as a map.
/// This is the most common way agents and UI interact with stored data.
@freezed
class Entity with _$Entity {
  const factory Entity({
    /// The subject URI of this entity.
    required String uri,

    /// The rdf:type of this entity (e.g., 'schema:Note').
    required String type,

    /// All predicates and their values.
    /// Multi-valued predicates have List<String> values.
    required Map<String, dynamic> properties,

    /// Raw triples for this entity (useful for advanced operations).
    required List<Triple> triples,
  }) = _Entity;

  /// Construct an Entity from a list of triples sharing the same subject.
  factory Entity.fromTriples(String uri, List<Triple> triples) {
    final props = <String, dynamic>{};
    String? type;

    for (final t in triples) {
      if (t.predicate == NS.rdfType) {
        type = t.objectValue;
        continue;
      }

      if (props.containsKey(t.predicate)) {
        // Multi-valued: convert to list
        final existing = props[t.predicate];
        if (existing is List) {
          existing.add(t.objectValue);
        } else {
          props[t.predicate] = [existing, t.objectValue];
        }
      } else {
        props[t.predicate] = t.objectValue;
      }
    }

    return Entity(
      uri: uri,
      type: type ?? 'unknown',
      properties: props,
      triples: triples,
    );
  }

  /// Get a single-valued property, or null.
  String? get(String predicate) {
    final val = properties[predicate];
    if (val is List) return val.firstOrNull;
    return val as String?;
  }

  /// Get a multi-valued property as a list.
  List<String> getAll(String predicate) {
    final val = properties[predicate];
    if (val == null) return [];
    if (val is List) return val.cast<String>();
    return [val as String];
  }

  /// Shorthand accessors for common Schema.org properties.
  String? get name => get(NS.schemaName);
  String? get description => get(NS.schemaDescription);
  DateTime? get dateCreated {
    final val = get(NS.schemaDateCreated);
    return val != null ? DateTime.tryParse(val) : null;
  }
  DateTime? get dateModified {
    final val = get(NS.schemaDateModified);
    return val != null ? DateTime.tryParse(val) : null;
  }
  List<String> get tags => getAll(NS.kabukTag);
}
```

### NS Constants

```dart
/// Namespace constants for all URIs used in Kabuk.
/// Use these instead of raw strings to prevent typos and enable refactoring.
abstract final class NS {
  // ── Namespace Prefixes ──────────────────────────────────
  static const schema = 'schema:';
  static const kabuk = 'kabuk:';
  static const rdf = 'rdf:';
  static const rdfs = 'rdfs:';
  static const xsd = 'xsd:';

  // ── Full Namespace URIs (for serialization) ─────────────
  static const schemaFull = 'https://schema.org/';
  static const rdfFull = 'http://www.w3.org/1999/02/22-rdf-syntax-ns#';
  static const rdfsFull = 'http://www.w3.org/2000/01/rdf-schema#';
  static const xsdFull = 'http://www.w3.org/2001/XMLSchema#';
  static const kabukFull = 'kabuk://';

  // ── RDF Core ────────────────────────────────────────────
  static const rdfType = 'rdf:type';

  // ── RDFS ────────────────────────────────────────────────
  static const rdfsLabel = 'rdfs:label';
  static const rdfsComment = 'rdfs:comment';

  // ── Schema.org Types ────────────────────────────────────
  static const schemaNote = 'schema:Note';
  static const schemaPerson = 'schema:Person';
  static const schemaEvent = 'schema:Event';
  static const schemaImageObject = 'schema:ImageObject';
  static const schemaVideoObject = 'schema:VideoObject';
  static const schemaAudioObject = 'schema:AudioObject';
  static const schemaMessage = 'schema:Message';
  static const schemaAction = 'schema:Action';

  // ── Schema.org Properties ───────────────────────────────
  static const schemaName = 'schema:name';
  static const schemaDescription = 'schema:description';
  static const schemaText = 'schema:text';
  static const schemaDateCreated = 'schema:dateCreated';
  static const schemaDateModified = 'schema:dateModified';
  static const schemaStartDate = 'schema:startDate';
  static const schemaEndDate = 'schema:endDate';
  static const schemaLocation = 'schema:location';
  static const schemaOrganizer = 'schema:organizer';
  static const schemaAttendee = 'schema:attendee';
  static const schemaGivenName = 'schema:givenName';
  static const schemaFamilyName = 'schema:familyName';
  static const schemaEmail = 'schema:email';
  static const schemaTelephone = 'schema:telephone';
  static const schemaImage = 'schema:image';
  static const schemaUrl = 'schema:url';
  static const schemaJobTitle = 'schema:jobTitle';
  static const schemaWorksFor = 'schema:worksFor';
  static const schemaAddress = 'schema:address';
  static const schemaBirthDate = 'schema:birthDate';
  static const schemaContentUrl = 'schema:contentUrl';
  static const schemaEncodingFormat = 'schema:encodingFormat';
  static const schemaContentSize = 'schema:contentSize';
  static const schemaWidth = 'schema:width';
  static const schemaHeight = 'schema:height';
  static const schemaDuration = 'schema:duration';
  static const schemaThumbnail = 'schema:thumbnail';
  static const schemaSender = 'schema:sender';
  static const schemaRecipient = 'schema:recipient';
  static const schemaReplyTo = 'schema:replyTo';
  static const schemaAuthor = 'schema:author';

  // ── Kabuk Types ─────────────────────────────────────────
  static const kabukConversation = 'kabuk:Conversation';

  // ── Kabuk Properties ────────────────────────────────────
  static const kabukTag = 'kabuk:tag';
  static const kabukPinned = 'kabuk:pinned';
  static const kabukNotes = 'kabuk:notes';
  static const kabukReminder = 'kabuk:reminder';
  static const kabukRecurrence = 'kabuk:recurrence';
  static const kabukAllDay = 'kabuk:allDay';
  static const kabukConversationPred = 'kabuk:conversation';
  static const kabukRead = 'kabuk:read';
  static const kabukEncrypted = 'kabuk:encrypted';
  static const kabukContentType = 'kabuk:contentType';
  static const kabukAttachment = 'kabuk:attachment';
  static const kabukParticipant = 'kabuk:participant';
  static const kabukConversationType = 'kabuk:conversationType';
  static const kabukLastMessageAt = 'kabuk:lastMessageAt';
  static const kabukLastMessagePreview = 'kabuk:lastMessagePreview';
  static const kabukMuted = 'kabuk:muted';
  static const kabukArchived = 'kabuk:archived';
  static const kabukDueDate = 'kabuk:dueDate';
  static const kabukCompleted = 'kabuk:completed';
  static const kabukCompletedAt = 'kabuk:completedAt';
  static const kabukPriority = 'kabuk:priority';
  static const kabukAssignee = 'kabuk:assignee';
  static const kabukParentTask = 'kabuk:parentTask';
  static const kabukImportSource = 'kabuk:importSource';

  // ── Kabuk EXIF Properties ───────────────────────────────
  static const kabukExifMake = 'kabuk:exif/make';
  static const kabukExifModel = 'kabuk:exif/model';
  static const kabukExifGpsLatitude = 'kabuk:exif/gpsLatitude';
  static const kabukExifGpsLongitude = 'kabuk:exif/gpsLongitude';
  static const kabukExifFocalLength = 'kabuk:exif/focalLength';
  static const kabukExifExposureTime = 'kabuk:exif/exposureTime';
  static const kabukExifIso = 'kabuk:exif/iso';
  static const kabukExifAperture = 'kabuk:exif/aperture';

  // ── URI Prefixes for Entity Generation ──────────────────
  static const notePrefix = 'kabuk:note/';
  static const personPrefix = 'kabuk:person/';
  static const eventPrefix = 'kabuk:event/';
  static const mediaPrefix = 'kabuk:media/';
  static const filePrefix = 'kabuk:file/';
  static const messagePrefix = 'kabuk:message/';
  static const conversationPrefix = 'kabuk:conversation/';
  static const preferencePrefix = 'kabuk:preference/';
  static const agentPrefix = 'kabuk:agent/';
  static const widgetPrefix = 'kabuk:widget/';
  static const capabilityPrefix = 'kabuk:capability/';
  static const taskPrefix = 'kabuk:task/';
  static const tagPrefix = 'kabuk:tag/';

  // ── Graph Prefixes ──────────────────────────────────────
  static const graphDefault = 'kabuk:graph/default';
  static const graphUser = 'kabuk:graph/user';
  static const graphAgentPrefix = 'kabuk:graph/agent/';
  static const graphImportPrefix = 'kabuk:graph/import/';
  static const graphDevicePrefix = 'kabuk:graph/device/';

  /// Expand a prefixed URI to its full form.
  static String expand(String prefixed) {
    if (prefixed.startsWith('schema:')) {
      return prefixed.replaceFirst('schema:', schemaFull);
    }
    if (prefixed.startsWith('rdf:')) {
      return prefixed.replaceFirst('rdf:', rdfFull);
    }
    if (prefixed.startsWith('rdfs:')) {
      return prefixed.replaceFirst('rdfs:', rdfsFull);
    }
    if (prefixed.startsWith('xsd:')) {
      return prefixed.replaceFirst('xsd:', xsdFull);
    }
    if (prefixed.startsWith('kabuk:')) {
      return prefixed.replaceFirst('kabuk:', kabukFull);
    }
    return prefixed;
  }

  /// Compact a full URI to its prefixed form.
  static String compact(String full) {
    if (full.startsWith(schemaFull)) {
      return full.replaceFirst(schemaFull, 'schema:');
    }
    if (full.startsWith(rdfFull)) {
      return full.replaceFirst(rdfFull, 'rdf:');
    }
    if (full.startsWith(rdfsFull)) {
      return full.replaceFirst(rdfsFull, 'rdfs:');
    }
    if (full.startsWith(xsdFull)) {
      return full.replaceFirst(xsdFull, 'xsd:');
    }
    if (full.startsWith(kabukFull)) {
      return full.replaceFirst(kabukFull, 'kabuk:');
    }
    return full;
  }
}
```

---

## 12. Performance

### Indexing Strategy

The index set is designed for the most common query patterns:

| Index | Covers | Query Pattern |
|---|---|---|
| `idx_triples_subject` | subject | "Get all triples for entity X" |
| `idx_triples_predicate` | predicate | "Find all triples with predicate Y" |
| `idx_triples_object_uri` | object_value WHERE uri | "Find entities linked to entity Z" |
| `idx_triples_graph` | graph | "Get all triples in graph G" |
| `idx_triples_subject_predicate` | (subject, predicate) | "Get the name of entity X" — most common pattern |
| `idx_triples_type` | object_value WHERE predicate=rdf:type | "Find all Notes" — type-based listing |
| `idx_triples_datetime` | object_value WHERE datetime | Date range queries |
| `idx_triples_graph_subject` | (graph, subject) | Graph-scoped entity lookup |
| `idx_triples_unique` | (subject, predicate, object_value, graph) | Duplicate prevention + exact match |

**Index overhead:** Each index adds ~10-15% storage overhead per column indexed. With 9 indexes on a table, storage is roughly 2x the raw data. For a store of 50,000 triples (~5MB raw), total database size will be ~10-15MB. Well within mobile limits.

### FTS5 for Full-Text Search

The FTS5 virtual table indexes subject and object_value. This supports:

- **Prefix queries**: `"meet*"` matches "meeting", "meetup"
- **Phrase queries**: `"quarterly budget"` matches the exact phrase
- **Boolean operators**: `"budget AND quarterly"`, `"budget OR planning"`
- **Near queries**: `"budget NEAR planning"` matches within 10 tokens
- **Column filters**: `"object_value: quarterly"` searches only object values

FTS5 is incrementally updated via triggers on every INSERT, UPDATE, DELETE.

### In-Memory Cache

```dart
/// LRU cache for frequently accessed triples.
class TripleCache {
  final int maxEntries;
  final LinkedHashMap<String, List<Triple>> _cache;

  /// Cache key is the subject URI for entity lookups,
  /// or a query hash for query result caching.
  List<Triple>? get(String key);
  void put(String key, List<Triple> triples);

  /// Invalidate cache entries affected by a ChangeSet.
  void invalidate(ChangeSet changes) {
    for (final subject in changes.affectedSubjects) {
      _cache.remove(subject);
    }
    // Also invalidate any query result caches that might
    // be affected (conservative: clear all query caches).
    _clearQueryCaches();
  }
}
```

**Cache strategy:**
- **Entity cache**: Keyed by subject URI. Caches the `List<Triple>` for an entity. Invalidated when any triple with that subject changes.
- **Query cache**: Keyed by query hash. Caches query results. Invalidated conservatively (all query caches cleared on any mutation). Future optimization: fine-grained invalidation based on predicate/type matching.
- **Default size**: 500 entity entries, 100 query entries. Configurable.

### Batch Inserts

For bulk operations (import, sync), use batch inserts to amortize transaction overhead:

```dart
/// Batch insert with a single transaction and deferred index updates.
Future<ChangeSet> batchInsert(List<Triple> triples) async {
  return _db.transaction(() async {
    // Temporarily disable triggers for FTS update
    await _db.customStatement('DROP TRIGGER IF EXISTS triples_ai');

    // Batch insert
    final batch = _db.batch();
    for (final t in triples) {
      batch.insert(_db.triplesTable, t.toCompanion());
    }
    await batch.commit(noResult: true);

    // Rebuild FTS index
    await _db.customStatement(
      "INSERT INTO triples_fts(triples_fts) VALUES('rebuild')",
    );

    // Re-create trigger
    await _createFtsTriggers();

    // Emit combined change set
    return ChangeSet(/* ... */);
  });
}
```

**Batch performance:**
- Individual inserts: ~200 triples/second
- Batched inserts (one transaction): ~10,000 triples/second
- Batched with deferred FTS: ~20,000 triples/second

### Lazy Blob Loading

Blob data is never loaded unless explicitly requested:

```dart
// Blob metadata is always available (from the blobs table)
final blob = await store.getBlobMeta(hash);
print('${blob.mimeType}, ${blob.size} bytes');

// Blob data is loaded only on demand
final data = await store.readBlob(hash);
// data is Uint8List
```

For media-heavy entities (photos, videos), the UI loads thumbnails first (small blobs) and full-resolution data only when the user opens the detail view.

### Query Result Pagination

```dart
// Standard offset-based pagination
final page = await store.query()
    .predicate(NS.rdfType)
    .object(NS.schemaNote)
    .orderBy(TripleField.updatedAt, descending: true)
    .limit(20)
    .offset(page * 20)
    .get();

// Cursor-based pagination (more efficient for large sets)
final page = await store.query()
    .predicate(NS.rdfType)
    .object(NS.schemaNote)
    .objectLessThan(lastSeenTimestamp) // Cursor
    .orderBy(TripleField.updatedAt, descending: true)
    .limit(20)
    .get();
```

### Expected Scale

| Metric | Comfortable Range | Notes |
|---|---|---|
| Total triples | 10,000 – 100,000 | SQLite handles millions, but mobile memory is the constraint |
| Entity count | 1,000 – 10,000 | ~10 triples per entity average |
| Query latency (indexed) | < 5ms | On-device SQLite is fast |
| Query latency (FTS) | < 20ms | FTS5 is well-optimized |
| Query latency (graph traversal, 3 hops) | < 50ms | Depends on fan-out |
| Blob storage | Up to 1GB | Size limited by device storage |
| Mutation throughput | 200+ triples/sec (individual), 10k+/sec (batched) | Per-transaction |

---

## 13. Implementation Task List

### Phase 1 — Core Schema & Basic CRUD

**Goal:** A working knowledge store that can create, read, update, and delete triples with Drift.

- [ ] Create `lib/knowledge/` directory structure
  ```
  lib/knowledge/
    store.dart                 # KnowledgeStore interface
    store_impl.dart            # KnowledgeStoreImpl (Drift-backed)
    query.dart                 # QueryBuilder
    mutation.dart              # MutationBuilder
    types/
      triple.dart              # Triple Freezed class
      blob.dart                # Blob Freezed class
      entity.dart              # Entity convenience class
      object_type.dart         # ObjectType enum
      ns.dart                  # NS namespace constants
    database/
      database.dart            # Drift database definition
      tables.dart              # Table definitions (triples, blobs)
  ```
- [ ] Define Drift `TriplesTable` and `BlobsTable` in `database/tables.dart`
- [ ] Define Drift database class in `database/database.dart`
- [ ] Implement `Triple` Freezed data class with JSON serialization
- [ ] Implement `Blob` Freezed data class
- [ ] Implement `ObjectType` enum
- [ ] Implement `NS` constants class (all namespace prefixes, URIs, helpers)
- [ ] Implement `KnowledgeStore` abstract interface
  - [ ] `query()` → `QueryBuilder`
  - [ ] `mutate()` → `Future<ChangeSet>`
  - [ ] `getBlobMeta()` / `readBlob()` / `storeBlob()`
  - [ ] `close()`
- [ ] Implement `QueryBuilder` with basic filters
  - [ ] `subject()`, `subjectPrefix()`, `predicate()`, `object()`, `objectType()`
  - [ ] `graph()`
  - [ ] `objectGreaterThan()`, `objectLessThan()`, `objectBetween()`, `objectIn()`
  - [ ] `orderBy()`, `limit()`, `offset()`
  - [ ] `get()`, `count()`, `getGroupedBySubject()`
- [ ] Implement `MutationBuilder`
  - [ ] `createEntity()` — generate UUID, add rdf:type + timestamps
  - [ ] `add()` — insert triple (no-op on duplicate)
  - [ ] `set()` — upsert triple
  - [ ] `remove()` — delete specific triple
  - [ ] `removeWhere()` — delete by pattern
  - [ ] `storeBlob()` — content-addressed blob storage
  - [ ] `removeBlob()` — delete unreferenced blob
- [ ] Implement `Entity.fromTriples()` convenience constructor
- [ ] Implement `Entity.get()`, `Entity.getAll()`, shorthand accessors
- [ ] Create Riverpod provider for `KnowledgeStore`
- [ ] Write unit tests for:
  - [ ] Triple creation, query, update, delete
  - [ ] QueryBuilder filter combinations
  - [ ] MutationBuilder transaction atomicity
  - [ ] Entity materialization from triples
  - [ ] Blob storage and retrieval
  - [ ] Unique constraint enforcement
  - [ ] NS.expand() and NS.compact()

### Phase 2 — FTS5, Change Events, Riverpod Integration

**Goal:** Full-text search, reactive change stream, and Riverpod providers for UI binding.

- [ ] Define FTS5 virtual table in Drift migration
- [ ] Implement FTS5 sync triggers (insert, update, delete)
- [ ] Add `fullText()` to `QueryBuilder` — translates to FTS5 MATCH
- [ ] Implement `KnowledgeChange` sealed class (added, removed, updated)
- [ ] Implement `ChangeSet` Freezed class
  - [ ] `added`, `removed`, `updated` convenience getters
  - [ ] `affectedSubjects` computation
- [ ] Wire mutation path to emit `ChangeSet` on broadcast `StreamController`
- [ ] Implement `KnowledgeStore.changes` stream
- [ ] Implement `watchSubject()` filtered stream
- [ ] Implement `watchPattern()` filtered stream
- [ ] Add `watch()` to `QueryBuilder` — returns `Stream<List<Triple>>`
- [ ] Create Riverpod providers:
  - [ ] `knowledgeStoreProvider` — singleton store instance
  - [ ] `knowledgeChangesProvider` — stream of all change sets
  - [ ] `entityProvider` — watch single entity by URI
  - [ ] `entitiesByTypeProvider` — watch all entities of a given type
  - [ ] `queryProvider` — generic query-watching provider
- [ ] Write unit tests for:
  - [ ] FTS5 search accuracy (prefix, phrase, boolean)
  - [ ] ChangeSet emission on each mutation type
  - [ ] Stream filtering (watchSubject, watchPattern)
  - [ ] Riverpod provider reactivity (mutation → provider rebuild)

### Phase 3 — Encryption & Blob Security

**Goal:** Per-triple and per-blob encryption with key management.

- [ ] Implement key derivation (Argon2id from passphrase)
- [ ] Implement platform keystore integration
  - [ ] Android Keystore
  - [ ] iOS Secure Enclave / Keychain
  - [ ] Desktop OS keychain
- [ ] Implement HKDF for deriving encryption sub-keys
- [ ] Implement AES-256-GCM encrypt/decrypt for triple object values
- [ ] Wire encryption into mutation path (encrypt on write if `encrypted=true`)
- [ ] Wire decryption into query path (decrypt on read if `encrypted=1`)
- [ ] Exclude encrypted triples from FTS5 indexing
- [ ] Implement blob encryption (AES-256-GCM for blob data)
- [ ] Implement key rotation
  - [ ] Re-encrypt all encrypted triples in a transaction
  - [ ] Re-encrypt all encrypted blobs in batches
  - [ ] Update keystore with new key
- [ ] Implement passphrase change flow
- [ ] Write unit tests for:
  - [ ] Encrypt/decrypt roundtrip
  - [ ] Encrypted triples excluded from FTS
  - [ ] Key rotation re-encrypts all data
  - [ ] Blob encryption roundtrip
  - [ ] Key derivation determinism (same passphrase → same key)

### Phase 4 — Import/Export & Named Graphs

**Goal:** Turtle, N-Triples, JSON-LD serialization. Full backup/restore. Named graph management.

- [ ] Implement Turtle parser (subset: prefixed names, typed literals, multi-value)
- [ ] Implement Turtle serializer (`exportTurtle()`)
- [ ] Implement N-Triples serializer (`exportNTriples()` as stream)
- [ ] Implement N-Triples parser
- [ ] Implement JSON-LD serializer (`exportJsonLd()`)
- [ ] Implement JSON-LD parser (using `@context` for prefix resolution)
- [ ] Implement selective export (by graph, by type, by subject list)
- [ ] Implement `importTurtle()`, `importNTriples()`, `importJsonLd()`
- [ ] Implement full SQLite backup (encrypted `.db` file)
- [ ] Implement backup restore with schema validation
- [ ] Implement graph metadata storage and querying
- [ ] Add graph-awareness to all `QueryBuilder` methods
- [ ] Add graph parameter to all `MutationBuilder` methods
- [ ] Write unit tests for:
  - [ ] Turtle roundtrip (export → parse → compare)
  - [ ] N-Triples roundtrip
  - [ ] JSON-LD roundtrip
  - [ ] Selective export filtering
  - [ ] Backup/restore integrity
  - [ ] Named graph isolation in queries
  - [ ] Graph metadata CRUD

### Phase 5 — Performance Optimization

**Goal:** Cache layer, batch operations, benchmarks, production readiness.

- [ ] Implement `TripleCache` (LRU) for entity lookups
- [ ] Implement query result caching with conservative invalidation
- [ ] Wire cache invalidation into `ChangeSet` emission path
- [ ] Implement `batchInsert()` with deferred FTS rebuild
- [ ] Implement cursor-based pagination in `QueryBuilder`
- [ ] Add `EXPLAIN QUERY PLAN` logging in debug mode
- [ ] Profile and optimize hot query paths
- [ ] Benchmark suite:
  - [ ] Insert throughput (individual vs. batch)
  - [ ] Query latency by pattern (subject, predicate, FTS, graph traversal)
  - [ ] Memory footprint at 10k, 50k, 100k triples
  - [ ] FTS5 search latency at scale
  - [ ] Cache hit rate under typical usage patterns
- [ ] Optimize index set based on benchmark results (add/remove indexes)
- [ ] Implement database vacuuming on schedule
- [ ] Implement WAL checkpoint management
- [ ] Add telemetry hooks for query performance monitoring
- [ ] Write integration tests:
  - [ ] 10,000 triple stress test (CRUD + query)
  - [ ] Concurrent read/write safety
  - [ ] Cache coherency under rapid mutations
  - [ ] Memory leak detection under sustained load
