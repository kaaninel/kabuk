/// Identity agent — manages Nostr identity and social interactions.
///
/// Provides tools for managing the user's Nostr identity, connecting to
/// relays, publishing events (text notes, profile metadata), fetching
/// profiles, and reading the user's social feed. Uses the [NostrService]
/// for all relay communication and [AuthService] for signing.
library;

import 'dart:convert';

import 'package:kabuk/agents/base.dart';
import 'package:kabuk/agents/context.dart';
import 'package:kabuk/agents/llm.dart';
import 'package:kabuk/agents/memory.dart';
import 'package:kabuk/agents/messages.dart';
import 'package:kabuk/config/result.dart';
import 'package:kabuk/services/auth.dart' show AuthService;
import 'package:kabuk/services/exports.dart' show AuthService;
import 'package:kabuk/services/nostr.dart';
import 'package:kabuk/services/nostr_utils.dart';

/// Agent for Nostr identity and social communication.
///
/// Handles profile management, relay connections, publishing notes,
/// reading feeds, and interacting with the Nostr network through
/// the user's secp256k1 keypair.
class IdentityAgent extends BaseAgent with AgentMemoryMixin {
  @override
  String get name => 'identity';

  @override
  String get description =>
      'Manages Nostr identity — profile, relays, publish notes, read feed.';

  @override
  String get systemPrompt => '''
You are the Identity agent for Kabuk. You manage the user's decentralized
identity on the Nostr network — a censorship-resistant, open social protocol
based on cryptographic keypairs.

Capabilities:
• Show identity info — public key (hex and npub/bech32), display name
• Connect to Nostr relays for publishing and reading
• Publish text notes (kind 1 events) to connected relays
• Update profile metadata (name, about, picture URL)
• Fetch other users' Nostr profiles by npub or hex pubkey
• Read the user's social feed from connected relays
• Sign arbitrary messages with the user's secp256k1 keypair

Nostr Context:
• Nostr uses secp256k1 keypairs — the private key never leaves the device
• npub is the human-readable public key format (bech32-encoded)
• Relays are WebSocket servers that store and relay events
• Kind 1 = text note, Kind 0 = profile metadata
• The user's keypair is managed by Kabuk's Auth service

Usage Guidelines:
• Always confirm before publishing to the network — it's public and permanent
• When showing identity, display both the npub and a truncated hex key
• Warn users if no relays are connected before trying to publish/read
• When fetching someone else's profile, search by npub or name
• Keep relay management simple — most users only need 2-3 relays
• Emphasize that the private key stays on-device and is never shared
''';

  @override
  List<AgentTool> get tools => [
    AgentTool(
      name: 'get_identity',
      description: 'Get the current user\'s Nostr identity information.',
      parameters: <String, dynamic>{
        'type': 'object',
        'properties': <String, dynamic>{},
      },
      execute: _getIdentity,
    ),
    AgentTool(
      name: 'publish_note',
      description: 'Publish a text note (kind 1) to the Nostr network.',
      parameters: {
        'type': 'object',
        'properties': {
          'content': {
            'type': 'string',
            'description': 'The text content of the note to publish.',
          },
        },
        'required': ['content'],
      },
      execute: _publishNote,
    ),
    AgentTool(
      name: 'update_profile',
      description: 'Update the user\'s Nostr profile metadata (kind 0).',
      parameters: {
        'type': 'object',
        'properties': {
          'name': {'type': 'string', 'description': 'Display name.'},
          'about': {'type': 'string', 'description': 'Short bio / about text.'},
          'picture': {
            'type': 'string',
            'description': 'URL of the profile picture.',
          },
          'nip05': {
            'type': 'string',
            'description': 'NIP-05 identifier (e.g. user@domain.com).',
          },
        },
      },
      execute: _updateProfile,
    ),
    AgentTool(
      name: 'list_relays',
      description: 'List all configured Nostr relays and their status.',
      parameters: <String, dynamic>{
        'type': 'object',
        'properties': <String, dynamic>{},
      },
      execute: _listRelays,
    ),
    AgentTool(
      name: 'add_relay',
      description: 'Add and connect to a new Nostr relay.',
      parameters: {
        'type': 'object',
        'properties': {
          'url': {
            'type': 'string',
            'description': 'The relay WebSocket URL (wss://...).',
          },
          'read': {
            'type': 'boolean',
            'description': 'Read events from this relay (default true).',
          },
          'write': {
            'type': 'boolean',
            'description': 'Write events to this relay (default true).',
          },
        },
        'required': ['url'],
      },
      execute: _addRelay,
    ),
    AgentTool(
      name: 'remove_relay',
      description: 'Remove a Nostr relay.',
      parameters: {
        'type': 'object',
        'properties': {
          'url': {'type': 'string', 'description': 'The relay URL to remove.'},
        },
        'required': ['url'],
      },
      execute: _removeRelay,
    ),
    AgentTool(
      name: 'fetch_profile',
      description: 'Fetch a user\'s profile from relays by their public key.',
      parameters: {
        'type': 'object',
        'properties': {
          'pubkey': {
            'type': 'string',
            'description': 'The hex-encoded public key or npub to look up.',
          },
        },
        'required': ['pubkey'],
      },
      execute: _fetchProfile,
    ),
    AgentTool(
      name: 'read_feed',
      description: 'Read recent text notes from the Nostr network.',
      parameters: {
        'type': 'object',
        'properties': {
          'authors': {
            'type': 'array',
            'items': {'type': 'string'},
            'description':
                'Public keys to filter by (hex). If empty, reads global feed.',
          },
          'limit': {
            'type': 'integer',
            'description': 'Maximum number of notes (default 20).',
          },
        },
      },
      execute: _readFeed,
    ),
    AgentTool(
      name: 'sign_message',
      description: 'Sign an arbitrary message with the user\'s Nostr keypair.',
      parameters: {
        'type': 'object',
        'properties': {
          'message': {'type': 'string', 'description': 'The message to sign.'},
        },
        'required': ['message'],
      },
      execute: _signMessage,
    ),
    AgentTool(
      name: 'list_identities',
      description: 'List all stored Nostr identities with their public keys.',
      parameters: <String, dynamic>{
        'type': 'object',
        'properties': <String, dynamic>{},
      },
      execute: _listIdentities,
    ),
    AgentTool(
      name: 'switch_identity',
      description: 'Switch the active identity by public key hex.',
      parameters: {
        'type': 'object',
        'properties': {
          'pubkey': {
            'type': 'string',
            'description':
                'Hex-encoded public key of the identity to switch to.',
          },
        },
        'required': ['pubkey'],
      },
      execute: _switchIdentity,
    ),
    AgentTool(
      name: 'remove_identity',
      description:
          'Remove a stored identity by public key hex. '
          'Cannot remove the last identity.',
      parameters: {
        'type': 'object',
        'properties': {
          'pubkey': {
            'type': 'string',
            'description': 'Hex-encoded public key of the identity to remove.',
          },
        },
        'required': ['pubkey'],
      },
      execute: _removeIdentity,
    ),
  ];

  @override
  Set<AgentCapability> get requiredCapabilities => {
    AgentCapability.llmCall,
    AgentCapability.knowledgeRead,
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
        'What would you like to do with your identity?',
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

  Future<ToolResult> _getIdentity(
    Map<String, dynamic> args,
    AgentContext context,
  ) async {
    final user = await context.auth.currentUser;
    if (user == null) {
      return const ToolResult.text(
        'No identity configured. Generate a keypair in Settings → Identity.',
      );
    }

    final nostr = context.nostr;
    final relayCount = nostr?.connectedRelays.length ?? 0;
    final totalRelays = nostr?.relays.length ?? 0;

    return ToolResult.text('''
**Your Nostr Identity**
- **Name:** ${user.displayName}
- **npub:** ${user.npub ?? 'N/A'}
- **Public Key:** ${user.publicKeyHex ?? 'N/A'}
- **Created:** ${user.createdAt?.toIso8601String() ?? 'Unknown'}
- **Relays:** $relayCount connected / $totalRelays configured
''');
  }

  Future<ToolResult> _publishNote(
    Map<String, dynamic> args,
    AgentContext context,
  ) async {
    final content = args['content'] as String? ?? '';
    if (content.isEmpty) {
      return const ToolResult.error('Note content cannot be empty.');
    }

    final nostr = context.nostr;
    if (nostr == null) {
      return const ToolResult.error(
        'Nostr service not available. Configure your identity first.',
      );
    }

    try {
      final event = await nostr.publishTextNote(content);
      return ToolResult.text(
        'Published note to Nostr!\n'
        '- **Event ID:** ${event.id.substring(0, 16)}...\n'
        '- **Relays:** ${nostr.connectedRelays.length} relay(s)',
      );
    } on StateError {
      return const ToolResult.error(
        'No identity configured. Generate a keypair first.',
      );
    }
  }

  Future<ToolResult> _updateProfile(
    Map<String, dynamic> args,
    AgentContext context,
  ) async {
    final nostr = context.nostr;
    if (nostr == null) {
      return const ToolResult.error('Nostr service not available.');
    }

    try {
      final event = await nostr.publishMetadata(
        name: args['name'] as String?,
        about: args['about'] as String?,
        picture: args['picture'] as String?,
        nip05: args['nip05'] as String?,
      );

      // Also update local display name if provided.
      final name = args['name'] as String?;
      if (name != null) {
        await context.auth.setDisplayName(name);
      }

      return ToolResult.text(
        'Profile updated and published to relays.\n'
        '- **Event ID:** ${event.id.substring(0, 16)}...',
      );
    } on StateError {
      return const ToolResult.error('No identity configured.');
    }
  }

  Future<ToolResult> _listRelays(
    Map<String, dynamic> args,
    AgentContext context,
  ) async {
    final nostr = context.nostr;
    if (nostr == null) {
      return const ToolResult.text('Nostr service not available.');
    }

    final relays = nostr.relays;
    if (relays.isEmpty) {
      return const ToolResult.text(
        'No relays configured. Add relays to connect to the Nostr network.',
      );
    }

    final connected = nostr.connectedRelays.toSet();
    final lines = relays
        .map((r) {
          final status = connected.contains(r.url) ? '🟢' : '🔴';
          final mode = [if (r.read) 'read', if (r.write) 'write'].join('+');
          return '- $status **${r.url}** ($mode)';
        })
        .join('\n');

    return ToolResult.text(
      'Configured relays:\n$lines\n\n'
      '${connected.length}/${relays.length} connected.',
    );
  }

  Future<ToolResult> _addRelay(
    Map<String, dynamic> args,
    AgentContext context,
  ) async {
    final url = args['url'] as String? ?? '';
    if (url.isEmpty || !url.startsWith('wss://')) {
      return const ToolResult.error(
        'Invalid relay URL. Must start with wss://',
      );
    }

    final nostr = context.nostr;
    if (nostr == null) {
      return const ToolResult.error('Nostr service not available.');
    }

    final read = args['read'] as bool? ?? true;
    final write = args['write'] as bool? ?? true;

    await nostr.addRelay(RelayConfig(url: url, read: read, write: write));

    return ToolResult.text('Added relay: $url (read: $read, write: $write)');
  }

  Future<ToolResult> _removeRelay(
    Map<String, dynamic> args,
    AgentContext context,
  ) async {
    final url = args['url'] as String? ?? '';
    if (url.isEmpty) {
      return const ToolResult.error('Relay URL is required.');
    }

    final nostr = context.nostr;
    if (nostr == null) {
      return const ToolResult.error('Nostr service not available.');
    }

    await nostr.removeRelay(url);
    return ToolResult.text('Removed relay: $url');
  }

  Future<ToolResult> _fetchProfile(
    Map<String, dynamic> args,
    AgentContext context,
  ) async {
    final pubkey = args['pubkey'] as String? ?? '';
    if (pubkey.isEmpty) {
      return const ToolResult.error('Public key is required.');
    }

    final nostr = context.nostr;
    if (nostr == null) {
      return const ToolResult.error('Nostr service not available.');
    }

    // Handle npub format.
    final hexKey = pubkey.startsWith('npub1') ? _npubToHex(pubkey) : pubkey;

    if (hexKey == null) {
      return const ToolResult.error('Invalid public key format.');
    }

    final event = await nostr.fetchProfile(hexKey);
    if (event == null) {
      return ToolResult.text('No profile found for $pubkey.');
    }

    try {
      final metadata = jsonDecode(event.content) as Map<String, dynamic>;
      final name = metadata['name'] as String? ?? 'Unknown';
      final about = metadata['about'] as String? ?? '';
      final nip05 = metadata['nip05'] as String? ?? '';

      return ToolResult.text('''
**Profile: $name**
- **About:** $about
- **NIP-05:** $nip05
- **Pubkey:** ${event.pubkey.substring(0, 16)}...
- **Last updated:** ${DateTime.fromMillisecondsSinceEpoch(event.createdAt * 1000)}
''');
    } on FormatException {
      return const ToolResult.text('Profile found but metadata was not valid JSON.');
    }
  }

  Future<ToolResult> _readFeed(
    Map<String, dynamic> args,
    AgentContext context,
  ) async {
    final nostr = context.nostr;
    if (nostr == null) {
      return const ToolResult.error('Nostr service not available.');
    }

    final authors = (args['authors'] as List?)?.cast<String>();
    final limit = (args['limit'] as int?) ?? 20;

    final sub = nostr.subscribe([
      NostrFilter(authors: authors, kinds: [NostrKind.textNote], limit: limit),
    ]);

    final events = await collectNostrEvents(
      sub,
      limit: limit,
      timeout: const Duration(seconds: 5),
    );

    if (events.isEmpty) {
      return const ToolResult.text('No notes found matching the criteria.');
    }

    // Sort by created_at descending.
    events.sort((a, b) => b.createdAt.compareTo(a.createdAt));

    final lines = events
        .take(limit)
        .map((e) {
          final time = DateTime.fromMillisecondsSinceEpoch(e.createdAt * 1000);
          final author = e.pubkey.substring(0, 8);
          final preview = e.content.length > 100
              ? '${e.content.substring(0, 100)}…'
              : e.content;
          return '- **$author...** ($time)\n  $preview';
        })
        .join('\n');

    return ToolResult.text('Recent notes:\n$lines');
  }

  Future<ToolResult> _signMessage(
    Map<String, dynamic> args,
    AgentContext context,
  ) async {
    final message = args['message'] as String? ?? '';
    if (message.isEmpty) {
      return const ToolResult.error('Message cannot be empty.');
    }

    try {
      final result = await context.auth.sign(message.codeUnits);
      switch (result) {
        case Success(:final value):
          final sigHex = value
              .map((b) => b.toRadixString(16).padLeft(2, '0'))
              .join();
          return ToolResult.text(
            'Message signed!\n- **Signature:** ${sigHex.substring(0, 32)}...',
          );
        case Failure(:final error):
          return ToolResult.error('Signing failed: $error');
      }
    } on StateError {
      return const ToolResult.error('No identity configured.');
    }
  }

  // ---------------------------------------------------------------------------
  // Multi-identity tools
  // ---------------------------------------------------------------------------

  Future<ToolResult> _listIdentities(
    Map<String, dynamic> args,
    AgentContext context,
  ) async {
    final identities = await context.auth.listIdentities();
    if (identities.isEmpty) {
      return const ToolResult.text('No identities stored.');
    }
    final current = await context.auth.currentUser;
    final lines = identities
        .map((id) {
          final active = id.id == current?.id ? ' **[ACTIVE]**' : '';
          final name = id.displayName.isNotEmpty ? id.displayName : 'Unnamed';
          final npub = id.npub ?? id.id.substring(0, 16);
          final created = id.createdAt != null
              ? ' (created ${id.createdAt!.toIso8601String().substring(0, 10)})'
              : '';
          return '- **$name**$active\n  $npub$created';
        })
        .join('\n');
    return ToolResult.text('${identities.length} identities:\n$lines');
  }

  Future<ToolResult> _switchIdentity(
    Map<String, dynamic> args,
    AgentContext context,
  ) async {
    var pubkey = args['pubkey'] as String? ?? '';
    if (pubkey.isEmpty) {
      return const ToolResult.error('Public key is required.');
    }
    // Support npub input.
    if (pubkey.startsWith('npub1')) {
      final hex = _npubToHex(pubkey);
      if (hex == null) return const ToolResult.error('Invalid npub.');
      pubkey = hex;
    }
    final result = await context.auth.switchIdentity(pubkey);
    return switch (result) {
      Success(:final value) => ToolResult.text(
        'Switched to **${value.displayName}** (${value.npub ?? value.id.substring(0, 16)}).',
      ),
      Failure(:final error) => ToolResult.error('Switch failed: $error'),
    };
  }

  Future<ToolResult> _removeIdentity(
    Map<String, dynamic> args,
    AgentContext context,
  ) async {
    var pubkey = args['pubkey'] as String? ?? '';
    if (pubkey.isEmpty) {
      return const ToolResult.error('Public key is required.');
    }
    if (pubkey.startsWith('npub1')) {
      final hex = _npubToHex(pubkey);
      if (hex == null) return const ToolResult.error('Invalid npub.');
      pubkey = hex;
    }
    final result = await context.auth.removeIdentity(pubkey);
    return switch (result) {
      Success() => const ToolResult.text('Identity removed successfully.'),
      Failure(:final error) => ToolResult.error('Remove failed: $error'),
    };
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Convert an npub bech32 string to hex pubkey.
  String? _npubToHex(String npub) {
    try {
      if (!npub.startsWith('npub1')) return null;
      final decoded = _bech32Decode(npub);
      if (decoded != null && decoded.length == 32) {
        return decoded.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      }
      return null;
    } on Object {
      return null;
    }
  }

  /// Minimal bech32 decoder for npub1... strings.
  static List<int>? _bech32Decode(String bech32) {
    const charset = 'qpzry9x8gf2tvdw0s3jn54khce6mua7l';
    final pos = bech32.lastIndexOf('1');
    if (pos < 1 || pos + 7 > bech32.length) return null;
    final data = <int>[];
    for (var i = pos + 1; i < bech32.length; i++) {
      final idx = charset.indexOf(bech32[i].toLowerCase());
      if (idx < 0) return null;
      data.add(idx);
    }
    // Remove checksum (last 6 chars).
    final values = data.sublist(0, data.length - 6);
    // Convert from 5-bit to 8-bit.
    final result = <int>[];
    var acc = 0;
    var bits = 0;
    for (final v in values) {
      acc = (acc << 5) | v;
      bits += 5;
      while (bits >= 8) {
        bits -= 8;
        result.add((acc >> bits) & 0xFF);
      }
    }
    return result;
  }
}
