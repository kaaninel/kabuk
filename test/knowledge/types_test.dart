import 'package:flutter_test/flutter_test.dart';
import 'package:kabuk/config/namespaces.dart';
import 'package:kabuk/knowledge/triple.dart';
import 'package:kabuk/knowledge/types/event.dart';
import 'package:kabuk/knowledge/types/media.dart';
import 'package:kabuk/knowledge/types/note.dart';
import 'package:kabuk/knowledge/types/person.dart';

void main() {
  // ---------------------------------------------------------------------------
  // NoteData
  // ---------------------------------------------------------------------------

  group('NoteData', () {
    test('fromTriples() extracts name', () {
      final triples = [
        const Triple(
          subject: 'kabuk:Note/1',
          predicate: NS.schemaName,
          objectValue: 'My Note',
          objectType: ObjectType.string,
        ),
      ];

      final note = NoteData.fromTriples('kabuk:Note/1', triples);

      expect(note.uri, 'kabuk:Note/1');
      expect(note.name, 'My Note');
    });

    test('fromTriples() extracts text', () {
      final triples = [
        const Triple(
          subject: 'kabuk:Note/1',
          predicate: NS.schemaText,
          objectValue: 'Body text here',
          objectType: ObjectType.string,
        ),
      ];

      final note = NoteData.fromTriples('kabuk:Note/1', triples);
      expect(note.text, 'Body text here');
    });

    test('fromTriples() extracts dateCreated', () {
      final triples = [
        const Triple(
          subject: 'kabuk:Note/1',
          predicate: NS.schemaDateCreated,
          objectValue: '2026-02-25T12:00:00.000Z',
          objectType: ObjectType.string,
        ),
      ];

      final note = NoteData.fromTriples('kabuk:Note/1', triples);
      expect(note.dateCreated, isNotNull);
      expect(note.dateCreated!.year, 2026);
      expect(note.dateCreated!.month, 2);
    });

    test('fromTriples() extracts dateModified', () {
      final triples = [
        const Triple(
          subject: 'kabuk:Note/1',
          predicate: NS.schemaDateModified,
          objectValue: '2026-02-25T13:00:00.000Z',
          objectType: ObjectType.string,
        ),
      ];

      final note = NoteData.fromTriples('kabuk:Note/1', triples);
      expect(note.dateModified, isNotNull);
      expect(note.dateModified!.hour, 13);
    });

    test('fromTriples() extracts tags', () {
      final triples = [
        const Triple(
          subject: 'kabuk:Note/1',
          predicate: NS.kabukTag,
          objectValue: 'important',
          objectType: ObjectType.string,
        ),
        const Triple(
          subject: 'kabuk:Note/1',
          predicate: NS.kabukTag,
          objectValue: 'work',
          objectType: ObjectType.string,
        ),
      ];

      final note = NoteData.fromTriples('kabuk:Note/1', triples);
      expect(note.tags, containsAll(['important', 'work']));
      expect(note.tags.length, 2);
    });

    test('fromTriples() handles missing fields gracefully', () {
      final note = NoteData.fromTriples('kabuk:Note/1', []);
      expect(note.uri, 'kabuk:Note/1');
      expect(note.name, isNull);
      expect(note.text, isNull);
      expect(note.dateCreated, isNull);
      expect(note.dateModified, isNull);
      expect(note.tags, isEmpty);
    });

    test('fromTriples() handles invalid date gracefully', () {
      final triples = [
        const Triple(
          subject: 'kabuk:Note/1',
          predicate: NS.schemaDateCreated,
          objectValue: 'not-a-date',
          objectType: ObjectType.string,
        ),
      ];

      final note = NoteData.fromTriples('kabuk:Note/1', triples);
      expect(note.dateCreated, isNull);
    });

    test('fromTriples() ignores unknown predicates', () {
      final triples = [
        const Triple(
          subject: 'kabuk:Note/1',
          predicate: NS.schemaName,
          objectValue: 'Valid',
          objectType: ObjectType.string,
        ),
        const Triple(
          subject: 'kabuk:Note/1',
          predicate: 'https://unknown.org/predicate',
          objectValue: 'Ignored',
          objectType: ObjectType.string,
        ),
      ];

      final note = NoteData.fromTriples('kabuk:Note/1', triples);
      expect(note.name, 'Valid');
    });

    test('roundtrip: all fields present', () {
      final triples = [
        const Triple(
          subject: 'kabuk:Note/rt',
          predicate: NS.schemaName,
          objectValue: 'Roundtrip',
          objectType: ObjectType.string,
        ),
        const Triple(
          subject: 'kabuk:Note/rt',
          predicate: NS.schemaText,
          objectValue: 'Body',
          objectType: ObjectType.string,
        ),
        const Triple(
          subject: 'kabuk:Note/rt',
          predicate: NS.schemaDateCreated,
          objectValue: '2026-01-01T00:00:00.000Z',
          objectType: ObjectType.string,
        ),
        const Triple(
          subject: 'kabuk:Note/rt',
          predicate: NS.schemaDateModified,
          objectValue: '2026-02-01T00:00:00.000Z',
          objectType: ObjectType.string,
        ),
        const Triple(
          subject: 'kabuk:Note/rt',
          predicate: NS.kabukTag,
          objectValue: 'tag1',
          objectType: ObjectType.string,
        ),
      ];

      final note = NoteData.fromTriples('kabuk:Note/rt', triples);
      expect(note.uri, 'kabuk:Note/rt');
      expect(note.name, 'Roundtrip');
      expect(note.text, 'Body');
      expect(note.dateCreated, DateTime.utc(2026, 1, 1));
      expect(note.dateModified, DateTime.utc(2026, 2, 1));
      expect(note.tags, ['tag1']);
    });
  });

  // ---------------------------------------------------------------------------
  // PersonData
  // ---------------------------------------------------------------------------

  group('PersonData', () {
    test('fromTriples() extracts name', () {
      final triples = [
        const Triple(
          subject: 'kabuk:Person/1',
          predicate: NS.schemaName,
          objectValue: 'Alice Smith',
          objectType: ObjectType.string,
        ),
      ];

      final person = PersonData.fromTriples('kabuk:Person/1', triples);
      expect(person.name, 'Alice Smith');
    });

    test('fromTriples() extracts givenName and familyName', () {
      final triples = [
        const Triple(
          subject: 'kabuk:Person/1',
          predicate: NS.schemaGivenName,
          objectValue: 'Alice',
          objectType: ObjectType.string,
        ),
        const Triple(
          subject: 'kabuk:Person/1',
          predicate: NS.schemaFamilyName,
          objectValue: 'Smith',
          objectType: ObjectType.string,
        ),
      ];

      final person = PersonData.fromTriples('kabuk:Person/1', triples);
      expect(person.givenName, 'Alice');
      expect(person.familyName, 'Smith');
    });

    test('fromTriples() extracts email and telephone', () {
      final triples = [
        const Triple(
          subject: 'kabuk:Person/1',
          predicate: NS.schemaEmail,
          objectValue: 'alice@example.com',
          objectType: ObjectType.string,
        ),
        const Triple(
          subject: 'kabuk:Person/1',
          predicate: NS.schemaTelephone,
          objectValue: '+1-555-0100',
          objectType: ObjectType.string,
        ),
      ];

      final person = PersonData.fromTriples('kabuk:Person/1', triples);
      expect(person.email, 'alice@example.com');
      expect(person.telephone, '+1-555-0100');
    });

    test('fromTriples() extracts description', () {
      final triples = [
        const Triple(
          subject: 'kabuk:Person/1',
          predicate: NS.schemaDescription,
          objectValue: 'A test person',
          objectType: ObjectType.string,
        ),
      ];

      final person = PersonData.fromTriples('kabuk:Person/1', triples);
      expect(person.description, 'A test person');
    });

    test('fromTriples() handles missing fields gracefully', () {
      final person = PersonData.fromTriples('kabuk:Person/1', []);
      expect(person.uri, 'kabuk:Person/1');
      expect(person.name, isNull);
      expect(person.givenName, isNull);
      expect(person.familyName, isNull);
      expect(person.email, isNull);
      expect(person.telephone, isNull);
      expect(person.description, isNull);
    });

    test('roundtrip: all fields present', () {
      final triples = [
        const Triple(
          subject: 'kabuk:Person/rt',
          predicate: NS.schemaName,
          objectValue: 'Bob Jones',
          objectType: ObjectType.string,
        ),
        const Triple(
          subject: 'kabuk:Person/rt',
          predicate: NS.schemaGivenName,
          objectValue: 'Bob',
          objectType: ObjectType.string,
        ),
        const Triple(
          subject: 'kabuk:Person/rt',
          predicate: NS.schemaFamilyName,
          objectValue: 'Jones',
          objectType: ObjectType.string,
        ),
        const Triple(
          subject: 'kabuk:Person/rt',
          predicate: NS.schemaEmail,
          objectValue: 'bob@example.com',
          objectType: ObjectType.string,
        ),
        const Triple(
          subject: 'kabuk:Person/rt',
          predicate: NS.schemaTelephone,
          objectValue: '+1-555-0200',
          objectType: ObjectType.string,
        ),
        const Triple(
          subject: 'kabuk:Person/rt',
          predicate: NS.schemaDescription,
          objectValue: 'Works at Acme',
          objectType: ObjectType.string,
        ),
      ];

      final person = PersonData.fromTriples('kabuk:Person/rt', triples);
      expect(person.uri, 'kabuk:Person/rt');
      expect(person.name, 'Bob Jones');
      expect(person.givenName, 'Bob');
      expect(person.familyName, 'Jones');
      expect(person.email, 'bob@example.com');
      expect(person.telephone, '+1-555-0200');
      expect(person.description, 'Works at Acme');
    });
  });

  // ---------------------------------------------------------------------------
  // EventData
  // ---------------------------------------------------------------------------

  group('EventData', () {
    test('fromTriples() extracts name', () {
      final triples = [
        const Triple(
          subject: 'kabuk:Event/1',
          predicate: NS.schemaName,
          objectValue: 'Team Meeting',
          objectType: ObjectType.string,
        ),
      ];

      final event = EventData.fromTriples('kabuk:Event/1', triples);
      expect(event.name, 'Team Meeting');
    });

    test('fromTriples() extracts startDate and endDate', () {
      final triples = [
        const Triple(
          subject: 'kabuk:Event/1',
          predicate: NS.schemaStartDate,
          objectValue: '2026-03-01T09:00:00.000Z',
          objectType: ObjectType.string,
        ),
        const Triple(
          subject: 'kabuk:Event/1',
          predicate: NS.schemaEndDate,
          objectValue: '2026-03-01T10:00:00.000Z',
          objectType: ObjectType.string,
        ),
      ];

      final event = EventData.fromTriples('kabuk:Event/1', triples);
      expect(event.startDate, isNotNull);
      expect(event.startDate!.month, 3);
      expect(event.endDate, isNotNull);
      expect(event.endDate!.hour, 10);
    });

    test('fromTriples() extracts location', () {
      final triples = [
        const Triple(
          subject: 'kabuk:Event/1',
          predicate: NS.schemaLocation,
          objectValue: 'Room 42',
          objectType: ObjectType.string,
        ),
      ];

      final event = EventData.fromTriples('kabuk:Event/1', triples);
      expect(event.location, 'Room 42');
    });

    test('fromTriples() extracts description', () {
      final triples = [
        const Triple(
          subject: 'kabuk:Event/1',
          predicate: NS.schemaDescription,
          objectValue: 'Weekly sync',
          objectType: ObjectType.string,
        ),
      ];

      final event = EventData.fromTriples('kabuk:Event/1', triples);
      expect(event.description, 'Weekly sync');
    });

    test('fromTriples() extracts organizer', () {
      final triples = [
        const Triple(
          subject: 'kabuk:Event/1',
          predicate: NS.schemaOrganizer,
          objectValue: 'kabuk:Person/alice',
          objectType: ObjectType.string,
        ),
      ];

      final event = EventData.fromTriples('kabuk:Event/1', triples);
      expect(event.organizer, 'kabuk:Person/alice');
    });

    test('fromTriples() extracts reminder', () {
      final triples = [
        const Triple(
          subject: 'kabuk:Event/1',
          predicate: NS.kabukReminder,
          objectValue: '2026-02-28T08:00:00.000Z',
          objectType: ObjectType.string,
        ),
      ];

      final event = EventData.fromTriples('kabuk:Event/1', triples);
      expect(event.reminder, isNotNull);
      expect(event.reminder!.day, 28);
    });

    test('fromTriples() handles missing fields gracefully', () {
      final event = EventData.fromTriples('kabuk:Event/1', []);
      expect(event.uri, 'kabuk:Event/1');
      expect(event.name, isNull);
      expect(event.startDate, isNull);
      expect(event.endDate, isNull);
      expect(event.location, isNull);
      expect(event.description, isNull);
      expect(event.organizer, isNull);
      expect(event.reminder, isNull);
    });

    test('fromTriples() handles invalid date gracefully', () {
      final triples = [
        const Triple(
          subject: 'kabuk:Event/1',
          predicate: NS.schemaStartDate,
          objectValue: 'invalid',
          objectType: ObjectType.string,
        ),
      ];

      final event = EventData.fromTriples('kabuk:Event/1', triples);
      expect(event.startDate, isNull);
    });

    test('roundtrip: all fields present', () {
      final triples = [
        const Triple(
          subject: 'kabuk:Event/rt',
          predicate: NS.schemaName,
          objectValue: 'Conference',
          objectType: ObjectType.string,
        ),
        const Triple(
          subject: 'kabuk:Event/rt',
          predicate: NS.schemaStartDate,
          objectValue: '2026-06-15T09:00:00.000Z',
          objectType: ObjectType.string,
        ),
        const Triple(
          subject: 'kabuk:Event/rt',
          predicate: NS.schemaEndDate,
          objectValue: '2026-06-15T17:00:00.000Z',
          objectType: ObjectType.string,
        ),
        const Triple(
          subject: 'kabuk:Event/rt',
          predicate: NS.schemaLocation,
          objectValue: 'Convention Center',
          objectType: ObjectType.string,
        ),
        const Triple(
          subject: 'kabuk:Event/rt',
          predicate: NS.schemaDescription,
          objectValue: 'Annual tech conf',
          objectType: ObjectType.string,
        ),
        const Triple(
          subject: 'kabuk:Event/rt',
          predicate: NS.schemaOrganizer,
          objectValue: 'kabuk:Person/organizer',
          objectType: ObjectType.string,
        ),
        const Triple(
          subject: 'kabuk:Event/rt',
          predicate: NS.kabukReminder,
          objectValue: '2026-06-14T09:00:00.000Z',
          objectType: ObjectType.string,
        ),
      ];

      final event = EventData.fromTriples('kabuk:Event/rt', triples);
      expect(event.uri, 'kabuk:Event/rt');
      expect(event.name, 'Conference');
      expect(event.startDate, DateTime.utc(2026, 6, 15, 9));
      expect(event.endDate, DateTime.utc(2026, 6, 15, 17));
      expect(event.location, 'Convention Center');
      expect(event.description, 'Annual tech conf');
      expect(event.organizer, 'kabuk:Person/organizer');
      expect(event.reminder, DateTime.utc(2026, 6, 14, 9));
    });
  });

  // ---------------------------------------------------------------------------
  // MediaData
  // ---------------------------------------------------------------------------

  group('MediaData', () {
    test('fromTriples() resolves ImageObject type', () {
      final triples = [
        const Triple(
          subject: 'kabuk:MediaObject/1',
          predicate: NS.rdfType,
          objectValue: NS.schemaImageObject,
          objectType: ObjectType.uri,
        ),
      ];

      final media = MediaData.fromTriples('kabuk:MediaObject/1', triples);
      expect(media.type, MediaType.image);
    });

    test('fromTriples() resolves VideoObject type', () {
      final triples = [
        const Triple(
          subject: 'kabuk:MediaObject/1',
          predicate: NS.rdfType,
          objectValue: NS.schemaVideoObject,
          objectType: ObjectType.uri,
        ),
      ];

      final media = MediaData.fromTriples('kabuk:MediaObject/1', triples);
      expect(media.type, MediaType.video);
    });

    test('fromTriples() resolves AudioObject type', () {
      final triples = [
        const Triple(
          subject: 'kabuk:MediaObject/1',
          predicate: NS.rdfType,
          objectValue: NS.schemaAudioObject,
          objectType: ObjectType.uri,
        ),
      ];

      final media = MediaData.fromTriples('kabuk:MediaObject/1', triples);
      expect(media.type, MediaType.audio);
    });

    test('fromTriples() defaults to other when no specific type', () {
      final triples = [
        const Triple(
          subject: 'kabuk:MediaObject/1',
          predicate: NS.rdfType,
          objectValue: NS.schemaMediaObject,
          objectType: ObjectType.uri,
        ),
      ];

      final media = MediaData.fromTriples('kabuk:MediaObject/1', triples);
      expect(media.type, MediaType.other);
    });

    test('fromTriples() extracts name', () {
      final triples = [
        const Triple(
          subject: 'kabuk:MediaObject/1',
          predicate: NS.rdfType,
          objectValue: NS.schemaImageObject,
          objectType: ObjectType.uri,
        ),
        const Triple(
          subject: 'kabuk:MediaObject/1',
          predicate: NS.schemaName,
          objectValue: 'photo.jpg',
          objectType: ObjectType.string,
        ),
      ];

      final media = MediaData.fromTriples('kabuk:MediaObject/1', triples);
      expect(media.name, 'photo.jpg');
    });

    test('fromTriples() extracts contentUrl', () {
      final triples = [
        const Triple(
          subject: 'kabuk:MediaObject/1',
          predicate: NS.rdfType,
          objectValue: NS.schemaImageObject,
          objectType: ObjectType.uri,
        ),
        const Triple(
          subject: 'kabuk:MediaObject/1',
          predicate: NS.schemaContentUrl,
          objectValue: '/path/to/photo.jpg',
          objectType: ObjectType.string,
        ),
      ];

      final media = MediaData.fromTriples('kabuk:MediaObject/1', triples);
      expect(media.contentUrl, '/path/to/photo.jpg');
    });

    test('fromTriples() extracts encodingFormat', () {
      final triples = [
        const Triple(
          subject: 'kabuk:MediaObject/1',
          predicate: NS.rdfType,
          objectValue: NS.schemaImageObject,
          objectType: ObjectType.uri,
        ),
        const Triple(
          subject: 'kabuk:MediaObject/1',
          predicate: NS.schemaEncodingFormat,
          objectValue: 'image/jpeg',
          objectType: ObjectType.string,
        ),
      ];

      final media = MediaData.fromTriples('kabuk:MediaObject/1', triples);
      expect(media.encodingFormat, 'image/jpeg');
    });

    test('fromTriples() extracts integer fields', () {
      final triples = [
        const Triple(
          subject: 'kabuk:MediaObject/1',
          predicate: NS.rdfType,
          objectValue: NS.schemaImageObject,
          objectType: ObjectType.uri,
        ),
        const Triple(
          subject: 'kabuk:MediaObject/1',
          predicate: NS.schemaContentSize,
          objectValue: '1024000',
          objectType: ObjectType.integer,
        ),
        const Triple(
          subject: 'kabuk:MediaObject/1',
          predicate: NS.schemaWidth,
          objectValue: '1920',
          objectType: ObjectType.integer,
        ),
        const Triple(
          subject: 'kabuk:MediaObject/1',
          predicate: NS.schemaHeight,
          objectValue: '1080',
          objectType: ObjectType.integer,
        ),
      ];

      final media = MediaData.fromTriples('kabuk:MediaObject/1', triples);
      expect(media.contentSize, 1024000);
      expect(media.width, 1920);
      expect(media.height, 1080);
    });

    test('fromTriples() extracts duration and thumbnail', () {
      final triples = [
        const Triple(
          subject: 'kabuk:MediaObject/1',
          predicate: NS.rdfType,
          objectValue: NS.schemaVideoObject,
          objectType: ObjectType.uri,
        ),
        const Triple(
          subject: 'kabuk:MediaObject/1',
          predicate: NS.schemaDuration,
          objectValue: 'PT2H30M',
          objectType: ObjectType.string,
        ),
        const Triple(
          subject: 'kabuk:MediaObject/1',
          predicate: NS.schemaThumbnail,
          objectValue: '/path/to/thumb.jpg',
          objectType: ObjectType.string,
        ),
      ];

      final media = MediaData.fromTriples('kabuk:MediaObject/1', triples);
      expect(media.duration, 'PT2H30M');
      expect(media.thumbnail, '/path/to/thumb.jpg');
    });

    test('fromTriples() handles missing fields gracefully', () {
      final media = MediaData.fromTriples('kabuk:MediaObject/1', []);
      expect(media.uri, 'kabuk:MediaObject/1');
      expect(media.type, MediaType.other);
      expect(media.name, isNull);
      expect(media.contentUrl, isNull);
      expect(media.encodingFormat, isNull);
      expect(media.contentSize, isNull);
      expect(media.width, isNull);
      expect(media.height, isNull);
      expect(media.duration, isNull);
      expect(media.thumbnail, isNull);
    });

    test('fromTriples() handles invalid integer gracefully', () {
      final triples = [
        const Triple(
          subject: 'kabuk:MediaObject/1',
          predicate: NS.rdfType,
          objectValue: NS.schemaImageObject,
          objectType: ObjectType.uri,
        ),
        const Triple(
          subject: 'kabuk:MediaObject/1',
          predicate: NS.schemaWidth,
          objectValue: 'not-a-number',
          objectType: ObjectType.string,
        ),
      ];

      final media = MediaData.fromTriples('kabuk:MediaObject/1', triples);
      expect(media.width, isNull);
    });

    test('schemaTypeUri maps correctly', () {
      expect(
        MediaData.fromTriples('x', [
          const Triple(
            subject: 'x',
            predicate: NS.rdfType,
            objectValue: NS.schemaImageObject,
            objectType: ObjectType.uri,
          ),
        ]).schemaTypeUri,
        NS.schemaImageObject,
      );
      expect(
        MediaData.fromTriples('x', [
          const Triple(
            subject: 'x',
            predicate: NS.rdfType,
            objectValue: NS.schemaVideoObject,
            objectType: ObjectType.uri,
          ),
        ]).schemaTypeUri,
        NS.schemaVideoObject,
      );
      expect(
        MediaData.fromTriples('x', [
          const Triple(
            subject: 'x',
            predicate: NS.rdfType,
            objectValue: NS.schemaAudioObject,
            objectType: ObjectType.uri,
          ),
        ]).schemaTypeUri,
        NS.schemaAudioObject,
      );
      expect(
        MediaData.fromTriples('x', []).schemaTypeUri,
        NS.schemaMediaObject,
      );
    });

    test('roundtrip: all fields for an image', () {
      final triples = [
        const Triple(
          subject: 'kabuk:MediaObject/rt',
          predicate: NS.rdfType,
          objectValue: NS.schemaImageObject,
          objectType: ObjectType.uri,
        ),
        const Triple(
          subject: 'kabuk:MediaObject/rt',
          predicate: NS.schemaName,
          objectValue: 'vacation.png',
          objectType: ObjectType.string,
        ),
        const Triple(
          subject: 'kabuk:MediaObject/rt',
          predicate: NS.schemaContentUrl,
          objectValue: '/photos/vacation.png',
          objectType: ObjectType.string,
        ),
        const Triple(
          subject: 'kabuk:MediaObject/rt',
          predicate: NS.schemaEncodingFormat,
          objectValue: 'image/png',
          objectType: ObjectType.string,
        ),
        const Triple(
          subject: 'kabuk:MediaObject/rt',
          predicate: NS.schemaContentSize,
          objectValue: '2048000',
          objectType: ObjectType.integer,
        ),
        const Triple(
          subject: 'kabuk:MediaObject/rt',
          predicate: NS.schemaWidth,
          objectValue: '3840',
          objectType: ObjectType.integer,
        ),
        const Triple(
          subject: 'kabuk:MediaObject/rt',
          predicate: NS.schemaHeight,
          objectValue: '2160',
          objectType: ObjectType.integer,
        ),
        const Triple(
          subject: 'kabuk:MediaObject/rt',
          predicate: NS.schemaThumbnail,
          objectValue: '/thumbs/vacation.jpg',
          objectType: ObjectType.string,
        ),
      ];

      final media = MediaData.fromTriples('kabuk:MediaObject/rt', triples);
      expect(media.uri, 'kabuk:MediaObject/rt');
      expect(media.type, MediaType.image);
      expect(media.name, 'vacation.png');
      expect(media.contentUrl, '/photos/vacation.png');
      expect(media.encodingFormat, 'image/png');
      expect(media.contentSize, 2048000);
      expect(media.width, 3840);
      expect(media.height, 2160);
      expect(media.thumbnail, '/thumbs/vacation.jpg');
    });
  });
}
