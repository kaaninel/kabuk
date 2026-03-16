import 'package:flutter_test/flutter_test.dart';
import 'package:kabuk/rfw/built_in_libraries.dart';
import 'package:kabuk/rfw/models.dart';

void main() {
  late List<RfwLibrary> libraries;

  setUp(() {
    libraries = builtInLibraries();
  });

  // ---------------------------------------------------------------------------
  // Overall structure
  // ---------------------------------------------------------------------------

  group('builtInLibraries()', () {
    test('returns exactly 7 libraries', () {
      expect(libraries, hasLength(7));
    });

    test('all libraries have unique names', () {
      final names = libraries.map((l) => l.name).toSet();
      expect(names, hasLength(7));
    });

    test('expected library names are present', () {
      final names = libraries.map((l) => l.name).toSet();
      expect(
        names,
        containsAll([
          'kabuk:core',
          'kabuk:notes',
          'kabuk:contacts',
          'kabuk:dashboard',
          'kabuk:media',
          'kabuk:calendar',
          'kabuk:chat',
        ]),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // Common properties for all libraries
  // ---------------------------------------------------------------------------

  group('all libraries', () {
    test('have non-empty name', () {
      for (final lib in libraries) {
        expect(
          lib.name,
          isNotEmpty,
          reason: 'Library name should be non-empty',
        );
      }
    });

    test('have non-empty version', () {
      for (final lib in libraries) {
        expect(lib.version, isNotEmpty, reason: '${lib.name} version');
      }
    });

    test('have author set to "Kabuk Project"', () {
      for (final lib in libraries) {
        expect(lib.author, 'Kabuk Project', reason: '${lib.name} author');
      }
    });

    test('have non-empty description', () {
      for (final lib in libraries) {
        expect(lib.description, isNotEmpty, reason: '${lib.name} description');
      }
    });

    test('have at least one widget', () {
      for (final lib in libraries) {
        expect(
          lib.widgets,
          isNotEmpty,
          reason: '${lib.name} should have widgets',
        );
      }
    });

    test('all widget definitions have non-empty rfwSource', () {
      for (final lib in libraries) {
        for (final entry in lib.widgets.entries) {
          expect(
            entry.value.rfwSource,
            isNotEmpty,
            reason: '${lib.name}/${entry.key} rfwSource should not be empty',
          );
        }
      }
    });

    test('all widget definitions have non-empty name', () {
      for (final lib in libraries) {
        for (final entry in lib.widgets.entries) {
          expect(
            entry.value.name,
            isNotEmpty,
            reason: '${lib.name}/${entry.key} name should not be empty',
          );
          // Widget name should match map key
          expect(
            entry.value.name,
            entry.key,
            reason: '${lib.name}: widget name should match map key',
          );
        }
      }
    });
  });

  // ---------------------------------------------------------------------------
  // kabuk:core
  // ---------------------------------------------------------------------------

  group('kabuk:core', () {
    late RfwLibrary core;

    setUp(() {
      core = libraries.firstWhere((l) => l.name == 'kabuk:core');
    });

    test('has version 1.0.0', () {
      expect(core.version, '1.0.0');
    });

    test('has no dependencies', () {
      expect(core.dependencies, isEmpty);
    });

    test('has expected widgets', () {
      expect(
        core.widgets.keys,
        containsAll([
          'Card',
          'ListTile',
          'EmptyState',
          'ErrorState',
          'LoadingState',
          'Grid',
        ]),
      );
    });

    test('Card widget has proper data contract', () {
      final card = core.widgets['Card']!;
      expect(
        card.dataContract.keys,
        containsAll(['title', 'subtitle', 'body']),
      );
    });

    test('ErrorState widget has onRetry event', () {
      final error = core.widgets['ErrorState']!;
      expect(error.events, contains('onRetry'));
    });
  });

  // ---------------------------------------------------------------------------
  // kabuk:notes
  // ---------------------------------------------------------------------------

  group('kabuk:notes', () {
    late RfwLibrary notes;

    setUp(() {
      notes = libraries.firstWhere((l) => l.name == 'kabuk:notes');
    });

    test('depends on kabuk:core', () {
      expect(notes.dependencies, contains('kabuk:core'));
    });

    test('declares schema type https://schema.org/Note', () {
      expect(notes.schemaTypes, contains('https://schema.org/Note'));
    });

    test('has NoteCard and NoteDetail widgets', () {
      expect(notes.widgets.keys, containsAll(['NoteCard', 'NoteDetail']));
    });

    test('NoteCard data contract includes name, text, dateCreated', () {
      final card = notes.widgets['NoteCard']!;
      expect(
        card.dataContract.keys,
        containsAll(['name', 'text', 'dateCreated']),
      );
    });

    test('NoteCard has onTap and onDelete events', () {
      final card = notes.widgets['NoteCard']!;
      expect(card.events, containsAll(['onTap', 'onDelete']));
    });

    test('NoteDetail has onEdit and onDelete events', () {
      final detail = notes.widgets['NoteDetail']!;
      expect(detail.events, containsAll(['onEdit', 'onDelete']));
    });
  });

  // ---------------------------------------------------------------------------
  // kabuk:contacts
  // ---------------------------------------------------------------------------

  group('kabuk:contacts', () {
    late RfwLibrary contacts;

    setUp(() {
      contacts = libraries.firstWhere((l) => l.name == 'kabuk:contacts');
    });

    test('depends on kabuk:core', () {
      expect(contacts.dependencies, contains('kabuk:core'));
    });

    test('declares schema type https://schema.org/Person', () {
      expect(contacts.schemaTypes, contains('https://schema.org/Person'));
    });

    test('has ContactCard widget', () {
      expect(contacts.widgets.keys, contains('ContactCard'));
    });

    test('ContactCard data contract includes name and email', () {
      final card = contacts.widgets['ContactCard']!;
      expect(card.dataContract.keys, containsAll(['name', 'email']));
    });
  });

  // ---------------------------------------------------------------------------
  // kabuk:media
  // ---------------------------------------------------------------------------

  group('kabuk:media', () {
    late RfwLibrary media;

    setUp(() {
      media = libraries.firstWhere((l) => l.name == 'kabuk:media');
    });

    test('depends on kabuk:core', () {
      expect(media.dependencies, contains('kabuk:core'));
    });

    test('declares image, video, audio schema types', () {
      expect(
        media.schemaTypes,
        containsAll([
          'https://schema.org/ImageObject',
          'https://schema.org/VideoObject',
          'https://schema.org/AudioObject',
        ]),
      );
    });

    test('has ImageCard, VideoCard, AudioCard, Gallery widgets', () {
      expect(
        media.widgets.keys,
        containsAll(['ImageCard', 'VideoCard', 'AudioCard', 'Gallery']),
      );
    });

    test('VideoCard has onPlay event', () {
      final video = media.widgets['VideoCard']!;
      expect(video.events, contains('onPlay'));
    });

    test('AudioCard has onPlay event', () {
      final audio = media.widgets['AudioCard']!;
      expect(audio.events, contains('onPlay'));
    });
  });

  // ---------------------------------------------------------------------------
  // kabuk:calendar
  // ---------------------------------------------------------------------------

  group('kabuk:calendar', () {
    late RfwLibrary calendar;

    setUp(() {
      calendar = libraries.firstWhere((l) => l.name == 'kabuk:calendar');
    });

    test('depends on kabuk:core', () {
      expect(calendar.dependencies, contains('kabuk:core'));
    });

    test('declares schema type https://schema.org/Event', () {
      expect(calendar.schemaTypes, contains('https://schema.org/Event'));
    });

    test('has EventCard and EventList widgets', () {
      expect(calendar.widgets.keys, containsAll(['EventCard', 'EventList']));
    });

    test('EventCard data contract includes date fields', () {
      final card = calendar.widgets['EventCard']!;
      expect(
        card.dataContract.keys,
        containsAll(['name', 'startDate', 'endDate', 'location']),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // kabuk:chat
  // ---------------------------------------------------------------------------

  group('kabuk:chat', () {
    late RfwLibrary chat;

    setUp(() {
      chat = libraries.firstWhere((l) => l.name == 'kabuk:chat');
    });

    test('depends on kabuk:core', () {
      expect(chat.dependencies, contains('kabuk:core'));
    });

    test('declares Message and Conversation schema types', () {
      expect(
        chat.schemaTypes,
        containsAll([
          'https://schema.org/Message',
          'https://schema.org/Conversation',
        ]),
      );
    });

    test('has MessageBubble and ConversationList widgets', () {
      expect(
        chat.widgets.keys,
        containsAll(['MessageBubble', 'ConversationList']),
      );
    });

    test('MessageBubble data contract includes sender and text', () {
      final msg = chat.widgets['MessageBubble']!;
      expect(msg.dataContract.keys, containsAll(['sender', 'text', 'time']));
    });
  });

  // ---------------------------------------------------------------------------
  // kabuk:dashboard
  // ---------------------------------------------------------------------------

  group('kabuk:dashboard', () {
    late RfwLibrary dashboard;

    setUp(() {
      dashboard = libraries.firstWhere((l) => l.name == 'kabuk:dashboard');
    });

    test('depends on kabuk:core', () {
      expect(dashboard.dependencies, contains('kabuk:core'));
    });

    test('has StatWidget and QuickAction widgets', () {
      expect(
        dashboard.widgets.keys,
        containsAll(['StatWidget', 'QuickAction']),
      );
    });

    test('StatWidget data contract includes value and label', () {
      final stat = dashboard.widgets['StatWidget']!;
      expect(stat.dataContract.keys, containsAll(['value', 'label']));
    });

    test('QuickAction has onTap event', () {
      final action = dashboard.widgets['QuickAction']!;
      expect(action.events, contains('onTap'));
    });
  });

  // ---------------------------------------------------------------------------
  // Schema type mapping completeness
  // ---------------------------------------------------------------------------

  group('schema type mappings', () {
    test('Note type is covered by exactly one library', () {
      final noteLibs = libraries
          .where((l) => l.schemaTypes.contains('https://schema.org/Note'))
          .toList();
      expect(noteLibs, hasLength(1));
      expect(noteLibs.first.name, 'kabuk:notes');
    });

    test('Person type is covered by exactly one library', () {
      final personLibs = libraries
          .where((l) => l.schemaTypes.contains('https://schema.org/Person'))
          .toList();
      expect(personLibs, hasLength(1));
      expect(personLibs.first.name, 'kabuk:contacts');
    });

    test('Event type is covered by exactly one library', () {
      final eventLibs = libraries
          .where((l) => l.schemaTypes.contains('https://schema.org/Event'))
          .toList();
      expect(eventLibs, hasLength(1));
      expect(eventLibs.first.name, 'kabuk:calendar');
    });

    test('ImageObject type is covered by media library', () {
      final mediaLibs = libraries
          .where(
            (l) => l.schemaTypes.contains('https://schema.org/ImageObject'),
          )
          .toList();
      expect(mediaLibs, hasLength(1));
      expect(mediaLibs.first.name, 'kabuk:media');
    });

    test('core library has no schema types (utility only)', () {
      final core = libraries.firstWhere((l) => l.name == 'kabuk:core');
      expect(core.schemaTypes, isEmpty);
    });

    test('dashboard library has no schema types', () {
      final dashboard = libraries.firstWhere(
        (l) => l.name == 'kabuk:dashboard',
      );
      expect(dashboard.schemaTypes, isEmpty);
    });
  });
}
