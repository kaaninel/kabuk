/// Schema.org-based FollowedUser type helpers for the Kabuk knowledge store.
///
/// Provides [FollowedUserData] for structured access to followed accounts
/// (Reddit users, RSS authors, etc.), plus [KnowledgeStoreFollowExtension]
/// convenience methods on [KnowledgeStore].
library;

import 'package:kabuk/config/namespaces.dart';
import 'package:kabuk/knowledge/store.dart';
import 'package:kabuk/knowledge/triple.dart';
import 'package:meta/meta.dart';

/// Immutable representation of a followed user/account.
@immutable
class FollowedUserData {
  /// Creates a [FollowedUserData] with the given field values.
  const FollowedUserData({
    required this.uri,
    this.name,
    this.profileUrl,
    this.followedAt,
  });

  /// Constructs a [FollowedUserData] from a subject [uri] and its [triples].
  factory FollowedUserData.fromTriples(String uri, List<Triple> triples) {
    return FollowedUserData(
      uri: uri,
      name: triples
          .where((t) => t.predicate == NS.schemaName)
          .firstOrNull
          ?.objectValue,
      profileUrl: triples
          .where((t) => t.predicate == NS.kabukProfileUrl)
          .firstOrNull
          ?.objectValue,
      followedAt: _tryParseDateTime(
        triples
            .where((t) => t.predicate == NS.kabukFollowedAt)
            .firstOrNull
            ?.objectValue,
      ),
    );
  }

  /// The entity URI (e.g. `kabuk:FollowedUser/<uuid>`).
  final String uri;

  /// Display name of the followed user (`schema:name`).
  final String? name;

  /// URL of the user's profile page (`kabuk:profileUrl`).
  final String? profileUrl;

  /// When the follow was created (`kabuk:followedAt`).
  final DateTime? followedAt;

  static DateTime? _tryParseDateTime(String? v) =>
      v == null ? null : DateTime.tryParse(v);
}

// =============================================================================
// KnowledgeStore extension
// =============================================================================

/// Extension methods for managing followed users in [KnowledgeStore].
extension KnowledgeStoreFollowExtension on KnowledgeStore {
  /// Creates a new FollowedUser entity and returns its URI.
  Future<String> createFollowedUser({
    required String name,
    String? profileUrl,
  }) {
    return mutate((ctx) async {
      final uri = ctx.create('FollowedUser');
      await ctx.set(
        uri,
        NS.rdfType,
        NS.kabukFollowedUser,
        objectType: ObjectType.uri,
      );
      await ctx.set(uri, NS.schemaName, name);
      await ctx.set(
        uri,
        NS.kabukFollowedAt,
        DateTime.now().toUtc().toIso8601String(),
      );
      if (profileUrl != null && profileUrl.isNotEmpty) {
        await ctx.set(uri, NS.kabukProfileUrl, profileUrl);
      }
      return uri;
    });
  }

  /// Returns all followed user entities, sorted by follow date (newest first).
  Future<List<FollowedUserData>> listFollowedUsers() async {
    final typeTriples = await query()
        .where(NS.rdfType, equals: NS.kabukFollowedUser)
        .execute();

    final uris = typeTriples.map((t) => t.subject).toSet().toList();
    if (uris.isEmpty) return [];
    final allTriples = await getEntities(uris);
    final results = <FollowedUserData>[];
    for (final uri in uris) {
      final triples = allTriples[uri];
      if (triples != null && triples.isNotEmpty) {
        results.add(FollowedUserData.fromTriples(uri, triples));
      }
    }

    results.sort((a, b) {
      final aDate = a.followedAt ?? DateTime(2000);
      final bDate = b.followedAt ?? DateTime(2000);
      return bDate.compareTo(aDate);
    });

    return results;
  }

  /// Returns `true` if a user with the given [profileUrl] is followed.
  Future<bool> isFollowing(String profileUrl) async {
    final matches = await query()
        .where(NS.kabukProfileUrl, equals: profileUrl)
        .execute();
    return matches.isNotEmpty;
  }

  /// Returns the entity URI of the followed user matching [profileUrl], or
  /// `null` if not followed.
  Future<String?> followedUriFor(String profileUrl) async {
    final matches = await query()
        .where(NS.kabukProfileUrl, equals: profileUrl)
        .execute();
    return matches.firstOrNull?.subject;
  }

  /// Removes the followed user entity with the given [uri].
  Future<void> unfollowUser(String uri) {
    return mutate((ctx) async => ctx.remove(subject: uri));
  }
}
