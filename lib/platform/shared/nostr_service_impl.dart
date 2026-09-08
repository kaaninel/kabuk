/// Nostr service implementation — event signing and relay communication.
///
/// Uses [AuthService] for secp256k1 signing and web_socket_channel
/// for WebSocket relay connections. Events are signed per NIP-01 and
/// published to all configured write relays.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:kabuk/services/auth.dart';
import 'package:kabuk/services/nip44.dart';
import 'package:kabuk/services/nostr.dart';
import 'package:pointycastle/export.dart';
import 'package:uuid/uuid.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

const _uuid = Uuid();

/// Cross-platform [NostrService] implementation.
///
/// Signs events using [AuthService]'s secp256k1 keypair and communicates
/// with Nostr relays via WebSocket. Manages multiple relay connections
/// with automatic reconnection.
class SharedNostrService implements NostrService {
  /// Creates a [SharedNostrService].
  SharedNostrService({required this.auth, this.onRelayLoad, this.onRelaySave});

  /// The auth service providing signing capability.
  final AuthService auth;

  /// Async function to load saved relay config JSON.
  final Future<String?> Function()? onRelayLoad;

  /// Async function to save relay config JSON.
  final Future<void> Function(String json)? onRelaySave;

  final Map<String, _RelayConnection> _connections = {};
  final List<RelayConfig> _relayConfigs = [];
  final Map<String, StreamController<NostrEvent>> _subscriptions = {};

  /// Stores the original filter list for every active subscription so that
  /// we can re-send the REQ to relays that connect (or complete NIP-42 auth)
  /// *after* the subscription was created.
  final Map<String, List<NostrFilter>> _subscriptionFilters = {};

  /// Tracks relays to which we have already sent a NIP-42 AUTH response on
  /// the current connection.  We only attempt auth *once per connection* to
  /// avoid an infinite AUTH → CLOSED → AUTH loop on relays (like paid
  /// nostr.wine) that never accept our credentials.  The entry is removed
  /// whenever the relay disconnects, so a fresh reconnect triggers a new
  /// auth attempt.
  final Set<String> _authAttemptedRelays = {};

  /// Relays that sent `CLOSED auth-required` after we already attempted auth.
  ///
  /// Subscriptions are never replayed to these relays — they require
  /// credentials we don't have (paid / private relays).  Cleared on
  /// disconnect so a fresh connection can retry.
  final Set<String> _authRejectedRelays = {};

  /// Pending OK completers: eventId → {relayUrl → `Completer<bool>`}.
  ///
  /// Populated by [publishEvent] so that [_handleRelayMessage] can resolve
  /// each relay's acknowledgement when the OK message arrives.
  final Map<String, Map<String, Completer<bool>>> _pendingOks = {};

  bool _configLoaded = false;

  // -------------------------------------------------------------------------
  // Default relays — used when no relays are configured
  // -------------------------------------------------------------------------

  /// Well-known public relays for out-of-the-box connectivity.
  ///
  /// These are added automatically on first launch so users can start
  /// messaging immediately after onboarding without manual relay setup.
  static const List<RelayConfig> defaultRelays = [
    RelayConfig(url: 'wss://relay.damus.io'),
    RelayConfig(url: 'wss://relay.nostr.band'),
    RelayConfig(url: 'wss://nos.lol'),
    RelayConfig(url: 'wss://relay.snort.social'),
    RelayConfig(url: 'wss://nostr.wine', read: true, write: false),
    RelayConfig(url: 'wss://relay.0xchat.com'), // 0xchat native relay
    RelayConfig(url: 'wss://inbox.nostr.wine'), // NIP-17 DM inbox relay
    RelayConfig(url: 'wss://purplepag.es'), // NIP-65 relay list metadata
  ];

  /// Relays that are essential for NIP-17 DM delivery.
  ///
  /// These are merged into any existing relay config on startup so that
  /// users who configured relays before DM support was added automatically
  /// gain inbox connectivity without wiping their custom relay list.
  static const List<RelayConfig> dmEssentialRelays = [
    RelayConfig(url: 'wss://relay.0xchat.com'),
    RelayConfig(url: 'wss://inbox.nostr.wine'),
    RelayConfig(url: 'wss://auth.nostr1.com'), // NIP-42 authenticated inbox
    RelayConfig(url: 'wss://purplepag.es', read: true, write: false),
  ];

  /// Pre-computed SHA-256 of `"BIP0340/challenge"`.
  ///
  /// Used to build the BIP-340 tagged hash for Schnorr challenge computation:
  /// `SHA256(tag || tag || R.x || P.x || m)` where `tag = SHA256("BIP0340/challenge")`.
  static final Uint8List _bip340ChallengeTagHash = _sha256(
    Uint8List.fromList(utf8.encode('BIP0340/challenge')),
  );

  // -------------------------------------------------------------------------
  // Config persistence
  // -------------------------------------------------------------------------

  /// Loads relay configuration from persistence.
  ///
  /// If no relays are configured (first launch), seeds with [defaultRelays]
  /// so the user can communicate immediately after generating a keypair.
  Future<void> _ensureConfigLoaded() async {
    if (_configLoaded) return;
    _configLoaded = true;
    if (onRelayLoad != null) {
      final json = await onRelayLoad!();
      if (json != null) {
        try {
          final list = jsonDecode(json) as List;
          for (final item in list) {
            _relayConfigs.add(
              RelayConfig.fromJson(item as Map<String, dynamic>),
            );
          }
        } on Object {
          // Corrupted — ignore.
        }
      }
    }
    // Seed defaults if no relays are configured.
    if (_relayConfigs.isEmpty) {
      _relayConfigs.addAll(defaultRelays);
      await _persistConfig();
    } else {
      // Merge DM-essential relays that might be missing in older persisted
      // configs (e.g. users who configured relays before NIP-17 DM support
      // was added won't have the inbox relays in their saved list).
      final existing = _relayConfigs.map((r) => r.url).toSet();
      var dirty = false;
      for (final relay in dmEssentialRelays) {
        if (!existing.contains(relay.url)) {
          _relayConfigs.add(relay);
          dirty = true;
        }
      }
      if (dirty) await _persistConfig();
    }
  }

  /// Persists relay configuration.
  Future<void> _persistConfig() async {
    if (onRelaySave == null) return;
    final json = jsonEncode(_relayConfigs.map((r) => r.toJson()).toList());
    await onRelaySave!(json);
  }

  // -------------------------------------------------------------------------
  // Event signing (NIP-01)
  // -------------------------------------------------------------------------

  @override
  Future<NostrEvent> signEvent(UnsignedNostrEvent event) async {
    final pubkeyHex = await auth.getPublicKeyHex();
    if (pubkeyHex == null) {
      throw StateError('No identity configured — generate or import a keypair');
    }

    final createdAt =
        event.createdAt ?? (DateTime.now().millisecondsSinceEpoch ~/ 1000);

    // Compute event ID per NIP-01: SHA-256 of serialized event array.
    final serialized = jsonEncode([
      0,
      pubkeyHex,
      createdAt,
      event.kind,
      event.tags,
      event.content,
    ]);
    final idHash = _sha256(Uint8List.fromList(utf8.encode(serialized)));
    final idHex = _bytesToHex(idHash);

    // Sign the event ID (which is already a SHA-256 hash).
    final sigResult = await auth.signHash(idHash);
    final sig = sigResult.getOrThrow();
    final sigHex = _bytesToHex(sig);

    return NostrEvent(
      id: idHex,
      pubkey: pubkeyHex,
      createdAt: createdAt,
      kind: event.kind,
      tags: event.tags,
      content: event.content,
      sig: sigHex,
    );
  }

  @override
  Future<bool> verifyEvent(NostrEvent event) async {
    // Recompute event ID.
    final serialized = jsonEncode(event.serialized);
    final expectedId = _bytesToHex(
      _sha256(Uint8List.fromList(utf8.encode(serialized))),
    );

    if (event.id != expectedId) return false;

    // Verify signature against the event ID hash.
    final idHash = _hexToBytes(event.id);
    final sig = _hexToBytes(event.sig);
    final pubKey = _hexToBytes(event.pubkey);

    return auth.verifyHash(idHash, sig, publicKey: pubKey);
  }

  // -------------------------------------------------------------------------
  // Relay communication
  // -------------------------------------------------------------------------

  @override
  Future<List<String>> publishEvent(NostrEvent event) async {
    await _ensureConfigLoaded();
    final sent = <String>[];
    final eventJson = jsonEncode(['EVENT', event.toJson()]);

    // Create per-relay OK completers before sending so we don't miss fast ACKs.
    final okMap = <String, Completer<bool>>{};
    _pendingOks[event.id] = okMap;

    for (final entry in _connections.entries) {
      final url = entry.key;
      final conn = entry.value;
      final config = _relayConfigs.where((r) => r.url == url).firstOrNull;

      // Only publish to write relays.
      if (config != null && !config.write) continue;

      if (conn.isConnected) {
        try {
          okMap[url] = Completer<bool>();
          conn.channel.sink.add(eventJson);
          sent.add(url);
        } on Object {
          okMap.remove(url);
        }
      }
    }

    if (okMap.isEmpty) {
      _pendingOks.remove(event.id);
      return [];
    }

    // Wait up to 8 s for all relays to ACK. Relays that don't respond in
    // time are treated as accepted (optimistic — they may still process it).
    const timeout = Duration(seconds: 8);
    final accepted = <String>[];
    await Future.wait(
      okMap.entries.map((e) async {
        final url = e.key;
        final ok = await e.value.future.timeout(
          timeout,
          onTimeout: () => true, // optimistic
        );
        if (ok) accepted.add(url);
      }),
    );

    _pendingOks.remove(event.id);
    return accepted;
  }

  @override
  Stream<NostrEvent> subscribe(List<NostrFilter> filters) {
    final subId = _uuid.v4().replaceAll('-', '').substring(0, 16);
    final controller = StreamController<NostrEvent>.broadcast( // ignore: close_sinks
      onCancel: () {
        _closeSubscription(subId);
      },
    );
    _subscriptions[subId] = controller;
    _subscriptionFilters[subId] = filters;

    // Send REQ to all connected read relays.
    final reqJson = jsonEncode([
      'REQ',
      subId,
      ...filters.map((f) => f.toJson()),
    ]);

    for (final entry in _connections.entries) {
      final url = entry.key;
      final conn = entry.value;
      final config = _relayConfigs.where((r) => r.url == url).firstOrNull;

      if (config != null && !config.read) continue;

      if (conn.isConnected) {
        try {
          conn.channel.sink.add(reqJson);
        } on Object {
          // Skip.
        }
      }
    }

    return controller.stream;
  }

  void _closeSubscription(String subId) {
    _subscriptions.remove(subId);
    _subscriptionFilters.remove(subId);

    // Send CLOSE to all connected relays.
    final closeJson = jsonEncode(['CLOSE', subId]);
    for (final conn in _connections.values) {
      if (conn.isConnected) {
        try {
          conn.channel.sink.add(closeJson);
        } on Object {
          // Skip.
        }
      }
    }
  }

  @override
  Future<bool> connectRelay(String url) async {
    await _ensureConfigLoaded();

    if (_connections.containsKey(url) && _connections[url]!.isConnected) {
      return true;
    }

    try {
      final channel = WebSocketChannel.connect(Uri.parse(url));
      await channel.ready;

      final conn = _RelayConnection(url: url, channel: channel);
      _connections[url] = conn;

      // Listen for messages.
      conn.subscription = channel.stream.listen(
        (data) => _handleRelayMessage(url, data as String),
        onError: (Object error) {
          conn.isConnected = false;
          _authAttemptedRelays.remove(url);
          _authRejectedRelays.remove(url);
          _scheduleReconnect(url);
        },
        onDone: () {
          conn.isConnected = false;
          _authAttemptedRelays.remove(url);
          _authRejectedRelays.remove(url);
          _scheduleReconnect(url);
        },
      );

      conn.isConnected = true;
      debugPrint(
        '[Nostr] connected to $url, replaying ${_subscriptionFilters.length} subscriptions',
      );
      // Re-send any existing subscriptions to this relay — covers the case
      // where `subscribe()` was already called before this relay connected.
      _replaySubscriptionsToRelay(url);
      return true;
    } on Object {
      return false;
    }
  }

  @override
  Future<void> disconnectRelay(String url) async {
    final conn = _connections.remove(url);
    if (conn != null) {
      conn.isConnected = false;
      conn.reconnectTimer?.cancel();
      await conn.subscription?.cancel();
      await conn.channel.sink.close();
    }
  }

  /// Re-sends every active REQ subscription to [relayUrl].
  ///
  /// Called when a relay finishes connecting (so late-joining relays receive
  /// all current subscriptions) and after a successful NIP-42 AUTH response
  /// (since auth-required relays reject the initial REQ; once auth is accepted
  /// we must re-subscribe so the relay starts forwarding matching events).
  void _replaySubscriptionsToRelay(String relayUrl) {
    final conn = _connections[relayUrl];
    if (conn == null || !conn.isConnected) return;

    // Never replay to relays that already rejected auth — they require
    // credentials we cannot satisfy and would loop indefinitely.
    if (_authRejectedRelays.contains(relayUrl)) return;

    final config = _relayConfigs.where((r) => r.url == relayUrl).firstOrNull;
    if (config != null && !config.read) return;

    for (final entry in _subscriptionFilters.entries) {
      final subId = entry.key;
      final filters = entry.value;
      final reqJson = jsonEncode([
        'REQ',
        subId,
        ...filters.map((f) => f.toJson()),
      ]);
      try {
        conn.channel.sink.add(reqJson);
      } on Object {
        // Best-effort — skip on error.
      }
    }
  }

  void _scheduleReconnect(String url) {
    final conn = _connections[url];
    if (conn == null) return;

    conn.reconnectTimer?.cancel();
    conn.reconnectTimer = Timer(
      Duration(seconds: conn.reconnectDelay),
      () async {
        if (!_connections.containsKey(url)) return;
        final success = await connectRelay(url);
        if (!success) {
          // Exponential backoff (capped at 120s).
          conn.reconnectDelay = (conn.reconnectDelay * 2).clamp(1, 120);
          _scheduleReconnect(url);
        } else {
          conn.reconnectDelay = 5;
        }
      },
    );
  }

  void _handleRelayMessage(String relayUrl, String data) {
    final msg = parseRelayMessage(data);
    if (msg == null) return;

    switch (msg) {
      case RelayEventMessage(:final subscriptionId, :final event):
        // Only log events that actually have a listener — otherwise every
        // relay push for every connected relay floods the console even when
        // nobody is consuming the subscription.
        if (_subscriptions.containsKey(subscriptionId)) {
          debugPrint(
            '[Nostr] EVENT from $relayUrl kind=${event.kind} subId=$subscriptionId',
          );
          _subscriptions[subscriptionId]?.add(event);
        }
      case RelayEoseMessage():
        // End of stored events — no action needed for now.
        break;
      case RelayOkMessage(:final eventId, :final accepted):
        // Resolve the per-relay completer for this event if one exists.
        _pendingOks[eventId]?[relayUrl]?.complete(accepted);
        break;
      case RelayNoticeMessage(:final message):
        debugPrint('[Nostr] NOTICE from $relayUrl: $message');
        break;
      case RelayClosedMessage(:final subscriptionId, :final message):
        // A relay closed our subscription — this is per-relay (e.g. because
        // NIP-42 auth is required). Do NOT close the StreamController here:
        // other relays may still be serving it, and after auth we replay the
        // REQ. Only _closeSubscription() (triggered by stream cancel) truly
        // tears down the subscription.
        final authRequired =
            message != null && message.startsWith('auth-required');
        if (authRequired && _authAttemptedRelays.contains(relayUrl)) {
          // We already sent AUTH but the relay still rejects us — it needs
          // credentials we don't have (paid / private relay).  Mark as
          // permanently rejected so we stop replaying subscriptions here.
          _authRejectedRelays.add(relayUrl);
        }
        debugPrint(
          '[Nostr] relay $relayUrl CLOSED sub $subscriptionId: $message',
        );
      case RelayAuthMessage(:final challenge):
        // NIP-42: sign a kind 22242 event and send it back so auth-required
        // relays (e.g. auth.nostr1.com) accept our REQ and EVENT messages.
        unawaited(_handleNip42Auth(relayUrl, challenge));
    }
  }

  /// Responds to a NIP-42 AUTH challenge from [relayUrl].
  ///
  /// Builds and signs a kind 22242 event with the relay URL and challenge
  /// tags, then sends `["AUTH", event]` back over the existing connection.
  Future<void> _handleNip42Auth(String relayUrl, String challenge) async {
    // Only attempt NIP-42 auth once per connection to prevent an infinite
    // AUTH → CLOSED → AUTH loop on relays that never accept our credentials.
    if (_authAttemptedRelays.contains(relayUrl)) {
      debugPrint(
        '[Nostr] NIP-42 skipping duplicate AUTH challenge from $relayUrl',
      );
      return;
    }
    _authAttemptedRelays.add(relayUrl);
    try {
      final authEvent = await signEvent(
        UnsignedNostrEvent(
          kind: NostrKind.clientAuth,
          content: '',
          tags: [
            ['relay', relayUrl],
            ['challenge', challenge],
          ],
        ),
      );
      final msg = jsonEncode(['AUTH', authEvent.toJson()]);
      final conn = _connections[relayUrl];
      if (conn != null && conn.isConnected) {
        conn.channel.sink.add(msg);
        debugPrint(
          '[Nostr] NIP-42 auth sent to $relayUrl, replaying ${_subscriptionFilters.length} subscriptions',
        );
        // NIP-42: the relay rejected the initial REQ while we were un-auth'd.
        // Re-send all active subscriptions now that auth has been answered so
        // the relay starts forwarding matching events to us.
        _replaySubscriptionsToRelay(relayUrl);
      }
    } on Object {
      // If auth fails (e.g. no identity configured yet), ignore — the relay
      // will reject subsequent REQ/EVENT messages with a restricted error.
    }
  }

  @override
  List<String> get connectedRelays => _connections.entries
      .where((e) => e.value.isConnected)
      .map((e) => e.key)
      .toList();

  @override
  List<RelayConfig> get relays => List.unmodifiable(_relayConfigs);

  @override
  Future<void> addRelay(RelayConfig relay) async {
    await _ensureConfigLoaded();
    _relayConfigs.removeWhere((r) => r.url == relay.url);
    _relayConfigs.add(relay);
    await _persistConfig();
    await connectRelay(relay.url);
  }

  @override
  Future<void> removeRelay(String url) async {
    await _ensureConfigLoaded();
    _relayConfigs.removeWhere((r) => r.url == url);
    await _persistConfig();
    await disconnectRelay(url);
  }

  // -------------------------------------------------------------------------
  // Convenience methods
  // -------------------------------------------------------------------------

  @override
  Future<NostrEvent> publishMetadata({
    String? name,
    String? about,
    String? picture,
    String? nip05,
  }) async {
    final metadata = <String, String>{};
    if (name != null) metadata['name'] = name;
    if (about != null) metadata['about'] = about;
    if (picture != null) metadata['picture'] = picture;
    if (nip05 != null) metadata['nip05'] = nip05;

    final event = await signEvent(
      UnsignedNostrEvent(
        kind: NostrKind.metadata,
        content: jsonEncode(metadata),
      ),
    );

    await publishEvent(event);
    return event;
  }

  @override
  Future<NostrEvent?> fetchProfile(String pubkeyHex) async {
    final completer = Completer<NostrEvent?>();
    NostrEvent? result;

    final sub = subscribe([
      NostrFilter(authors: [pubkeyHex], kinds: [NostrKind.metadata], limit: 1),
    ]);

    Timer? timeout;
    StreamSubscription<NostrEvent>? subscription;

    timeout = Timer(const Duration(seconds: 5), () {
      if (!completer.isCompleted) {
        subscription?.cancel();
        completer.complete(result);
      }
    });

    subscription = sub.listen(
      (event) {
        if (result == null || event.createdAt > result!.createdAt) {
          result = event;
        }
      },
      onDone: () {
        timeout?.cancel();
        if (!completer.isCompleted) completer.complete(result);
      },
    );

    return completer.future;
  }

  // ---------------------------------------------------------------------------
  // Social interactions (NIP-10, NIP-18, NIP-25)
  // ---------------------------------------------------------------------------

  @override
  Future<NostrEvent> publishReaction(
    String targetEventId,
    String targetPubkey, {
    String reaction = '+',
    String? relayUrl,
  }) async {
    final tags = <List<String>>[
      ['e', targetEventId, ?relayUrl],
      ['p', targetPubkey],
    ];

    final event = await signEvent(
      UnsignedNostrEvent(
        kind: NostrKind.reaction,
        content: reaction,
        tags: tags,
      ),
    );
    await publishEvent(event);
    return event;
  }

  @override
  Future<NostrEvent> publishReply(
    String targetEventId,
    String targetPubkey,
    String content, {
    String? relayUrl,
  }) async {
    // NIP-10: reply uses 'e' tag with 'reply' marker.
    final tags = <List<String>>[
      ['e', targetEventId, relayUrl ?? '', 'reply'],
      ['p', targetPubkey],
    ];

    final event = await signEvent(
      UnsignedNostrEvent(
        kind: NostrKind.textNote,
        content: content,
        tags: tags,
      ),
    );
    await publishEvent(event);
    return event;
  }

  @override
  Future<NostrEvent> publishRepost(
    String targetEventId,
    String targetPubkey,
    String serializedEvent, {
    String? relayUrl,
  }) async {
    final tags = <List<String>>[
      ['e', targetEventId, relayUrl ?? ''],
      ['p', targetPubkey],
    ];

    final event = await signEvent(
      UnsignedNostrEvent(
        kind: NostrKind.repost,
        content: serializedEvent,
        tags: tags,
      ),
    );
    await publishEvent(event);
    return event;
  }

  @override
  Future<NostrEvent> deleteEvents(
    List<String> eventIds, {
    String? reason,
  }) async {
    final tags = <List<String>>[
      for (final id in eventIds) ['e', id],
    ];

    final event = await signEvent(
      UnsignedNostrEvent(
        kind: NostrKind.deletion,
        content: reason ?? '',
        tags: tags,
      ),
    );
    await publishEvent(event);
    return event;
  }

  // ---------------------------------------------------------------------------
  // Long-Form Content (NIP-23)
  // ---------------------------------------------------------------------------

  @override
  Stream<NostrEvent> fetchLongFormContent({
    List<String>? authors,
    List<String>? dTags,
    int limit = 20,
    int? since,
  }) {
    return subscribe([
      NostrFilter(
        kinds: const [NostrKind.longFormContent],
        authors: authors,
        dTags: dTags,
        limit: limit,
        since: since,
      ),
    ]);
  }

  @override
  Future<NostrLongFormContent?> fetchArticle(
    String authorPubkey,
    String identifier,
  ) async {
    final events = <NostrEvent>[];
    await subscribe([
          NostrFilter(
            kinds: const [NostrKind.longFormContent],
            authors: [authorPubkey],
            dTags: [identifier],
            limit: 1,
          ),
        ])
        .listen(events.add)
        .asFuture<void>()
        .timeout(const Duration(seconds: 5), onTimeout: () {});

    if (events.isEmpty) return null;
    return NostrLongFormContent.fromEvent(events.first);
  }

  @override
  Future<NostrEvent> shareUrl(
    String url, {
    String? title,
    String? comment,
    List<String>? hashtags,
  }) async {
    final buffer = StringBuffer();
    if (comment != null && comment.isNotEmpty) {
      buffer.writeln(comment);
      buffer.writeln();
    }
    if (title != null && title.isNotEmpty) {
      buffer.writeln(title);
    }
    buffer.write(url);

    final tags = <List<String>>[
      ['r', url],
      if (hashtags != null)
        for (final tag in hashtags) ['t', tag],
    ];

    final event = await signEvent(
      UnsignedNostrEvent(
        kind: NostrKind.textNote,
        content: buffer.toString(),
        tags: tags,
      ),
    );
    await publishEvent(event);
    return event;
  }

  @override
  Stream<NostrEvent> fetchReactions(List<String> eventIds) {
    return subscribe([
      NostrFilter(eTags: eventIds, kinds: [NostrKind.reaction], limit: 500),
    ]);
  }

  @override
  Stream<NostrEvent> fetchReplies(List<String> eventIds) {
    return subscribe([
      NostrFilter(eTags: eventIds, kinds: [NostrKind.textNote], limit: 200),
    ]);
  }

  @override
  Stream<NostrEvent> fetchReposts(List<String> eventIds) {
    return subscribe([
      NostrFilter(eTags: eventIds, kinds: [NostrKind.repost], limit: 200),
    ]);
  }

  @override
  Stream<NostrEvent> fetchGlobalFeed({int limit = 50, int? since}) {
    return subscribe([
      NostrFilter(kinds: [NostrKind.textNote], limit: limit, since: since),
    ]);
  }

  @override
  Stream<NostrEvent> fetchFollowingFeed(
    List<String> pubkeys, {
    int limit = 50,
    int? since,
  }) {
    return subscribe([
      NostrFilter(
        authors: pubkeys,
        kinds: [NostrKind.textNote],
        limit: limit,
        since: since,
      ),
    ]);
  }

  @override
  Future<List<String>> fetchContactList() async {
    final pubkey = await auth.getPublicKeyHex();
    if (pubkey == null) return [];

    final completer = Completer<List<String>>();
    NostrEvent? latestContacts;

    final sub = subscribe([
      NostrFilter(authors: [pubkey], kinds: [NostrKind.contacts], limit: 1),
    ]);

    Timer? timeout;
    StreamSubscription<NostrEvent>? subscription;

    timeout = Timer(const Duration(seconds: 5), () {
      if (!completer.isCompleted) {
        subscription?.cancel();
        final pubkeys = <String>[];
        if (latestContacts != null) {
          for (final tag in latestContacts!.tags) {
            if (tag.isNotEmpty && tag[0] == 'p' && tag.length >= 2) {
              pubkeys.add(tag[1]);
            }
          }
        }
        completer.complete(pubkeys);
      }
    });

    subscription = sub.listen(
      (event) {
        if (latestContacts == null ||
            event.createdAt > latestContacts!.createdAt) {
          latestContacts = event;
        }
      },
      onDone: () {
        timeout?.cancel();
        if (!completer.isCompleted) {
          final pubkeys = <String>[];
          if (latestContacts != null) {
            for (final tag in latestContacts!.tags) {
              if (tag.isNotEmpty && tag[0] == 'p' && tag.length >= 2) {
                pubkeys.add(tag[1]);
              }
            }
          }
          completer.complete(pubkeys);
        }
      },
    );

    return completer.future;
  }

  // ---------------------------------------------------------------------------
  // Topic / hashtag discovery (NIP-12 t-tag queries)
  // ---------------------------------------------------------------------------

  @override
  Stream<NostrEvent> searchByHashtag(
    List<String> hashtags, {
    int limit = 50,
    int? since,
  }) {
    final normalized = hashtags.map((h) => h.toLowerCase().trim()).toList();
    return subscribe([
      NostrFilter(
        tTags: normalized,
        kinds: [NostrKind.textNote],
        limit: limit,
        since: since,
      ),
    ]);
  }

  @override
  Stream<NostrEvent> searchContent(
    String query, {
    List<int>? kinds,
    int limit = 50,
    int? since,
  }) {
    return subscribe([
      NostrFilter(
        search: query,
        kinds: kinds ?? [NostrKind.textNote],
        limit: limit,
        since: since,
      ),
    ]);
  }

  @override
  Future<List<({String hashtag, int count})>> trendingHashtags({
    int sampleSize = 500,
    Duration window = const Duration(hours: 24),
  }) async {
    final since =
        DateTime.now().subtract(window).millisecondsSinceEpoch ~/ 1000;
    final events = <NostrEvent>[];
    final completer = Completer<List<({String hashtag, int count})>>();

    Timer? timeout;
    StreamSubscription<NostrEvent>? subscription;

    timeout = Timer(const Duration(seconds: 10), () {
      subscription?.cancel();
      if (!completer.isCompleted) {
        completer.complete(_countHashtags(events));
      }
    });

    subscription =
        subscribe([
          NostrFilter(
            kinds: [NostrKind.textNote],
            limit: sampleSize,
            since: since,
          ),
        ]).listen(
          events.add,
          onDone: () {
            timeout?.cancel();
            if (!completer.isCompleted) {
              completer.complete(_countHashtags(events));
            }
          },
          onError: (_) {
            // Ignore individual errors.
          },
        );

    return completer.future;
  }

  /// Counts hashtag occurrences in a list of events and returns sorted results.
  static List<({String hashtag, int count})> _countHashtags(
    List<NostrEvent> events,
  ) {
    final counts = <String, int>{};
    for (final event in events) {
      for (final tag in event.tags) {
        if (tag.isNotEmpty && tag[0] == 't' && tag.length >= 2) {
          final hashtag = tag[1].toLowerCase().trim();
          if (hashtag.isNotEmpty) {
            counts[hashtag] = (counts[hashtag] ?? 0) + 1;
          }
        }
      }
    }
    final sorted = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted
        .take(50)
        .map((e) => (hashtag: e.key, count: e.value))
        .toList();
  }

  // ---------------------------------------------------------------------------
  // URL-based social interactions (r-tag anchored)
  // ---------------------------------------------------------------------------

  @override
  Stream<NostrEvent> fetchCommentsForUrl(String url, {int limit = 200}) {
    return subscribe([
      NostrFilter(rTags: [url], kinds: [NostrKind.textNote], limit: limit),
    ]);
  }

  @override
  Stream<NostrEvent> fetchReactionsForUrl(String url, {int limit = 500}) {
    return subscribe([
      NostrFilter(rTags: [url], kinds: [NostrKind.reaction], limit: limit),
    ]);
  }

  @override
  Stream<NostrEvent> fetchRepostsForUrl(String url, {int limit = 200}) {
    return subscribe([
      NostrFilter(rTags: [url], kinds: [NostrKind.repost], limit: limit),
    ]);
  }

  @override
  Future<NostrEvent> publishCommentForUrl(String url, String content) async {
    final tags = <List<String>>[
      ['r', url],
    ];

    final event = await signEvent(
      UnsignedNostrEvent(
        kind: NostrKind.textNote,
        content: content,
        tags: tags,
      ),
    );
    await publishEvent(event);
    return event;
  }

  @override
  Future<NostrEvent> publishReactionForUrl(
    String url, {
    String reaction = '+',
  }) async {
    final tags = <List<String>>[
      ['r', url],
    ];

    final event = await signEvent(
      UnsignedNostrEvent(
        kind: NostrKind.reaction,
        content: reaction,
        tags: tags,
      ),
    );
    await publishEvent(event);
    return event;
  }

  @override
  Future<NostrEvent> publishRepostForUrl(String url, {String? comment}) async {
    final tags = <List<String>>[
      ['r', url],
    ];

    final event = await signEvent(
      UnsignedNostrEvent(
        kind: NostrKind.repost,
        content: comment ?? url,
        tags: tags,
      ),
    );
    await publishEvent(event);
    return event;
  }

  // ---------------------------------------------------------------------------
  // Direct Messages (NIP-17 gift-wrapped, NIP-44 encrypted)
  // ---------------------------------------------------------------------------

  @override
  @override
  Future<int> sendDirectMessage(
    String recipientPubkey,
    String content, {
    String? replyToEventId,
  }) async {
    final myPrivKey = await auth.getPrivateKeyBytes();
    final myPubKey = await auth.getPublicKeyHex();
    if (myPrivKey == null || myPubKey == null) {
      throw StateError('No identity configured — generate or import a keypair');
    }

    final recipientPubKeyBytes = _hexToBytes(recipientPubkey);

    // 1. Create and sign the kind 14 (DM) inner event (NIP-17).
    //    Must be a complete signed Nostr event with id and sig — 0xchat and
    //    other compliant clients validate the inner event signature after
    //    decrypting the seal.
    final dmSignedEvent = await signEvent(
      UnsignedNostrEvent(
        kind: NostrKind.directMessage,
        content: content,
        tags: [
          ['p', recipientPubkey],
          if (replyToEventId != null) ['e', replyToEventId, '', 'reply'],
        ],
      ),
    );
    final dmJson = jsonEncode(dmSignedEvent.toJson());

    // 2. Seal: encrypt kind 14 with NIP-44 (my privkey → recipient pubkey).
    //    Sign the seal (kind 13) with the real sender key.
    final sealConvKey = Nip44.getConversationKey(
      myPrivKey,
      recipientPubKeyBytes,
    );
    final sealedContent = Nip44.encrypt(dmJson, sealConvKey);

    final sealEvent = await signEvent(
      UnsignedNostrEvent(
        kind: NostrKind.seal,
        content: sealedContent,
        tags: const [],
        createdAt: _randomisedTimestamp(),
      ),
    );
    final sealJson = jsonEncode(sealEvent.toJson());

    // 3. Fetch the recipient's NIP-65 inbox relays (kind 10002) so the gift
    //    wrap reaches the relays the recipient actually monitors.  Clients such
    //    as 0xchat use dedicated inbox relays — publishing only to our own
    //    connected relays usually never delivers the message.
    final recipientInboxRelays = await _fetchRecipientInboxRelays(
      recipientPubkey,
    );

    // 4. Gift wrap to recipient: encrypt seal with throwaway key → recipient.
    //    Always include the essential DM relays as a guaranteed baseline,
    //    merged with any NIP-65 inbox relays fetched above. This ensures
    //    delivery even when the NIP-65 lookup timed out or returned an
    //    incomplete relay list (e.g. inbox.nostr.wine, auth.nostr1.com,
    //    relay.0xchat.com are always targeted).
    final essentialDmUrls = dmEssentialRelays
        .where((r) => r.write)
        .map((r) => r.url);
    final recipientTargetRelays = {
      ...essentialDmUrls,
      ...recipientInboxRelays,
    }.toList();
    final relayCount = await _publishGiftWrap(
      sealJson,
      recipientPubKeyBytes,
      recipientPubkey,
      targetRelays: recipientTargetRelays,
    );

    // 5. Gift wrap to self: encrypt seal with another throwaway key → self.
    //    This lets us read our own sent messages.
    final myPubKeyBytes = _hexToBytes(myPubKey);
    await _publishGiftWrap(sealJson, myPubKeyBytes, myPubKey);
    return relayCount;
  }

  /// Creates and publishes a kind 1059 gift wrap.
  ///
  /// When [targetRelays] is provided the event is published to exactly those
  /// relay URLs (connecting temporarily if needed) rather than to all connected
  /// write relays.  Use this to deliver directly to a recipient's NIP-65 inbox
  /// relays.
  ///
  /// Returns the number of relays that accepted the event.
  Future<int> _publishGiftWrap(
    String sealJson,
    Uint8List recipientPubKeyBytes,
    String recipientPubkeyHex, {
    List<String>? targetRelays,
  }) async {
    final throwaway = Nip44.generateThrowawayKeypair();
    final wrapConvKey = Nip44.getConversationKey(
      throwaway.privateKey,
      recipientPubKeyBytes,
    );
    final wrappedContent = Nip44.encrypt(sealJson, wrapConvKey);

    // Sign the gift wrap with the throwaway key.
    // We build the event manually since the throwaway key is not in AuthService.
    final throwawayPubHex = _bytesToHex(throwaway.publicKey);
    final createdAt = _randomisedTimestamp();

    final serialized = jsonEncode([
      0,
      throwawayPubHex,
      createdAt,
      NostrKind.giftWrap,
      [
        ['p', recipientPubkeyHex],
      ],
      wrappedContent,
    ]);
    final idHash = _sha256(Uint8List.fromList(utf8.encode(serialized)));
    final idHex = _bytesToHex(idHash);

    // Schnorr sign with the throwaway private key.
    final sig = _schnorrSignWithKey(idHash, throwaway.privateKey);
    final sigHex = _bytesToHex(sig);

    final giftWrapEvent = NostrEvent(
      id: idHex,
      pubkey: throwawayPubHex,
      createdAt: createdAt,
      kind: NostrKind.giftWrap,
      tags: [
        ['p', recipientPubkeyHex],
      ],
      content: wrappedContent,
      sig: sigHex,
    );

    if (targetRelays != null && targetRelays.isNotEmpty) {
      await _publishEventToRelays(giftWrapEvent, targetRelays);
      return targetRelays.length; // optimistic count for targeted publishes
    } else {
      final accepted = await publishEvent(giftWrapEvent);
      return accepted.length;
    }
  }

  /// Signs a 32-byte [hash] with a raw [privateKey] using Schnorr (BIP-340).
  ///
  /// Used for signing gift wrap events with throwaway keys.
  Uint8List _schnorrSignWithKey(Uint8List hash, Uint8List privateKey) {
    final params = ECDomainParameters('secp256k1');
    final d = Nip44.bytesToBigInt(privateKey);
    final n = params.n;
    final gPoint = params.G;

    final point = gPoint * d;
    final px = point!.x!.toBigInteger()!;

    // Ensure even Y (BIP-340 convention).
    final effectiveD = point.y!.toBigInteger()!.isEven ? d : n - d;

    // Deterministic nonce: k = SHA256(d_bytes || hash).
    final dBytes = Nip44.bigIntToBytes(effectiveD, 32);
    final nonceInput = Uint8List(64);
    nonceInput.setAll(0, dBytes);
    nonceInput.setAll(32, hash);
    final kHash = _sha256(nonceInput);
    var k = Nip44.bytesToBigInt(kHash) % n;
    if (k == BigInt.zero) {
      throw StateError('Invalid nonce');
    }

    final rPoint = gPoint * k;
    if (!rPoint!.y!.toBigInteger()!.isEven) {
      k = n - k;
    }
    final rx = rPoint.x!.toBigInteger()!;

    // BIP-340 Schnorr challenge: taggedHash("BIP0340/challenge", R.x || P.x || m).
    // taggedHash(tag, x) = SHA256(SHA256(tag) || SHA256(tag) || x)
    // This differs from a plain SHA256 — omitting the tag prefix makes the
    // signature non-standard and rejected by all compliant Nostr clients.
    final eInput = Uint8List(32 + 32 + 32 + 32 + hash.length); // 160 bytes
    eInput.setAll(0, _bip340ChallengeTagHash); // SHA256("BIP0340/challenge")
    eInput.setAll(32, _bip340ChallengeTagHash); // SHA256("BIP0340/challenge")
    eInput.setAll(64, Nip44.bigIntToBytes(rx, 32));
    eInput.setAll(96, Nip44.bigIntToBytes(px, 32));
    eInput.setAll(128, hash);
    final e = Nip44.bytesToBigInt(_sha256(eInput)) % n;

    final s = (k + e * effectiveD) % n;

    final sig = Uint8List(64);
    sig.setAll(0, Nip44.bigIntToBytes(rx, 32));
    sig.setAll(32, Nip44.bigIntToBytes(s, 32));
    return sig;
  }

  /// Returns a randomised timestamp within ±48 hours of now.
  ///
  /// NIP-59 recommends randomising timestamps on gift wraps and seals
  /// to prevent timing correlation attacks.
  int _randomisedTimestamp() {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final random = Random.secure();
    // ±2 days in seconds.
    final offset = random.nextInt(172800) - 86400;
    return now + offset;
  }

  @override
  Future<void> publishUserStatus(String status, {String? url}) async {
    final event = await signEvent(
      UnsignedNostrEvent(
        kind: NostrKind.userStatus,
        content: status,
        tags: [
          ['d', 'general'],
          if (url != null) ['r', url],
        ],
      ),
    );
    await publishEvent(event);
  }

  @override
  Stream<String> watchUserStatus(String pubkeyHex) {
    return subscribe([
      NostrFilter(
        kinds: [NostrKind.userStatus],
        authors: [pubkeyHex],
        dTags: ['general'],
        limit: 1,
      ),
    ]).map((ev) => ev.content);
  }

  // N1 — typing indicator ------------------------------------------------

  /// Ephemeral kind 14 gift-wrapped to [recipientPubkey] with a "typing" tag.
  ///
  /// The event carries an `expiration` tag 30 s in the future so NIP-40
  /// compliant relays drop it automatically.  Recipients unwrap the gift
  /// wrap just like a normal DM; the typing tag tells the UI this is a
  /// transient signal and not a real message.
  @override
  Future<void> sendTypingIndicator(String recipientPubkey) async {
    final myPrivKey = await auth.getPrivateKeyBytes();
    final myPubKey = await auth.getPublicKeyHex();
    if (myPrivKey == null || myPubKey == null) return;

    final expiry = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 30;
    final recipientPubKeyBytes = _hexToBytes(recipientPubkey);

    // Inner kind 14 with typing tag.
    final dmEvent = await signEvent(
      UnsignedNostrEvent(
        kind: NostrKind.directMessage,
        content: '',
        tags: [
          ['p', recipientPubkey],
          ['typing', 'true'],
          ['expiration', '$expiry'],
        ],
      ),
    );
    final dmJson = jsonEncode(dmEvent.toJson());

    // Seal.
    final sealConvKey = Nip44.getConversationKey(
      myPrivKey,
      recipientPubKeyBytes,
    );
    final sealedContent = Nip44.encrypt(dmJson, sealConvKey);
    final sealEvent = await signEvent(
      UnsignedNostrEvent(
        kind: NostrKind.seal,
        content: sealedContent,
        tags: const [],
        createdAt: _randomisedTimestamp(),
      ),
    );
    final sealJson = jsonEncode(sealEvent.toJson());

    // Gift wrap to recipient only (no self-copy needed for ephemeral).
    await _publishGiftWrap(sealJson, recipientPubKeyBytes, recipientPubkey);
  }

  @override
  Stream<bool> watchTypingIndicator(String senderPubkey) {
    // We watch the DM stream and filter for typing-tagged kind-14 events.
    return watchDirectMessages()
        .where((dm) {
          return dm.senderPubkey == senderPubkey && dm.isTypingIndicator;
        })
        .map((_) => true);
  }

  @override
  Stream<NostrDm> watchDirectMessages({int? since}) {
    final controller = StreamController<NostrDm>.broadcast();
    StreamSubscription<NostrEvent>? innerSub;

    controller.onCancel = () {
      innerSub?.cancel();
      if (!controller.isClosed) controller.close();
    };

    () async {
      final myPubKey = await auth.getPublicKeyHex();
      if (myPubKey == null) {
        if (!controller.isClosed) unawaited(controller.close());
        return;
      }

      final sub = subscribe([
        NostrFilter(
          kinds: [NostrKind.giftWrap],
          pTags: [myPubKey],
          since: since,
        ),
      ]);

      // If controller was already cancelled before we got here, clean up.
      if (controller.isClosed) return;

      innerSub = sub.listen(
        (event) async {
          final dm = await unwrapGiftWrap(event);
          if (dm != null && !controller.isClosed) {
            debugPrint(
              '[Nostr] watchDMs: DM from ${dm.senderPubkey.substring(0, 8)}: ${dm.content.substring(0, dm.content.length.clamp(0, 40))}',
            );
            controller.add(dm);
          }
        },
        onError: (Object e) {
          if (!controller.isClosed) controller.addError(e);
        },
        onDone: () {
          if (!controller.isClosed) controller.close();
        },
      );
    }();

    return controller.stream;
  }

  @override
  Future<NostrDm?> unwrapGiftWrap(NostrEvent giftWrap) async {
    try {
      if (giftWrap.kind != NostrKind.giftWrap) {
        debugPrint('[Nostr] unwrap: wrong kind ${giftWrap.kind}');
        return null;
      }

      final myPrivKey = await auth.getPrivateKeyBytes();
      final myPubKey = await auth.getPublicKeyHex();
      if (myPrivKey == null || myPubKey == null) return null;

      // Layer 1: Decrypt gift wrap (kind 1059) → kind 13 seal.
      // The gift wrap pubkey is a throwaway key.
      final throwawayPubKey = _hexToBytes(giftWrap.pubkey);
      final wrapConvKey = Nip44.getConversationKey(myPrivKey, throwawayPubKey);
      final sealJson = Nip44.decrypt(giftWrap.content, wrapConvKey);
      final sealData = jsonDecode(sealJson) as Map<String, dynamic>;
      debugPrint('[Nostr] unwrap layer1 OK, seal kind=${sealData['kind']}');

      // Validate it's a kind 13 seal.
      if (sealData['kind'] != NostrKind.seal) {
        debugPrint('[Nostr] unwrap: seal wrong kind ${sealData['kind']}');
        return null;
      }

      // Layer 2: Decrypt seal (kind 13) → kind 14 DM.
      final senderPubkey = sealData['pubkey'] as String;
      final senderPubKeyBytes = _hexToBytes(senderPubkey);
      final sealConvKey = Nip44.getConversationKey(
        myPrivKey,
        senderPubKeyBytes,
      );
      final dmJson = Nip44.decrypt(sealData['content'] as String, sealConvKey);
      final dmData = jsonDecode(dmJson) as Map<String, dynamic>;
      debugPrint('[Nostr] unwrap layer2 OK, dm kind=${dmData['kind']}');

      // Validate it's a kind 14 DM.
      if (dmData['kind'] != NostrKind.directMessage) {
        debugPrint('[Nostr] unwrap: DM wrong kind ${dmData['kind']}');
        return null;
      }

      // Extract recipient, reply-to, and other tags.
      final tags = (dmData['tags'] as List?) ?? [];
      String? recipientPubkey;
      String? replyToId;
      final parsedTags = <List<String>>[];
      for (final tag in tags) {
        final t = (tag as List).map((e) => e.toString()).toList();
        parsedTags.add(t);
        if (t.isNotEmpty && t[0] == 'p' && t.length >= 2) {
          recipientPubkey = t[1];
        }
        if (t.isNotEmpty && t[0] == 'e' && t.length >= 2) {
          replyToId = t[1];
        }
      }

      recipientPubkey ??= myPubKey;
      final isOwnMessage = senderPubkey == myPubKey;

      final createdAt = dmData['created_at'] as int? ?? giftWrap.createdAt;

      return NostrDm(
        id: giftWrap.id,
        senderPubkey: senderPubkey,
        recipientPubkey: recipientPubkey,
        content: dmData['content'] as String? ?? '',
        timestamp: DateTime.fromMillisecondsSinceEpoch(createdAt * 1000),
        isOwnMessage: isOwnMessage,
        replyToId: replyToId,
        mediaUrl: _extractTagValue(dmData, 'url'),
        mimeType: _extractTagValue(dmData, 'm'),
        fileName: _extractTagValue(dmData, 'filename'),
        tags: parsedTags,
      );
    } on Object catch (e) {
      // Decryption failed — not for us or corrupted.
      debugPrint(
        '[Nostr] unwrapGiftWrap failed for ${giftWrap.id.substring(0, 8)}: $e',
      );
      return null;
    }
  }

  /// Extracts a tag value from a parsed DM event data map.
  static String? _extractTagValue(Map<String, dynamic> data, String tagName) {
    final tags = (data['tags'] as List?) ?? [];
    for (final tag in tags) {
      final t = (tag as List).map((e) => e.toString()).toList();
      if (t.isNotEmpty && t[0] == tagName && t.length >= 2) {
        return t[1];
      }
    }
    return null;
  }

  @override
  Future<List<NostrDm>> fetchDmHistory(
    String peerPubkey, {
    int? since,
    int limit = 100,
  }) async {
    final myPubKey = await auth.getPublicKeyHex();
    if (myPubKey == null) return [];

    // Request gift wraps addressed to us.
    final sub = subscribe([
      NostrFilter(
        kinds: [NostrKind.giftWrap],
        pTags: [myPubKey],
        limit: limit,
        since: since,
      ),
    ]);

    final dms = <NostrDm>[];
    final events = <NostrEvent>[];
    final completer = Completer<void>();

    Timer? timer;
    StreamSubscription<NostrEvent>? subscription;

    void finish() {
      timer?.cancel();
      subscription?.cancel();
      if (!completer.isCompleted) completer.complete();
    }

    timer = Timer(const Duration(seconds: 10), finish);

    subscription = sub.listen(
      (event) {
        events.add(event);
        if (events.length >= limit) finish();
      },
      onDone: finish,
      onError: (_) => finish(),
    );

    await completer.future;

    // Unwrap all events and filter for the target peer.
    for (final event in events) {
      final dm = await unwrapGiftWrap(event);
      if (dm != null && dm.conversationPubkey == peerPubkey) {
        dms.add(dm);
      }
    }

    // Sort by timestamp ascending.
    dms.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return dms;
  }

  // ---------------------------------------------------------------------------
  // Group Channels (NIP-28)
  // ---------------------------------------------------------------------------

  @override
  Future<NostrEvent> createChannel({
    required String name,
    String? about,
    String? picture,
  }) async {
    final metadata = <String, String>{
      'name': name,
      'about': ?about,
      'picture': ?picture,
    };

    final event = await signEvent(
      UnsignedNostrEvent(
        kind: NostrKind.channelCreation,
        content: jsonEncode(metadata),
      ),
    );

    await publishEvent(event);
    return event;
  }

  @override
  Future<NostrEvent> updateChannelMetadata(
    String channelId, {
    String? name,
    String? about,
    String? picture,
  }) async {
    final metadata = <String, String>{
      'name': ?name,
      'about': ?about,
      'picture': ?picture,
    };

    final event = await signEvent(
      UnsignedNostrEvent(
        kind: NostrKind.channelMetadata,
        content: jsonEncode(metadata),
        tags: [
          ['e', channelId, '', 'root'],
        ],
      ),
    );

    await publishEvent(event);
    return event;
  }

  @override
  Future<NostrEvent> sendChannelMessage(
    String channelId,
    String content, {
    String? replyTo,
  }) async {
    final tags = <List<String>>[
      ['e', channelId, '', 'root'],
      if (replyTo != null) ['e', replyTo, '', 'reply'],
    ];

    final event = await signEvent(
      UnsignedNostrEvent(
        kind: NostrKind.channelMessage,
        content: content,
        tags: tags,
      ),
    );

    await publishEvent(event);
    return event;
  }

  @override
  Stream<NostrEvent> watchChannelMessages(
    String channelId, {
    int? since,
    int limit = 50,
  }) {
    return subscribe([
      NostrFilter(
        eTags: [channelId],
        kinds: [NostrKind.channelMessage],
        limit: limit,
        since: since,
      ),
    ]);
  }

  @override
  Future<NostrEvent?> fetchChannelMetadata(String channelId) async {
    // Look for the latest kind 41 update first.
    final completer = Completer<NostrEvent?>();
    NostrEvent? result;

    final sub = subscribe([
      NostrFilter(
        ids: [channelId],
        kinds: [NostrKind.channelCreation],
        limit: 1,
      ),
      NostrFilter(
        eTags: [channelId],
        kinds: [NostrKind.channelMetadata],
        limit: 1,
      ),
    ]);

    Timer? timeout;
    StreamSubscription<NostrEvent>? subscription;

    timeout = Timer(const Duration(seconds: 5), () {
      subscription?.cancel();
      if (!completer.isCompleted) completer.complete(result);
    });

    subscription = sub.listen(
      (event) {
        if (result == null || event.createdAt > result!.createdAt) {
          result = event;
        }
      },
      onDone: () {
        timeout?.cancel();
        if (!completer.isCompleted) completer.complete(result);
      },
    );

    return completer.future;
  }

  @override
  Stream<NostrEvent> searchChannels(String query, {int limit = 20}) {
    return subscribe([
      NostrFilter(
        search: query,
        kinds: [NostrKind.channelCreation],
        limit: limit,
      ),
    ]);
  }

  // ---------------------------------------------------------------------------
  // Profile Caching
  // ---------------------------------------------------------------------------

  /// In-memory profile cache: pubkeyHex → (profile, fetchedAt).
  final Map<String, NostrProfile> _profileCache = {};

  @override
  Future<NostrProfile?> fetchProfileCached(
    String pubkeyHex, {
    Duration maxAge = const Duration(hours: 1),
  }) async {
    final cached = _profileCache[pubkeyHex];
    if (cached != null && cached.fetchedAt != null) {
      final age = DateTime.now().difference(cached.fetchedAt!);
      if (age < maxAge) return cached;
    }

    final event = await fetchProfile(pubkeyHex);
    if (event == null) return cached; // Return stale if relay returns nothing.

    try {
      final metadata = jsonDecode(event.content) as Map<String, dynamic>;
      final profile = NostrProfile(
        pubkey: pubkeyHex,
        name: metadata['name'] as String? ?? '',
        about: metadata['about'] as String?,
        picture: metadata['picture'] as String?,
        nip05: metadata['nip05'] as String?,
        banner: metadata['banner'] as String?,
        lud16: metadata['lud16'] as String?,
        fetchedAt: DateTime.now(),
      );
      _profileCache[pubkeyHex] = profile;
      return profile;
    } on Object {
      return cached;
    }
  }

  @override
  void clearProfileCache([String? pubkeyHex]) {
    if (pubkeyHex != null) {
      _profileCache.remove(pubkeyHex);
    } else {
      _profileCache.clear();
    }
  }

  // ---------------------------------------------------------------------------
  // NIP-05 Verification
  // ---------------------------------------------------------------------------

  /// Cache for NIP-05 verification results.
  final Map<String, ({bool verified, DateTime cachedAt})> _nip05Cache = {};

  @override
  Future<bool> verifyNip05(
    String nip05Identifier,
    String pubkeyHex, {
    Duration cacheDuration = const Duration(hours: 1),
  }) async {
    // Check cache first.
    final cacheKey = '$nip05Identifier:$pubkeyHex';
    final cached = _nip05Cache[cacheKey];
    if (cached != null &&
        DateTime.now().difference(cached.cachedAt) < cacheDuration) {
      return cached.verified;
    }

    try {
      // Parse the NIP-05 identifier: name@domain
      final parts = nip05Identifier.split('@');
      if (parts.length != 2) return _cacheNip05(cacheKey, false);

      final name = parts[0];
      final domain = parts[1];

      // Fetch the .well-known/nostr.json from the domain.
      final uri = Uri.https(domain, '/.well-known/nostr.json', {'name': name});
      final response = await http.get(uri).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        return _cacheNip05(cacheKey, false);
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final names = json['names'] as Map<String, dynamic>?;
      if (names == null) return _cacheNip05(cacheKey, false);

      final registeredPubkey = names[name] as String?;
      final verified = registeredPubkey == pubkeyHex;
      return _cacheNip05(cacheKey, verified);
    } on Object {
      // Network errors, JSON parse errors, timeouts — all count as unverified.
      return _cacheNip05(cacheKey, false);
    }
  }

  bool _cacheNip05(String key, bool verified) {
    _nip05Cache[key] = (verified: verified, cachedAt: DateTime.now());
    return verified;
  }

  // ---------------------------------------------------------------------------
  // Contact List Publishing (NIP-02)
  // ---------------------------------------------------------------------------

  @override
  Future<NostrEvent> publishContactList(List<String> pubkeys) async {
    final tags = pubkeys.map((pk) => ['p', pk]).toList();

    final event = await signEvent(
      UnsignedNostrEvent(
        kind: NostrKind.contacts,
        content: '', // NIP-02: content is for relay metadata, usually empty.
        tags: tags,
      ),
    );

    await publishEvent(event);
    return event;
  }

  // ---------------------------------------------------------------------------
  // Relay List Publishing (NIP-65)
  // ---------------------------------------------------------------------------

  @override
  Future<NostrEvent> publishRelayList() async {
    await _ensureConfigLoaded();

    final tags = _relayConfigs.map((r) {
      if (r.read && r.write) return ['r', r.url];
      if (r.read) return ['r', r.url, 'read'];
      return ['r', r.url, 'write'];
    }).toList();

    final event = await signEvent(
      UnsignedNostrEvent(kind: NostrKind.relayList, content: '', tags: tags),
    );

    await publishEvent(event);
    return event;
  }

  // ---------------------------------------------------------------------------
  // Lists & Bookmarks (NIP-51)
  // ---------------------------------------------------------------------------

  @override
  Future<NostrEvent> publishBookmarkList({
    required String name,
    List<String> eventIds = const [],
    List<String> urls = const [],
    List<String> hashtags = const [],
  }) async {
    final tags = <List<String>>[
      ['d', name],
      for (final id in eventIds) ['e', id],
      for (final url in urls) ['r', url],
      for (final tag in hashtags) ['t', tag],
    ];

    final event = await signEvent(
      UnsignedNostrEvent(
        kind: NostrKind.categorizedBookmarkList,
        content: '',
        tags: tags,
      ),
    );
    await publishEvent(event);
    return event;
  }

  @override
  Future<NostrBookmarkList?> fetchBookmarkList(String name) async {
    final myPubKey = await auth.getPublicKeyHex();
    if (myPubKey == null) return null;

    final events = <NostrEvent>[];
    await subscribe([
          NostrFilter(
            kinds: const [NostrKind.categorizedBookmarkList],
            authors: [myPubKey],
            dTags: [name],
            limit: 1,
          ),
        ])
        .listen(events.add)
        .asFuture<void>()
        .timeout(const Duration(seconds: 5), onTimeout: () {});

    if (events.isEmpty) return null;

    final event = events.first;
    return NostrBookmarkList(
      name: name,
      eventIds: event.tags
          .where((t) => t.length >= 2 && t[0] == 'e')
          .map((t) => t[1])
          .toList(),
      urls: event.tags
          .where((t) => t.length >= 2 && t[0] == 'r')
          .map((t) => t[1])
          .toList(),
      hashtags: event.tags
          .where((t) => t.length >= 2 && t[0] == 't')
          .map((t) => t[1])
          .toList(),
      createdAt: DateTime.fromMillisecondsSinceEpoch(event.createdAt * 1000),
    );
  }

  @override
  Future<List<NostrBookmarkList>> fetchAllBookmarkLists() async {
    final myPubKey = await auth.getPublicKeyHex();
    if (myPubKey == null) return [];

    final events = <NostrEvent>[];
    await subscribe([
          NostrFilter(
            kinds: const [NostrKind.categorizedBookmarkList],
            authors: [myPubKey],
          ),
        ])
        .listen(events.add)
        .asFuture<void>()
        .timeout(const Duration(seconds: 5), onTimeout: () {});

    // Deduplicate by d-tag (keep latest).
    final byName = <String, NostrEvent>{};
    for (final event in events) {
      final dTag = event.tags
          .where((t) => t.length >= 2 && t[0] == 'd')
          .map((t) => t[1])
          .firstOrNull;
      if (dTag == null) continue;
      final existing = byName[dTag];
      if (existing == null || event.createdAt > existing.createdAt) {
        byName[dTag] = event;
      }
    }

    return byName.entries.map((entry) {
      final event = entry.value;
      return NostrBookmarkList(
        name: entry.key,
        eventIds: event.tags
            .where((t) => t.length >= 2 && t[0] == 'e')
            .map((t) => t[1])
            .toList(),
        urls: event.tags
            .where((t) => t.length >= 2 && t[0] == 'r')
            .map((t) => t[1])
            .toList(),
        hashtags: event.tags
            .where((t) => t.length >= 2 && t[0] == 't')
            .map((t) => t[1])
            .toList(),
        createdAt: DateTime.fromMillisecondsSinceEpoch(event.createdAt * 1000),
      );
    }).toList();
  }

  @override
  Future<NostrEvent> publishMuteList({
    List<String> pubkeys = const [],
    List<String> eventIds = const [],
    List<String> hashtags = const [],
  }) async {
    final tags = <List<String>>[
      for (final pk in pubkeys) ['p', pk],
      for (final id in eventIds) ['e', id],
      for (final tag in hashtags) ['t', tag],
    ];

    final event = await signEvent(
      UnsignedNostrEvent(kind: NostrKind.muteList, content: '', tags: tags),
    );
    await publishEvent(event);
    return event;
  }

  @override
  Future<NostrMuteList?> fetchMuteList() async {
    final myPubKey = await auth.getPublicKeyHex();
    if (myPubKey == null) return null;

    final events = <NostrEvent>[];
    await subscribe([
          NostrFilter(
            kinds: const [NostrKind.muteList],
            authors: [myPubKey],
            limit: 1,
          ),
        ])
        .listen(events.add)
        .asFuture<void>()
        .timeout(const Duration(seconds: 5), onTimeout: () {});

    if (events.isEmpty) return null;

    final event = events.first;
    return NostrMuteList(
      pubkeys: event.tags
          .where((t) => t.length >= 2 && t[0] == 'p')
          .map((t) => t[1])
          .toList(),
      eventIds: event.tags
          .where((t) => t.length >= 2 && t[0] == 'e')
          .map((t) => t[1])
          .toList(),
      hashtags: event.tags
          .where((t) => t.length >= 2 && t[0] == 't')
          .map((t) => t[1])
          .toList(),
    );
  }

  @override
  Future<NostrEvent> publishPinList(List<String> eventIds) async {
    final tags = <List<String>>[
      for (final id in eventIds) ['e', id],
    ];

    final event = await signEvent(
      UnsignedNostrEvent(kind: NostrKind.pinList, content: '', tags: tags),
    );
    await publishEvent(event);
    return event;
  }

  @override
  Future<List<String>> fetchPinList() async {
    final myPubKey = await auth.getPublicKeyHex();
    if (myPubKey == null) return [];

    final events = <NostrEvent>[];
    await subscribe([
          NostrFilter(
            kinds: const [NostrKind.pinList],
            authors: [myPubKey],
            limit: 1,
          ),
        ])
        .listen(events.add)
        .asFuture<void>()
        .timeout(const Duration(seconds: 5), onTimeout: () {});

    if (events.isEmpty) return [];

    return events.first.tags
        .where((t) => t.length >= 2 && t[0] == 'e')
        .map((t) => t[1])
        .toList();
  }

  // ---------------------------------------------------------------------------
  // Media Sharing in DMs
  // ---------------------------------------------------------------------------

  @override
  Future<void> sendDirectMessageWithMedia(
    String recipientPubkey, {
    required String mediaUrl,
    String? mimeType,
    String? content,
    String? fileName,
    String? replyToEventId,
  }) async {
    final myPrivKey = await auth.getPrivateKeyBytes();
    final myPubKey = await auth.getPublicKeyHex();
    if (myPrivKey == null || myPubKey == null) {
      throw StateError('No identity configured — generate or import a keypair');
    }

    final recipientPubKeyBytes = _hexToBytes(recipientPubkey);

    // Build tags for media metadata (NIP-92 imeta format).
    final tags = <List<String>>[
      ['p', recipientPubkey],
      // NIP-92 imeta tag: space-separated key-value pairs for media metadata.
      [
        'imeta',
        'url $mediaUrl',
        if (mimeType != null) 'm $mimeType',
        if (fileName != null) 'filename $fileName',
      ],
      if (replyToEventId != null) ['e', replyToEventId, '', 'reply'],
    ];

    // Create and sign the kind 14 DM event with media metadata in tags (NIP-17).
    //    Must include id and sig — clients validate the inner event signature.
    final dmSignedEvent = await signEvent(
      UnsignedNostrEvent(
        kind: NostrKind.directMessage,
        content: content ?? mediaUrl,
        tags: tags,
      ),
    );
    final dmJson = jsonEncode(dmSignedEvent.toJson());

    // Seal with NIP-44.
    final sealConvKey = Nip44.getConversationKey(
      myPrivKey,
      recipientPubKeyBytes,
    );
    final sealedContent = Nip44.encrypt(dmJson, sealConvKey);

    final sealEvent = await signEvent(
      UnsignedNostrEvent(
        kind: NostrKind.seal,
        content: sealedContent,
        tags: const [],
        createdAt: _randomisedTimestamp(),
      ),
    );
    final sealJson = jsonEncode(sealEvent.toJson());

    // Fetch recipient's NIP-65 inbox relays for reliable delivery.
    final recipientInboxRelays = await _fetchRecipientInboxRelays(
      recipientPubkey,
    );

    // Gift wrap to recipient and self.
    await _publishGiftWrap(
      sealJson,
      recipientPubKeyBytes,
      recipientPubkey,
      targetRelays: recipientInboxRelays.isNotEmpty
          ? recipientInboxRelays
          : null,
    );
    final myPubKeyBytes = _hexToBytes(myPubKey);
    await _publishGiftWrap(sealJson, myPubKeyBytes, myPubKey);
  }

  // ---------------------------------------------------------------------------
  // NIP-65 inbox relay discovery
  // ---------------------------------------------------------------------------

  /// Fetches the inbox relay URLs for [pubkeyHex] from their NIP-65 relay list
  /// (kind 10002).
  ///
  /// Returns URLs of relays tagged without a marker or with a `"read"` marker
  /// — these are the relays the user monitors for incoming events.
  /// Falls back to an empty list if no relay list event is found within 3 s.
  Future<List<String>> _fetchRecipientInboxRelays(String pubkeyHex) async {
    final events = <NostrEvent>[];
    final completer = Completer<void>();
    Timer? timer;
    StreamSubscription<NostrEvent>? sub;

    void finish() {
      timer?.cancel();
      sub?.cancel();
      if (!completer.isCompleted) completer.complete();
    }

    timer = Timer(const Duration(seconds: 3), finish);
    sub =
        subscribe([
          NostrFilter(
            authors: [pubkeyHex],
            kinds: [NostrKind.relayList],
            limit: 1,
          ),
        ]).listen(
          (e) {
            events.add(e);
            finish(); // take the first result and stop waiting
          },
          onDone: finish,
          onError: (_) => finish(),
        );

    await completer.future;

    if (events.isEmpty) return [];

    final inboxRelays = <String>[];
    for (final tag in events.first.tags) {
      if (tag.isEmpty || tag[0] != 'r' || tag.length < 2) continue;
      final url = tag[1];
      // If tag[2] is 'write', this is a write-only relay — skip for inbox.
      final marker = tag.length >= 3 ? tag[2] : '';
      if (marker == 'write') continue;
      inboxRelays.add(url);
    }
    return inboxRelays;
  }

  /// Publishes [event] to specific relay [urls].
  ///
  /// Connects temporarily to any URL that is not already connected.
  Future<void> _publishEventToRelays(
    NostrEvent event,
    List<String> urls,
  ) async {
    final eventJson = jsonEncode(['EVENT', event.toJson()]);
    for (final url in urls) {
      // Reuse an existing connection or open a transient one.
      if (!(_connections.containsKey(url) && _connections[url]!.isConnected)) {
        await connectRelay(url);
      }
      final conn = _connections[url];
      if (conn != null && conn.isConnected) {
        try {
          conn.channel.sink.add(eventJson);
        } on Object {
          // Skip failures on individual relays.
        }
      }
    }
  }

  // ---------------------------------------------------------------------------
  // NIP-36: Sensitive Content (content-warning tag)
  // ---------------------------------------------------------------------------

  @override
  Future<NostrEvent> publishTextNote(
    String content, {
    List<List<String>>? tags,
    String? contentWarning,
  }) async {
    final allTags = <List<String>>[
      ...?tags,
      if (contentWarning != null) ['content-warning', contentWarning],
    ];
    final event = await signEvent(
      UnsignedNostrEvent(
        kind: NostrKind.textNote,
        content: content,
        tags: allTags,
      ),
    );
    await publishEvent(event);
    return event;
  }

  @override
  Future<NostrEvent> publishSensitiveTextNote(
    String content, {
    String? contentWarning,
    List<List<String>>? tags,
  }) => publishTextNote(
    content,
    tags: tags,
    contentWarning: contentWarning ?? '',
  );

  @override
  Future<NostrEvent> publishLongFormContent({
    required String identifier,
    required String title,
    required String content,
    String? summary,
    String? image,
    List<String> hashtags = const [],
    DateTime? publishedAt,
    String? contentWarning,
  }) async {
    final now = DateTime.now();
    final pubAt = publishedAt ?? now;
    final tags = <List<String>>[
      ['d', identifier],
      ['title', title],
      ['published_at', (pubAt.millisecondsSinceEpoch ~/ 1000).toString()],
      if (summary != null) ['summary', summary],
      if (image != null) ['image', image],
      for (final tag in hashtags) ['t', tag],
      if (contentWarning != null) ['content-warning', contentWarning],
    ];

    final event = await signEvent(
      UnsignedNostrEvent(
        kind: NostrKind.longFormContent,
        content: content,
        tags: tags,
      ),
    );
    await publishEvent(event);
    return event;
  }

  // ---------------------------------------------------------------------------
  // NIP-46: Nostr Connect (Remote Signing)
  // ---------------------------------------------------------------------------

  @override
  Future<String?> sendNostrConnectRequest(
    String bunkerPubkey, {
    required String method,
    required List<dynamic> params,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final myPrivKey = await auth.getPrivateKeyBytes();
    final myPubKey = await auth.getPublicKeyHex();
    if (myPrivKey == null || myPubKey == null) {
      throw StateError('No identity configured');
    }

    final requestId = _uuid.v4();
    final requestPayload = jsonEncode({
      'id': requestId,
      'method': method,
      'params': params,
    });

    // Encrypt request using NIP-44.
    final bunkerPubkeyBytes = _hexToBytes(bunkerPubkey);
    final convKey = Nip44.getConversationKey(myPrivKey, bunkerPubkeyBytes);
    final encrypted = Nip44.encrypt(requestPayload, convKey);

    // Publish kind 24133 request event.
    final requestEvent = await signEvent(
      UnsignedNostrEvent(
        kind: NostrKind.nostrConnectRequest,
        content: encrypted,
        tags: [
          ['p', bunkerPubkey],
        ],
      ),
    );
    await publishEvent(requestEvent);

    // Wait for a kind 24134 response from the bunker.
    final completer = Completer<String?>();
    Timer? timer;
    StreamSubscription<NostrEvent>? sub;

    void finish(String? result) {
      timer?.cancel();
      sub?.cancel();
      if (!completer.isCompleted) completer.complete(result);
    }

    timer = Timer(timeout, () => finish(null));

    sub =
        subscribe([
          NostrFilter(
            kinds: const [NostrKind.nostrConnectResponse],
            pTags: [myPubKey],
            authors: [bunkerPubkey],
          ),
        ]).listen((event) {
          try {
            final decrypted = Nip44.decrypt(event.content, convKey);
            final json = jsonDecode(decrypted) as Map<String, dynamic>;
            if (json['id'] == requestId) {
              final error = json['error'] as String?;
              if (error != null && error.isNotEmpty) {
                finish(null);
              } else {
                finish(json['result'] as String?);
              }
            }
          } on Object {
            // Not for us or malformed.
          }
        });

    return completer.future;
  }

  // ---------------------------------------------------------------------------
  // NIP-56: Reporting
  // ---------------------------------------------------------------------------

  @override
  Future<NostrEvent> reportContent({
    String? targetEventId,
    required String targetPubkey,
    required NostrReportType reportType,
    String? reason,
  }) async {
    final tags = <List<String>>[
      ['p', targetPubkey, reportType.value],
      if (targetEventId != null) ['e', targetEventId, reportType.value],
    ];

    final event = await signEvent(
      UnsignedNostrEvent(
        kind: NostrKind.report,
        content: reason ?? '',
        tags: tags,
      ),
    );
    await publishEvent(event);
    return event;
  }

  // ---------------------------------------------------------------------------
  // NIP-58: Badges
  // ---------------------------------------------------------------------------

  @override
  Future<NostrEvent> defineBadge({
    required String badgeId,
    required String name,
    String? description,
    String? image,
    List<({String url, String dimensions})> thumbs = const [],
  }) async {
    final tags = <List<String>>[
      ['d', badgeId],
      ['name', name],
      if (description != null) ['description', description],
      if (image != null) ['image', image],
      for (final t in thumbs) ['thumb', t.url, t.dimensions],
    ];

    final event = await signEvent(
      UnsignedNostrEvent(
        kind: NostrKind.badgeDefinition,
        content: '',
        tags: tags,
      ),
    );
    await publishEvent(event);
    return event;
  }

  @override
  Future<NostrEvent> awardBadge({
    required String badgeDefinitionEventId,
    required String badgeIdentifier,
    required String badgeCreatorPubkey,
    required List<String> recipientPubkeys,
    List<String> awardedEventIds = const [],
  }) async {
    // NIP-58 requires both the `a`-tag (kind:creator:d-tag address) and the
    // `e`-tag (specific event ID) to reference the badge definition.
    final tags = <List<String>>[
      [
        'a',
        '${NostrKind.badgeDefinition}:$badgeCreatorPubkey:$badgeIdentifier',
      ],
      ['e', badgeDefinitionEventId],
      for (final pk in recipientPubkeys) ['p', pk],
      for (final id in awardedEventIds) ['e', id],
    ];

    final event = await signEvent(
      UnsignedNostrEvent(kind: NostrKind.badgeAward, content: '', tags: tags),
    );
    await publishEvent(event);
    return event;
  }

  @override
  Stream<NostrEvent> fetchBadgeDefinitions(
    String creatorPubkey, {
    int limit = 50,
  }) {
    return subscribe([
      NostrFilter(
        kinds: const [NostrKind.badgeDefinition],
        authors: [creatorPubkey],
        limit: limit,
      ),
    ]);
  }

  @override
  Stream<NostrEvent> fetchBadgesAwardedTo(
    String recipientPubkey, {
    int limit = 50,
  }) {
    return subscribe([
      NostrFilter(
        kinds: const [NostrKind.badgeAward],
        pTags: [recipientPubkey],
        limit: limit,
      ),
    ]);
  }

  // ---------------------------------------------------------------------------
  // NIP-78: Application-Specific Data
  // ---------------------------------------------------------------------------

  @override
  Future<NostrEvent> publishAppData({
    required String appId,
    required String content,
    List<List<String>> extraTags = const [],
  }) async {
    final tags = <List<String>>[
      ['d', appId],
      ...extraTags,
    ];

    final event = await signEvent(
      UnsignedNostrEvent(kind: NostrKind.appData, content: content, tags: tags),
    );
    await publishEvent(event);
    return event;
  }

  @override
  Future<NostrEvent?> fetchAppData(String appId, {String? authorPubkey}) async {
    final pubkey = authorPubkey ?? await auth.getPublicKeyHex();
    if (pubkey == null) return null;

    final events = <NostrEvent>[];
    await subscribe([
          NostrFilter(
            kinds: const [NostrKind.appData],
            authors: [pubkey],
            dTags: [appId],
            limit: 1,
          ),
        ])
        .listen(events.add)
        .asFuture<void>()
        .timeout(const Duration(seconds: 5), onTimeout: () {});

    if (events.isEmpty) return null;
    // Return the most recent one.
    events.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return events.first;
  }

  // ---------------------------------------------------------------------------
  // NIP-84: Highlights
  // ---------------------------------------------------------------------------

  @override
  Future<NostrEvent> publishHighlight({
    required String content,
    required String sourceUrl,
    String? comment,
    String? context,
    String? sourceArticleAddr,
  }) async {
    final tags = <List<String>>[
      ['r', sourceUrl],
      if (context != null) ['context', context],
      if (comment != null) ['comment', comment],
      if (sourceArticleAddr != null) ['a', sourceArticleAddr],
    ];

    final event = await signEvent(
      UnsignedNostrEvent(
        kind: NostrKind.highlight,
        content: content,
        tags: tags,
      ),
    );
    await publishEvent(event);
    return event;
  }

  @override
  Stream<NostrEvent> fetchHighlights(String sourceUrl, {int limit = 100}) {
    return subscribe([
      NostrFilter(
        kinds: const [NostrKind.highlight],
        rTags: [sourceUrl],
        limit: limit,
      ),
    ]);
  }

  @override
  Stream<NostrEvent> fetchHighlightsByAuthor(
    String authorPubkey, {
    int limit = 50,
  }) {
    return subscribe([
      NostrFilter(
        kinds: const [NostrKind.highlight],
        authors: [authorPubkey],
        limit: limit,
      ),
    ]);
  }

  // ---------------------------------------------------------------------------
  // NIP-89: App Handlers
  // ---------------------------------------------------------------------------

  @override
  Future<NostrEvent> publishAppHandler({
    required String handlerId,
    required String name,
    required String url,
    String? description,
    String? picture,
    List<int> supportedKinds = const [],
  }) async {
    final tags = <List<String>>[
      ['d', handlerId],
      ['name', name],
      ['web', url, 'nevent'],
      if (description != null) ['about', description],
      if (picture != null) ['picture', picture],
      for (final k in supportedKinds) ['k', k.toString()],
    ];

    final event = await signEvent(
      UnsignedNostrEvent(
        kind: NostrKind.handlerInformation,
        content: '',
        tags: tags,
      ),
    );
    await publishEvent(event);
    return event;
  }

  @override
  Stream<NostrEvent> fetchAppHandlers(int kind, {int limit = 20}) {
    return subscribe([
      NostrFilter(
        kinds: const [NostrKind.handlerInformation],
        kTags: [kind.toString()],
        limit: limit,
      ),
    ]);
  }

  @override
  Future<NostrEvent> setPreferredAppHandler({
    required int eventKind,
    required String handlerCoordinate,
    required String handlerRelayUrl,
  }) async {
    final tags = <List<String>>[
      ['d', eventKind.toString()],
      ['a', handlerCoordinate, handlerRelayUrl],
      ['k', eventKind.toString()],
    ];

    final event = await signEvent(
      UnsignedNostrEvent(
        kind: NostrKind.handlerRecommendation,
        content: '',
        tags: tags,
      ),
    );
    await publishEvent(event);
    return event;
  }

  @override
  Future<NostrEvent?> fetchPreferredAppHandler(int eventKind) async {
    final myPubKey = await auth.getPublicKeyHex();
    if (myPubKey == null) return null;

    final events = <NostrEvent>[];
    await subscribe([
          NostrFilter(
            kinds: const [NostrKind.handlerRecommendation],
            authors: [myPubKey],
            dTags: [eventKind.toString()],
            limit: 1,
          ),
        ])
        .listen(events.add)
        .asFuture<void>()
        .timeout(const Duration(seconds: 5), onTimeout: () {});

    if (events.isEmpty) return null;
    return events.first;
  }

  // ---------------------------------------------------------------------------
  // NIP-90: Data Vending Machines (DVMs)
  // ---------------------------------------------------------------------------

  @override
  Future<NostrEvent> submitDvmJob({
    required int jobKind,
    required List<NostrDvmInput> inputs,
    String? outputMimeType,
    int? bidMillisats,
    List<String> dvmPubkeys = const [],
    List<List<String>> extraTags = const [],
  }) async {
    assert(
      jobKind >= 5000 && jobKind <= 5999,
      'DVM job kind must be 5000-5999, got $jobKind',
    );

    final tags = <List<String>>[
      for (final input in inputs) input.toTag(),
      if (outputMimeType != null) ['output', outputMimeType],
      if (bidMillisats != null) ['bid', bidMillisats.toString()],
      for (final pk in dvmPubkeys) ['p', pk],
      ...extraTags,
    ];

    final event = await signEvent(
      UnsignedNostrEvent(kind: jobKind, content: '', tags: tags),
    );
    await publishEvent(event);
    return event;
  }

  @override
  Stream<NostrEvent> watchDvmJobResults(String jobEventId) {
    // Filter by e-tag pointing to the job request; accept result kinds
    // (6000-6999) and feedback kind (7000) client-side.
    return subscribe([
      NostrFilter(eTags: [jobEventId]),
    ]).where((event) => event.kind >= 6000 && event.kind <= 7000);
  }

  // ---------------------------------------------------------------------------
  // NIP-94: File Metadata
  // ---------------------------------------------------------------------------

  @override
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
  }) async {
    final tags = <List<String>>[
      ['url', url],
      ['m', mimeType],
      if (sha256 != null) ['x', sha256],
      if (originalHash != null) ['ox', originalHash],
      if (size != null) ['size', size.toString()],
      if (dimensions != null) ['dim', dimensions],
      if (blurhash != null) ['blurhash', blurhash],
      if (magnetUri != null) ['magnet', magnetUri],
      if (torrentInfoHash != null) ['i', torrentInfoHash],
      for (final fb in fallbackUrls) ['fallback', fb],
    ];

    final event = await signEvent(
      UnsignedNostrEvent(
        kind: NostrKind.fileMetadata,
        content: description ?? '',
        tags: tags,
      ),
    );
    await publishEvent(event);
    return event;
  }

  @override
  Stream<NostrEvent> fetchFileMetadata({
    List<String>? authors,
    List<String>? mimeTypes,
    int limit = 50,
  }) {
    // NIP-94 doesn't define a `#m` filter, but relay support varies.
    // We filter client-side if mimeTypes is specified.
    final raw = subscribe([
      NostrFilter(
        kinds: const [NostrKind.fileMetadata],
        authors: authors,
        limit: limit,
      ),
    ]);

    if (mimeTypes == null || mimeTypes.isEmpty) return raw;

    return raw.where((event) {
      for (final tag in event.tags) {
        if (tag.length >= 2 && tag[0] == 'm') {
          return mimeTypes.contains(tag[1]);
        }
      }
      return false;
    });
  }

  /// Connects to all configured relays.
  Future<void> connectAll() async {
    await _ensureConfigLoaded();
    for (final config in _relayConfigs) {
      await connectRelay(config.url);
    }
  }

  @override
  Future<void> dispose() async {
    // Copy values before iterating to avoid concurrent modification
    // if close/cancel callbacks trigger map changes.
    final subs = _subscriptions.values.toList();
    _subscriptions.clear();
    _subscriptionFilters.clear();

    for (final sub in subs) {
      await sub.close();
    }

    final conns = _connections.values.toList();
    _connections.clear();

    for (final conn in conns) {
      conn.reconnectTimer?.cancel();
      await conn.subscription?.cancel();
      try {
        await conn.channel.sink.close();
      } on Object {
        // Channel may already be closed.
      }
    }
  }

  // -------------------------------------------------------------------------
  // Utilities
  // -------------------------------------------------------------------------

  static Uint8List _sha256(Uint8List input) {
    final digest = SHA256Digest();
    return digest.process(input);
  }

  static String _bytesToHex(Uint8List bytes) {
    final buffer = StringBuffer();
    for (final b in bytes) {
      buffer.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }

  static Uint8List _hexToBytes(String hex) {
    final result = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < hex.length; i += 2) {
      result[i ~/ 2] = int.parse(hex.substring(i, i + 2), radix: 16);
    }
    return result;
  }
}

/// Internal relay connection state.
class _RelayConnection {
  _RelayConnection({required this.url, required this.channel});

  final String url;
  final WebSocketChannel channel;
  // ignore: cancel_subscriptions
  StreamSubscription<dynamic>? subscription;
  bool isConnected = false;
  Timer? reconnectTimer;
  int reconnectDelay = 5;
}
