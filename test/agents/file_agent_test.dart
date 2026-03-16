import 'package:flutter_test/flutter_test.dart';
import 'package:kabuk/agents/base.dart';
import 'package:kabuk/agents/domains/file_agent.dart';
import 'package:kabuk/agents/llm.dart';
import 'package:kabuk/agents/messages.dart';
import 'package:kabuk/config/namespaces.dart';
import 'package:kabuk/knowledge/triple.dart';
import 'package:kabuk/services/vault.dart';
import 'package:mocktail/mocktail.dart';

import '../helpers/mocks.dart';

void main() {
  late FileAgent agent;
  late MockAgentContextBundle bundle;

  setUpAll(() {
    registerFallbackValue(FakeLlmRequest());
    registerFallbackValue(fakeMutationAction);
  });

  setUp(() {
    agent = FileAgent();
    bundle = createMockAgentContext();
  });

  // ---------------------------------------------------------------------------
  // Agent metadata
  // ---------------------------------------------------------------------------

  group('FileAgent metadata', () {
    test('name is "files"', () {
      expect(agent.name, 'files');
    });

    test('description is non-empty', () {
      expect(agent.description, isNotEmpty);
    });

    test('systemPrompt is non-empty', () {
      expect(agent.systemPrompt, isNotEmpty);
    });

    test('declares expected tools', () {
      final toolNames = agent.tools.map((t) => t.name).toList();
      expect(
        toolNames,
        containsAll([
          'list_files',
          'tag_file',
          'get_metadata',
          'create_smart_folder',
          'import_file',
        ]),
      );
    });

    test('requires knowledgeRead, knowledgeWrite, vaultRead, and llmCall', () {
      expect(
        agent.requiredCapabilities,
        containsAll([
          AgentCapability.knowledgeRead,
          AgentCapability.knowledgeWrite,
          AgentCapability.vaultRead,
          AgentCapability.llmCall,
        ]),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // process() — LLM paths
  // ---------------------------------------------------------------------------

  group('process() with TextLlmResponse', () {
    test('returns text response from LLM', () async {
      stubLlmStreamText(bundle.llm, 'I can help with files!');

      final message = AgentMessage.user(
        id: 'msg-1',
        timestamp: DateTime.now(),
        content: 'Show my files',
      );

      final response = await agent.process(message, bundle.context);

      expect(response, isA<StreamingAgentResponse>());
      final text = await collectStreamingText(response);
      expect(text, 'I can help with files!');
      verify(() => bundle.llm.stream(any())).called(1);
    });
  });

  group('process() with ErrorLlmResponse', () {
    test('returns error response', () async {
      stubLlmStreamError(bundle.llm, 'API error');

      final message = AgentMessage.user(
        id: 'msg-2',
        timestamp: DateTime.now(),
        content: 'List files',
      );

      final response = await agent.process(message, bundle.context);

      expect(response, isA<StreamingAgentResponse>());
      await expectLater(
        (response as StreamingAgentResponse).events,
        emitsError(isA<LlmStreamException>()),
      );
    });
  });

  group('process() with empty content', () {
    test('returns prompt for non-user message', () async {
      final message = AgentMessage.toolCall(
        id: 'msg-3',
        timestamp: DateTime.now(),
        toolName: 'list_files',
        arguments: {},
      );

      final response = await agent.process(message, bundle.context);

      expect(response, isA<TextAgentResponse>());
      expect((response as TextAgentResponse).content, contains('file'));
      verifyNever(() => bundle.llm.stream(any()));
    });
  });

  // ---------------------------------------------------------------------------
  // list_files tool
  // ---------------------------------------------------------------------------

  group('list_files tool', () {
    test('returns "No files" when store is empty', () async {
      final mockQb = MockQueryBuilder();
      bundle.knowledge.onQuery = () => mockQb;
      when(() => mockQb.predicate(any())).thenReturn(mockQb);
      when(() => mockQb.object(any())).thenReturn(mockQb);
      when(() => mockQb.limit(any())).thenReturn(mockQb);
      when(mockQb.execute).thenAnswer((_) async => <Triple>[]);

      final tool = agent.tools.firstWhere((t) => t.name == 'list_files');
      final result = await tool.execute({}, bundle.context);

      expect(result, isA<TextToolResult>());
      expect((result as TextToolResult).content, contains('No files'));
    });

    test('returns formatted files when found', () async {
      final mockQb = MockQueryBuilder();
      bundle.knowledge.onQuery = () => mockQb;
      when(() => mockQb.predicate(any())).thenReturn(mockQb);
      when(() => mockQb.object(any())).thenReturn(mockQb);
      when(() => mockQb.limit(any())).thenReturn(mockQb);
      when(mockQb.execute).thenAnswer(
        (_) async => [
          const Triple(
            subject: 'kabuk:MediaObject/1',
            predicate: NS.rdfType,
            objectValue: NS.schemaMediaObject,
            objectType: ObjectType.uri,
          ),
        ],
      );

      when(() => bundle.knowledge.getEntities(any())).thenAnswer(
        (_) async => {
          'kabuk:MediaObject/1': [
            const Triple(
              subject: 'kabuk:MediaObject/1',
              predicate: NS.schemaName,
              objectValue: 'document.pdf',
              objectType: ObjectType.string,
            ),
            const Triple(
              subject: 'kabuk:MediaObject/1',
              predicate: NS.schemaContentSize,
              objectValue: '1024',
              objectType: ObjectType.string,
            ),
          ],
        },
      );

      final tool = agent.tools.firstWhere((t) => t.name == 'list_files');
      final result = await tool.execute({}, bundle.context);

      expect(result, isA<TextToolResult>());
      final text = (result as TextToolResult).content;
      expect(text, contains('document.pdf'));
    });
  });

  // ---------------------------------------------------------------------------
  // get_metadata tool
  // ---------------------------------------------------------------------------

  group('get_metadata tool', () {
    test('returns error for missing uri', () async {
      final tool = agent.tools.firstWhere((t) => t.name == 'get_metadata');
      final result = await tool.execute({'uri': ''}, bundle.context);

      expect(result, isA<ErrorToolResult>());
    });

    test('returns metadata for valid file', () async {
      when(() => bundle.knowledge.getEntity(any())).thenAnswer(
        (_) async => [
          const Triple(
            subject: 'kabuk:MediaObject/1',
            predicate: NS.schemaName,
            objectValue: 'photo.jpg',
            objectType: ObjectType.string,
          ),
          const Triple(
            subject: 'kabuk:MediaObject/1',
            predicate: NS.schemaEncodingFormat,
            objectValue: 'image/jpeg',
            objectType: ObjectType.string,
          ),
          const Triple(
            subject: 'kabuk:MediaObject/1',
            predicate: NS.schemaContentSize,
            objectValue: '2048000',
            objectType: ObjectType.string,
          ),
        ],
      );

      final tool = agent.tools.firstWhere((t) => t.name == 'get_metadata');
      final result = await tool.execute({
        'uri': 'kabuk:MediaObject/1',
      }, bundle.context);

      expect(result, isA<TextToolResult>());
      final text = (result as TextToolResult).content;
      expect(text, contains('photo.jpg'));
    });

    test('returns error when file not found', () async {
      when(
        () => bundle.knowledge.getEntity(any()),
      ).thenAnswer((_) async => <Triple>[]);

      final tool = agent.tools.firstWhere((t) => t.name == 'get_metadata');
      final result = await tool.execute({
        'uri': 'kabuk:MediaObject/nonexistent',
      }, bundle.context);

      expect(result, isA<ErrorToolResult>());
    });
  });

  // ---------------------------------------------------------------------------
  // tag_file tool
  // ---------------------------------------------------------------------------

  group('tag_file tool', () {
    test('returns error for missing uri', () async {
      final tool = agent.tools.firstWhere((t) => t.name == 'tag_file');
      final result = await tool.execute({
        'uri': '',
        'tag': 'important',
      }, bundle.context);

      expect(result, isA<ErrorToolResult>());
    });

    test('returns error for missing tag', () async {
      final tool = agent.tools.firstWhere((t) => t.name == 'tag_file');
      final result = await tool.execute({
        'uri': 'kabuk:MediaObject/1',
        'tag': '',
      }, bundle.context);

      expect(result, isA<ErrorToolResult>());
    });

    test('adds tag to file', () async {
      when(() => bundle.knowledge.getEntity(any())).thenAnswer(
        (_) async => [
          const Triple(
            subject: 'kabuk:MediaObject/1',
            predicate: NS.schemaName,
            objectValue: 'doc.pdf',
            objectType: ObjectType.string,
          ),
        ],
      );

      bundle.knowledge.onMutate = <T>(action) async {
        return await action(FakeMutationContext());
      };

      final tool = agent.tools.firstWhere((t) => t.name == 'tag_file');
      final result = await tool.execute({
        'uri': 'kabuk:MediaObject/1',
        'tag': 'work',
      }, bundle.context);

      expect(result, isA<TextToolResult>());
      expect((result as TextToolResult).content.toLowerCase(), contains('tag'));
    });
  });

  // ---------------------------------------------------------------------------
  // create_smart_folder tool
  // ---------------------------------------------------------------------------

  group('create_smart_folder tool', () {
    test('creates smart folder', () async {
      bundle.knowledge.onMutate = <T>(action) async {
        return await action(FakeMutationContext());
      };

      final tool = agent.tools.firstWhere(
        (t) => t.name == 'create_smart_folder',
      );
      final result = await tool.execute({
        'name': 'Work Docs',
        'tags': ['work', 'documents'],
      }, bundle.context);

      expect(result, isA<TextToolResult>());
      expect((result as TextToolResult).content, contains('Work Docs'));
      expect(bundle.knowledge.mutateCallCount, 1);
    });
  });

  // ---------------------------------------------------------------------------
  // import_file tool
  // ---------------------------------------------------------------------------

  group('import_file tool', () {
    test('returns error for missing path', () async {
      final tool = agent.tools.firstWhere((t) => t.name == 'import_file');
      final result = await tool.execute({'path': ''}, bundle.context);

      expect(result, isA<ErrorToolResult>());
    });

    test('imports file via vault service', () async {
      final now = DateTime.now();
      when(() => bundle.vault.importFromPath(any())).thenAnswer(
        (_) async => VaultEntry(
          hash: 'abc123',
          name: 'report.pdf',
          mimeType: 'application/pdf',
          size: 4096,
          createdAt: now,
          modifiedAt: now,
          tags: [],
          metadata: {},
          encrypted: true,
        ),
      );

      bundle.knowledge.onMutate = <T>(action) async {
        return await action(FakeMutationContext());
      };

      final tool = agent.tools.firstWhere((t) => t.name == 'import_file');
      final result = await tool.execute({
        'path': '/tmp/report.pdf',
      }, bundle.context);

      expect(result, isA<TextToolResult>());
      final text = (result as TextToolResult).content;
      expect(text, contains('report.pdf'));
      verify(() => bundle.vault.importFromPath('/tmp/report.pdf')).called(1);
    });
  });

  // ---------------------------------------------------------------------------
  // Tool schema validation
  // ---------------------------------------------------------------------------

  group('tool schemas', () {
    test('tag_file requires uri and tag', () {
      final tool = agent.tools.firstWhere((t) => t.name == 'tag_file');
      expect(tool.parameters['required'], containsAll(['uri', 'tag']));
    });

    test('get_metadata requires uri', () {
      final tool = agent.tools.firstWhere((t) => t.name == 'get_metadata');
      expect(tool.parameters['required'], contains('uri'));
    });

    test('create_smart_folder requires name and tags', () {
      final tool = agent.tools.firstWhere(
        (t) => t.name == 'create_smart_folder',
      );
      expect(tool.parameters['required'], containsAll(['name', 'tags']));
    });

    test('import_file requires path', () {
      final tool = agent.tools.firstWhere((t) => t.name == 'import_file');
      expect(tool.parameters['required'], contains('path'));
    });

    test('toFunctionSchema produces valid structure', () {
      final tool = agent.tools.first;
      final schema = tool.toFunctionSchema();
      expect(schema['type'], 'function');
      final fn = schema['function'] as Map<String, dynamic>;
      expect(fn, contains('name'));
      expect(fn, contains('description'));
      expect(fn, contains('parameters'));
    });
  });

  // ---------------------------------------------------------------------------
  // process() — error handling
  // ---------------------------------------------------------------------------

  group('process() error handling', () {
    test('returns error when LLM throws', () async {
      when(
        () => bundle.llm.stream(any()),
      ).thenThrow(Exception('Connection failed'));

      final message = AgentMessage.user(
        id: 'msg-err',
        timestamp: DateTime.now(),
        content: 'List files',
      );

      final response = await agent.process(message, bundle.context);

      expect(response, isA<StreamingAgentResponse>());
      await expectLater(
        (response as StreamingAgentResponse).events,
        emitsError(isA<Exception>()),
      );
    });
  });
}
