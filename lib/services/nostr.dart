/// Nostr protocol service — NIP-01 event model, relay communication.
///
/// Implements the core Nostr protocol: events, subscriptions, and relay
/// WebSocket communication. Events are signed with the user's secp256k1
/// keypair from [AuthService]. Relay connections are managed here.
///
/// References:
/// - NIP-01: https://github.com/nostr-protocol/nips/blob/master/01.md
/// - NIP-02: https://github.com/nostr-protocol/nips/blob/master/02.md
library;

import 'dart:async';
import 'dart:convert';

import 'package:kabuk/services/auth.dart' show AuthService;

/// A Nostr event (NIP-01).
///
/// Events are the fundamental data type in Nostr. Each event has an
/// `id` (SHA-256 hash of the serialized event), a `pubkey` (the
/// author's 32-byte x-only public key), a `kind` (integer type),
/// `tags` (arrays of strings), `content` (string payload), and a
/// `sig` (Schnorr signature over the id).
class NostrEvent {
  /// Creates a [NostrEvent] with all fields.
  const NostrEvent({
    required this.id,
    required this.pubkey,
    required this.createdAt,
    required this.kind,
    required this.tags,
    required this.content,
    required this.sig,
  });

  /// The event ID — SHA-256 of the serialized event.
  final String id;

  /// Author's 32-byte x-only public key (hex).
  final String pubkey;

  /// Unix timestamp in seconds.
  final int createdAt;

  /// Event kind (0=metadata, 1=text note, 3=contacts, etc.).
  final int kind;

  /// Event tags — each tag is a list of strings.
  final List<List<String>> tags;

  /// Event content string.
  final String content;

  /// 64-byte Schnorr signature over the event id (hex).
  final String sig;

  /// Serializes to JSON for relay communication.
  Map<String, dynamic> toJson() => {
    'id': id,
    'pubkey': pubkey,
    'created_at': createdAt,
    'kind': kind,
    'tags': tags,
    'content': content,
    'sig': sig,
  };

  /// Parses from JSON received from a relay.
  ///
  /// Fields are parsed with null-safe accessors so malformed relay data
  /// produces an event with default values instead of crashing.
  factory NostrEvent.fromJson(Map<String, dynamic> json) => NostrEvent(
    id: json['id'] as String? ?? '',
    pubkey: json['pubkey'] as String? ?? '',
    createdAt: (json['created_at'] as num?)?.toInt() ?? 0,
    kind: (json['kind'] as num?)?.toInt() ?? 0,
    tags:
        (json['tags'] as List?)
            ?.map(
              (t) =>
                  (t as List?)?.map((e) => e.toString()).toList() ?? <String>[],
            )
            .toList() ??
        <List<String>>[],
    content: json['content'] as String? ?? '',
    sig: json['sig'] as String? ?? '',
  );

  /// Returns the serialized array used to compute the event ID.
  ///
  /// Per NIP-01: `[0, pubkey, created_at, kind, tags, content]`
  List<dynamic> get serialized => [0, pubkey, createdAt, kind, tags, content];

  /// Serialized JSON string for event ID computation.
  String get serializedString => jsonEncode(serialized);

  /// Whether this event has valid required fields.
  ///
  /// Returns `false` if [id], [pubkey], or [sig] are empty strings,
  /// which indicates the event was parsed from malformed data.
  bool get isValid => id.isNotEmpty && pubkey.isNotEmpty && sig.isNotEmpty;

  @override
  String toString() =>
      'NostrEvent(id: $id, kind: $kind, '
      'pubkey: ${pubkey.substring(0, 8)}...)';
}

/// An unsigned Nostr event (before ID and signature).
///
/// Used during event construction. Call [NostrService.signEvent] to
/// produce a fully signed [NostrEvent].
class UnsignedNostrEvent {
  /// Creates an [UnsignedNostrEvent].
  const UnsignedNostrEvent({
    required this.kind,
    required this.content,
    this.tags = const [],
    this.createdAt,
  });

  /// Event kind.
  final int kind;

  /// Event content.
  final String content;

  /// Event tags.
  final List<List<String>> tags;

  /// Unix timestamp. If null, the current time is used.
  final int? createdAt;
}

/// Well-known Nostr event kinds.
abstract final class NostrKind {
  /// Kind 0: User metadata (NIP-01).
  static const int metadata = 0;

  /// Kind 1: Short text note (NIP-01).
  static const int textNote = 1;

  /// Kind 2: Recommend relay (NIP-01, deprecated).
  static const int recommendRelay = 2;

  /// Kind 3: Contact list (NIP-02).
  static const int contacts = 3;

  /// Kind 4: Encrypted direct message (NIP-04, legacy).
  static const int encryptedDM = 4;

  /// Kind 5: Event deletion (NIP-09).
  static const int deletion = 5;

  /// Kind 6: Repost (NIP-18).
  static const int repost = 6;

  /// Kind 7: Reaction (NIP-25).
  static const int reaction = 7;

  /// Kind 13: Seal (NIP-59) — encrypted real event, signed by real sender.
  static const int seal = 13;

  /// Kind 14: Direct message (NIP-17) — the actual DM content.
  static const int directMessage = 14;

  /// Kind 40: Channel creation (NIP-28) — public group chat metadata.
  static const int channelCreation = 40;

  /// Kind 41: Channel metadata update (NIP-28).
  static const int channelMetadata = 41;

  /// Kind 42: Channel message (NIP-28) — a message in a public group chat.
  static const int channelMessage = 42;

  /// Kind 43: Channel hide message (NIP-28) — hide a message.
  static const int channelHideMessage = 43;

  /// Kind 44: Channel mute user (NIP-28) — mute a user in a channel.
  static const int channelMuteUser = 44;

  /// Kind 1059: Gift wrap (NIP-59) — encrypted seal, signed by throwaway key.
  static const int giftWrap = 1059;

  /// Kind 10000: Mute list (NIP-51).
  static const int muteList = 10000;

  /// Kind 10001: Pin list (NIP-51).
  static const int pinList = 10001;

  /// Kind 30000: Categorized people list (NIP-51, parameterized replaceable).
  static const int categorizedPeopleList = 30000;

  /// Kind 30001: Categorized bookmark list (NIP-51, parameterized replaceable).
  static const int categorizedBookmarkList = 30001;

  /// Kind 30023: Long-form content (NIP-23, parameterized replaceable).
  static const int longFormContent = 30023;

  /// Kind 10002: Relay list metadata (NIP-65).
  static const int relayList = 10002;

  /// Kind 22242: Client authentication (NIP-42).
  static const int clientAuth = 22242;

  // ---- NIP-36: Sensitive Content ----

  // NIP-36 is a tag on existing kinds, not a separate kind.
  // Use the `content-warning` tag on any event.

  // ---- NIP-46: Nostr Connect ----

  /// Kind 24133: Nostr Connect request (NIP-46).
  static const int nostrConnectRequest = 24133;

  /// Kind 24134: Nostr Connect response (NIP-46).
  static const int nostrConnectResponse = 24134;

  // ---- NIP-56: Reporting ----

  /// Kind 1984: Reporting event (NIP-56).
  static const int report = 1984;

  // ---- NIP-58: Badges ----

  /// Kind 30009: Badge definition (NIP-58, parameterized replaceable).
  static const int badgeDefinition = 30009;

  /// Kind 8: Badge award (NIP-58).
  static const int badgeAward = 8;

  /// Kind 30008: Profile badges list (NIP-58, parameterized replaceable).
  static const int profileBadges = 30008;

  // ---- NIP-78: Application-Specific Data ----

  /// Kind 30078: Application-specific data (NIP-78, parameterized replaceable).
  static const int appData = 30078;

  // ---- NIP-315: User Status ----

  /// Kind 30315: User status (NIP-315, parameterized replaceable).
  ///
  /// Used to broadcast online presence, music, activity, etc.
  static const int userStatus = 30315;

  // ---- NIP-84: Highlights ----

  /// Kind 9802: Highlight (NIP-84).
  static const int highlight = 9802;

  // ---- NIP-89: App Handlers ----

  /// Kind 31990: Handler information (NIP-89, parameterized replaceable).
  static const int handlerInformation = 31990;

  /// Kind 31989: User's preferred app handlers (NIP-89, parameterized replaceable).
  static const int handlerRecommendation = 31989;

  // ---- NIP-90: Data Vending Machines ----

  /// Kind 5000–5999: DVM job request range start (NIP-90).
  static const int dvmJobRequestBase = 5000;

  /// Kind 5100: DVM text-extraction request (NIP-90).
  static const int dvmTextExtract = 5100;

  /// Kind 5200: DVM speech-to-text request (NIP-90).
  static const int dvmSpeechToText = 5200;

  /// Kind 5300: DVM summarization request (NIP-90).
  static const int dvmSummarize = 5300;

  /// Kind 5400: DVM translation request (NIP-90).
  static const int dvmTranslate = 5400;

  /// Kind 5600: DVM image generation request (NIP-90).
  static const int dvmImageGenerate = 5600;

  /// Kind 7000: DVM job feedback (NIP-90).
  static const int dvmJobFeedback = 7000;

  // ---- NIP-94: File Metadata ----

  /// Kind 1063: File metadata (NIP-94).
  static const int fileMetadata = 1063;
}

/// A Nostr subscription filter (NIP-01).
///
/// Filters specify which events a client wants to receive from a relay.
/// Multiple filters can be submitted in a single REQ message.
class NostrFilter {
  /// Creates a [NostrFilter].
  const NostrFilter({
    this.ids,
    this.authors,
    this.kinds,
    this.eTags,
    this.pTags,
    this.rTags,
    this.tTags,
    this.dTags,
    this.aTags,
    this.kTags,
    this.search,
    this.since,
    this.until,
    this.limit,
  });

  /// Event IDs to match.
  final List<String>? ids;

  /// Author public keys to match.
  final List<String>? authors;

  /// Event kinds to match.
  final List<int>? kinds;

  /// Event IDs referenced in `e` tags.
  final List<String>? eTags;

  /// Public keys referenced in `p` tags.
  final List<String>? pTags;

  /// URLs referenced in `r` tags (used for URL-based social interactions).
  final List<String>? rTags;

  /// Hashtags referenced in `t` tags (NIP-12 generic tag queries).
  ///
  /// Used for topic-based content discovery. Tags should be lowercase.
  final List<String>? tTags;

  /// Identifiers referenced in `d` tags (NIP-51, NIP-23).
  ///
  /// Used to query parameterized replaceable events by their d-tag value.
  final List<String>? dTags;

  /// Parameterized replaceable event addresses in `a` tags.
  ///
  /// Format: `"<kind>:<pubkey>:<d-identifier>"`. Used to subscribe to
  /// replies or reactions targeting specific replaceable events.
  final List<String>? aTags;

  /// Event kinds referenced in `k` tags.
  ///
  /// Used in NIP-56 reports and NIP-90 DVMs to filter by referenced kind.
  final List<String>? kTags;

  /// NIP-50 search query string.
  ///
  /// Relays that support NIP-50 will perform full-text search on events.
  /// Not all relays support this — results may be empty on non-NIP-50 relays.
  final String? search;

  /// Events must be newer than this timestamp.
  final int? since;

  /// Events must be older than this timestamp.
  final int? until;

  /// Maximum number of events to return.
  final int? limit;

  /// Serializes to JSON for relay REQ messages.
  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{};
    if (ids != null) map['ids'] = ids;
    if (authors != null) map['authors'] = authors;
    if (kinds != null) map['kinds'] = kinds;
    if (eTags != null) map['#e'] = eTags;
    if (pTags != null) map['#p'] = pTags;
    if (rTags != null) map['#r'] = rTags;
    if (tTags != null) map['#t'] = tTags;
    if (dTags != null) map['#d'] = dTags;
    if (aTags != null) map['#a'] = aTags;
    if (kTags != null) map['#k'] = kTags;
    if (search != null) map['search'] = search;
    if (since != null) map['since'] = since;
    if (until != null) map['until'] = until;
    if (limit != null) map['limit'] = limit;
    return map;
  }
}

/// Nostr relay message types received from a relay.
sealed class RelayMessage {
  /// Creates a [RelayMessage].
  const RelayMessage();
}

/// EVENT message — a relay sending an event matching a subscription.
final class RelayEventMessage extends RelayMessage {
  /// Creates a [RelayEventMessage].
  const RelayEventMessage({required this.subscriptionId, required this.event});

  /// The subscription ID this event matches.
  final String subscriptionId;

  /// The received event.
  final NostrEvent event;
}

/// EOSE message — end of stored events for a subscription.
final class RelayEoseMessage extends RelayMessage {
  /// Creates a [RelayEoseMessage].
  const RelayEoseMessage({required this.subscriptionId});

  /// The subscription ID that finished.
  final String subscriptionId;
}

/// OK message — relay acknowledgment of a published event.
final class RelayOkMessage extends RelayMessage {
  /// Creates a [RelayOkMessage].
  const RelayOkMessage({
    required this.eventId,
    required this.accepted,
    this.message,
  });

  /// The event ID being acknowledged.
  final String eventId;

  /// Whether the event was accepted.
  final bool accepted;

  /// Optional human-readable message.
  final String? message;
}

/// NOTICE message — relay sending an informational message.
final class RelayNoticeMessage extends RelayMessage {
  /// Creates a [RelayNoticeMessage].
  const RelayNoticeMessage({required this.message});

  /// The notice content.
  final String message;
}

/// CLOSED message — relay closed a subscription.
final class RelayClosedMessage extends RelayMessage {
  /// Creates a [RelayClosedMessage].
  const RelayClosedMessage({required this.subscriptionId, this.message});

  /// The subscription that was closed.
  final String subscriptionId;

  /// Optional reason.
  final String? message;
}

/// AUTH message — relay requesting client authentication (NIP-42).
///
/// The client must respond with a signed kind 22242 event containing
/// `["relay", relayUrl]` and `["challenge", challenge]` tags.
final class RelayAuthMessage extends RelayMessage {
  /// Creates a [RelayAuthMessage].
  const RelayAuthMessage({required this.challenge});

  /// The challenge string the client must sign.
  final String challenge;
}

/// Parses a raw JSON relay message into a [RelayMessage].
///
/// Returns `null` if the message cannot be parsed.
RelayMessage? parseRelayMessage(String raw) {
  try {
    final data = jsonDecode(raw) as List;
    if (data.isEmpty) return null;

    final type = data[0] as String;

    return switch (type) {
      'EVENT' when data.length >= 3 => RelayEventMessage(
        subscriptionId: data[1] as String,
        event: NostrEvent.fromJson(data[2] as Map<String, dynamic>),
      ),
      'EOSE' when data.length >= 2 => RelayEoseMessage(
        subscriptionId: data[1] as String,
      ),
      'OK' when data.length >= 3 => RelayOkMessage(
        eventId: data[1] as String,
        accepted: data[2] as bool,
        message: data.length > 3 ? data[3] as String? : null,
      ),
      'NOTICE' when data.length >= 2 => RelayNoticeMessage(
        message: data[1] as String,
      ),
      'CLOSED' when data.length >= 2 => RelayClosedMessage(
        subscriptionId: data[1] as String,
        message: data.length > 2 ? data[2] as String? : null,
      ),
      'AUTH' when data.length >= 2 => RelayAuthMessage(
        challenge: data[1] as String,
      ),
      _ => null,
    };
  } on Object {
    return null;
  }
}

/// Abstract Nostr service interface.
///
/// Provides event creation/signing and relay communication. Platform
/// implementations handle the actual WebSocket connections.
abstract interface class NostrService {
  /// Signs an [UnsignedNostrEvent] using the user's keypair.
  ///
  /// Returns a fully signed [NostrEvent] with computed ID and signature.
  /// Throws [StateError] if no identity is configured.
  Future<NostrEvent> signEvent(UnsignedNostrEvent event);

  /// Verifies a [NostrEvent]'s ID and signature.
  Future<bool> verifyEvent(NostrEvent event);

  /// Publishes an [event] to all connected relays.
  ///
  /// Returns a list of relay URLs that accepted the event.
  Future<List<String>> publishEvent(NostrEvent event);

  /// Subscribes to events matching the given [filters] on all connected relays.
  ///
  /// Returns a stream of events from all relays. The subscription ID
  /// is auto-generated.
  Stream<NostrEvent> subscribe(List<NostrFilter> filters);

  /// Connects to a relay at the given [url].
  ///
  /// Returns `true` if the connection was established.
  Future<bool> connectRelay(String url);

  /// Disconnects from a relay at the given [url].
  Future<void> disconnectRelay(String url);

  /// Returns the list of currently connected relay URLs.
  List<String> get connectedRelays;

  /// Returns the list of configured relay URLs (including disconnected ones).
  List<RelayConfig> get relays;

  /// Adds a relay to the configuration.
  Future<void> addRelay(RelayConfig relay);

  /// Removes a relay from the configuration.
  Future<void> removeRelay(String url);

  /// Publishes a user metadata event (kind 0).
  ///
  /// Convenience method for NIP-01 metadata events.
  Future<NostrEvent> publishMetadata({
    String? name,
    String? about,
    String? picture,
    String? nip05,
  });

  /// Publishes a text note (kind 1).
  ///
  /// [contentWarning] adds a NIP-36 `content-warning` tag with an optional
  /// reason label, signalling sensitive content to clients.
  Future<NostrEvent> publishTextNote(
    String content, {
    List<List<String>>? tags,
    String? contentWarning,
  });

  /// Fetches the profile metadata for a pubkey from relays.
  Future<NostrEvent?> fetchProfile(String pubkeyHex);

  // ---------------------------------------------------------------------------
  // Social interactions (NIP-10, NIP-18, NIP-25)
  // ---------------------------------------------------------------------------

  /// Publishes a reaction (NIP-25, kind 7) to a target event.
  ///
  /// [reaction] defaults to '+' (like). Can be any emoji or '-' for dislike.
  /// Returns the signed reaction event.
  Future<NostrEvent> publishReaction(
    String targetEventId,
    String targetPubkey, {
    String reaction = '+',
    String? relayUrl,
  });

  /// Publishes a reply (kind 1 with NIP-10 `e`/`p` tags) to a target event.
  ///
  /// Returns the signed reply event.
  Future<NostrEvent> publishReply(
    String targetEventId,
    String targetPubkey,
    String content, {
    String? relayUrl,
  });

  /// Publishes a repost (NIP-18, kind 6) of a target event.
  ///
  /// Returns the signed repost event.
  Future<NostrEvent> publishRepost(
    String targetEventId,
    String targetPubkey,
    String serializedEvent, {
    String? relayUrl,
  });

  /// Deletes one or more events (NIP-09, kind 5).
  ///
  /// Publishes a kind 5 deletion event that marks the given event IDs
  /// as deleted. Relays that support NIP-09 will stop serving these
  /// events and may purge them entirely.
  ///
  /// Only events authored by the current user can be deleted. The
  /// optional [reason] explains why the events are being deleted.
  ///
  /// Returns the signed deletion event.
  Future<NostrEvent> deleteEvents(List<String> eventIds, {String? reason});

  // ---------------------------------------------------------------------------
  // Long-Form Content (NIP-23)
  // ---------------------------------------------------------------------------

  /// Publishes a long-form article (NIP-23, kind 30023).
  ///
  /// [identifier] is the unique d-tag value for this article. Publishing
  /// with the same identifier replaces the previous version (parameterized
  /// replaceable event).
  ///
  /// [content] is the article body in Markdown format.
  /// [title], [summary], and [image] are metadata tags.
  /// [hashtags] are topic tags for discoverability.
  /// [contentWarning] adds a NIP-36 `content-warning` tag for sensitive articles.
  ///
  /// Returns the signed article event.
  Future<NostrEvent> publishLongFormContent({
    required String identifier,
    required String title,
    required String content,
    String? summary,
    String? image,
    List<String> hashtags = const [],
    DateTime? publishedAt,
    String? contentWarning,
  });

  /// Fetches long-form articles (kind 30023) by author pubkey.
  ///
  /// Returns a stream of article events.
  Stream<NostrEvent> fetchLongFormContent({
    List<String>? authors,
    List<String>? dTags,
    int limit = 20,
    int? since,
  });

  /// Fetches a single long-form article by author and identifier.
  Future<NostrLongFormContent?> fetchArticle(
    String authorPubkey,
    String identifier,
  );

  /// Shares a URL as a kind 1 text note with an optional comment.
  ///
  /// Useful for sharing RSS/Reddit content to Nostr. Returns the
  /// signed event so the caller can link it to the article entity.
  Future<NostrEvent> shareUrl(
    String url, {
    String? title,
    String? comment,
    List<String>? hashtags,
  });

  /// Fetches reactions (kind 7) for one or more event IDs.
  ///
  /// Returns a stream of reaction events. Listen for a bounded time
  /// to collect results.
  Stream<NostrEvent> fetchReactions(List<String> eventIds);

  /// Fetches replies (kind 1 referencing the target via `e` tag) for event IDs.
  Stream<NostrEvent> fetchReplies(List<String> eventIds);

  /// Fetches reposts (kind 6) for event IDs.
  Stream<NostrEvent> fetchReposts(List<String> eventIds);

  /// Fetches the global feed (kind 1 notes from all followed or public).
  ///
  /// [limit] controls how many events to request from each relay.
  /// [since] limits to events after this Unix timestamp.
  Stream<NostrEvent> fetchGlobalFeed({int limit = 50, int? since});

  /// Searches for events by hashtag/topic.
  ///
  /// Fetches kind 1 text notes that contain the given [hashtags] in `t` tags.
  /// This enables topic-based content discovery across the Nostr network.
  Stream<NostrEvent> searchByHashtag(
    List<String> hashtags, {
    int limit = 50,
    int? since,
  });

  /// Performs a NIP-50 full-text search on supporting relays.
  ///
  /// Not all relays support NIP-50. Results may be empty if no connected
  /// relay supports text search.
  Stream<NostrEvent> searchContent(
    String query, {
    List<int>? kinds,
    int limit = 50,
    int? since,
  });

  /// Fetches trending/popular hashtags from connected relays.
  ///
  /// This uses a heuristic: fetches recent events and counts `t` tag
  /// occurrences to find trending topics. Returns a list of
  /// (hashtag, count) pairs sorted by popularity.
  Future<List<({String hashtag, int count})>> trendingHashtags({
    int sampleSize = 500,
    Duration window = const Duration(hours: 24),
  });

  /// Fetches the feed for a specific set of followed pubkeys.
  Stream<NostrEvent> fetchFollowingFeed(
    List<String> pubkeys, {
    int limit = 50,
    int? since,
  });

  /// Fetches the contact list (kind 3) for the current user.
  ///
  /// Returns a list of pubkeys the user follows.
  Future<List<String>> fetchContactList();

  // ---------------------------------------------------------------------------
  // URL-based social interactions (r-tag anchored)
  // ---------------------------------------------------------------------------

  /// Fetches comments (kind 1 notes referencing [url] via `r` tag).
  ///
  /// Used for URL-anchored social: any article URL can have Nostr
  /// comments without a prior "share" step.
  Stream<NostrEvent> fetchCommentsForUrl(String url, {int limit = 200});

  /// Fetches reactions (kind 7) referencing [url] via `r` tag.
  Stream<NostrEvent> fetchReactionsForUrl(String url, {int limit = 500});

  /// Fetches reposts (kind 6) referencing [url] via `r` tag.
  Stream<NostrEvent> fetchRepostsForUrl(String url, {int limit = 200});

  /// Publishes a comment about a URL as a kind 1 note with an `r` tag.
  ///
  /// This is the primary way users interact socially with any content.
  /// No prior "share to Nostr" step is needed.
  Future<NostrEvent> publishCommentForUrl(String url, String content);

  /// Publishes a reaction to a URL via `r` tag (kind 7).
  ///
  /// [reaction] defaults to '+' (like). Can be any emoji.
  Future<NostrEvent> publishReactionForUrl(String url, {String reaction = '+'});

  /// Publishes a repost referencing a URL via `r` tag (kind 6).
  Future<NostrEvent> publishRepostForUrl(String url, {String? comment});

  // ---------------------------------------------------------------------------
  // Direct Messages (NIP-17 gift-wrapped, NIP-44 encrypted)
  // ---------------------------------------------------------------------------

  /// Sends a NIP-17 gift-wrapped direct message to [recipientPubkey].
  ///
  /// The message is encrypted with NIP-44, sealed in a kind 13 event,
  /// and wrapped in a kind 1059 gift wrap. A self-addressed copy is
  /// also published so the sender can read their own messages.
  ///
  /// [replyToEventId] is an optional NIP-10 `e` tag referencing the event
  /// being replied to (for threaded conversations).
  /// Returns the number of relays that accepted the recipient gift wrap.
  Future<int> sendDirectMessage(
    String recipientPubkey,
    String content, {
    String? replyToEventId,
  });

  /// Publishes the user's online status (NIP-315, kind 30315).
  ///
  /// Pass an empty [status] string to clear the status ("offline").
  /// [url] is an optional link associated with the status.
  Future<void> publishUserStatus(String status, {String? url});

  /// Watches for NIP-315 status events from [pubkeyHex].
  ///
  /// Emits the status string whenever the user publishes a new kind 30315
  /// event. Emits an empty string if the status is cleared.
  Stream<String> watchUserStatus(String pubkeyHex);

  /// Sends a transient typing indicator to [recipientPubkey] (N1).
  ///
  /// Publishes an ephemeral kind 14 gift-wrapped event containing
  /// a `typing` tag. Relays that support ephemeral deletion (NIP-09)
  /// will drop it after expiry; all clients simply ignore it after TTL.
  Future<void> sendTypingIndicator(String recipientPubkey);

  /// Watches for typing indicator events from [senderPubkey] (N1).
  ///
  /// Emits `true` when the sender starts typing and completes when no
  /// further events are received.
  Stream<bool> watchTypingIndicator(String senderPubkey);

  /// Subscribes to incoming gift-wrapped DMs (kind 1059) and returns
  /// a stream of decrypted [NostrDm] messages.
  ///
  /// Listens for kind 1059 events tagged with the current user's pubkey.
  /// Each event is unwrapped (1059 → 13 → 14) and the decrypted DM
  /// is emitted on the stream.
  ///
  /// Pass [since] (Unix timestamp in seconds) to only receive events
  /// newer than that point in time. This prevents the relay from
  /// replaying the entire DM history on every reconnect.
  Stream<NostrDm> watchDirectMessages({int? since});

  /// Unwraps a single kind 1059 gift-wrap event into a [NostrDm].
  ///
  /// Returns `null` if decryption fails (wrong recipient, corrupted, etc.).
  Future<NostrDm?> unwrapGiftWrap(NostrEvent giftWrap);

  /// Fetches DM history with a specific [peerPubkey] from relays.
  ///
  /// Backfills past gift-wrapped DMs by requesting kind 1059 events
  /// from relays, unwrapping each, and returning those exchanged with
  /// the given peer. [since] limits to events after a timestamp (useful
  /// for incremental sync). [limit] caps the number of events to request.
  Future<List<NostrDm>> fetchDmHistory(
    String peerPubkey, {
    int? since,
    int limit = 100,
  });

  // ---------------------------------------------------------------------------
  // Group Channels (NIP-28 public group chats)
  // ---------------------------------------------------------------------------

  /// Creates a new public channel (kind 40).
  ///
  /// The [name] is required. [about] and [picture] are optional metadata.
  /// Returns the signed channel creation event. The event's ID becomes
  /// the channel identifier.
  Future<NostrEvent> createChannel({
    required String name,
    String? about,
    String? picture,
  });

  /// Updates channel metadata (kind 41).
  ///
  /// Only the original channel creator should call this. The [channelId]
  /// must reference a valid kind 40 event.
  Future<NostrEvent> updateChannelMetadata(
    String channelId, {
    String? name,
    String? about,
    String? picture,
  });

  /// Sends a message to a public channel (kind 42).
  ///
  /// The [channelId] is the event ID of the kind 40 creation event.
  /// [content] is the message text. [replyTo] references a specific
  /// message in the channel (adds a reply marker `e` tag).
  Future<NostrEvent> sendChannelMessage(
    String channelId,
    String content, {
    String? replyTo,
  });

  /// Subscribes to messages in a public channel (kind 42).
  ///
  /// Returns a stream of channel messages. The [channelId] must be the
  /// event ID of the kind 40 creation event. [since] limits to messages
  /// after a timestamp. [limit] controls the backfill count.
  Stream<NostrEvent> watchChannelMessages(
    String channelId, {
    int? since,
    int limit = 50,
  });

  /// Fetches channel metadata (kind 40 + latest kind 41) by [channelId].
  ///
  /// Returns the channel creation event or the most recent metadata update.
  Future<NostrEvent?> fetchChannelMetadata(String channelId);

  /// Searches for public channels by name or description.
  ///
  /// Uses NIP-50 search on supporting relays. Falls back to fetching
  /// recent kind 40 events if search is unsupported.
  Stream<NostrEvent> searchChannels(String query, {int limit = 20});

  // ---------------------------------------------------------------------------
  // Profile Caching
  // ---------------------------------------------------------------------------

  /// Fetches a profile with local caching.
  ///
  /// Returns a cached profile if available and not stale (within [maxAge]).
  /// Otherwise fetches from relays and caches the result.
  Future<NostrProfile?> fetchProfileCached(
    String pubkeyHex, {
    Duration maxAge = const Duration(hours: 1),
  });

  /// Clears the local profile cache for [pubkeyHex], or all profiles if null.
  void clearProfileCache([String? pubkeyHex]);

  // ---------------------------------------------------------------------------
  // NIP-05 Verification
  // ---------------------------------------------------------------------------

  /// Verifies a NIP-05 identifier against a public key (NIP-05).
  ///
  /// Performs an HTTP GET to `https://{domain}/.well-known/nostr.json?name={name}`
  /// and checks whether the returned pubkey matches [pubkeyHex].
  ///
  /// Returns `true` if verified, `false` if the identifier doesn't match
  /// or the domain doesn't serve a valid nostr.json.
  ///
  /// Results are cached for [cacheDuration] to avoid repeated HTTP requests.
  Future<bool> verifyNip05(
    String nip05Identifier,
    String pubkeyHex, {
    Duration cacheDuration = const Duration(hours: 1),
  });

  // ---------------------------------------------------------------------------
  // Contact List Management (NIP-02)
  // ---------------------------------------------------------------------------

  /// Publishes the user's contact list (kind 3) to relays.
  ///
  /// The [pubkeys] are the hex-encoded public keys of contacts to follow.
  /// This replaces the entire contact list — include all existing contacts.
  Future<NostrEvent> publishContactList(List<String> pubkeys);

  // ---------------------------------------------------------------------------
  // Relay List (NIP-65)
  // ---------------------------------------------------------------------------

  /// Publishes the user's relay list metadata (kind 10002).
  ///
  /// Advertises which relays this user reads from and writes to,
  /// enabling other clients to discover the best relays to reach them.
  Future<NostrEvent> publishRelayList();

  // ---------------------------------------------------------------------------
  // Lists & Bookmarks (NIP-51)
  // ---------------------------------------------------------------------------

  /// Publishes a categorized bookmark list (NIP-51, kind 30001).
  ///
  /// [name] is the list identifier (d-tag). [eventIds] and [urls] are
  /// the items to include. Each list is a parameterized replaceable
  /// event, so publishing replaces the previous version.
  ///
  /// Returns the signed list event.
  Future<NostrEvent> publishBookmarkList({
    required String name,
    List<String> eventIds = const [],
    List<String> urls = const [],
    List<String> hashtags = const [],
  });

  /// Fetches a categorized bookmark list by name for the current user.
  ///
  /// Returns the event IDs, URLs, and hashtags in the list.
  /// Returns `null` if no list with [name] exists.
  Future<NostrBookmarkList?> fetchBookmarkList(String name);

  /// Fetches all bookmark lists for the current user.
  Future<List<NostrBookmarkList>> fetchAllBookmarkLists();

  /// Publishes a mute list (NIP-51, kind 10000).
  ///
  /// [pubkeys] are hex-encoded public keys to mute. [eventIds] are
  /// events to mute. [hashtags] are topics to mute.
  Future<NostrEvent> publishMuteList({
    List<String> pubkeys = const [],
    List<String> eventIds = const [],
    List<String> hashtags = const [],
  });

  /// Fetches the current user's mute list (kind 10000).
  Future<NostrMuteList?> fetchMuteList();

  /// Publishes a pin list (NIP-51, kind 10001).
  ///
  /// [eventIds] are the events to pin to the user's profile.
  Future<NostrEvent> publishPinList(List<String> eventIds);

  /// Fetches the current user's pin list (kind 10001).
  Future<List<String>> fetchPinList();

  // ---------------------------------------------------------------------------
  // Media / File Sharing
  // ---------------------------------------------------------------------------

  /// Sends a direct message with a media attachment.
  ///
  /// The [mediaUrl] is the URL of the uploaded media file. The [mimeType]
  /// is optional but recommended for rendering. The [content] provides
  /// an optional text caption alongside the media. [replyToEventId] is an
  /// optional event ID this media message is replying to.
  Future<void> sendDirectMessageWithMedia(
    String recipientPubkey, {
    required String mediaUrl,
    String? mimeType,
    String? content,
    String? fileName,
    String? replyToEventId,
  });

  // ---------------------------------------------------------------------------
  // NIP-36: Sensitive Content
  // ---------------------------------------------------------------------------

  /// Publishes a text note with a content-warning tag (NIP-36).
  ///
  /// Identical to [publishTextNote] but adds a `content-warning` tag with
  /// the optional [contentWarning] reason label.
  Future<NostrEvent> publishSensitiveTextNote(
    String content, {
    String? contentWarning,
    List<List<String>>? tags,
  });

  // ---------------------------------------------------------------------------
  // NIP-46: Nostr Connect (Remote Signing)
  // ---------------------------------------------------------------------------

  /// Sends a NIP-46 remote-signing request to a bunker pubkey.
  ///
  /// [bunkerPubkey] is the signer's public key (from `nostrconnect://` URI).
  /// [method] is the RPC method name:
  ///   - `connect` — initial handshake; include `[clientPubkey, secret, perms]` in [params]
  ///   - `sign_event` — sign an unsigned event JSON; include `[eventJson]` in [params]
  ///   - `get_public_key` — returns the managed pubkey; [params] = `[]`
  ///   - `get_relays` — returns relay preferences; [params] = `[]`
  ///   - `nip04_encrypt` / `nip04_decrypt` — legacy encryption
  ///   - `nip44_encrypt` / `nip44_decrypt` — NIP-44 encryption
  /// [params] are the JSON-serializable parameters for the chosen method.
  ///
  /// For the initial `connect` call from a `nostrconnect://` URI:
  /// ```dart
  /// final myPubkey = await auth.getPublicKeyHex();
  /// await nostr.sendNostrConnectRequest(bunkerPubkey,
  ///   method: 'connect',
  ///   params: [myPubkey, secret, ''],
  /// );
  /// ```
  ///
  /// Returns the result string from the bunker, or `null` on timeout/error.
  Future<String?> sendNostrConnectRequest(
    String bunkerPubkey, {
    required String method,
    required List<dynamic> params,
    Duration timeout = const Duration(seconds: 30),
  });

  // ---------------------------------------------------------------------------
  // NIP-56: Reporting
  // ---------------------------------------------------------------------------

  /// Reports an event or user to the network (NIP-56, kind 1984).
  ///
  /// [targetEventId] is the event to report (required if reporting an event).
  /// [targetPubkey] is the author's pubkey (always required).
  /// [reportType] classifies the violation.
  /// [reason] is an optional human-readable explanation.
  Future<NostrEvent> reportContent({
    String? targetEventId,
    required String targetPubkey,
    required NostrReportType reportType,
    String? reason,
  });

  // ---------------------------------------------------------------------------
  // NIP-58: Badges
  // ---------------------------------------------------------------------------

  /// Defines a badge (NIP-58, kind 30009).
  ///
  /// [badgeId] is the unique `d`-tag identifier. [name] is the display name.
  /// [description] is an optional description. [image] is the badge artwork URL.
  /// [thumbs] are thumbnail variants as (url, dimensions) pairs.
  Future<NostrEvent> defineBadge({
    required String badgeId,
    required String name,
    String? description,
    String? image,
    List<({String url, String dimensions})> thumbs = const [],
  });

  /// Awards a badge to one or more recipients (NIP-58, kind 8).
  ///
  /// [badgeDefinitionEventId] references the kind 30009 definition event ID.
  /// [badgeIdentifier] is the `d`-tag value of the referenced kind 30009 event.
  /// [badgeCreatorPubkey] is the badge creator's public key.
  /// [recipientPubkeys] are the recipients' public keys.
  /// [awardedEventIds] optionally cite the events that earned the badge.
  Future<NostrEvent> awardBadge({
    required String badgeDefinitionEventId,
    required String badgeIdentifier,
    required String badgeCreatorPubkey,
    required List<String> recipientPubkeys,
    List<String> awardedEventIds = const [],
  });

  /// Fetches badge definition events for a creator (kind 30009).
  Stream<NostrEvent> fetchBadgeDefinitions(
    String creatorPubkey, {
    int limit = 50,
  });

  /// Fetches badge awards (kind 8) received by a pubkey.
  Stream<NostrEvent> fetchBadgesAwardedTo(
    String recipientPubkey, {
    int limit = 50,
  });

  // ---------------------------------------------------------------------------
  // NIP-78: Application-Specific Data
  // ---------------------------------------------------------------------------

  /// Publishes arbitrary application-specific data (NIP-78, kind 30078).
  ///
  /// [appId] is the `d`-tag — a namespaced identifier such as
  /// `com.example.myapp:settings`. [content] is the JSON or text payload.
  /// Publishing with the same [appId] replaces the previous version.
  Future<NostrEvent> publishAppData({
    required String appId,
    required String content,
    List<List<String>> extraTags = const [],
  });

  /// Fetches application-specific data for [appId].
  ///
  /// [authorPubkey] defaults to the current user if null.
  Future<NostrEvent?> fetchAppData(String appId, {String? authorPubkey});

  // ---------------------------------------------------------------------------
  // NIP-84: Highlights
  // ---------------------------------------------------------------------------

  /// Publishes a highlight (NIP-84, kind 9802).
  ///
  /// [content] is the highlighted text passage. [sourceUrl] is the URL of the
  /// source document. [comment] is an optional annotation. [context] provides
  /// surrounding text for context. [sourceArticleAddr] is an optional NIP-19
  /// `naddr` identifying a Nostr article (kind 30023) as the source.
  Future<NostrEvent> publishHighlight({
    required String content,
    required String sourceUrl,
    String? comment,
    String? context,
    String? sourceArticleAddr,
  });

  /// Fetches highlights (kind 9802) referencing [sourceUrl].
  Stream<NostrEvent> fetchHighlights(String sourceUrl, {int limit = 100});

  /// Fetches highlights published by [authorPubkey].
  Stream<NostrEvent> fetchHighlightsByAuthor(
    String authorPubkey, {
    int limit = 50,
  });

  // ---------------------------------------------------------------------------
  // NIP-89: App Handlers
  // ---------------------------------------------------------------------------

  /// Publishes a handler information event (NIP-89, kind 31990).
  ///
  /// Advertises that this app can handle certain Nostr event kinds.
  /// [handlerId] is the `d`-tag. [name] is the display name. [url] is
  /// the deep-link template (e.g. `https://app.example.com/nostr?id=<bech32>`).
  /// [supportedKinds] are the kinds this handler can render.
  Future<NostrEvent> publishAppHandler({
    required String handlerId,
    required String name,
    required String url,
    String? description,
    String? picture,
    List<int> supportedKinds = const [],
  });

  /// Fetches handler information events (kind 31990) that can handle [kind].
  Stream<NostrEvent> fetchAppHandlers(int kind, {int limit = 20});

  /// Sets the user's preferred handler for [eventKind] (kind 31989).
  ///
  /// [handlerCoordinate] is the `a`-tag address of the kind 31990 handler info event,
  /// formatted as `"31990:<handler-pubkey>:<handler-d-tag>"`.
  Future<NostrEvent> setPreferredAppHandler({
    required int eventKind,
    required String handlerCoordinate,
    required String handlerRelayUrl,
  });

  /// Fetches the user's preferred handler (kind 31989) for [eventKind].
  Future<NostrEvent?> fetchPreferredAppHandler(int eventKind);

  // ---------------------------------------------------------------------------
  // NIP-90: Data Vending Machines (DVMs)
  // ---------------------------------------------------------------------------

  /// Submits a DVM job request (kind 5000-5999).
  ///
  /// [jobKind] must be in the range 5000-5999. [inputs] are the input
  /// parameters as `i` tags (type, value pairs). [outputMimeType] hints the
  /// expected result format. [bidMillisats] is an optional bid in millisats.
  /// [dvmPubkeys] targets specific DVMs; empty = broadcast to all DVMs.
  ///
  /// Returns the signed job request event whose ID is the job identifier.
  Future<NostrEvent> submitDvmJob({
    required int jobKind,
    required List<NostrDvmInput> inputs,
    String? outputMimeType,
    int? bidMillisats,
    List<String> dvmPubkeys = const [],
    List<List<String>> extraTags = const [],
  });

  /// Subscribes to DVM job results/feedback for a job event ID.
  ///
  /// Emits kind 6000-6999 (results) and kind 7000 (feedback) events
  /// matching [jobEventId]. Listen until you receive a success result
  /// or cancel the subscription.
  Stream<NostrEvent> watchDvmJobResults(String jobEventId);

  // ---------------------------------------------------------------------------
  // NIP-94: File Metadata
  // ---------------------------------------------------------------------------

  /// Publishes file metadata (NIP-94, kind 1063).
  ///
  /// Announces a file to the network with rich metadata for discovery
  /// and rendering. [url] is the file URL. [mimeType] is required.
  /// [sha256] is the file's SHA-256 hash (hex).
  Future<NostrEvent> publishFileMetadata({
    required String url,
    required String mimeType,
    String? sha256,
    int? size,
    String? dimensions,
    String? blurhash,
    String? originalHash,
    String? magnetUri,
    String? torrentInfoHash,
    String? description,
    List<String> fallbackUrls = const [],
  });

  /// Fetches file metadata events (kind 1063) by MIME type or author.
  Stream<NostrEvent> fetchFileMetadata({
    List<String>? authors,
    List<String>? mimeTypes,
    int limit = 50,
  });

  /// Disposes all relay connections.
  Future<void> dispose();
}

/// A NIP-23 long-form content article.
class NostrLongFormContent {
  /// Creates a [NostrLongFormContent].
  const NostrLongFormContent({
    required this.identifier,
    required this.title,
    required this.content,
    required this.authorPubkey,
    this.summary,
    this.image,
    this.hashtags = const [],
    this.publishedAt,
    this.eventId,
  });

  /// The d-tag identifier.
  final String identifier;

  /// The article title.
  final String title;

  /// The article body (Markdown).
  final String content;

  /// The author's public key (hex).
  final String authorPubkey;

  /// A short summary of the article.
  final String? summary;

  /// Cover image URL.
  final String? image;

  /// Topic hashtags.
  final List<String> hashtags;

  /// When the article was first published.
  final DateTime? publishedAt;

  /// The Nostr event ID for the latest version.
  final String? eventId;

  /// Parses a [NostrLongFormContent] from a kind 30023 event.
  factory NostrLongFormContent.fromEvent(NostrEvent event) {
    String? identifier;
    String? title;
    String? summary;
    String? image;
    DateTime? publishedAt;
    final hashtags = <String>[];

    for (final tag in event.tags) {
      if (tag.length < 2) continue;
      switch (tag[0]) {
        case 'd':
          identifier = tag[1];
        case 'title':
          title = tag[1];
        case 'summary':
          summary = tag[1];
        case 'image':
          image = tag[1];
        case 'published_at':
          final ts = int.tryParse(tag[1]);
          if (ts != null) {
            publishedAt = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
          }
        case 't':
          hashtags.add(tag[1]);
      }
    }

    return NostrLongFormContent(
      identifier: identifier ?? '',
      title: title ?? 'Untitled',
      content: event.content,
      authorPubkey: event.pubkey,
      summary: summary,
      image: image,
      hashtags: hashtags,
      publishedAt: publishedAt,
      eventId: event.id,
    );
  }
}

/// A NIP-51 categorized bookmark list.
class NostrBookmarkList {
  /// Creates a [NostrBookmarkList].
  const NostrBookmarkList({
    required this.name,
    this.eventIds = const [],
    this.urls = const [],
    this.hashtags = const [],
    this.createdAt,
  });

  /// The list identifier (d-tag value).
  final String name;

  /// Bookmarked event IDs.
  final List<String> eventIds;

  /// Bookmarked URLs.
  final List<String> urls;

  /// Bookmarked hashtags/topics.
  final List<String> hashtags;

  /// When the list was last updated.
  final DateTime? createdAt;
}

/// A NIP-51 mute list.
class NostrMuteList {
  /// Creates a [NostrMuteList].
  const NostrMuteList({
    this.pubkeys = const [],
    this.eventIds = const [],
    this.hashtags = const [],
  });

  /// Muted pubkeys.
  final List<String> pubkeys;

  /// Muted event IDs.
  final List<String> eventIds;

  /// Muted hashtags.
  final List<String> hashtags;
}

/// A decrypted Nostr direct message (NIP-17).
///
/// Represents the content of a kind 14 event after unwrapping
/// the kind 1059 gift wrap and kind 13 seal layers.
class NostrDm {
  /// Creates a [NostrDm].
  const NostrDm({
    required this.id,
    required this.senderPubkey,
    required this.recipientPubkey,
    required this.content,
    required this.timestamp,
    required this.isOwnMessage,
    this.replyToId,
    this.mediaUrl,
    this.mimeType,
    this.fileName,
    this.tags = const [],
  });

  /// The inner event ID (from the kind 14 event).
  final String id;

  /// The real sender's public key (hex).
  final String senderPubkey;

  /// The recipient's public key (hex).
  final String recipientPubkey;

  /// The decrypted message content.
  final String content;

  /// When the message was sent (from the kind 14 event).
  final DateTime timestamp;

  /// Whether this message was sent by the current user.
  final bool isOwnMessage;

  /// The event ID this message is replying to (if any).
  final String? replyToId;

  /// URL of an attached media file (if any).
  final String? mediaUrl;

  /// MIME type of the attached media (e.g. `image/jpeg`).
  final String? mimeType;

  /// Original file name of the attached media.
  final String? fileName;

  /// Raw inner DM event tags (NIP-01 tag arrays).
  final List<List<String>> tags;

  /// Whether this event is a transient typing indicator (N1).
  ///
  /// Typing indicator DMs carry a `["typing", "true"]` tag and have
  /// empty content. They should not be persisted as real messages.
  bool get isTypingIndicator =>
      tags.any((t) => t.length >= 2 && t[0] == 'typing' && t[1] == 'true');

  /// Whether this message has a media attachment.
  bool get hasMedia => mediaUrl != null;

  /// Returns the pubkey of the other party in the conversation.
  String get conversationPubkey =>
      isOwnMessage ? recipientPubkey : senderPubkey;

  @override
  String toString() =>
      'NostrDm(id: $id, '
      'from: ${senderPubkey.substring(0, 8)}..., '
      'to: ${recipientPubkey.substring(0, 8)}...)';
}

/// Cached Nostr profile metadata.
///
/// Represents a user's kind 0 metadata event, parsed and cached
/// for efficient lookups without re-fetching from relays.
class NostrProfile {
  /// Creates a [NostrProfile].
  const NostrProfile({
    required this.pubkey,
    required this.name,
    this.about,
    this.picture,
    this.nip05,
    this.banner,
    this.lud16,
    this.fetchedAt,
  });

  /// The user's public key (hex).
  final String pubkey;

  /// Display name.
  final String name;

  /// Bio / about text.
  final String? about;

  /// Profile picture URL.
  final String? picture;

  /// NIP-05 identifier (e.g. user@domain.com).
  final String? nip05;

  /// Banner image URL.
  final String? banner;

  /// Lightning address (LUD-16).
  final String? lud16;

  /// When this profile was fetched from relays.
  final DateTime? fetchedAt;

  /// Short display name — first 8 chars of pubkey if name is empty.
  String get displayName =>
      name.isNotEmpty ? name : '${pubkey.substring(0, 8)}...';
}

/// Configuration for a single Nostr relay.
class RelayConfig {
  /// Creates a [RelayConfig].
  const RelayConfig({required this.url, this.read = true, this.write = true});

  /// The relay WebSocket URL (wss://...).
  final String url;

  /// Whether to read events from this relay.
  final bool read;

  /// Whether to write events to this relay.
  final bool write;

  /// Serializes to JSON.
  Map<String, dynamic> toJson() => {'url': url, 'read': read, 'write': write};

  /// Parses from JSON.
  factory RelayConfig.fromJson(Map<String, dynamic> json) => RelayConfig(
    url: json['url'] as String,
    read: json['read'] as bool? ?? true,
    write: json['write'] as bool? ?? true,
  );
}

// ---------------------------------------------------------------------------
// NIP-56: Report types
// ---------------------------------------------------------------------------

/// Report violation types for NIP-56 kind 1984 events.
enum NostrReportType {
  /// Nudity / explicit sexual content.
  nudity('nudity'),

  /// Malware or malicious content.
  malware('malware'),

  /// Profanity or offensive language.
  profanity('profanity'),

  /// Illegal content.
  illegal('illegal'),

  /// Spam.
  spam('spam'),

  /// Impersonation of another person or entity.
  impersonation('impersonation'),

  /// Other violation not covered above.
  other('other');

  const NostrReportType(this.value);

  /// The string value used in the Nostr event tag.
  final String value;
}

// ---------------------------------------------------------------------------
// NIP-58: Badge models
// ---------------------------------------------------------------------------

/// A NIP-58 badge definition (kind 30009).
class NostrBadge {
  /// Creates a [NostrBadge].
  const NostrBadge({
    required this.badgeId,
    required this.name,
    required this.creatorPubkey,
    this.description,
    this.image,
    this.thumbs = const [],
    this.eventId,
  });

  /// The unique badge identifier (d-tag).
  final String badgeId;

  /// Display name of the badge.
  final String name;

  /// Creator's public key (hex).
  final String creatorPubkey;

  /// Optional description.
  final String? description;

  /// Badge image URL.
  final String? image;

  /// Thumbnail variants as (url, dimensions) pairs.
  final List<({String url, String dimensions})> thumbs;

  /// The Nostr event ID for this definition.
  final String? eventId;

  /// Parses a [NostrBadge] from a kind 30009 event.
  factory NostrBadge.fromEvent(NostrEvent event) {
    String? badgeId;
    String? name;
    String? description;
    String? image;
    final thumbs = <({String url, String dimensions})>[];

    for (final tag in event.tags) {
      if (tag.length < 2) continue;
      switch (tag[0]) {
        case 'd':
          badgeId = tag[1];
        case 'name':
          name = tag[1];
        case 'description':
          description = tag[1];
        case 'image':
          image = tag[1];
        case 'thumb':
          if (tag.length >= 3) {
            thumbs.add((url: tag[1], dimensions: tag[2]));
          } else {
            thumbs.add((url: tag[1], dimensions: ''));
          }
      }
    }

    return NostrBadge(
      badgeId: badgeId ?? '',
      name: name ?? 'Unknown Badge',
      creatorPubkey: event.pubkey,
      description: description,
      image: image,
      thumbs: thumbs,
      eventId: event.id,
    );
  }
}

// ---------------------------------------------------------------------------
// NIP-90: DVM models
// ---------------------------------------------------------------------------

/// Input type for a NIP-90 DVM job.
enum NostrDvmInputType {
  /// Plain URL to a publicly accessible resource.
  url('url'),

  /// A Nostr event ID (hex or bech32).
  event('event'),

  /// A Nostr job event ID.
  job('job'),

  /// Raw text content.
  text('text');

  const NostrDvmInputType(this.value);

  /// The string value used in the `i` tag.
  final String value;
}

/// A single input parameter for a NIP-90 DVM job request.
class NostrDvmInput {
  /// Creates a [NostrDvmInput].
  const NostrDvmInput({
    required this.type,
    required this.value,
    this.relay,
    this.marker,
  });

  /// The input type.
  final NostrDvmInputType type;

  /// The input value.
  final String value;

  /// Optional relay URL hint (for event-type inputs).
  final String? relay;

  /// Optional marker for additional context.
  final String? marker;

  /// Serializes to an `i` Nostr event tag.
  List<String> toTag() {
    final tag = <String>['i', value, type.value];
    if (relay != null) tag.add(relay!);
    if (marker != null) tag.add(marker!);
    return tag;
  }
}

/// The status of a NIP-90 DVM job.
enum NostrDvmJobStatus {
  /// DVM is processing the job.
  processing,

  /// DVM encountered an error.
  error,

  /// Job completed successfully.
  success,

  /// Partial result available.
  partial,

  /// Payment is required before the DVM will process the job.
  paymentRequired,
}

/// A parsed NIP-90 DVM job feedback or result event.
class NostrDvmResult {
  /// Creates a [NostrDvmResult].
  const NostrDvmResult({
    required this.jobEventId,
    required this.dvmPubkey,
    required this.content,
    required this.status,
    required this.isResult,
    this.amount,
    this.bolt11,
  });

  /// The job request event ID this result belongs to.
  final String jobEventId;

  /// The DVM's public key (hex).
  final String dvmPubkey;

  /// The result content (or status message for feedback).
  final String content;

  /// The job status.
  final NostrDvmJobStatus status;

  /// Whether this is a final result (kind 6000-6999) vs feedback (kind 7000).
  final bool isResult;

  /// Amount in millisats, if the DVM requested payment.
  final int? amount;

  /// BOLT-11 invoice, if the DVM requested payment.
  final String? bolt11;

  /// Parses a [NostrDvmResult] from a kind 6000-6999 or kind 7000 event.
  factory NostrDvmResult.fromEvent(NostrEvent event) {
    String? jobEventId;
    NostrDvmJobStatus status = event.kind == 7000
        ? NostrDvmJobStatus.processing
        : NostrDvmJobStatus.success;
    int? amount;
    String? bolt11;

    for (final tag in event.tags) {
      if (tag.length < 2) continue;
      switch (tag[0]) {
        case 'e':
          jobEventId = tag[1];
        case 'status':
          status = switch (tag[1]) {
            'processing' => NostrDvmJobStatus.processing,
            'error' => NostrDvmJobStatus.error,
            'success' => NostrDvmJobStatus.success,
            'partial' => NostrDvmJobStatus.partial,
            'payment-required' => NostrDvmJobStatus.paymentRequired,
            _ => NostrDvmJobStatus.processing,
          };
        case 'amount':
          if (tag.length >= 2) amount = int.tryParse(tag[1]);
          if (tag.length >= 3) bolt11 = tag[2];
      }
    }

    final isResult = event.kind >= 6000 && event.kind < 7000;

    return NostrDvmResult(
      jobEventId: jobEventId ?? '',
      dvmPubkey: event.pubkey,
      content: event.content,
      status: status,
      isResult: isResult,
      amount: amount,
      bolt11: bolt11,
    );
  }
}

// ---------------------------------------------------------------------------
// NIP-94: File metadata model
// ---------------------------------------------------------------------------

/// A NIP-94 file metadata event (kind 1063).
class NostrFileMetadata {
  /// Creates a [NostrFileMetadata].
  const NostrFileMetadata({
    required this.url,
    required this.mimeType,
    required this.publisherPubkey,
    this.sha256,
    this.originalHash,
    this.size,
    this.dimensions,
    this.blurhash,
    this.description,
    this.magnetUri,
    this.torrentInfoHash,
    this.fallbackUrls = const [],
    this.eventId,
  });

  /// Direct URL to the file.
  final String url;

  /// MIME type of the file.
  final String mimeType;

  /// Publisher's public key (hex).
  final String publisherPubkey;

  /// SHA-256 hash of the file after NIP-96 processing (hex).
  final String? sha256;

  /// SHA-256 hash of the original file before processing (hex).
  final String? originalHash;

  /// File size in bytes.
  final int? size;

  /// Pixel dimensions (e.g. `"1920x1080"`).
  final String? dimensions;

  /// Blurhash placeholder.
  final String? blurhash;

  /// Human-readable description.
  final String? description;

  /// Optional magnet URI.
  final String? magnetUri;

  /// Optional BitTorrent info hash.
  final String? torrentInfoHash;

  /// Alternative URLs to the same content.
  final List<String> fallbackUrls;

  /// The Nostr event ID.
  final String? eventId;

  /// Parses a [NostrFileMetadata] from a kind 1063 event.
  factory NostrFileMetadata.fromEvent(NostrEvent event) {
    String? url;
    String? mimeType;
    String? sha256;
    String? originalHash;
    int? size;
    String? dimensions;
    String? blurhash;
    String? description;
    String? magnetUri;
    String? torrentInfoHash;
    final fallbackUrls = <String>[];

    for (final tag in event.tags) {
      if (tag.length < 2) continue;
      switch (tag[0]) {
        case 'url':
          url = tag[1];
        case 'm':
          mimeType = tag[1];
        case 'x':
          sha256 = tag[1];
        case 'ox':
          originalHash = tag[1];
        case 'size':
          size = int.tryParse(tag[1]);
        case 'dim':
          dimensions = tag[1];
        case 'blurhash':
          blurhash = tag[1];
        case 'magnet':
          magnetUri = tag[1];
        case 'i':
          torrentInfoHash = tag[1];
        case 'fallback':
          fallbackUrls.add(tag[1]);
      }
    }

    // NIP-94: content is the description/caption.
    description = event.content.isNotEmpty ? event.content : null;

    return NostrFileMetadata(
      url: url ?? '',
      mimeType: mimeType ?? 'application/octet-stream',
      publisherPubkey: event.pubkey,
      sha256: sha256,
      originalHash: originalHash,
      size: size,
      dimensions: dimensions,
      blurhash: blurhash,
      description: description,
      magnetUri: magnetUri,
      torrentInfoHash: torrentInfoHash,
      fallbackUrls: fallbackUrls,
      eventId: event.id,
    );
  }
}
