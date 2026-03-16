/// Nostr social interaction types for the Kabuk knowledge store.
///
/// Provides data classes for Nostr-specific social interactions:
/// reactions (NIP-25), replies (NIP-10), and reposts (NIP-18).
/// Also extends [KnowledgeStore] with convenience methods for
/// creating and querying Nostr content and interactions.
library;

import 'package:kabuk/config/namespaces.dart';
import 'package:kabuk/knowledge/store.dart';
import 'package:kabuk/knowledge/triple.dart';
import 'package:kabuk/services/nostr.dart';
import 'package:meta/meta.dart';

/// Social interaction counters cached from Nostr for a content item.
@immutable
class NostrSocialStats {
  /// Creates [NostrSocialStats] with the given counts.
  const NostrSocialStats({
    this.reactionCount = 0,
    this.replyCount = 0,
    this.repostCount = 0,
    this.userReacted = false,
    this.userReposted = false,
  });

  /// Number of reactions (NIP-25 kind 7) on this event.
  final int reactionCount;

  /// Number of replies to this event.
  final int replyCount;

  /// Number of reposts (NIP-18 kind 6) of this event.
  final int repostCount;

  /// Whether the current user has reacted to this event.
  final bool userReacted;

  /// Whether the current user has reposted this event.
  final bool userReposted;
}

/// Immutable representation of a Nostr text note (kind 1).
///
/// Stored as a `kabuk:NostrNote` entity in the knowledge store,
/// linked to the original Nostr event via [nostrEventId] and [nostrPubkey].
@immutable
class NostrNoteData {
  /// Creates a [NostrNoteData] with the given field values.
  const NostrNoteData({
    required this.uri,
    this.content,
    this.authorPubkey,
    this.authorName,
    this.authorPicture,
    this.nostrEventId,
    this.datePublished,
    this.image,
    this.replyToEventId,
    this.stats = const NostrSocialStats(),
    this.tags = const [],
  });

  /// Constructs a [NostrNoteData] from a subject [uri] and its [triples].
  factory NostrNoteData.fromTriples(String uri, List<Triple> triples) {
    return NostrNoteData(
      uri: uri,
      content: triples
          .where((t) => t.predicate == NS.schemaText)
          .firstOrNull
          ?.objectValue,
      authorPubkey: triples
          .where((t) => t.predicate == NS.kabukNostrPubkey)
          .firstOrNull
          ?.objectValue,
      authorName: triples
          .where((t) => t.predicate == NS.schemaAuthor)
          .firstOrNull
          ?.objectValue,
      authorPicture: triples
          .where((t) => t.predicate == NS.schemaImage)
          .firstOrNull
          ?.objectValue,
      nostrEventId: triples
          .where((t) => t.predicate == NS.kabukNostrEventId)
          .firstOrNull
          ?.objectValue,
      datePublished: _tryParseDateTime(
        triples
            .where((t) => t.predicate == NS.schemaDatePublished)
            .firstOrNull
            ?.objectValue,
      ),
      image: triples
          .where((t) => t.predicate == NS.schemaThumbnail)
          .firstOrNull
          ?.objectValue,
      replyToEventId: triples
          .where((t) => t.predicate == NS.kabukConversation)
          .firstOrNull
          ?.objectValue,
      stats: NostrSocialStats(
        reactionCount:
            int.tryParse(
              triples
                      .where((t) => t.predicate == NS.kabukNostrReactionCount)
                      .firstOrNull
                      ?.objectValue ??
                  '',
            ) ??
            0,
        replyCount:
            int.tryParse(
              triples
                      .where((t) => t.predicate == NS.kabukNostrReplyCount)
                      .firstOrNull
                      ?.objectValue ??
                  '',
            ) ??
            0,
        repostCount:
            int.tryParse(
              triples
                      .where((t) => t.predicate == NS.kabukNostrRepostCount)
                      .firstOrNull
                      ?.objectValue ??
                  '',
            ) ??
            0,
        userReacted:
            triples
                .where((t) => t.predicate == NS.kabukNostrUserReacted)
                .firstOrNull
                ?.objectValue ==
            'true',
        userReposted:
            triples
                .where((t) => t.predicate == NS.kabukNostrUserReposted)
                .firstOrNull
                ?.objectValue ==
            'true',
      ),
      tags: triples
          .where((t) => t.predicate == NS.kabukTag)
          .map((t) => t.objectValue)
          .toList(),
    );
  }

  /// The entity URI (e.g. `kabuk:NostrNote/<uuid>`).
  final String uri;

  /// The text content of the note.
  final String? content;

  /// The Nostr public key (hex) of the author.
  final String? authorPubkey;

  /// Cached display name of the author.
  final String? authorName;

  /// Cached profile picture URL of the author.
  final String? authorPicture;

  /// The Nostr event ID (hex) of this note.
  final String? nostrEventId;

  /// When the note was published.
  final DateTime? datePublished;

  /// An image URL embedded in or attached to the note.
  final String? image;

  /// If this is a reply, the event ID it replies to.
  final String? replyToEventId;

  /// Cached social interaction stats.
  final NostrSocialStats stats;

  /// User-assigned tags.
  final List<String> tags;

  static DateTime? _tryParseDateTime(String? value) =>
      value == null ? null : DateTime.tryParse(value);
}

/// Convenience methods for Nostr social data in the knowledge store.
extension KnowledgeStoreNostrExtension on KnowledgeStore {
  /// Creates a Nostr note entity from a [NostrEvent] of kind 1.
  ///
  /// Extracts content, author, and timestamp from the event.
  /// Optionally stores resolved [authorName] and [authorPicture].
  Future<String> createNostrNote({
    required NostrEvent event,
    String? authorName,
    String? authorPicture,
  }) {
    return mutate((ctx) async {
      final uri = ctx.create('NostrNote');
      await ctx.set(
        uri,
        NS.rdfType,
        NS.kabukNostrNote,
        objectType: ObjectType.uri,
      );
      await ctx.set(uri, NS.schemaText, event.content);
      await ctx.set(uri, NS.kabukNostrEventId, event.id);
      await ctx.set(uri, NS.kabukNostrPubkey, event.pubkey);

      if (authorName != null) {
        await ctx.set(uri, NS.schemaAuthor, authorName);
      }
      if (authorPicture != null) {
        await ctx.set(uri, NS.schemaImage, authorPicture);
      }

      // Extract image URLs from content.
      final imageUrl = _extractImageUrl(event.content);
      if (imageUrl != null) {
        await ctx.set(uri, NS.schemaThumbnail, imageUrl);
      }

      // Check if this is a reply (has 'e' tag).
      for (final tag in event.tags) {
        if (tag.isNotEmpty && tag[0] == 'e' && tag.length >= 2) {
          // NIP-10: last 'e' tag with marker 'reply' or unmarked is the reply target.
          final marker = tag.length >= 4 ? tag[3] : null;
          if (marker == 'reply' || marker == null) {
            await ctx.set(uri, NS.kabukConversation, tag[1]);
          }
        }
        // Store hashtags.
        if (tag.isNotEmpty && tag[0] == 't' && tag.length >= 2) {
          await ctx.add(uri, NS.kabukTag, tag[1]);
        }
      }

      final pubDate = DateTime.fromMillisecondsSinceEpoch(
        event.createdAt * 1000,
      ).toIso8601String();
      await ctx.set(uri, NS.schemaDatePublished, pubDate);
      await ctx.set(
        uri,
        NS.schemaDateCreated,
        DateTime.now().toIso8601String(),
      );

      // Initialize social counters.
      await ctx.set(uri, NS.kabukNostrReactionCount, '0');
      await ctx.set(uri, NS.kabukNostrReplyCount, '0');
      await ctx.set(uri, NS.kabukNostrRepostCount, '0');
      await ctx.set(uri, NS.kabukNostrUserReacted, 'false');
      await ctx.set(uri, NS.kabukNostrUserReposted, 'false');

      return uri;
    });
  }

  /// Finds a Nostr note entity by its Nostr event ID.
  Future<NostrNoteData?> findNostrNoteByEventId(String eventId) async {
    final triples = await query()
        .where(NS.kabukNostrEventId, equals: eventId)
        .limit(1)
        .execute();
    if (triples.isEmpty) return null;
    final uri = triples.first.subject;
    final entity = await getEntity(uri);
    return NostrNoteData.fromTriples(uri, entity);
  }

  /// Lists Nostr notes ordered by most recently published.
  Future<List<NostrNoteData>> listNostrNotes({
    int limit = 50,
    String? authorPubkey,
  }) async {
    var q = query()
        .where(NS.rdfType, equals: NS.kabukNostrNote)
        .orderBy(NS.schemaDatePublished, descending: true)
        .limit(limit);

    if (authorPubkey != null) {
      q = q.where(NS.kabukNostrPubkey, equals: authorPubkey);
    }

    final typeTriples = await q.execute();
    final uris = typeTriples.map((t) => t.subject).toSet();
    final notes = <NostrNoteData>[];
    for (final uri in uris) {
      final triples = await getEntity(uri);
      notes.add(NostrNoteData.fromTriples(uri, triples));
    }
    return notes;
  }

  /// Updates the cached social stats for a Nostr note.
  Future<void> updateNostrStats(
    String noteUri, {
    int? reactionCount,
    int? replyCount,
    int? repostCount,
    bool? userReacted,
    bool? userReposted,
  }) {
    return mutate((ctx) async {
      if (reactionCount != null) {
        await ctx.set(
          noteUri,
          NS.kabukNostrReactionCount,
          reactionCount.toString(),
        );
      }
      if (replyCount != null) {
        await ctx.set(noteUri, NS.kabukNostrReplyCount, replyCount.toString());
      }
      if (repostCount != null) {
        await ctx.set(
          noteUri,
          NS.kabukNostrRepostCount,
          repostCount.toString(),
        );
      }
      if (userReacted != null) {
        await ctx.set(
          noteUri,
          NS.kabukNostrUserReacted,
          userReacted.toString(),
        );
      }
      if (userReposted != null) {
        await ctx.set(
          noteUri,
          NS.kabukNostrUserReposted,
          userReposted.toString(),
        );
      }
    });
  }

  /// Links an existing article to a Nostr event for social interactions.
  ///
  /// This allows any feed content (RSS, Reddit) to be shared on Nostr
  /// and receive reactions/comments from the Nostr network.
  Future<void> linkArticleToNostr(
    String articleUri, {
    required String nostrEventId,
    String? nostrPubkey,
  }) {
    return mutate((ctx) async {
      await ctx.set(articleUri, NS.kabukNostrEventId, nostrEventId);
      if (nostrPubkey != null) {
        await ctx.set(articleUri, NS.kabukNostrPubkey, nostrPubkey);
      }
      // Initialize social counters on the article.
      await ctx.set(articleUri, NS.kabukNostrReactionCount, '0');
      await ctx.set(articleUri, NS.kabukNostrReplyCount, '0');
      await ctx.set(articleUri, NS.kabukNostrRepostCount, '0');
      await ctx.set(articleUri, NS.kabukNostrUserReacted, 'false');
      await ctx.set(articleUri, NS.kabukNostrUserReposted, 'false');
    });
  }

  /// Gets the Nostr event ID linked to an article, if any.
  Future<String?> getNostrEventId(String entityUri) async {
    final triples = await getEntity(entityUri);
    return triples
        .where((t) => t.predicate == NS.kabukNostrEventId)
        .firstOrNull
        ?.objectValue;
  }
}

/// Extracts the first image URL from note content.
String? _extractImageUrl(String content) {
  final match = RegExp(
    r'https?://\S+\.(?:jpg|jpeg|png|gif|webp|svg)',
    caseSensitive: false,
  ).firstMatch(content);
  return match?.group(0);
}
