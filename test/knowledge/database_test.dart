import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kabuk/knowledge/database.dart';

void main() {
  late KabukDatabase db;

  setUp(() async {
    db = KabukDatabase(NativeDatabase.memory());
    // Wait for beforeOpen triggers / FTS setup to complete
    // by performing a trivial query.
    await db.findTriples();
  });

  tearDown(() async {
    await db.close();
  });

  // ---------------------------------------------------------------------------
  // deleteTriple
  // ---------------------------------------------------------------------------

  group('deleteTriple', () {
    test('with object filters deletes only matching triple', () async {
      // Insert two triples for the same subject+predicate with different values.
      await db.insertTriple(
        TriplesCompanion.insert(
          subject: 'kabuk:Note/1',
          predicate: 'schema:name',
          objectType: 'string',
          objectString: const Value('Note A'),
        ),
      );
      await db.insertTriple(
        TriplesCompanion.insert(
          subject: 'kabuk:Note/1',
          predicate: 'schema:name',
          objectType: 'string',
          objectString: const Value('Note B'),
        ),
      );

      // Delete only "Note A".
      final deleted = await db.deleteTriple(
        subject: 'kabuk:Note/1',
        predicate: 'schema:name',
        objectString: 'Note A',
      );

      expect(deleted, 1);

      final remaining = await db.findTriples(subject: 'kabuk:Note/1');
      expect(remaining, hasLength(1));
      expect(remaining.first.objectString, 'Note B');
    });

    test('without object filters deletes all for subject+predicate', () async {
      await db.insertTriple(
        TriplesCompanion.insert(
          subject: 'kabuk:Note/2',
          predicate: 'schema:tag',
          objectType: 'string',
          objectString: const Value('tag-a'),
        ),
      );
      await db.insertTriple(
        TriplesCompanion.insert(
          subject: 'kabuk:Note/2',
          predicate: 'schema:tag',
          objectType: 'string',
          objectString: const Value('tag-b'),
        ),
      );

      final deleted = await db.deleteTriple(
        subject: 'kabuk:Note/2',
        predicate: 'schema:tag',
      );

      expect(deleted, 2);

      final remaining = await db.findTriples(subject: 'kabuk:Note/2');
      expect(remaining, isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  // findTriplesBySubjects
  // ---------------------------------------------------------------------------

  group('findTriplesBySubjects', () {
    test('returns triples for multiple subjects', () async {
      for (final subj in ['kabuk:A', 'kabuk:B', 'kabuk:C']) {
        await db.insertTriple(
          TriplesCompanion.insert(
            subject: subj,
            predicate: 'schema:name',
            objectType: 'string',
            objectString: Value('Name of $subj'),
          ),
        );
      }

      final results = await db.findTriplesBySubjects(['kabuk:A', 'kabuk:C']);

      expect(results, hasLength(2));
      final subjects = results.map((t) => t.subject).toSet();
      expect(subjects, containsAll(['kabuk:A', 'kabuk:C']));
    });

    test('returns empty for unknown subjects', () async {
      final results = await db.findTriplesBySubjects([
        'kabuk:Unknown1',
        'kabuk:Unknown2',
      ]);
      expect(results, isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  // Conversations
  // ---------------------------------------------------------------------------

  group('Conversations', () {
    test('insert and retrieve a conversation', () async {
      await db.upsertConversation(
        ConversationsCompanion.insert(
          id: 'conv-1',
          title: const Value('Test Chat'),
          agentName: const Value('notes'),
        ),
      );

      final conv = await db.getConversation('conv-1');

      expect(conv, isNotNull);
      expect(conv!.id, 'conv-1');
      expect(conv.title, 'Test Chat');
      expect(conv.agentName, 'notes');
    });

    test('delete conversation also deletes its messages', () async {
      await db.upsertConversation(
        ConversationsCompanion.insert(
          id: 'conv-2',
          title: const Value('Chat to Delete'),
        ),
      );
      await db.insertMessage(
        MessagesCompanion.insert(
          id: 'msg-1',
          conversationId: 'conv-2',
          role: 'user',
          content: 'Hello',
          timestamp: DateTime(2026, 1, 1),
        ),
      );
      await db.insertMessage(
        MessagesCompanion.insert(
          id: 'msg-2',
          conversationId: 'conv-2',
          role: 'agent',
          content: 'Hi there!',
          timestamp: DateTime(2026, 1, 1, 0, 0, 1),
        ),
      );

      await db.deleteConversation('conv-2');

      final conv = await db.getConversation('conv-2');
      expect(conv, isNull);

      final msgs = await db.getMessages('conv-2');
      expect(msgs, isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  // FTS: searchTriples
  // ---------------------------------------------------------------------------

  group('searchTriples (FTS)', () {
    test('finds matching content', () async {
      await db.insertTriple(
        TriplesCompanion.insert(
          subject: 'kabuk:Note/fts-1',
          predicate: 'schema:text',
          objectType: 'string',
          objectString: const Value('Flutter is an amazing framework'),
        ),
      );
      await db.insertTriple(
        TriplesCompanion.insert(
          subject: 'kabuk:Note/fts-2',
          predicate: 'schema:text',
          objectType: 'string',
          objectString: const Value('Dart programming language'),
        ),
      );

      // Rebuild FTS index so triggers are accounted for.
      await db.rebuildFtsIndex();

      final results = await db.searchTriples('Flutter');

      expect(results, hasLength(1));
      expect(results.first.subject, 'kabuk:Note/fts-1');
    });

    test('sanitizes user input (double quotes)', () async {
      await db.insertTriple(
        TriplesCompanion.insert(
          subject: 'kabuk:Note/fts-3',
          predicate: 'schema:text',
          objectType: 'string',
          objectString: const Value('Quoted "word" inside'),
        ),
      );

      await db.rebuildFtsIndex();

      // User input with double-quotes should not break FTS syntax.
      final results = await db.searchTriples('"word"');

      // The sanitizer wraps input in quotes after escaping, so it
      // should find the row containing the literal `word`.
      expect(results, isNotEmpty);
    });
  });
}
