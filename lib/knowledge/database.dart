/// Drift database definition for the Kabuk knowledge store.
///
/// Defines the SQLite schema for RDF triples, blob storage metadata,
/// and conversation history. The generated code is produced by
/// `build_runner` via `drift_dev`.
library;

import 'package:drift/drift.dart';

part 'database.g.dart';

/// Table storing RDF triples — the core data structure of the knowledge store.
///
/// Each row represents a single (subject, predicate, object) triple.
/// Objects are typed via [objectType] and stored in the corresponding
/// column ([objectUri], [objectString], [objectInt], [objectReal]).
class Triples extends Table {
  /// Auto-incrementing primary key.
  IntColumn get id => integer().autoIncrement()();

  /// The subject URI of the triple.
  TextColumn get subject => text()();

  /// The predicate URI of the triple.
  TextColumn get predicate => text()();

  /// The type of the object value.
  ///
  /// One of: `uri`, `string`, `integer`, `real`, `datetime`, `boolean`,
  /// `blobRef`.
  TextColumn get objectType => text()();

  /// Object value when [objectType] is `uri` or `blobRef`.
  TextColumn get objectUri => text().nullable()();

  /// Object value when [objectType] is `string`.
  TextColumn get objectString => text().nullable()();

  /// Object value when [objectType] is `integer`, `boolean`, or `datetime`.
  ///
  /// Booleans are stored as 0/1. DateTimes are stored as milliseconds
  /// since epoch.
  IntColumn get objectInt => integer().nullable()();

  /// Object value when [objectType] is `real`.
  RealColumn get objectReal => real().nullable()();

  /// The named graph this triple belongs to (optional).
  TextColumn get graph => text().withDefault(const Constant('default'))();

  /// Timestamp when this triple was created.
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  /// Timestamp when this triple was last updated.
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  List<Set<Column>> get uniqueKeys => [
    {
      subject,
      predicate,
      objectType,
      objectUri,
      objectString,
      objectInt,
      objectReal,
      graph,
    },
  ];
}

/// Table storing binary blobs referenced by triples via `blobRef`.
///
/// Blobs are content-addressed by their SHA-256 hash. Encryption is
/// applied transparently by the vault service before data reaches
/// this table.
class Blobs extends Table {
  /// SHA-256 content hash — the primary key.
  TextColumn get hash => text()();

  /// The binary data.
  BlobColumn get data => blob()();

  /// MIME type of the blob (e.g. `image/png`).
  TextColumn get mimeType => text().nullable()();

  /// Size in bytes.
  IntColumn get size => integer()();

  /// Timestamp when the blob was stored.
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {hash};
}

/// Table storing conversation messages for the chat system.
///
/// Each message belongs to a conversation identified by [conversationId].
/// Messages are ordered by [timestamp] within a conversation.
class Messages extends Table {
  /// Unique message identifier (UUID).
  TextColumn get id => text()();

  /// The conversation this message belongs to.
  TextColumn get conversationId => text()();

  /// Message role: `user`, `agent`, `system`, `tool_call`, `tool_result`.
  TextColumn get role => text()();

  /// The agent that produced this message (null for user messages).
  TextColumn get agentName => text().nullable()();

  /// Text content of the message.
  TextColumn get content => text()();

  /// JSON-encoded metadata (tool arguments, widget results, etc.).
  TextColumn get metadata => text().nullable()();

  /// When the message was created.
  DateTimeColumn get timestamp => dateTime()();

  /// Nostr event ID for messages sent/received via Nostr DMs.
  TextColumn get nostrEventId => text().nullable()();

  /// Delivery status: `sending`, `sent`, `delivered`, `failed`.
  TextColumn get status => text().withDefault(const Constant('sent'))();

  /// The message ID this is replying to (for threaded replies).
  TextColumn get replyToId => text().nullable()();

  /// Whether this message is pinned/starred in the conversation.
  BoolColumn get isPinned => boolean().withDefault(const Constant(false))();

  /// When the message expires and should be auto-deleted (disappearing messages).
  ///
  /// Stored as a UTC DateTime. `null` means the message never expires.
  DateTimeColumn get expiresAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Table storing NIP-25 reactions to messages.
///
/// Reactions are keyed by (messageId, pubkey) so a user can only react once
/// per message (the emoji can differ on an upsert).
class MessageReactions extends Table {
  /// Auto-incrementing primary key.
  IntColumn get id => integer().autoIncrement()();

  /// The local database message ID being reacted to.
  TextColumn get messageId => text()();

  /// The conversation this reaction belongs to.
  TextColumn get conversationId => text()();

  /// The reactor's Nostr public key (hex).
  TextColumn get pubkey => text()();

  /// The reaction emoji (NIP-25, default '+' for like, '-' for dislike).
  TextColumn get reaction => text().withDefault(const Constant('+'))();

  /// The Nostr event ID of the published kind-7 reaction event.
  TextColumn get nostrEventId => text().nullable()();

  /// When the reaction was created.
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  List<Set<Column>> get uniqueKeys => [
    {messageId, pubkey},
  ];
}

/// Table storing conversation metadata.
class Conversations extends Table {
  /// Unique conversation identifier (UUID).
  TextColumn get id => text()();

  /// Human-readable title for the conversation.
  TextColumn get title => text().withDefault(const Constant('New Chat'))();

  /// The primary agent handling this conversation.
  TextColumn get agentName => text().nullable()();

  /// Conversation type: `agent`, `nostr_dm`, `nostr_group`.
  TextColumn get type => text().withDefault(const Constant('agent'))();

  /// Nostr public key of the other party (for `nostr_dm` conversations).
  TextColumn get nostrPubkey => text().nullable()();

  /// Whether this conversation is pinned to the top.
  BoolColumn get isPinned => boolean().withDefault(const Constant(false))();

  /// Whether this conversation is archived (hidden from main list).
  BoolColumn get isArchived => boolean().withDefault(const Constant(false))();

  /// Whether notifications are muted for this conversation.
  BoolColumn get isMuted => boolean().withDefault(const Constant(false))();

  /// Number of unread messages.
  IntColumn get unreadCount => integer().withDefault(const Constant(0))();

  /// Preview text of the last message.
  TextColumn get lastMessage => text().nullable()();

  /// Timestamp of the last message (for sort ordering).
  DateTimeColumn get lastMessageAt => dateTime().nullable()();

  /// When the conversation was created.
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  /// When the conversation was last updated.
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

/// The Drift database for the Kabuk knowledge store.
///
/// This is the single SQLite database backing all persistent data in
/// Kabuk: RDF triples, blobs, conversations, and messages.
@DriftDatabase(
  tables: [Triples, Blobs, Messages, Conversations, MessageReactions],
)
class KabukDatabase extends _$KabukDatabase {
  /// Creates a [KabukDatabase] with the provided [QueryExecutor].
  KabukDatabase(super.e);

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();

      // Create indices for common query patterns.
      await customStatement(
        'CREATE INDEX idx_triples_subject ON triples(subject)',
      );
      await customStatement(
        'CREATE INDEX idx_triples_predicate ON triples(predicate)',
      );
      await customStatement(
        'CREATE INDEX idx_triples_object_uri ON triples(object_uri)',
      );
      await customStatement(
        'CREATE INDEX idx_triples_subject_predicate ON triples(subject, predicate)',
      );
      await customStatement('CREATE INDEX idx_triples_graph ON triples(graph)');
      await customStatement(
        'CREATE INDEX idx_messages_conversation ON messages(conversation_id, timestamp)',
      );
      await customStatement(
        'CREATE INDEX idx_conversations_updated ON conversations(updated_at DESC)',
      );
      await customStatement(
        'CREATE INDEX idx_conversations_type ON conversations(type)',
      );
      await customStatement(
        'CREATE INDEX idx_conversations_nostr_pubkey ON conversations(nostr_pubkey)',
      );
      await customStatement(
        'CREATE INDEX idx_conversations_last_message_at ON conversations(last_message_at DESC)',
      );
    },
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        // v2: Add Nostr DM and chat management columns.
        await customStatement(
          'ALTER TABLE messages ADD COLUMN nostr_event_id TEXT',
        );
        await customStatement(
          "ALTER TABLE messages ADD COLUMN status TEXT NOT NULL DEFAULT 'sent'",
        );
        await customStatement(
          'ALTER TABLE messages ADD COLUMN reply_to_id TEXT',
        );
        await customStatement(
          "ALTER TABLE conversations ADD COLUMN type TEXT NOT NULL DEFAULT 'agent'",
        );
        await customStatement(
          'ALTER TABLE conversations ADD COLUMN nostr_pubkey TEXT',
        );
        await customStatement(
          'ALTER TABLE conversations ADD COLUMN is_pinned INTEGER NOT NULL DEFAULT 0',
        );
        await customStatement(
          'ALTER TABLE conversations ADD COLUMN is_archived INTEGER NOT NULL DEFAULT 0',
        );
        await customStatement(
          'ALTER TABLE conversations ADD COLUMN is_muted INTEGER NOT NULL DEFAULT 0',
        );
        await customStatement(
          'ALTER TABLE conversations ADD COLUMN unread_count INTEGER NOT NULL DEFAULT 0',
        );
        await customStatement(
          'ALTER TABLE conversations ADD COLUMN last_message TEXT',
        );
        await customStatement(
          'ALTER TABLE conversations ADD COLUMN last_message_at INTEGER',
        );
        // Add new indices.
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_conversations_type ON conversations(type)',
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_conversations_nostr_pubkey ON conversations(nostr_pubkey)',
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_conversations_last_message_at ON conversations(last_message_at DESC)',
        );
      }
      if (from < 3) {
        // v3: Add pinned/expiry to messages, and reactions table.
        await customStatement(
          'ALTER TABLE messages ADD COLUMN is_pinned INTEGER NOT NULL DEFAULT 0',
        );
        await customStatement(
          'ALTER TABLE messages ADD COLUMN expires_at INTEGER',
        );
        await customStatement(
          'CREATE TABLE IF NOT EXISTS message_reactions ('
          'id INTEGER PRIMARY KEY AUTOINCREMENT, '
          'message_id TEXT NOT NULL, '
          'conversation_id TEXT NOT NULL, '
          'pubkey TEXT NOT NULL, '
          'reaction TEXT NOT NULL DEFAULT "+", '
          'nostr_event_id TEXT, '
          'created_at INTEGER NOT NULL, '
          'UNIQUE(message_id, pubkey)'
          ')',
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_reactions_message_id ON message_reactions(message_id)',
        );
      }
    },
    beforeOpen: (details) async {
      // Create FTS5 virtual table for full-text search.
      await customStatement(
        'CREATE VIRTUAL TABLE IF NOT EXISTS triples_fts USING fts5('
        'subject, predicate, object_string, '
        "content='triples', content_rowid='rowid'"
        ')',
      );

      // Triggers to keep the FTS5 index in sync with the triples table.
      await customStatement(
        'CREATE TRIGGER IF NOT EXISTS triples_ai AFTER INSERT ON triples BEGIN '
        'INSERT INTO triples_fts(rowid, subject, predicate, object_string) '
        'VALUES (new.rowid, new.subject, new.predicate, new.object_string); '
        'END',
      );
      await customStatement(
        'CREATE TRIGGER IF NOT EXISTS triples_ad AFTER DELETE ON triples BEGIN '
        'INSERT INTO triples_fts(triples_fts, rowid, subject, predicate, object_string) '
        "VALUES ('delete', old.rowid, old.subject, old.predicate, old.object_string); "
        'END',
      );
      await customStatement(
        'CREATE TRIGGER IF NOT EXISTS triples_au AFTER UPDATE ON triples BEGIN '
        'INSERT INTO triples_fts(triples_fts, rowid, subject, predicate, object_string) '
        "VALUES ('delete', old.rowid, old.subject, old.predicate, old.object_string); "
        'INSERT INTO triples_fts(rowid, subject, predicate, object_string) '
        'VALUES (new.rowid, new.subject, new.predicate, new.object_string); '
        'END',
      );

      // Rebuild FTS index on first creation or schema upgrade so
      // existing triples are indexed.
      if (details.wasCreated || details.hadUpgrade) {
        await customStatement(
          "INSERT INTO triples_fts(triples_fts) VALUES('rebuild')",
        );
      }
    },
  );

  // ---------------------------------------------------------------------------
  // Triple CRUD
  // ---------------------------------------------------------------------------

  /// Insert a triple and return its row ID.
  Future<int> insertTriple(TriplesCompanion triple) =>
      into(triples).insert(triple, mode: InsertMode.insertOrIgnore);

  /// Delete a specific triple by matching its fields.
  Future<int> deleteTriple({
    required String subject,
    required String predicate,
    String? objectUri,
    String? objectString,
    int? objectInt,
    double? objectReal,
    String? objectType,
  }) {
    final q = delete(triples)
      ..where((t) {
        var expr = t.subject.equals(subject) & t.predicate.equals(predicate);
        if (objectType != null) expr = expr & t.objectType.equals(objectType);
        if (objectUri != null) expr = expr & t.objectUri.equals(objectUri);
        if (objectString != null) {
          expr = expr & t.objectString.equals(objectString);
        }
        if (objectInt != null) expr = expr & t.objectInt.equals(objectInt);
        if (objectReal != null) expr = expr & t.objectReal.equals(objectReal);
        return expr;
      });
    return q.go();
  }

  /// Delete all triples with the given [subject].
  Future<int> deleteEntity(String subject) {
    return (delete(triples)..where((t) => t.subject.equals(subject))).go();
  }

  /// Find all triples matching the given criteria.
  Future<List<Triple>> findTriples({
    String? subject,
    String? predicate,
    String? objectUri,
    String? graph,
    int? limit,
    int? offset,
  }) {
    final q = select(triples);
    q.where((t) {
      Expression<bool> expr = const Constant(true);
      if (subject != null) expr = expr & t.subject.equals(subject);
      if (predicate != null) expr = expr & t.predicate.equals(predicate);
      if (objectUri != null) expr = expr & t.objectUri.equals(objectUri);
      if (graph != null) expr = expr & t.graph.equals(graph);
      return expr;
    });
    if (limit != null) q.limit(limit, offset: offset);
    return q.get();
  }

  /// Fetch all triples for a list of subjects in one query.
  Future<List<Triple>> findTriplesBySubjects(List<String> subjects) {
    return (select(triples)..where((t) => t.subject.isIn(subjects))).get();
  }

  /// Watch triples matching the given criteria reactively.
  Stream<List<Triple>> watchTriples({
    String? subject,
    String? predicate,
    String? objectUri,
    String? graph,
  }) {
    final q = select(triples);
    q.where((t) {
      Expression<bool> expr = const Constant(true);
      if (subject != null) expr = expr & t.subject.equals(subject);
      if (predicate != null) expr = expr & t.predicate.equals(predicate);
      if (objectUri != null) expr = expr & t.objectUri.equals(objectUri);
      if (graph != null) expr = expr & t.graph.equals(graph);
      return expr;
    });
    return q.watch();
  }

  /// Update all triples for a (subject, predicate) pair with a new value.
  Future<int> updateTripleObject({
    required String subject,
    required String predicate,
    required TriplesCompanion values,
  }) {
    return (update(triples)..where(
          (t) => t.subject.equals(subject) & t.predicate.equals(predicate),
        ))
        .write(values);
  }

  // ---------------------------------------------------------------------------
  // Blob CRUD
  // ---------------------------------------------------------------------------

  /// Store a blob, returning whether a new row was inserted.
  Future<int> storeBlob(BlobsCompanion blob) =>
      into(blobs).insert(blob, mode: InsertMode.insertOrReplace);

  /// Retrieve a blob by its hash.
  Future<Blob?> getBlob(String hash) =>
      (select(blobs)..where((b) => b.hash.equals(hash))).getSingleOrNull();

  /// Delete a blob by its hash.
  Future<int> deleteBlob(String hash) =>
      (delete(blobs)..where((b) => b.hash.equals(hash))).go();

  // ---------------------------------------------------------------------------
  // Conversation CRUD
  // ---------------------------------------------------------------------------

  /// List all conversations, most recently updated first.
  Future<List<Conversation>> listConversations({int? limit, int? offset}) {
    final q = select(conversations)
      ..orderBy([(c) => OrderingTerm.desc(c.updatedAt)]);
    if (limit != null) q.limit(limit, offset: offset);
    return q.get();
  }

  /// Watch all conversations reactively.
  Stream<List<Conversation>> watchConversations() {
    return (select(
      conversations,
    )..orderBy([(c) => OrderingTerm.desc(c.updatedAt)])).watch();
  }

  /// Watch non-archived conversations reactively, sorted by last message.
  Stream<List<Conversation>> watchActiveConversations() {
    return (select(conversations)
          ..where((c) => c.isArchived.equals(false))
          ..orderBy([
            (c) => OrderingTerm.desc(c.isPinned),
            (c) => OrderingTerm.desc(c.lastMessageAt),
            (c) => OrderingTerm.desc(c.updatedAt),
          ]))
        .watch();
  }

  /// Find a Nostr DM conversation by the other party's pubkey.
  Future<Conversation?> findNostrDmConversation(String pubkey) {
    return (select(conversations)..where(
          (c) => c.type.equals('nostr_dm') & c.nostrPubkey.equals(pubkey),
        ))
        .getSingleOrNull();
  }

  /// Get a single conversation by [id].
  Future<Conversation?> getConversation(String id) =>
      (select(conversations)..where((c) => c.id.equals(id))).getSingleOrNull();

  /// Insert or update a conversation.
  Future<int> upsertConversation(ConversationsCompanion conversation) => into(
    conversations,
  ).insert(conversation, mode: InsertMode.insertOrReplace);

  /// Update only the preview fields of an existing conversation
  /// (`lastMessage`, `lastMessageAt`, `updatedAt`) without touching any
  /// other columns such as `type`, `title`, or `nostrPubkey`.
  ///
  /// Prefer this over [upsertConversation] when you only want to update
  /// the preview after receiving a new message — [upsertConversation] uses
  /// `INSERT OR REPLACE` which would delete and re-insert the row, clearing
  /// all unspecified columns to their defaults.
  Future<void> updateConversationPreview(
    String conversationId, {
    required String lastMessage,
    required DateTime lastMessageAt,
  }) async {
    await (update(
      conversations,
    )..where((c) => c.id.equals(conversationId))).write(
      ConversationsCompanion(
        lastMessage: Value(lastMessage),
        lastMessageAt: Value(lastMessageAt),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Repairs Nostr DM conversations whose `type` or `nostrPubkey` fields
  /// were cleared by a previous `INSERT OR REPLACE` preview-update bug.
  ///
  /// Scans for conversations whose ID starts with `nostr_dm_` but where
  /// `type` is null, and restores the `type` and `nostrPubkey` values from
  /// the conversation ID.  Safe to call on every startup — it's a no-op
  /// when there is nothing to repair.
  Future<void> repairCorruptedNostrDmConversations() async {
    final rows = await (select(
      conversations,
    )..where((c) => c.id.like('nostr_dm_%') & c.type.isNull())).get();

    for (final row in rows) {
      final peerPubkey = row.id.replaceFirst('nostr_dm_', '');
      await (update(conversations)..where((c) => c.id.equals(row.id))).write(
        ConversationsCompanion(
          type: const Value('nostr_dm'),
          nostrPubkey: Value(peerPubkey),
          // Restore a minimal title if it was also wiped.
          title: row.title.isNotEmpty
              ? Value(row.title)
              : Value('${peerPubkey.substring(0, 8)}...'),
        ),
      );
    }
  }

  /// Delete a conversation and all its messages.
  Future<void> deleteConversation(String id) async {
    await (delete(messages)..where((m) => m.conversationId.equals(id))).go();
    await (delete(conversations)..where((c) => c.id.equals(id))).go();
  }

  // ---------------------------------------------------------------------------
  // Message CRUD
  // ---------------------------------------------------------------------------

  /// Get messages for a conversation, ordered by timestamp.
  Future<List<Message>> getMessages(String conversationId, {int? limit}) {
    final q = select(messages)
      ..where((m) => m.conversationId.equals(conversationId))
      ..orderBy([(m) => OrderingTerm.asc(m.timestamp)]);
    if (limit != null) q.limit(limit);
    return q.get();
  }

  /// Watch messages for a conversation reactively.
  Stream<List<Message>> watchMessages(String conversationId) {
    return (select(messages)
          ..where((m) => m.conversationId.equals(conversationId))
          ..orderBy([(m) => OrderingTerm.asc(m.timestamp)]))
        .watch();
  }

  /// Insert a message.
  Future<int> insertMessage(MessagesCompanion message) =>
      into(messages).insert(message);

  /// Update a message's delivery status.
  Future<void> updateMessageStatus(String messageId, String status) async {
    await (update(messages)..where((m) => m.id.equals(messageId))).write(
      MessagesCompanion(status: Value(status)),
    );
  }

  /// Retrieve a single message by its ID.
  Future<Message?> getMessageById(String id) =>
      (select(messages)..where((m) => m.id.equals(id))).getSingleOrNull();

  /// Returns the Unix timestamp (seconds) of the newest message across all
  /// Nostr DM conversations, or null if no messages exist. Used to compute
  /// the `since` filter for catch-up subscriptions (M2).
  Future<int?> getNewestNostrDmTimestamp() async {
    final rows = await customSelect(
      'SELECT MAX(strftime(\'%s\', timestamp)) AS ts '
      'FROM messages m '
      'INNER JOIN conversations c ON c.id = m.conversation_id '
      'WHERE c.type = \'nostr_dm\'',
      readsFrom: {messages, conversations},
    ).get();
    final val = rows.firstOrNull?.data['ts'];
    if (val == null) return null;
    return int.tryParse(val.toString());
  }

  /// Delete a single message from the database by its ID.
  Future<void> deleteMessage(String id) async {
    await (delete(messages)..where((m) => m.id.equals(id))).go();
  }

  /// Full-text search across message content within a conversation.
  ///
  /// Case-insensitive LIKE match. Returns matches ordered by timestamp.
  Future<List<Message>> searchMessages(
    String conversationId,
    String query,
  ) async {
    final lower = '%${query.toLowerCase()}%';
    return (select(messages)
          ..where(
            (m) =>
                m.conversationId.equals(conversationId) &
                m.content.lower().like(lower),
          )
          ..orderBy([(m) => OrderingTerm.asc(m.timestamp)]))
        .get();
  }

  /// Pin or unpin a message.
  Future<void> pinMessage(String messageId, {bool pinned = true}) async {
    await (update(messages)..where((m) => m.id.equals(messageId))).write(
      MessagesCompanion(isPinned: Value(pinned)),
    );
  }

  /// Watch all pinned messages in a conversation reactively.
  Stream<List<Message>> watchPinnedMessages(String conversationId) {
    return (select(messages)
          ..where(
            (m) =>
                m.conversationId.equals(conversationId) &
                m.isPinned.equals(true),
          )
          ..orderBy([(m) => OrderingTerm.desc(m.timestamp)]))
        .watch();
  }

  /// Set or clear the expiry time for a message (disappearing messages).
  Future<void> setMessageExpiry(String messageId, DateTime? expiresAt) async {
    await (update(messages)..where((m) => m.id.equals(messageId))).write(
      MessagesCompanion(expiresAt: Value(expiresAt)),
    );
  }

  /// Delete all messages whose [expiresAt] is in the past.
  Future<void> purgeExpiredMessages() async {
    final now = DateTime.now();
    await (delete(
      messages,
    )..where((m) => m.expiresAt.isSmallerOrEqualValue(now))).go();
  }

  // ---------------------------------------------------------------------------
  // Message Reactions CRUD
  // ---------------------------------------------------------------------------

  /// Insert or replace a reaction (upserts on the messageId+pubkey unique key).
  Future<void> upsertReaction(MessageReactionsCompanion reaction) async {
    await into(
      messageReactions,
    ).insert(reaction, mode: InsertMode.insertOrReplace);
  }

  /// Remove a reaction by (messageId, pubkey).
  Future<void> deleteReaction({
    required String messageId,
    required String pubkey,
  }) async {
    await (delete(messageReactions)..where(
          (r) => r.messageId.equals(messageId) & r.pubkey.equals(pubkey),
        ))
        .go();
  }

  /// Watch all reactions for a specific message reactively.
  Stream<List<MessageReaction>> watchReactions(String messageId) {
    return (select(messageReactions)
          ..where((r) => r.messageId.equals(messageId))
          ..orderBy([(r) => OrderingTerm.asc(r.createdAt)]))
        .watch();
  }

  /// Fetch reactions for a message as a one-shot query.
  Future<List<MessageReaction>> getReactions(String messageId) {
    return (select(
      messageReactions,
    )..where((r) => r.messageId.equals(messageId))).get();
  }

  /// Increment the unread count for a conversation by 1.
  Future<void> incrementUnreadCount(String conversationId) async {
    await customStatement(
      'UPDATE conversations SET unread_count = unread_count + 1 '
      'WHERE id = ?',
      [Variable.withString(conversationId)],
    );
  }

  /// Reset the unread count for a conversation to 0.
  Future<void> resetUnreadCount(String conversationId) async {
    await (update(conversations)..where((c) => c.id.equals(conversationId)))
        .write(const ConversationsCompanion(unreadCount: Value(0)));
  }

  /// Full-text search across triple subjects, predicates, and string
  /// objects using the FTS5 index.
  ///
  /// Results are ordered by relevance (FTS5 rank). The [query] is wrapped
  /// in double-quotes for literal matching to prevent FTS5 syntax errors
  /// from user input.
  Future<List<Triple>> searchTriples(String query, {int limit = 50}) async {
    // Sanitize: escape double-quotes so user input can't break FTS5 syntax.
    final sanitized = query.replaceAll('"', '""');
    final rows = await customSelect(
      'SELECT t.* FROM triples t '
      'INNER JOIN triples_fts ON triples_fts.rowid = t.rowid '
      'WHERE triples_fts MATCH ? '
      'ORDER BY rank '
      'LIMIT ?',
      variables: [Variable.withString('"$sanitized"'), Variable.withInt(limit)],
      readsFrom: {triples},
    ).get();
    return rows.map((row) => triples.map(row.data)).toList();
  }

  /// Rebuild the FTS5 full-text search index from scratch.
  ///
  /// This re-indexes every row in the triples table. Useful after bulk
  /// imports or if the index becomes out of sync.
  Future<void> rebuildFtsIndex() async {
    await customStatement(
      "INSERT INTO triples_fts(triples_fts) VALUES('rebuild')",
    );
  }
}
