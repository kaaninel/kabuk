/// Messaging agent — handles DMs, group chats, and media sharing over Nostr.
///
/// Provides tools for sending and reading direct messages, creating and
/// managing group channels (NIP-28), sharing media in conversations,
/// and managing contact lists. Works through [AgentContext.nostr].
library;

import 'dart:convert';

import 'package:kabuk/agents/base.dart';
import 'package:kabuk/agents/context.dart';
import 'package:kabuk/agents/llm.dart';
import 'package:kabuk/agents/memory.dart';
import 'package:kabuk/agents/messages.dart';

/// Agent for managing messaging — DMs, group channels, and media sharing.
class MessagingAgent extends BaseAgent with AgentMemoryMixin {
  @override
  String get name => 'messaging';

  @override
  String get description =>
      'Manages direct messages, group chats, and media sharing over Nostr.';

  @override
  String get systemPrompt => '''
You are the Messaging agent for Kabuk. You handle all Nostr-based messaging —
direct messages (DMs), group channels, and media sharing.

Capabilities:
• Send and read direct messages (NIP-17 gift-wrapped, end-to-end encrypted)
• Fetch DM history with a specific contact
• Create and manage group channels (NIP-28)
• Send messages to group channels
• Share media (images, files) in DMs
• Manage the user's contact list

Usage Guidelines:
• When the user wants to message someone, ask for the recipient (npub or hex
pubkey) if not already provided
• For DMs, messages are end-to-end encrypted — reassure the user about privacy
• When listing conversations, show the most recent message preview and timestamp
• For group channels, show the channel name and member count when available
• If the user provides an npub, convert it to hex before making API calls
• After sending a message, confirm delivery with a brief summary
• Be conversational — "Sent your message to Alice" is better than "Message
published successfully"
• When fetching history, show messages in chronological order with timestamps
• For media sharing, accept a URL and optional description
''';

  @override
  List<AgentTool> get tools => [
    AgentTool(
      name: 'send_dm',
      description: 'Send an encrypted direct message to a Nostr user.',
      parameters: {
        'type': 'object',
        'properties': {
          'recipient': {
            'type': 'string',
            'description': 'Recipient public key (hex or npub1... format).',
          },
          'content': {
            'type': 'string',
            'description': 'The message text to send.',
          },
        },
        'required': ['recipient', 'content'],
      },
      execute: _sendDm,
    ),
    AgentTool(
      name: 'fetch_dm_history',
      description: 'Fetch message history with a specific Nostr user.',
      parameters: {
        'type': 'object',
        'properties': {
          'peer': {
            'type': 'string',
            'description': 'Peer public key (hex or npub1... format).',
          },
          'limit': {
            'type': 'integer',
            'description': 'Maximum number of messages to fetch (default: 50).',
          },
        },
        'required': ['peer'],
      },
      execute: _fetchDmHistory,
    ),
    AgentTool(
      name: 'send_media_dm',
      description: 'Send a media attachment (image, file) in a DM.',
      parameters: {
        'type': 'object',
        'properties': {
          'recipient': {
            'type': 'string',
            'description': 'Recipient public key (hex or npub1... format).',
          },
          'media_url': {
            'type': 'string',
            'description': 'URL of the media file to share.',
          },
          'mime_type': {
            'type': 'string',
            'description': 'MIME type of the media (e.g., "image/jpeg").',
          },
          'caption': {
            'type': 'string',
            'description': 'Optional caption/description for the media.',
          },
          'file_name': {
            'type': 'string',
            'description': 'Original file name, if known.',
          },
        },
        'required': ['recipient', 'media_url'],
      },
      execute: _sendMediaDm,
    ),
    AgentTool(
      name: 'create_channel',
      description: 'Create a new public group channel (NIP-28).',
      parameters: {
        'type': 'object',
        'properties': {
          'name': {'type': 'string', 'description': 'Name of the channel.'},
          'about': {
            'type': 'string',
            'description': 'Description of the channel.',
          },
          'picture': {
            'type': 'string',
            'description': 'URL for the channel picture/avatar.',
          },
        },
        'required': ['name'],
      },
      execute: _createChannel,
    ),
    AgentTool(
      name: 'send_channel_message',
      description: 'Send a message to a group channel.',
      parameters: {
        'type': 'object',
        'properties': {
          'channel_id': {
            'type': 'string',
            'description': 'The channel event ID.',
          },
          'content': {
            'type': 'string',
            'description': 'The message text to send.',
          },
          'reply_to': {
            'type': 'string',
            'description': 'Event ID of the message being replied to, if any.',
          },
        },
        'required': ['channel_id', 'content'],
      },
      execute: _sendChannelMessage,
    ),
    AgentTool(
      name: 'search_channels',
      description: 'Search for public group channels by name or topic.',
      parameters: {
        'type': 'object',
        'properties': {
          'query': {
            'type': 'string',
            'description': 'Search query for channel names/descriptions.',
          },
          'limit': {
            'type': 'integer',
            'description': 'Maximum number of results to return (default: 10).',
          },
        },
        'required': ['query'],
      },
      execute: _searchChannels,
    ),
    AgentTool(
      name: 'get_channel_info',
      description: 'Get metadata for a group channel.',
      parameters: {
        'type': 'object',
        'properties': {
          'channel_id': {
            'type': 'string',
            'description': 'The channel event ID.',
          },
        },
        'required': ['channel_id'],
      },
      execute: _getChannelInfo,
    ),
    AgentTool(
      name: 'publish_contact_list',
      description: 'Publish the user\'s Nostr contact list (NIP-02).',
      parameters: {
        'type': 'object',
        'properties': {
          'pubkeys': {
            'type': 'array',
            'items': {'type': 'string'},
            'description':
                'List of hex public keys to include in the contact list.',
          },
        },
        'required': ['pubkeys'],
      },
      execute: _publishContactList,
    ),
    AgentTool(
      name: 'lookup_profile',
      description: 'Look up a Nostr user\'s profile by public key.',
      parameters: {
        'type': 'object',
        'properties': {
          'pubkey': {
            'type': 'string',
            'description': 'Public key (hex or npub1... format) to look up.',
          },
        },
        'required': ['pubkey'],
      },
      execute: _lookupProfile,
    ),
  ];

  @override
  Set<AgentCapability> get requiredCapabilities => {
    AgentCapability.knowledgeRead,
    AgentCapability.knowledgeWrite,
    AgentCapability.meshConnect,
    AgentCapability.meshSend,
    AgentCapability.authSign,
    AgentCapability.llmCall,
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
        'What would you like to do? I can send messages, fetch chat history, '
        'create group channels, and more.',
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
      temperature: 0.4,
    );
  }

  // ---------------------------------------------------------------------------
  // Tool Implementations
  // ---------------------------------------------------------------------------

  Future<ToolResult> _sendDm(
    Map<String, dynamic> args,
    AgentContext context,
  ) async {
    final nostr = context.nostr;
    if (nostr == null) {
      return const ToolResult.error('Nostr service is not available.');
    }

    final recipient = _resolvePublicKey(args['recipient'] as String);
    if (recipient == null) {
      return const ToolResult.error(
        'Invalid recipient. Please provide a valid hex pubkey or npub.',
      );
    }

    final content = args['content'] as String;

    try {
      await nostr.sendDirectMessage(recipient, content);
      return ToolResult.text('Message sent to ${_shortenPubkey(recipient)}.');
    } on Object catch (e) {
      return ToolResult.error('Failed to send message: $e');
    }
  }

  Future<ToolResult> _fetchDmHistory(
    Map<String, dynamic> args,
    AgentContext context,
  ) async {
    final nostr = context.nostr;
    if (nostr == null) {
      return const ToolResult.error('Nostr service is not available.');
    }

    final peer = _resolvePublicKey(args['peer'] as String);
    if (peer == null) {
      return const ToolResult.error(
        'Invalid peer pubkey. Please provide a valid hex pubkey or npub.',
      );
    }

    final limit = (args['limit'] as int?) ?? 50;

    try {
      final dms = await nostr.fetchDmHistory(peer, limit: limit);
      if (dms.isEmpty) {
        return ToolResult.text(
          'No message history found with ${_shortenPubkey(peer)}.',
        );
      }

      final buffer = StringBuffer(
        'Message history (${dms.length} messages):\n',
      );
      for (final dm in dms) {
        final direction = dm.isOwnMessage ? '→ You' : '← Them';
        final time = _formatTimestamp(dm.timestamp);
        buffer.writeln('[$time] $direction: ${dm.content}');
        if (dm.hasMedia) {
          buffer.writeln('  📎 ${dm.fileName ?? dm.mediaUrl ?? "attachment"}');
        }
      }

      return ToolResult.text(buffer.toString());
    } on Object catch (e) {
      return ToolResult.error('Failed to fetch history: $e');
    }
  }

  Future<ToolResult> _sendMediaDm(
    Map<String, dynamic> args,
    AgentContext context,
  ) async {
    final nostr = context.nostr;
    if (nostr == null) {
      return const ToolResult.error('Nostr service is not available.');
    }

    final recipient = _resolvePublicKey(args['recipient'] as String);
    if (recipient == null) {
      return const ToolResult.error(
        'Invalid recipient. Please provide a valid hex pubkey or npub.',
      );
    }

    final mediaUrl = args['media_url'] as String;
    final mimeType = args['mime_type'] as String?;
    final caption = args['caption'] as String?;
    final fileName = args['file_name'] as String?;

    try {
      await nostr.sendDirectMessageWithMedia(
        recipient,
        mediaUrl: mediaUrl,
        mimeType: mimeType,
        content: caption,
        fileName: fileName,
      );
      return ToolResult.text(
        'Media sent to ${_shortenPubkey(recipient)}: '
        '${fileName ?? mediaUrl}',
      );
    } on Object catch (e) {
      return ToolResult.error('Failed to send media: $e');
    }
  }

  Future<ToolResult> _createChannel(
    Map<String, dynamic> args,
    AgentContext context,
  ) async {
    final nostr = context.nostr;
    if (nostr == null) {
      return const ToolResult.error('Nostr service is not available.');
    }

    final channelName = args['name'] as String;
    final about = args['about'] as String?;
    final picture = args['picture'] as String?;

    try {
      final event = await nostr.createChannel(
        name: channelName,
        about: about,
        picture: picture,
      );
      return ToolResult.text(
        'Channel "$channelName" created (ID: ${event.id}).',
      );
    } on Object catch (e) {
      return ToolResult.error('Failed to create channel: $e');
    }
  }

  Future<ToolResult> _sendChannelMessage(
    Map<String, dynamic> args,
    AgentContext context,
  ) async {
    final nostr = context.nostr;
    if (nostr == null) {
      return const ToolResult.error('Nostr service is not available.');
    }

    final channelId = args['channel_id'] as String;
    final content = args['content'] as String;
    final replyTo = args['reply_to'] as String?;

    try {
      await nostr.sendChannelMessage(channelId, content, replyTo: replyTo);
      return const ToolResult.text('Message sent to channel.');
    } on Object catch (e) {
      return ToolResult.error('Failed to send channel message: $e');
    }
  }

  Future<ToolResult> _searchChannels(
    Map<String, dynamic> args,
    AgentContext context,
  ) async {
    final nostr = context.nostr;
    if (nostr == null) {
      return const ToolResult.error('Nostr service is not available.');
    }

    final query = args['query'] as String;
    final limit = (args['limit'] as int?) ?? 10;

    try {
      final events = await nostr.searchChannels(query, limit: limit).toList();

      if (events.isEmpty) {
        return ToolResult.text('No channels found matching "$query".');
      }

      final buffer = StringBuffer('Found ${events.length} channels:\n');
      for (final event in events) {
        try {
          final meta = jsonDecode(event.content) as Map<String, dynamic>;
          final name = meta['name'] as String? ?? 'Unnamed';
          final about = meta['about'] as String? ?? '';
          buffer.writeln('• $name — $about (ID: ${event.id})');
        } on Object {
          buffer.writeln('• Channel ${event.id}');
        }
      }
      return ToolResult.text(buffer.toString());
    } on Object catch (e) {
      return ToolResult.error('Failed to search channels: $e');
    }
  }

  Future<ToolResult> _getChannelInfo(
    Map<String, dynamic> args,
    AgentContext context,
  ) async {
    final nostr = context.nostr;
    if (nostr == null) {
      return const ToolResult.error('Nostr service is not available.');
    }

    final channelId = args['channel_id'] as String;

    try {
      final event = await nostr.fetchChannelMetadata(channelId);
      if (event == null) {
        return const ToolResult.text('Channel not found or no relays responded.');
      }

      final meta = jsonDecode(event.content) as Map<String, dynamic>;
      final name = meta['name'] as String? ?? 'Unnamed';
      final about = meta['about'] as String? ?? 'No description';
      final picture = meta['picture'] as String?;

      final buffer = StringBuffer()
        ..writeln('Channel: $name')
        ..writeln('About: $about')
        ..writeln('Created by: ${_shortenPubkey(event.pubkey)}');
      if (picture != null) buffer.writeln('Picture: $picture');

      return ToolResult.text(buffer.toString());
    } on Object catch (e) {
      return ToolResult.error('Failed to fetch channel info: $e');
    }
  }

  Future<ToolResult> _publishContactList(
    Map<String, dynamic> args,
    AgentContext context,
  ) async {
    final nostr = context.nostr;
    if (nostr == null) {
      return const ToolResult.error('Nostr service is not available.');
    }

    final pubkeys = (args['pubkeys'] as List).cast<String>();
    if (pubkeys.isEmpty) {
      return const ToolResult.error('No pubkeys provided.');
    }

    // Resolve any npubs to hex.
    final resolved = <String>[];
    for (final pk in pubkeys) {
      final hex = _resolvePublicKey(pk);
      if (hex == null) {
        return ToolResult.error('Invalid pubkey: $pk');
      }
      resolved.add(hex);
    }

    try {
      await nostr.publishContactList(resolved);
      return ToolResult.text(
        'Contact list published with ${resolved.length} contacts.',
      );
    } on Object catch (e) {
      return ToolResult.error('Failed to publish contact list: $e');
    }
  }

  Future<ToolResult> _lookupProfile(
    Map<String, dynamic> args,
    AgentContext context,
  ) async {
    final nostr = context.nostr;
    if (nostr == null) {
      return const ToolResult.error('Nostr service is not available.');
    }

    final pubkey = _resolvePublicKey(args['pubkey'] as String);
    if (pubkey == null) {
      return const ToolResult.error(
        'Invalid pubkey. Please provide a valid hex pubkey or npub.',
      );
    }

    try {
      final profile = await nostr.fetchProfileCached(pubkey);
      if (profile == null) {
        return ToolResult.text(
          'No profile found for ${_shortenPubkey(pubkey)}.',
        );
      }

      final buffer = StringBuffer()
        ..writeln('Name: ${profile.displayName}')
        ..writeln('Pubkey: ${_shortenPubkey(pubkey)}');
      if (profile.about != null) buffer.writeln('About: ${profile.about}');
      if (profile.nip05 != null) buffer.writeln('NIP-05: ${profile.nip05}');
      if (profile.picture != null) {
        buffer.writeln('Picture: ${profile.picture}');
      }
      if (profile.lud16 != null) {
        buffer.writeln('Lightning: ${profile.lud16}');
      }

      return ToolResult.text(buffer.toString());
    } on Object catch (e) {
      return ToolResult.error('Failed to look up profile: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Resolve a public key that may be in hex or npub format.
  static String? _resolvePublicKey(String input) {
    if (input.length == 64 && RegExp(r'^[0-9a-fA-F]+$').hasMatch(input)) {
      return input.toLowerCase();
    }
    if (input.startsWith('npub1')) {
      final decoded = _bech32Decode(input);
      if (decoded != null && decoded.length == 32) {
        return decoded.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      }
    }
    return null;
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
    final values = data.sublist(0, data.length - 6);
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

  /// Shorten a hex pubkey for display.
  static String _shortenPubkey(String hex) {
    if (hex.length <= 12) return hex;
    return '${hex.substring(0, 6)}...${hex.substring(hex.length - 6)}';
  }

  /// Format a timestamp for display.
  static String _formatTimestamp(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.month}/${dt.day}/${dt.year}';
  }
}
