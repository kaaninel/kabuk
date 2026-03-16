/// ContentBlock type helpers for the Kabuk knowledge store.
///
/// A ContentBlock is an individual piece of content within a document.
/// Blocks are ordered and linked to their parent document. The block-based
/// model enables Notion-style document editing where each paragraph,
/// image, code snippet, or media element is a discrete, reorderable unit.
library;

import 'package:kabuk/config/namespaces.dart';
import 'package:kabuk/knowledge/store.dart';
import 'package:kabuk/knowledge/triple.dart';
import 'package:meta/meta.dart';

/// The kind of content a block contains.
enum BlockType {
  /// A markdown text paragraph.
  text,

  /// A heading (H1, H2, or H3).
  heading,

  /// An image block with optional caption.
  image,

  /// A video block with optional caption.
  video,

  /// An audio block with optional caption.
  audio,

  /// A code block with optional language.
  code,

  /// A blockquote.
  quote,

  /// A horizontal divider.
  divider,

  /// A checklist/todo item.
  checklist,

  /// A callout/info box.
  callout,
}

/// Immutable representation of a content block within a document.
///
/// Each block has a [type], [order] for positioning, and type-specific
/// content fields. Use [ContentBlockData.fromTriples] to reconstruct
/// from the knowledge store.
@immutable
class ContentBlockData {
  /// Creates a [ContentBlockData] with explicit values.
  const ContentBlockData({
    required this.uri,
    required this.type,
    required this.order,
    required this.parentDocument,
    this.content,
    this.mediaUri,
    this.caption,
    this.language,
    this.checked,
    this.level,
    this.dateCreated,
    this.dateModified,
  });

  /// Constructs a [ContentBlockData] from a subject [uri] and its [triples].
  factory ContentBlockData.fromTriples(String uri, List<Triple> triples) {
    return ContentBlockData(
      uri: uri,
      type: _parseBlockType(
        triples
            .where((t) => t.predicate == NS.kabukBlockType)
            .firstOrNull
            ?.objectValue,
      ),
      order:
          int.tryParse(
            triples
                    .where((t) => t.predicate == NS.kabukBlockOrder)
                    .firstOrNull
                    ?.objectValue ??
                '',
          ) ??
          0,
      parentDocument:
          triples
              .where((t) => t.predicate == NS.kabukParentDocument)
              .firstOrNull
              ?.objectValue ??
          '',
      content: triples
          .where((t) => t.predicate == NS.kabukBlockContent)
          .firstOrNull
          ?.objectValue,
      mediaUri: triples
          .where((t) => t.predicate == NS.kabukBlockMediaUri)
          .firstOrNull
          ?.objectValue,
      caption: triples
          .where((t) => t.predicate == NS.kabukBlockCaption)
          .firstOrNull
          ?.objectValue,
      language: triples
          .where((t) => t.predicate == NS.kabukBlockLanguage)
          .firstOrNull
          ?.objectValue,
      checked: _tryParseBool(
        triples
            .where((t) => t.predicate == NS.kabukBlockChecked)
            .firstOrNull
            ?.objectValue,
      ),
      level: int.tryParse(
        triples
                .where((t) => t.predicate == NS.kabukBlockLevel)
                .firstOrNull
                ?.objectValue ??
            '',
      ),
      dateCreated: _tryParseDateTime(
        triples
            .where((t) => t.predicate == NS.schemaDateCreated)
            .firstOrNull
            ?.objectValue,
      ),
      dateModified: _tryParseDateTime(
        triples
            .where((t) => t.predicate == NS.schemaDateModified)
            .firstOrNull
            ?.objectValue,
      ),
    );
  }

  /// The entity URI (e.g. `kabuk:ContentBlock/<uuid>`).
  final String uri;

  /// The block type.
  final BlockType type;

  /// Sort order within the parent document (0-based).
  final int order;

  /// URI of the parent document this block belongs to.
  final String parentDocument;

  /// Primary text/markdown content (for text, heading, quote, callout, checklist).
  final String? content;

  /// URI of the associated media object (for image, video, audio blocks).
  final String? mediaUri;

  /// Optional caption for media blocks.
  final String? caption;

  /// Programming language for code blocks.
  final String? language;

  /// Whether a checklist item is checked.
  final bool? checked;

  /// Heading level (1, 2, or 3) for heading blocks.
  final int? level;

  /// When the block was created.
  final DateTime? dateCreated;

  /// When the block was last modified.
  final DateTime? dateModified;

  static BlockType _parseBlockType(String? value) => switch (value) {
    'text' => BlockType.text,
    'heading' => BlockType.heading,
    'image' => BlockType.image,
    'video' => BlockType.video,
    'audio' => BlockType.audio,
    'code' => BlockType.code,
    'quote' => BlockType.quote,
    'divider' => BlockType.divider,
    'checklist' => BlockType.checklist,
    'callout' => BlockType.callout,
    _ => BlockType.text,
  };

  static bool? _tryParseBool(String? value) => switch (value) {
    'true' => true,
    'false' => false,
    _ => null,
  };

  static DateTime? _tryParseDateTime(String? value) =>
      value == null ? null : DateTime.tryParse(value);
}

/// Convenience methods for working with ContentBlock entities.
extension KnowledgeStoreContentBlockExtension on KnowledgeStore {
  /// Creates a new content block within a document.
  ///
  /// Returns the URI of the newly created block.
  Future<String> createContentBlock({
    required String parentDocument,
    required BlockType type,
    required int order,
    String? content,
    String? mediaUri,
    String? caption,
    String? language,
    bool? checked,
    int? level,
  }) {
    return mutate((ctx) async {
      final uri = ctx.create('ContentBlock');
      await ctx.set(
        uri,
        NS.rdfType,
        NS.kabukContentBlock,
        objectType: ObjectType.uri,
      );
      await ctx.set(
        uri,
        NS.kabukParentDocument,
        parentDocument,
        objectType: ObjectType.uri,
      );
      await ctx.set(uri, NS.kabukBlockType, type.name);
      await ctx.set(
        uri,
        NS.kabukBlockOrder,
        order,
        objectType: ObjectType.integer,
      );

      if (content != null) {
        await ctx.set(uri, NS.kabukBlockContent, content);
      }
      if (mediaUri != null) {
        await ctx.set(
          uri,
          NS.kabukBlockMediaUri,
          mediaUri,
          objectType: ObjectType.uri,
        );
      }
      if (caption != null) {
        await ctx.set(uri, NS.kabukBlockCaption, caption);
      }
      if (language != null) {
        await ctx.set(uri, NS.kabukBlockLanguage, language);
      }
      if (checked != null) {
        await ctx.set(
          uri,
          NS.kabukBlockChecked,
          checked,
          objectType: ObjectType.boolean,
        );
      }
      if (level != null) {
        await ctx.set(
          uri,
          NS.kabukBlockLevel,
          level,
          objectType: ObjectType.integer,
        );
      }

      final now = DateTime.now().toIso8601String();
      await ctx.set(uri, NS.schemaDateCreated, now);
      await ctx.set(uri, NS.schemaDateModified, now);
      return uri;
    });
  }

  /// Updates a content block's content and modification timestamp.
  Future<void> updateContentBlock(
    String uri, {
    String? content,
    String? caption,
    String? language,
    bool? checked,
    int? level,
    int? order,
  }) {
    return mutate((ctx) async {
      if (content != null) {
        await ctx.set(uri, NS.kabukBlockContent, content);
      }
      if (caption != null) {
        await ctx.set(uri, NS.kabukBlockCaption, caption);
      }
      if (language != null) {
        await ctx.set(uri, NS.kabukBlockLanguage, language);
      }
      if (checked != null) {
        await ctx.set(
          uri,
          NS.kabukBlockChecked,
          checked,
          objectType: ObjectType.boolean,
        );
      }
      if (level != null) {
        await ctx.set(
          uri,
          NS.kabukBlockLevel,
          level,
          objectType: ObjectType.integer,
        );
      }
      if (order != null) {
        await ctx.set(
          uri,
          NS.kabukBlockOrder,
          order,
          objectType: ObjectType.integer,
        );
      }
      await ctx.set(
        uri,
        NS.schemaDateModified,
        DateTime.now().toIso8601String(),
      );
    });
  }

  /// Deletes a content block.
  Future<void> deleteContentBlock(String uri) {
    return mutate((ctx) async {
      await ctx.remove(subject: uri);
    });
  }

  /// Lists all content blocks for a document, ordered by [order].
  Future<List<ContentBlockData>> listDocumentBlocks(String documentUri) async {
    final triples = await query()
        .where(NS.kabukParentDocument, equals: documentUri)
        .execute();

    final blockUris = triples.map((t) => t.subject).toSet();
    final blocks = <ContentBlockData>[];

    for (final uri in blockUris) {
      final blockTriples = await getEntity(uri);
      if (blockTriples.isNotEmpty) {
        blocks.add(ContentBlockData.fromTriples(uri, blockTriples));
      }
    }

    blocks.sort((a, b) => a.order.compareTo(b.order));
    return blocks;
  }

  /// Reorders blocks by updating their order values.
  Future<void> reorderBlocks(List<String> blockUris) {
    return mutate((ctx) async {
      for (var i = 0; i < blockUris.length; i++) {
        await ctx.set(
          blockUris[i],
          NS.kabukBlockOrder,
          i,
          objectType: ObjectType.integer,
        );
        await ctx.set(
          blockUris[i],
          NS.schemaDateModified,
          DateTime.now().toIso8601String(),
        );
      }
    });
  }
}
