/// File agent — manages files and documents in the knowledge store.
///
/// Provides tools for listing, tagging, retrieving metadata, creating
/// smart folders, and importing files. Files are stored as
/// `schema:MediaObject` entities with Schema.org predicates and Kabuk
/// extensions for tags and folders.
library;

import 'package:kabuk/agents/base.dart';
import 'package:kabuk/agents/context.dart';
import 'package:kabuk/agents/llm.dart';
import 'package:kabuk/agents/memory.dart';
import 'package:kabuk/agents/messages.dart';
import 'package:kabuk/config/namespaces.dart';
import 'package:kabuk/services/vault.dart' show VaultEntry;

/// Kabuk-specific type URI for smart folders.
const String _kabukSmartFolder = '${NS.kabuk}SmartFolder';

/// Agent specialized in file and document management.
///
/// Handles listing, tagging, metadata retrieval, smart-folder creation,
/// and file import. All file entities live in the knowledge store as RDF
/// triples using `schema:MediaObject` (or subtypes) with Schema.org and
/// Kabuk predicates.
class FileAgent extends BaseAgent with AgentMemoryMixin {
  @override
  String get name => 'files';

  @override
  String get description =>
      'Manages files and documents — list, tag, inspect metadata, '
      'create smart folders, and import files.';

  @override
  String get systemPrompt => '''
You are the File agent for Kabuk. You manage the user's files and documents,
stored as schema:MediaObject entities in the knowledge store. Files are
encrypted in the Vault and indexed with metadata and tags.

Capabilities:
• List files — optionally filtered by tag or smart folder
• Add or remove tags on files for organization
• Retrieve full metadata for any file (size, type, dates, tags)
• Create smart folders — saved tag-based queries that auto-group files
• Import files from the device into Kabuk's encrypted vault

Usage Guidelines:
• When listing files, show filename, type, and tags if any
• Smart folders are like saved searches — e.g., a "Work" smart folder
shows all files tagged "work"
• When importing, confirm the file was added and mention its detected type
• Tags are the primary organization mechanism — encourage their use
• If the user asks about photos, images, videos, or documents, those are
all file types you manage
• Files are stored securely in the encrypted vault — reassure users about privacy
''';

  @override
  List<AgentTool> get tools => [
    AgentTool(
      name: 'list_files',
      description:
          'List files in the knowledge store, optionally filtered by tag '
          'or folder.',
      parameters: {
        'type': 'object',
        'properties': {
          'tag': {
            'type': 'string',
            'description': 'Only return files with this tag.',
          },
          'folder': {
            'type': 'string',
            'description': 'Only return files belonging to this folder URI.',
          },
          'limit': {
            'type': 'integer',
            'description': 'Maximum number of files to return (default 20).',
          },
        },
      },
      execute: _listFiles,
    ),
    AgentTool(
      name: 'tag_file',
      description: 'Add or remove a tag on a file entity.',
      parameters: {
        'type': 'object',
        'properties': {
          'uri': {
            'type': 'string',
            'description': 'The entity URI of the file.',
          },
          'tag': {'type': 'string', 'description': 'The tag to add or remove.'},
          'action': {
            'type': 'string',
            'enum': ['add', 'remove'],
            'description': 'Whether to add or remove the tag (default add).',
          },
        },
        'required': ['uri', 'tag'],
      },
      execute: _tagFile,
    ),
    AgentTool(
      name: 'get_metadata',
      description: 'Get full metadata of a file by its entity URI.',
      parameters: {
        'type': 'object',
        'properties': {
          'uri': {
            'type': 'string',
            'description': 'The entity URI of the file.',
          },
        },
        'required': ['uri'],
      },
      execute: _getMetadata,
    ),
    AgentTool(
      name: 'create_smart_folder',
      description: 'Create a named smart folder defined by a set of tags.',
      parameters: {
        'type': 'object',
        'properties': {
          'name': {
            'type': 'string',
            'description': 'Display name of the smart folder.',
          },
          'tags': {
            'type': 'array',
            'items': {'type': 'string'},
            'description':
                'Tags that define this folder — files matching all '
                'these tags appear in the folder.',
          },
        },
        'required': ['name', 'tags'],
      },
      execute: _createSmartFolder,
    ),
    AgentTool(
      name: 'import_file',
      description:
          'Import a file from a platform path into the vault and index '
          'it in the knowledge store.',
      parameters: {
        'type': 'object',
        'properties': {
          'path': {
            'type': 'string',
            'description': 'Platform-specific file path to import.',
          },
          'tags': {
            'type': 'array',
            'items': {'type': 'string'},
            'description': 'Optional tags to attach to the imported file.',
          },
        },
        'required': ['path'],
      },
      execute: _importFile,
    ),
  ];

  @override
  Set<AgentCapability> get requiredCapabilities => {
    AgentCapability.llmCall,
    AgentCapability.knowledgeRead,
    AgentCapability.knowledgeWrite,
    AgentCapability.vaultRead,
  };

  @override
  Future<AgentResponse> process(
    AgentMessage message,
    AgentContext context,
  ) async {
    final content = switch (message) {
      UserMessage(:final content) => content,
      SystemMessage(:final content) => content,
      _ => '',
    };

    if (content.isEmpty) {
      return const AgentResponse.text(
        'What would you like to do with your files?',
      );
    }

    // Include conversation history for multi-turn context.
    final llmMessages = <LlmMessage>[
      if (message case UserMessage(:final history?)) ...history,
      LlmMessage.user(content),
    ];

    final prompt = await buildSystemPromptWithMemory(context);
    return processLlmRequest(
      context: context,
      messages: llmMessages,
      systemPrompt: prompt,
      temperature: 0.5,
    );
  }

  // ---------------------------------------------------------------------------
  // Tool implementations
  // ---------------------------------------------------------------------------

  /// Lists files, optionally filtered by tag or folder.
  Future<ToolResult> _listFiles(
    Map<String, dynamic> args,
    AgentContext context,
  ) async {
    final tag = args['tag'] as String?;
    final folder = args['folder'] as String?;
    final limit = (args['limit'] as int?) ?? 20;

    // Start with all MediaObject entities.
    final query = context.knowledge
        .query()
        .predicate(NS.rdfType)
        .object(NS.schemaMediaObject)
        .limit(limit);

    final triples = await query.execute();

    if (triples.isEmpty) {
      return const ToolResult.text('No files found.');
    }

    final subjects = triples.map((t) => t.subject).toList();
    final entities = await context.knowledge.getEntities(subjects);

    final lines = <String>[];
    for (final triple in triples) {
      final entity = entities[triple.subject] ?? [];

      // Apply tag filter if specified.
      if (tag != null) {
        final hasTag = entity.any(
          (t) => t.predicate == NS.kabukTag && t.objectValue == tag,
        );
        if (!hasTag) continue;
      }

      // Apply folder filter if specified.
      if (folder != null) {
        final inFolder = entity.any(
          (t) => t.predicate == NS.kabukFolder && t.objectValue == folder,
        );
        if (!inFolder) continue;
      }

      final name = entity
          .where((t) => t.predicate == NS.schemaName)
          .firstOrNull
          ?.objectValue;
      final mime = entity
          .where((t) => t.predicate == NS.schemaEncodingFormat)
          .firstOrNull
          ?.objectValue;
      final size = entity
          .where((t) => t.predicate == NS.schemaContentSize)
          .firstOrNull
          ?.objectValue;
      final tags = entity
          .where((t) => t.predicate == NS.kabukTag)
          .map((t) => t.objectValue)
          .toList();

      final mimeText = mime != null ? ' ($mime)' : '';
      final sizeText = size != null
          ? ', ${_formatSize(int.tryParse(size))}'
          : '';
      final tagText = tags.isEmpty ? '' : ' [${tags.join(', ')}]';

      lines.add(
        '- **${name ?? 'Unnamed'}**$mimeText$sizeText$tagText\n'
        '  URI: `${triple.subject}`',
      );
    }

    if (lines.isEmpty) {
      final filterDesc = [
        if (tag != null) 'tag "$tag"',
        if (folder != null) 'folder "$folder"',
      ].join(' and ');
      return ToolResult.text('No files found matching $filterDesc.');
    }

    return ToolResult.text(
      'Found ${lines.length} file(s):\n${lines.join('\n')}',
    );
  }

  /// Adds or removes a tag on a file entity.
  Future<ToolResult> _tagFile(
    Map<String, dynamic> args,
    AgentContext context,
  ) async {
    final uri = args['uri'] as String?;
    if (uri == null || uri.isEmpty) {
      return const ToolResult.error('File URI is required.');
    }
    final tag = args['tag'] as String?;
    if (tag == null || tag.isEmpty) {
      return const ToolResult.error('Tag value is required.');
    }
    final action = (args['action'] as String?) ?? 'add';

    final entity = await context.knowledge.getEntity(uri);
    if (entity.isEmpty) {
      return ToolResult.error('File not found: $uri');
    }

    await context.knowledge.mutate((ctx) async {
      if (action == 'remove') {
        await ctx.remove(subject: uri, predicate: NS.kabukTag, object: tag);
      } else {
        await ctx.add(uri, NS.kabukTag, tag);
      }
      await ctx.set(
        uri,
        NS.schemaDateModified,
        DateTime.now().toIso8601String(),
      );
    });

    final verb = action == 'remove' ? 'Removed' : 'Added';
    return ToolResult.text('$verb tag "$tag" on file: $uri');
  }

  /// Returns full metadata for a file entity.
  Future<ToolResult> _getMetadata(
    Map<String, dynamic> args,
    AgentContext context,
  ) async {
    final uri = args['uri'] as String?;
    if (uri == null || uri.isEmpty) {
      return const ToolResult.error('File URI is required.');
    }

    final entity = await context.knowledge.getEntity(uri);
    if (entity.isEmpty) {
      return ToolResult.error('File not found: $uri');
    }

    final name = entity
        .where((t) => t.predicate == NS.schemaName)
        .firstOrNull
        ?.objectValue;
    final contentUrl = entity
        .where((t) => t.predicate == NS.schemaContentUrl)
        .firstOrNull
        ?.objectValue;
    final mime = entity
        .where((t) => t.predicate == NS.schemaEncodingFormat)
        .firstOrNull
        ?.objectValue;
    final size = entity
        .where((t) => t.predicate == NS.schemaContentSize)
        .firstOrNull
        ?.objectValue;
    final dateCreated = entity
        .where((t) => t.predicate == NS.schemaDateCreated)
        .firstOrNull
        ?.objectValue;
    final dateModified = entity
        .where((t) => t.predicate == NS.schemaDateModified)
        .firstOrNull
        ?.objectValue;
    final folder = entity
        .where((t) => t.predicate == NS.kabukFolder)
        .firstOrNull
        ?.objectValue;
    final tags = entity
        .where((t) => t.predicate == NS.kabukTag)
        .map((t) => t.objectValue)
        .toList();
    final rdfType = entity
        .where((t) => t.predicate == NS.rdfType)
        .firstOrNull
        ?.objectValue;

    final sizeFormatted = size != null
        ? _formatSize(int.tryParse(size))
        : 'unknown';
    final tagLine = tags.isEmpty ? 'none' : tags.join(', ');
    final folderLine = folder ?? 'none';

    return ToolResult.text('''
# ${name ?? 'Unnamed file'}
URI: $uri
Type: ${rdfType ?? 'unknown'}
MIME: ${mime ?? 'unknown'}
Size: $sizeFormatted
Content URL: ${contentUrl ?? 'N/A'}
Created: ${dateCreated ?? 'unknown'}
Modified: ${dateModified ?? 'unknown'}
Folder: $folderLine
Tags: $tagLine
''');
  }

  /// Creates a smart folder backed by a set of tags.
  Future<ToolResult> _createSmartFolder(
    Map<String, dynamic> args,
    AgentContext context,
  ) async {
    final folderName = args['name'] as String?;
    if (folderName == null || folderName.isEmpty) {
      return const ToolResult.error('Folder name is required.');
    }
    final tags = (args['tags'] as List<dynamic>?)?.cast<String>() ?? <String>[];
    if (tags.isEmpty) {
      return const ToolResult.error(
        'At least one tag is required to define a smart folder.',
      );
    }

    late final String entityUri;

    await context.knowledge.mutate((ctx) async {
      entityUri = ctx.create('SmartFolder');
      await ctx.set(entityUri, NS.rdfType, _kabukSmartFolder);
      await ctx.set(entityUri, NS.schemaName, folderName);
      await ctx.set(
        entityUri,
        NS.schemaDateCreated,
        DateTime.now().toIso8601String(),
      );
      for (final tag in tags) {
        await ctx.add(entityUri, NS.kabukTag, tag);
      }
    });

    return ToolResult.text(
      'Created smart folder "$folderName" '
      '(tags: ${tags.join(', ')})\nURI: $entityUri',
    );
  }

  /// Imports a file from a platform path into the vault and indexes it
  /// in the knowledge store.
  Future<ToolResult> _importFile(
    Map<String, dynamic> args,
    AgentContext context,
  ) async {
    final path = args['path'] as String?;
    if (path == null || path.isEmpty) {
      return const ToolResult.error('File path is required.');
    }
    final tags = (args['tags'] as List<dynamic>?)?.cast<String>() ?? <String>[];

    // Import the file into the vault.
    final VaultEntry entry;
    try {
      entry = await context.vault.importFromPath(path);
    } on Exception catch (e) {
      return ToolResult.error('Failed to import file: $e');
    }

    // Index the file in the knowledge store.
    late final String entityUri;

    await context.knowledge.mutate((ctx) async {
      entityUri = ctx.create('MediaObject');
      await ctx.set(entityUri, NS.rdfType, NS.schemaMediaObject);
      await ctx.set(entityUri, NS.schemaName, entry.name);
      await ctx.set(entityUri, NS.schemaContentUrl, entry.hash);
      await ctx.set(entityUri, NS.schemaEncodingFormat, entry.mimeType);
      await ctx.set(entityUri, NS.schemaContentSize, entry.size.toString());
      await ctx.set(
        entityUri,
        NS.schemaDateCreated,
        DateTime.now().toIso8601String(),
      );
      await ctx.set(
        entityUri,
        NS.schemaDateModified,
        DateTime.now().toIso8601String(),
      );
      for (final tag in tags) {
        await ctx.add(entityUri, NS.kabukTag, tag);
      }
    });

    final tagText = tags.isEmpty ? '' : ' (tags: ${tags.join(', ')})';
    return ToolResult.text(
      'Imported "${entry.name}" (${entry.mimeType}, '
      '${_formatSize(entry.size)})$tagText\n'
      'Vault hash: ${entry.hash}\n'
      'URI: $entityUri',
    );
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Formats a byte count into a human-readable string.
  static String _formatSize(int? bytes) {
    if (bytes == null) return 'unknown';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}
