import 'package:flutter_test/flutter_test.dart';
import 'package:kabuk/rfw/models.dart';
import 'package:kabuk/rfw/registry.dart';

void main() {
  late RfwRegistry registry;

  setUp(() {
    registry = RfwRegistry();
  });

  // ---------------------------------------------------------------------------
  // install() and getLibrary()
  // ---------------------------------------------------------------------------

  group('install()', () {
    test('adds a library to the registry', () {
      const lib = RfwLibrary(
        name: 'test:lib',
        version: '1.0.0',
        author: 'Test',
        description: 'A test library',
        widgets: {
          'Foo': RfwWidgetDef(
            name: 'Foo',
            rfwSource: 'widget Root = Text(text: "hi");',
          ),
        },
      );

      registry.install(lib);

      expect(registry.libraryNames, contains('test:lib'));
      expect(registry.getLibrary('test:lib'), isNotNull);
      expect(registry.getLibrary('test:lib')!.name, 'test:lib');
    });

    test('replaces library with same name', () {
      const lib1 = RfwLibrary(
        name: 'test:lib',
        version: '1.0.0',
        author: 'Test',
        description: 'Version 1',
        widgets: {'Foo': RfwWidgetDef(name: 'Foo', rfwSource: 'v1')},
      );
      const lib2 = RfwLibrary(
        name: 'test:lib',
        version: '2.0.0',
        author: 'Test',
        description: 'Version 2',
        widgets: {'Bar': RfwWidgetDef(name: 'Bar', rfwSource: 'v2')},
      );

      registry.install(lib1);
      registry.install(lib2);

      expect(registry.getLibrary('test:lib')!.version, '2.0.0');
      expect(registry.getLibrary('test:lib')!.widgets.keys, contains('Bar'));
      expect(
        registry.getLibrary('test:lib')!.widgets.keys,
        isNot(contains('Foo')),
      );
    });

    test('supports multiple different libraries', () {
      const lib1 = RfwLibrary(
        name: 'test:a',
        version: '1.0.0',
        author: 'Test',
        description: 'Library A',
        widgets: {},
      );
      const lib2 = RfwLibrary(
        name: 'test:b',
        version: '1.0.0',
        author: 'Test',
        description: 'Library B',
        widgets: {},
      );

      registry.install(lib1);
      registry.install(lib2);

      expect(registry.libraryNames.toList(), containsAll(['test:a', 'test:b']));
      expect(registry.libraries.length, 2);
    });
  });

  // ---------------------------------------------------------------------------
  // uninstall()
  // ---------------------------------------------------------------------------

  group('uninstall()', () {
    test('removes installed library and returns true', () {
      const lib = RfwLibrary(
        name: 'test:rm',
        version: '1.0.0',
        author: 'Test',
        description: 'To be removed',
        widgets: {},
      );

      registry.install(lib);
      expect(registry.uninstall('test:rm'), isTrue);
      expect(registry.getLibrary('test:rm'), isNull);
    });

    test('returns false for non-existent library', () {
      expect(registry.uninstall('nonexistent'), isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // getWidget()
  // ---------------------------------------------------------------------------

  group('getWidget()', () {
    test('finds installed widget', () {
      const lib = RfwLibrary(
        name: 'test:widgets',
        version: '1.0.0',
        author: 'Test',
        description: 'Widget lib',
        widgets: {
          'Card': RfwWidgetDef(
            name: 'Card',
            rfwSource: 'widget Root = Container();',
            description: 'A card',
          ),
          'Tile': RfwWidgetDef(
            name: 'Tile',
            rfwSource: 'widget Root = Row();',
            description: 'A tile',
          ),
        },
      );

      registry.install(lib);

      final card = registry.getWidget('test:widgets', 'Card');
      expect(card, isNotNull);
      expect(card!.name, 'Card');
      expect(card.description, 'A card');

      final tile = registry.getWidget('test:widgets', 'Tile');
      expect(tile, isNotNull);
      expect(tile!.name, 'Tile');
    });

    test('returns null for missing widget in existing library', () {
      const lib = RfwLibrary(
        name: 'test:sparse',
        version: '1.0.0',
        author: 'Test',
        description: 'Sparse',
        widgets: {'OnlyOne': RfwWidgetDef(name: 'OnlyOne', rfwSource: 'x')},
      );

      registry.install(lib);

      expect(registry.getWidget('test:sparse', 'Missing'), isNull);
    });

    test('returns null for non-existent library', () {
      expect(registry.getWidget('no:such:lib', 'Any'), isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // findWidgetsForType()
  // ---------------------------------------------------------------------------

  group('findWidgetsForType()', () {
    test('matches widgets from libraries declaring the schema type', () {
      const noteLib = RfwLibrary(
        name: 'test:notes',
        version: '1.0.0',
        author: 'Test',
        description: 'Notes',
        widgets: {
          'NoteCard': RfwWidgetDef(
            name: 'NoteCard',
            rfwSource: 'widget Root = Text(text: "note");',
          ),
        },
        schemaTypes: ['https://schema.org/Note'],
      );

      registry.install(noteLib);

      final results = registry.findWidgetsForType('https://schema.org/Note');
      expect(results, hasLength(1));
      expect(results.first.$1, 'test:notes');
      expect(results.first.$2.name, 'NoteCard');
    });

    test('returns all widgets from matching library', () {
      const lib = RfwLibrary(
        name: 'test:multi',
        version: '1.0.0',
        author: 'Test',
        description: 'Multi widgets',
        widgets: {
          'Widget1': RfwWidgetDef(name: 'Widget1', rfwSource: 'w1'),
          'Widget2': RfwWidgetDef(name: 'Widget2', rfwSource: 'w2'),
          'Widget3': RfwWidgetDef(name: 'Widget3', rfwSource: 'w3'),
        },
        schemaTypes: ['https://schema.org/Event'],
      );

      registry.install(lib);

      final results = registry.findWidgetsForType('https://schema.org/Event');
      expect(results, hasLength(3));
    });

    test('returns empty list for unmatched type', () {
      const lib = RfwLibrary(
        name: 'test:notes',
        version: '1.0.0',
        author: 'Test',
        description: 'Notes only',
        widgets: {'NoteCard': RfwWidgetDef(name: 'NoteCard', rfwSource: 'x')},
        schemaTypes: ['https://schema.org/Note'],
      );

      registry.install(lib);

      final results = registry.findWidgetsForType('https://schema.org/Person');
      expect(results, isEmpty);
    });

    test('returns empty for empty registry', () {
      final results = registry.findWidgetsForType('https://schema.org/Note');
      expect(results, isEmpty);
    });

    test('matches across multiple libraries', () {
      const lib1 = RfwLibrary(
        name: 'test:notes',
        version: '1.0.0',
        author: 'Test',
        description: 'Notes',
        widgets: {'NoteCard': RfwWidgetDef(name: 'NoteCard', rfwSource: 'n1')},
        schemaTypes: ['https://schema.org/Note'],
      );
      const lib2 = RfwLibrary(
        name: 'test:notes-alt',
        version: '1.0.0',
        author: 'Test',
        description: 'Alt Notes',
        widgets: {
          'CompactNote': RfwWidgetDef(name: 'CompactNote', rfwSource: 'n2'),
        },
        schemaTypes: ['https://schema.org/Note'],
      );

      registry.install(lib1);
      registry.install(lib2);

      final results = registry.findWidgetsForType('https://schema.org/Note');
      expect(results, hasLength(2));
      final libNames = results.map((r) => r.$1).toSet();
      expect(libNames, containsAll(['test:notes', 'test:notes-alt']));
    });
  });

  // ---------------------------------------------------------------------------
  // getAllLibraries / libraryNames / libraries
  // ---------------------------------------------------------------------------

  group('getAllLibraries', () {
    test('returns all installed libraries', () {
      registry.install(
        const RfwLibrary(
          name: 'a',
          version: '1.0.0',
          author: 'T',
          description: 'A',
          widgets: {},
        ),
      );
      registry.install(
        const RfwLibrary(
          name: 'b',
          version: '1.0.0',
          author: 'T',
          description: 'B',
          widgets: {},
        ),
      );
      registry.install(
        const RfwLibrary(
          name: 'c',
          version: '1.0.0',
          author: 'T',
          description: 'C',
          widgets: {},
        ),
      );

      expect(registry.libraryNames.toList(), containsAll(['a', 'b', 'c']));
      expect(registry.libraries.length, 3);
    });

    test('returns empty when none installed', () {
      expect(registry.libraryNames, isEmpty);
      expect(registry.libraries, isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  // checkDependencies()
  // ---------------------------------------------------------------------------

  group('checkDependencies()', () {
    test('returns empty when all dependencies satisfied', () {
      registry.install(
        const RfwLibrary(
          name: 'core',
          version: '1.0.0',
          author: 'T',
          description: 'Core',
          widgets: {},
        ),
      );

      const child = RfwLibrary(
        name: 'child',
        version: '1.0.0',
        author: 'T',
        description: 'Child',
        widgets: {},
        dependencies: ['core'],
      );

      expect(registry.checkDependencies(child), isEmpty);
    });

    test('returns missing dependencies', () {
      const child = RfwLibrary(
        name: 'child',
        version: '1.0.0',
        author: 'T',
        description: 'Child',
        widgets: {},
        dependencies: ['core >= 1.0.0', 'utils'],
      );

      final missing = registry.checkDependencies(child);
      expect(missing, hasLength(2));
      expect(missing, contains('core >= 1.0.0'));
      expect(missing, contains('utils'));
    });

    test('returns empty for libraries with no dependencies', () {
      const lib = RfwLibrary(
        name: 'standalone',
        version: '1.0.0',
        author: 'T',
        description: 'No deps',
        widgets: {},
      );

      expect(registry.checkDependencies(lib), isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  // clear()
  // ---------------------------------------------------------------------------

  group('clear()', () {
    test('removes all libraries', () {
      registry.install(
        const RfwLibrary(
          name: 'a',
          version: '1.0.0',
          author: 'T',
          description: 'A',
          widgets: {},
        ),
      );
      registry.install(
        const RfwLibrary(
          name: 'b',
          version: '1.0.0',
          author: 'T',
          description: 'B',
          widgets: {},
        ),
      );

      expect(registry.libraries.length, 2);

      registry.clear();

      expect(registry.libraries, isEmpty);
      expect(registry.libraryNames, isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  // RfwLibrary serialization
  // ---------------------------------------------------------------------------

  group('RfwLibrary serialization', () {
    test('toJson and fromJson roundtrip', () {
      const lib = RfwLibrary(
        name: 'test:ser',
        version: '2.0.0',
        author: 'Author',
        description: 'Serialization test',
        widgets: {
          'W': RfwWidgetDef(
            name: 'W',
            description: 'A widget',
            rfwSource: 'widget Root = Text(text: "hi");',
            dataContract: {'title': 'string'},
            events: ['onTap'],
          ),
        },
        dependencies: ['core'],
        schemaTypes: ['https://schema.org/Note'],
      );

      final json = lib.toJson();
      final restored = RfwLibrary.fromJson(json);

      expect(restored.name, lib.name);
      expect(restored.version, lib.version);
      expect(restored.author, lib.author);
      expect(restored.description, lib.description);
      expect(restored.dependencies, lib.dependencies);
      expect(restored.schemaTypes, lib.schemaTypes);
      expect(restored.widgets.keys, contains('W'));

      final w = restored.widgets['W']!;
      expect(w.name, 'W');
      expect(w.description, 'A widget');
      expect(w.rfwSource, contains('Text'));
      expect(w.dataContract, {'title': 'string'});
      expect(w.events, ['onTap']);
    });
  });

  // ---------------------------------------------------------------------------
  // RfwWidgetDef serialization
  // ---------------------------------------------------------------------------

  group('RfwWidgetDef serialization', () {
    test('toJson and fromJson roundtrip', () {
      const def = RfwWidgetDef(
        name: 'TestWidget',
        description: 'Test desc',
        rfwSource: 'widget Root = Container();',
        dataContract: {'a': 'string', 'b': 'int'},
        events: ['onTap', 'onLongPress'],
      );

      final json = def.toJson();
      final restored = RfwWidgetDef.fromJson(json);

      expect(restored.name, 'TestWidget');
      expect(restored.description, 'Test desc');
      expect(restored.rfwSource, 'widget Root = Container();');
      expect(restored.dataContract, {'a': 'string', 'b': 'int'});
      expect(restored.events, ['onTap', 'onLongPress']);
    });

    test('fromJson handles missing optional fields', () {
      final json = {'name': 'Minimal'};
      final def = RfwWidgetDef.fromJson(json);

      expect(def.name, 'Minimal');
      expect(def.description, '');
      expect(def.rfwSource, '');
      expect(def.dataContract, isEmpty);
      expect(def.events, isEmpty);
    });
  });
}
