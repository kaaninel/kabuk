/// Schema.org Person type helpers for the Kabuk knowledge store.
///
/// Provides [PersonData] for structured access to Person entities, plus
/// [KnowledgeStorePersonExtension] convenience methods on [KnowledgeStore].
///
/// People can have multiple labeled Nostr keys (e.g. "personal", "work").
/// The legacy single `kabukNostrPubkey` predicate is still read for backwards
/// compatibility; new entries are stored under `kabukNostrKeyEntry`.
library;

import 'package:kabuk/config/namespaces.dart';
import 'package:kabuk/knowledge/store.dart';
import 'package:kabuk/knowledge/triple.dart';
import 'package:meta/meta.dart';

// ---------------------------------------------------------------------------
// NostrKeyEntry
// ---------------------------------------------------------------------------

/// A single labeled Nostr public key belonging to a [PersonData].
///
/// People may have multiple Nostr identities (e.g. "personal" and "work").
/// Each is stored as a `kabuk:nostrKeyEntry` triple with the object value
/// `{pubkeyHex}:{label}` (colon-separated; label may be empty).
@immutable
class NostrKeyEntry {
  /// Creates a [NostrKeyEntry].
  const NostrKeyEntry({required this.pubkey, this.label = ''});

  /// Parses from the raw triple object string `{pubkeyHex}:{label}`.
  ///
  /// Pubkeys are always 64 hex chars, so the separator is at index 64.
  factory NostrKeyEntry.fromRaw(String raw) {
    if (raw.length > 65 && raw[64] == ':') {
      return NostrKeyEntry(
        pubkey: raw.substring(0, 64),
        label: raw.substring(65),
      );
    }
    // No label — the whole string is just a pubkey.
    return NostrKeyEntry(pubkey: raw);
  }

  /// Serializes to the raw triple object string used for storage.
  String toRaw() => label.isNotEmpty ? '$pubkey:$label' : pubkey;

  /// The 64-char hex Nostr public key.
  final String pubkey;

  /// User-supplied label (e.g. "personal", "work"). Empty means default.
  final String label;

  /// Display label — falls back to "Default" when empty.
  String get displayLabel => label.isNotEmpty ? label : 'Default';

  @override
  bool operator ==(Object other) =>
      other is NostrKeyEntry && other.pubkey == pubkey;

  @override
  int get hashCode => pubkey.hashCode;
}

// ---------------------------------------------------------------------------
// PersonData
// ---------------------------------------------------------------------------

/// Immutable representation of a Schema.org Person entity.
///
/// All fields are extracted from the underlying RDF triples.
/// Use [PersonData.fromTriples] to construct from raw store data,
/// or the [KnowledgeStorePersonExtension] helpers for high-level access.
@immutable
class PersonData {
  /// Creates a [PersonData] with the given field values.
  const PersonData({
    required this.uri,
    this.name,
    this.givenName,
    this.familyName,
    this.email,
    this.telephone,
    this.description,
    this.nostrKeys = const [],
  });

  /// Constructs a [PersonData] from a subject [uri] and its [triples].
  ///
  /// Reads both the new `kabukNostrKeyEntry` multi-key format and the legacy
  /// `kabukNostrPubkey` single-key format, deduplicating by pubkey.
  factory PersonData.fromTriples(String uri, List<Triple> triples) {
    final seenPubkeys = <String>{};
    final keys = <NostrKeyEntry>[];

    // New multi-key format.
    for (final t in triples.where(
      (t) => t.predicate == NS.kabukNostrKeyEntry,
    )) {
      final raw = t.objectValue;
      if (raw.isNotEmpty) {
        final entry = NostrKeyEntry.fromRaw(raw);
        if (seenPubkeys.add(entry.pubkey)) keys.add(entry);
      }
    }

    // Legacy single-key format — still readable for older data.
    for (final t in triples.where((t) => t.predicate == NS.kabukNostrPubkey)) {
      final raw = t.objectValue;
      if (raw.isNotEmpty && seenPubkeys.add(raw)) {
        keys.add(NostrKeyEntry(pubkey: raw));
      }
    }

    return PersonData(
      uri: uri,
      name: triples
          .where((t) => t.predicate == NS.schemaName)
          .firstOrNull
          ?.objectValue,
      givenName: triples
          .where((t) => t.predicate == NS.schemaGivenName)
          .firstOrNull
          ?.objectValue,
      familyName: triples
          .where((t) => t.predicate == NS.schemaFamilyName)
          .firstOrNull
          ?.objectValue,
      email: triples
          .where((t) => t.predicate == NS.schemaEmail)
          .firstOrNull
          ?.objectValue,
      telephone: triples
          .where((t) => t.predicate == NS.schemaTelephone)
          .firstOrNull
          ?.objectValue,
      description: triples
          .where((t) => t.predicate == NS.schemaDescription)
          .firstOrNull
          ?.objectValue,
      nostrKeys: keys,
    );
  }

  /// The entity URI (e.g. `kabuk:Person/<uuid>`).
  final String uri;

  /// The full display name (`schema:name`).
  final String? name;

  /// The given (first) name (`schema:givenName`).
  final String? givenName;

  /// The family (last) name (`schema:familyName`).
  final String? familyName;

  /// Email address (`schema:email`).
  final String? email;

  /// Phone number (`schema:telephone`).
  final String? telephone;

  /// A free-text description (`schema:description`).
  final String? description;

  /// All Nostr key entries (labeled identities) for this person.
  ///
  /// Includes both new `kabukNostrKeyEntry` entries and the legacy
  /// `kabukNostrPubkey` value, deduped by pubkey. Order is preserved.
  final List<NostrKeyEntry> nostrKeys;

  // ── Convenience ──────────────────────────────────────────────────────────

  /// Primary (first) Nostr pubkey, or `null` if none.
  ///
  /// Kept for backward compatibility with single-key callers.
  String? get nostrPubkey =>
      nostrKeys.isNotEmpty ? nostrKeys.first.pubkey : null;

  /// Whether this person has at least one Nostr key configured.
  bool get hasNostrKeys => nostrKeys.isNotEmpty;

  /// Returns the [NostrKeyEntry] for [pubkey], or `null` if not found.
  NostrKeyEntry? keyFor(String pubkey) {
    for (final k in nostrKeys) {
      if (k.pubkey == pubkey) return k;
    }
    return null;
  }
}

// ---------------------------------------------------------------------------
// Extension methods
// ---------------------------------------------------------------------------

/// Convenience methods for working with Person entities in the knowledge store.
extension KnowledgeStorePersonExtension on KnowledgeStore {
  /// Creates a new Person entity and returns its URI.
  ///
  /// [nostrPubkey] adds an initial Nostr key with [nostrLabel] (optional).
  Future<String> createPerson({
    String? name,
    String? givenName,
    String? familyName,
    String? email,
    String? telephone,
    String? description,
    String? nostrPubkey,
    String? nostrLabel,
  }) {
    return mutate((ctx) async {
      final uri = ctx.create('Person');
      await ctx.set(
        uri,
        NS.rdfType,
        NS.schemaPerson,
        objectType: ObjectType.uri,
      );

      final displayName =
          name ??
          _buildDisplayName(givenName: givenName, familyName: familyName);
      if (displayName != null) await ctx.set(uri, NS.schemaName, displayName);
      if (givenName != null) await ctx.set(uri, NS.schemaGivenName, givenName);
      if (familyName != null) {
        await ctx.set(uri, NS.schemaFamilyName, familyName);
      }
      if (email != null) await ctx.set(uri, NS.schemaEmail, email);
      if (telephone != null) await ctx.set(uri, NS.schemaTelephone, telephone);
      if (description != null) {
        await ctx.set(uri, NS.schemaDescription, description);
      }
      if (nostrPubkey != null) {
        final entry = NostrKeyEntry(
          pubkey: nostrPubkey,
          label: nostrLabel ?? '',
        );
        await ctx.add(uri, NS.kabukNostrKeyEntry, entry.toRaw());
      }
      return uri;
    });
  }

  /// Updates mutable scalar fields of an existing Person entity.
  Future<void> updatePerson(
    String uri, {
    String? name,
    String? email,
    String? telephone,
    String? description,
  }) {
    return mutate((ctx) async {
      if (name != null) await ctx.set(uri, NS.schemaName, name);
      if (email != null) await ctx.set(uri, NS.schemaEmail, email);
      if (telephone != null) {
        await ctx.set(uri, NS.schemaTelephone, telephone);
      }
      if (description != null) {
        await ctx.set(uri, NS.schemaDescription, description);
      }
    });
  }

  /// Adds or updates a Nostr identity for an existing Person entity.
  ///
  /// If a key with the same [pubkey] already exists its label is updated.
  Future<void> addPersonNostrKey(
    String personUri, {
    required String pubkey,
    String label = '',
  }) async {
    // Remove any existing entry for this pubkey (de-duplicate).
    await removePersonNostrKey(personUri, pubkey: pubkey);
    await mutate((ctx) async {
      final entry = NostrKeyEntry(pubkey: pubkey, label: label);
      await ctx.add(personUri, NS.kabukNostrKeyEntry, entry.toRaw());
    });
  }

  /// Removes the Nostr identity with [pubkey] from a Person entity.
  ///
  /// Handles both new-format (`kabukNostrKeyEntry`) and legacy
  /// (`kabukNostrPubkey`) entries.
  Future<void> removePersonNostrKey(
    String personUri, {
    required String pubkey,
  }) async {
    final existing = await getEntity(personUri);

    // Remove new-format entries where object starts with the pubkey.
    for (final t in existing.where(
      (t) => t.predicate == NS.kabukNostrKeyEntry,
    )) {
      final raw = t.objectValue;
      if (raw == pubkey || raw.startsWith('$pubkey:')) {
        await mutate(
          (ctx) => ctx.remove(
            subject: personUri,
            predicate: NS.kabukNostrKeyEntry,
            object: raw,
          ),
        );
      }
    }

    // Remove legacy single-key entry if it matches.
    for (final t in existing.where(
      (t) => t.predicate == NS.kabukNostrPubkey && t.objectValue == pubkey,
    )) {
      await mutate(
        (ctx) => ctx.remove(
          subject: personUri,
          predicate: NS.kabukNostrPubkey,
          object: t.objectValue,
        ),
      );
    }
  }

  /// Finds the [PersonData] whose Nostr keys include [pubkeyHex].
  ///
  /// Checks both the new `kabukNostrKeyEntry` and legacy `kabukNostrPubkey`
  /// predicates. Returns the first match, or `null`.
  Future<PersonData?> findPersonByNostrPubkey(String pubkeyHex) async {
    // Search new-format: object string contains pubkeyHex as a prefix.
    // The `contains` filter uses LIKE '%pubkey%'; we then do an exact prefix
    // check in Dart to avoid false positives.
    final newEntries = await query()
        .where(NS.kabukNostrKeyEntry, contains: pubkeyHex)
        .execute();
    for (final t in newEntries) {
      final raw = t.objectValue;
      if (raw == pubkeyHex || raw.startsWith('$pubkeyHex:')) {
        final triples = await getEntity(t.subject);
        return PersonData.fromTriples(t.subject, triples);
      }
    }

    // Fall back to legacy single-key format.
    final legacyEntries = await query()
        .where(NS.kabukNostrPubkey, equals: pubkeyHex)
        .execute();
    if (legacyEntries.isNotEmpty) {
      final triples = await getEntity(legacyEntries.first.subject);
      return PersonData.fromTriples(legacyEntries.first.subject, triples);
    }

    return null;
  }

  /// Retrieves a single Person by [uri], or `null` if not found.
  Future<PersonData?> getPersonData(String uri) async {
    final triples = await getEntity(uri);
    if (triples.isEmpty) return null;
    return PersonData.fromTriples(uri, triples);
  }

  /// Lists Person entities ordered by name, with at most [limit] results.
  Future<List<PersonData>> listPersons({int limit = 20}) async {
    final typeTriples = await query()
        .where(NS.rdfType, equals: NS.schemaPerson)
        .orderBy(NS.schemaName)
        .limit(limit)
        .execute();

    final uris = typeTriples.map((t) => t.subject).toSet().toList();
    if (uris.isEmpty) return [];
    final allTriples = await getEntities(uris);
    return [
      for (final uri in uris)
        if (allTriples[uri] case final triples? when triples.isNotEmpty)
          PersonData.fromTriples(uri, triples),
    ];
  }

  /// Finds a Person by [name] (case-insensitive).
  ///
  /// Returns the URI of the first matching Person, or `null` if none found.
  Future<String?> findPersonByName(String name) async {
    final candidates =
        await query()
            .whereType(NS.schemaPerson)
            .where(NS.schemaName, contains: name)
            .execute();
    final lowerName = name.toLowerCase();
    final uris = candidates.map((t) => t.subject).toSet().toList();
    if (uris.isEmpty) return null;
    final allTriples = await getEntities(uris);
    for (final uri in uris) {
      final triples = allTriples[uri];
      if (triples == null) continue;
      final entityName =
          triples
              .where((t) => t.predicate == NS.schemaName)
              .firstOrNull
              ?.objectValue;
      if (entityName != null && entityName.toLowerCase() == lowerName) {
        return uri;
      }
    }
    return null;
  }

  /// Finds a Person whose `schema:url` or `schema:sameAs` matches [url].
  ///
  /// Returns the URI of the first matching Person, or `null` if none found.
  Future<String?> findPersonByUrl(String url) async {
    // Check schema:url.
    final byUrl =
        await query()
            .whereType(NS.schemaPerson)
            .where(NS.schemaUrl, equals: url)
            .execute();
    if (byUrl.isNotEmpty) return byUrl.first.subject;

    // Check schema:sameAs.
    final bySameAs =
        await query()
            .whereType(NS.schemaPerson)
            .where(NS.schemaSameAs, equals: url)
            .execute();
    if (bySameAs.isNotEmpty) return bySameAs.first.subject;

    return null;
  }

  /// Creates a new Person or merges into an existing one if a match is found.
  ///
  /// Deduplication checks (in order):
  /// 1. Name (case-insensitive)
  ///
  /// Merge strategy: existing non-null values are preserved; nulls are filled
  /// from the new data. For description, the longer value wins.
  Future<String> createOrMergePerson({
    String? name,
    String? givenName,
    String? familyName,
    String? email,
    String? telephone,
    String? description,
    String? nostrPubkey,
    String? nostrLabel,
  }) async {
    // Try to find an existing match.
    String? existingUri;
    if (name != null && name.isNotEmpty) {
      existingUri = await findPersonByName(name);
    }

    if (existingUri == null) {
      return createPerson(
        name: name,
        givenName: givenName,
        familyName: familyName,
        email: email,
        telephone: telephone,
        description: description,
        nostrPubkey: nostrPubkey,
        nostrLabel: nostrLabel,
      );
    }

    // Merge into existing entity.
    final existing = await getPersonData(existingUri);
    if (existing == null) {
      return createPerson(
        name: name,
        givenName: givenName,
        familyName: familyName,
        email: email,
        telephone: telephone,
        description: description,
        nostrPubkey: nostrPubkey,
        nostrLabel: nostrLabel,
      );
    }

    await mutate((ctx) async {
      if (existing.givenName == null && givenName != null) {
        await ctx.set(existingUri!, NS.schemaGivenName, givenName);
      }
      if (existing.familyName == null && familyName != null) {
        await ctx.set(existingUri!, NS.schemaFamilyName, familyName);
      }
      if (existing.email == null && email != null) {
        await ctx.set(existingUri!, NS.schemaEmail, email);
      }
      if (existing.telephone == null && telephone != null) {
        await ctx.set(existingUri!, NS.schemaTelephone, telephone);
      }
      // Keep the longer description.
      if (description != null &&
          (existing.description == null ||
              description.length > existing.description!.length)) {
        await ctx.set(existingUri!, NS.schemaDescription, description);
      }
    });

    return existingUri;
  }
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

/// Builds a display name from optional given/family name parts.
String? _buildDisplayName({String? givenName, String? familyName}) {
  if (givenName != null && familyName != null) {
    return '$givenName $familyName';
  }
  return givenName ?? familyName;
}
