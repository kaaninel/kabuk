/// Schema.org Comment type helpers for the Kabuk knowledge store.
///
/// Provides [CommentData] for structured access to article comments
/// (e.g. Reddit threads), plus [KnowledgeStoreCommentExtension] convenience
/// methods on [KnowledgeStore].
///
/// Comment hierarchy is modelled with two predicates:
/// - `kabuk:parentArticle` — links a top-level comment to its article.
/// - `kabuk:parentComment` — links a reply to its direct parent comment.
library;

import 'package:kabuk/config/namespaces.dart';
import 'package:kabuk/knowledge/store.dart';
import 'package:kabuk/knowledge/triple.dart';
import 'package:meta/meta.dart';

/// Immutable representation of a Schema.org `Comment` entity.
@immutable
class CommentData {
  /// Creates a [CommentData] with the given field values.
  const CommentData({
    required this.uri,
    this.text,
    this.author,
    this.parentArticleUri,
    this.parentCommentUri,
    this.datePublished,
    this.score,
    this.depth = 0,
  });

  /// Constructs a [CommentData] from a subject [uri] and its [triples].
  factory CommentData.fromTriples(String uri, List<Triple> triples) {
    return CommentData(
      uri: uri,
      text: triples
          .where((t) => t.predicate == NS.schemaText)
          .firstOrNull
          ?.objectValue,
      author: triples
          .where((t) => t.predicate == NS.schemaAuthor)
          .firstOrNull
          ?.objectValue,
      parentArticleUri: triples
          .where((t) => t.predicate == NS.kabukParentArticle)
          .firstOrNull
          ?.objectValue,
      parentCommentUri: triples
          .where((t) => t.predicate == NS.kabukParentComment)
          .firstOrNull
          ?.objectValue,
      datePublished: _tryParseDateTime(
        triples
            .where((t) => t.predicate == NS.schemaDatePublished)
            .firstOrNull
            ?.objectValue,
      ),
      score: _tryParseInt(
        triples
            .where((t) => t.predicate == NS.kabukScore)
            .firstOrNull
            ?.objectValue,
      ),
      depth:
          _tryParseInt(
            triples
                .where((t) => t.predicate == NS.kabukCommentDepth)
                .firstOrNull
                ?.objectValue,
          ) ??
          0,
    );
  }

  /// The entity URI (e.g. `kabuk:Comment/<uuid>`).
  final String uri;

  /// Comment body text (`schema:text`).
  final String? text;

  /// Display name of the comment author (`schema:author`).
  final String? author;

  /// URI of the article this comment belongs to (`kabuk:parentArticle`).
  final String? parentArticleUri;

  /// URI of the parent comment for replies (`kabuk:parentComment`).
  ///
  /// `null` for top-level comments.
  final String? parentCommentUri;

  /// When the comment was posted (`schema:datePublished`).
  final DateTime? datePublished;

  /// Upvote score (`kabuk:score`).
  final int? score;

  /// Nesting depth — 0 for top-level, 1 for first-level replies, etc.
  final int depth;

  /// Whether this is a top-level comment (no parent comment).
  bool get isTopLevel => parentCommentUri == null;

  static DateTime? _tryParseDateTime(String? v) =>
      v == null ? null : DateTime.tryParse(v);

  static int? _tryParseInt(String? v) => v == null ? null : int.tryParse(v);
}

// =============================================================================
// KnowledgeStore extension
// =============================================================================

/// Extension methods for managing comments in [KnowledgeStore].
extension KnowledgeStoreCommentExtension on KnowledgeStore {
  /// Creates a new `schema:Comment` entity and returns its URI.
  ///
  /// At minimum, [text] and [parentArticleUri] must be provided.
  /// For replies, also pass [parentCommentUri] and [depth].
  Future<String> createComment({
    required String text,
    required String parentArticleUri,
    String? author,
    String? parentCommentUri,
    DateTime? datePublished,
    int? score,
    int depth = 0,
  }) {
    return mutate((ctx) async {
      final uri = ctx.create('Comment');
      await ctx.set(
        uri,
        NS.rdfType,
        NS.schemaCommentEntity,
        objectType: ObjectType.uri,
      );
      await ctx.set(uri, NS.schemaText, text);
      await ctx.set(
        uri,
        NS.kabukParentArticle,
        parentArticleUri,
        objectType: ObjectType.uri,
      );
      if (author != null) {
        await ctx.set(uri, NS.schemaAuthor, author);
      }
      if (parentCommentUri != null) {
        await ctx.set(
          uri,
          NS.kabukParentComment,
          parentCommentUri,
          objectType: ObjectType.uri,
        );
      }
      if (datePublished != null) {
        await ctx.set(
          uri,
          NS.schemaDatePublished,
          datePublished.toUtc().toIso8601String(),
        );
      }
      if (score != null) {
        await ctx.set(uri, NS.kabukScore, score.toString());
      }
      if (depth > 0) {
        await ctx.set(uri, NS.kabukCommentDepth, depth.toString());
      }
      return uri;
    });
  }

  /// Returns all top-level comments for [articleUri], sorted by score desc.
  Future<List<CommentData>> listCommentsForArticle(
    String articleUri, {
    int limit = 200,
  }) async {
    final typeTriples = await query()
        .where(NS.kabukParentArticle, equals: articleUri)
        .limit(limit)
        .execute();

    final results = <CommentData>[];
    for (final t in typeTriples) {
      final triples = await getEntity(t.subject);
      results.add(CommentData.fromTriples(t.subject, triples));
    }

    // Top-level first, then sort by score descending.
    results.sort((a, b) {
      if (a.depth != b.depth) return a.depth.compareTo(b.depth);
      final as_ = a.score ?? 0;
      final bs_ = b.score ?? 0;
      return bs_.compareTo(as_);
    });

    return results;
  }

  /// Returns all direct replies to a comment identified by [commentUri].
  Future<List<CommentData>> listReplies(String commentUri) async {
    final typeTriples = await query()
        .where(NS.kabukParentComment, equals: commentUri)
        .execute();

    final results = <CommentData>[];
    for (final t in typeTriples) {
      final triples = await getEntity(t.subject);
      results.add(CommentData.fromTriples(t.subject, triples));
    }

    results.sort((a, b) {
      final as_ = a.score ?? 0;
      final bs_ = b.score ?? 0;
      return bs_.compareTo(as_);
    });

    return results;
  }

  /// Deletes all comments associated with [articleUri].
  ///
  /// Useful when pruning stale article data.
  Future<void> deleteCommentsForArticle(String articleUri) async {
    final typeTriples = await query()
        .where(NS.kabukParentArticle, equals: articleUri)
        .execute();
    if (typeTriples.isEmpty) return;
    await mutate((ctx) async {
      for (final t in typeTriples) {
        await ctx.remove(subject: t.subject);
      }
    });
  }
}
