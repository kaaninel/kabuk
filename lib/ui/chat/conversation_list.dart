/// Conversation list — messaging-app-style home for the Chat tab.
///
/// Shows all conversations in a WhatsApp/iMessage-style list.
/// "Kabuk AI" is pinned at the top as the primary agent contact.
/// Contacts from the knowledge store appear as available people.
/// Tapping a conversation opens the [ConversationDetail] screen.
library;

import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kabuk/config/providers.dart';
import 'package:kabuk/knowledge/database.dart';
import 'package:kabuk/knowledge/types/person.dart';
import 'package:kabuk/ui/chat/contact_detail_sheet.dart';
import 'package:kabuk/ui/chat/conversation_detail.dart';
import 'package:kabuk/ui/chat/nostr_channel_detail.dart';
import 'package:kabuk/ui/chat/nostr_chat_detail.dart';
import 'package:kabuk/ui/chat/qr_contact_exchange.dart';
import 'package:kabuk/ui/shared/identity_quick_switcher.dart';
import 'package:kabuk/ui/shared/kabuk_keyboard.dart';
import 'package:kabuk/ui/theme.dart';

/// The main chat tab — a messaging-style conversation list.
///
/// Layout (top to bottom):
/// 1. Contact avatars row (horizontal scroll)
/// 2. Pinned "Kabuk AI" contact
/// 3. Recent conversations list
class ConversationList extends ConsumerStatefulWidget {
  /// Creates a [ConversationList].
  const ConversationList({super.key});

  @override
  ConsumerState<ConversationList> createState() => _ConversationListState();
}

class _ConversationListState extends ConsumerState<ConversationList> {
  final _searchController = TextEditingController();
  Timer? _debounceTimer;
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _searchQuery = value.toLowerCase().trim());
    });
  }

  @override
  Widget build(BuildContext context) {
    final conversationsAsync = ref.watch(conversationsProvider);
    final contactsAsync = ref.watch(contactsProvider);
    final isConfigured = ref.watch(llmConfigProvider) != null ||
        ref.watch(localModelConfigProvider) != null;

    return Scaffold(
      appBar: AppBar(
        leading: const IdentityQuickSwitcher(),
        title: const Text('Chat'),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.add_rounded, size: 26),
            tooltip: 'New conversation',
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(KabukTheme.radiusMd),
            ),
            color: KabukTheme.surface,
            onSelected: (value) {
              switch (value) {
                case 'qr':
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const QrContactExchange(),
                    ),
                  );
                case 'channel':
                  _showNewChannelSheet(context, ref);
                case 'dm':
                  _showNewDmSheet(context, ref);
                case 'contact':
                  _showAddContactSheet(context, ref);
                case 'import_nostr':
                  _importNostrContacts(context, ref);
              }
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(
                value: 'qr',
                child: Row(
                  children: [
                    Icon(Icons.qr_code_rounded, size: 20, semanticLabel: ''),
                    SizedBox(width: 12),
                    Text('Add via QR Code'),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'channel',
                child: Row(
                  children: [
                    Icon(Icons.group_add_outlined, size: 20, semanticLabel: ''),
                    SizedBox(width: 12),
                    Text('New Channel'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'dm',
                child: Row(
                  children: [
                    Icon(Icons.send_rounded, size: 20, semanticLabel: ''),
                    SizedBox(width: 12),
                    Text('New Message'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'contact',
                child: Row(
                  children: [
                    Icon(Icons.person_add_outlined, size: 20, semanticLabel: ''),
                    SizedBox(width: 12),
                    Text('Add Contact'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'import_nostr',
                child: Row(
                  children: [
                    Icon(Icons.download_rounded, size: 20, semanticLabel: ''),
                    SizedBox(width: 12),
                    Text('Import Nostr Contacts'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: conversationsAsync.when(
        data: (conversations) => _buildBody(
          context,
          ref,
          conversations,
          contactsAsync.valueOrNull ?? const [],
          isConfigured,
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Text(
            'Error: $e',
            style: const TextStyle(color: KabukTheme.error),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    WidgetRef ref,
    List<Conversation> conversations,
    List<PersonData> contacts,
    bool isConfigured,
  ) {
    // Exclude Nostr topic subscriptions (belong in Explore) and agent
    // conversations (shown via the pinned Kabuk AI tile above).
    final baseFiltered = conversations
        .where(
          (c) =>
              c.type != 'nostr_topic' &&
              c.type != 'agent' &&
              !c.title.startsWith('Subscribed to Nostr topic'),
        )
        .toList();

    // Apply search filter if active.
    final filtered = _searchQuery.isEmpty
        ? baseFiltered
        : baseFiltered.where((c) {
            final title = c.title.toLowerCase();
            final lastMsg = (c.lastMessage ?? '').toLowerCase();
            return title.contains(_searchQuery) ||
                lastMsg.contains(_searchQuery);
          }).toList();

    return CustomScrollView(
      slivers: [
        // Contacts row (horizontal scroll strip).
        if (contacts.isNotEmpty)
          SliverToBoxAdapter(child: _ContactsRow(contacts: contacts)),

        // Search field.
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              KabukTheme.spacingMd,
              KabukTheme.spacingSm,
              KabukTheme.spacingMd,
              KabukTheme.spacingXs,
            ),
            child: KabukKeyboard(
              simple: true,
              controller: _searchController,
              onChanged: _onSearchChanged,
              hintText: 'Search conversations\u2026',
            ),
          ),
        ),

        // Section header.
        if (contacts.isNotEmpty)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                KabukTheme.spacingMd,
                KabukTheme.spacingSm,
                KabukTheme.spacingMd,
                KabukTheme.spacingXs,
              ),
              child: Text(
                'Recent',
                style: TextStyle(
                  color: KabukTheme.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),

        // Kabuk AI — always pinned, not affected by search.
        SliverToBoxAdapter(child: _KabukAiTile(isConfigured: isConfigured)),

        // Conversation list.
        if (filtered.isNotEmpty)
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) =>
                  _ConversationTile(conversation: filtered[index]),
              childCount: filtered.length,
            ),
          ),

        // Empty state when search returns no results.
        if (filtered.isEmpty && _searchQuery.isNotEmpty)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(KabukTheme.spacingLg),
              child: Center(
                child: Text(
                  'No conversations found',
                  style: TextStyle(
                    color: KabukTheme.textSecondary,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// Bottom sheet for creating a new NIP-28 group channel.
  void _showNewChannelSheet(BuildContext context, WidgetRef ref) {
    final nameCtrl = TextEditingController();
    final aboutCtrl = TextEditingController();

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: KabukTheme.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(KabukTheme.radiusXl),
        ),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
          KabukTheme.spacingMd,
          KabukTheme.spacingMd,
          KabukTheme.spacingMd,
          MediaQuery.of(ctx).viewInsets.bottom + KabukTheme.spacingMd,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: KabukTheme.textSecondary.withAlpha(100),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: KabukTheme.spacingMd),
            Row(
              children: [
                Icon(
                  Icons.group_rounded,
                  size: 20,
                  color: KabukTheme.blueAccent.withAlpha(180),
                ),
                const SizedBox(width: 8),
                Text(
                  'New Group Channel',
                  style: Theme.of(ctx).textTheme.titleLarge,
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Create a public channel',
              style: TextStyle(color: KabukTheme.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: KabukTheme.spacingMd),
            TextField(
              controller: nameCtrl,
              textCapitalization: TextCapitalization.words,
              style: const TextStyle(color: KabukTheme.textPrimary),
              decoration: const InputDecoration(
                labelText: 'Channel Name',
                prefixIcon: Icon(Icons.tag_rounded, size: 20),
              ),
            ),
            const SizedBox(height: KabukTheme.spacingSm),
            TextField(
              controller: aboutCtrl,
              maxLines: 2,
              style: const TextStyle(color: KabukTheme.textPrimary),
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
                prefixIcon: Icon(Icons.info_outline, size: 20),
              ),
            ),
            const SizedBox(height: KabukTheme.spacingLg),
            FilledButton(
              onPressed: () async {
                final channelName = nameCtrl.text.trim();
                if (channelName.isEmpty) return;
                final nostr = ref.read(nostrServiceProvider);
                try {
                  final about = aboutCtrl.text.trim().isEmpty
                      ? null
                      : aboutCtrl.text.trim();
                  final channelEvent = await nostr.createChannel(
                    name: channelName,
                    about: about,
                  );
                  final channelId = channelEvent.id;
                  final convId = 'nostr_channel_$channelId';
                  final db = ref.read(databaseProvider);
                  await db.upsertConversation(
                    ConversationsCompanion(
                      id: Value(convId),
                      title: Value(channelName),
                      type: const Value('nostr_channel'),
                      nostrPubkey: Value(channelId),
                      createdAt: Value(DateTime.now()),
                      updatedAt: Value(DateTime.now()),
                    ),
                  );
                  if (ctx.mounted) Navigator.of(ctx).pop();
                  if (context.mounted) {
                    unawaited(Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => NostrChannelDetail(
                          conversationId: convId,
                          channelEventId: channelId,
                          channelName: channelName,
                          channelAbout: about,
                        ),
                      ),
                    ));
                  }
                } on Object catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Failed to create channel: $e')),
                    );
                  }
                }
              },
              child: const Text('Create Channel'),
            ),
            const SizedBox(height: KabukTheme.spacingSm),
          ],
        ),
      ),
    ).then((_) {
      nameCtrl.dispose();
      aboutCtrl.dispose();
    });
  }

  /// Bottom sheet for adding a new contact.
  void _showAddContactSheet(BuildContext context, WidgetRef ref) {
    final nameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final nostrCtrl = TextEditingController();

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: KabukTheme.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(KabukTheme.radiusXl),
        ),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
          KabukTheme.spacingMd,
          KabukTheme.spacingMd,
          KabukTheme.spacingMd,
          MediaQuery.of(ctx).viewInsets.bottom + KabukTheme.spacingMd,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: KabukTheme.textSecondary.withAlpha(100),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: KabukTheme.spacingMd),
            Text('New Contact', style: Theme.of(ctx).textTheme.titleLarge),
            const SizedBox(height: KabukTheme.spacingMd),
            TextField(
              controller: nameCtrl,
              textCapitalization: TextCapitalization.words,
              style: const TextStyle(color: KabukTheme.textPrimary),
              decoration: const InputDecoration(
                labelText: 'Name',
                prefixIcon: Icon(Icons.person_outline, size: 20),
              ),
            ),
            const SizedBox(height: KabukTheme.spacingSm),
            TextField(
              controller: nostrCtrl,
              style: const TextStyle(
                color: KabukTheme.textPrimary,
                fontFamily: 'monospace',
                fontSize: 13,
              ),
              decoration: const InputDecoration(
                labelText: 'Nostr pubkey (npub or hex)',
                prefixIcon: Icon(Icons.key_rounded, size: 20),
                hintText: 'npub1... or 64-char hex',
                hintStyle: TextStyle(
                  color: KabukTheme.textSecondary,
                  fontSize: 12,
                ),
              ),
            ),
            const SizedBox(height: KabukTheme.spacingSm),
            TextField(
              controller: emailCtrl,
              keyboardType: TextInputType.emailAddress,
              style: const TextStyle(color: KabukTheme.textPrimary),
              decoration: const InputDecoration(
                labelText: 'Email (optional)',
                prefixIcon: Icon(Icons.email_outlined, size: 20),
              ),
            ),
            const SizedBox(height: KabukTheme.spacingSm),
            TextField(
              controller: phoneCtrl,
              keyboardType: TextInputType.phone,
              style: const TextStyle(color: KabukTheme.textPrimary),
              decoration: const InputDecoration(
                labelText: 'Phone (optional)',
                prefixIcon: Icon(Icons.phone_outlined, size: 20),
              ),
            ),
            const SizedBox(height: KabukTheme.spacingLg),
            FilledButton(
              onPressed: () async {
                final name = nameCtrl.text.trim();
                if (name.isEmpty) return;
                final nostrPubkey = _normalizeNostrPubkey(
                  nostrCtrl.text.trim(),
                );
                final store = ref.read(knowledgeStoreProvider);
                await store.createPerson(
                  name: name,
                  email: emailCtrl.text.trim().isEmpty
                      ? null
                      : emailCtrl.text.trim(),
                  telephone: phoneCtrl.text.trim().isEmpty
                      ? null
                      : phoneCtrl.text.trim(),
                  nostrPubkey: nostrPubkey,
                );
                if (ctx.mounted) {
                  Navigator.of(ctx).pop();
                }
              },
              child: const Text('Add Contact'),
            ),
            const SizedBox(height: KabukTheme.spacingSm),
          ],
        ),
      ),
    ).then((_) {
      nameCtrl.dispose();
      emailCtrl.dispose();
      phoneCtrl.dispose();
      nostrCtrl.dispose();
      // Use Future.delayed(Duration.zero) to push the invalidation past the
      // current event-loop turn.  The modal route will have fully unmounted
      // its overlay entry by the time this runs, so there are no lingering
      // provider dependents from the sheet's context tree.
      Future<void>.delayed(Duration.zero, () {
        ref.invalidate(contactsProvider);
      });
    });
  }

  /// Normalizes a Nostr public key input.
  ///
  /// Accepts npub1... bech32 or 64-char hex pubkey.
  /// Returns null if input is empty or invalid.
  static String? _normalizeNostrPubkey(String input) {
    if (input.isEmpty) return null;
    // Already hex (64 chars, all hex digits).
    if (input.length == 64 && RegExp(r'^[0-9a-fA-F]+$').hasMatch(input)) {
      return input.toLowerCase();
    }
    // npub bech32 — decode to hex.
    if (input.startsWith('npub1')) {
      try {
        final decoded = _bech32Decode(input);
        if (decoded != null && decoded.length == 32) {
          return decoded.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
        }
      } on Object {
        // Invalid npub — fall through.
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

  /// Bottom sheet for starting a new Nostr DM by pubkey.
  void _showNewDmSheet(BuildContext context, WidgetRef ref) {
    final pubkeyCtrl = TextEditingController();
    final nameCtrl = TextEditingController();

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: KabukTheme.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(KabukTheme.radiusXl),
        ),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
          KabukTheme.spacingMd,
          KabukTheme.spacingMd,
          KabukTheme.spacingMd,
          MediaQuery.of(ctx).viewInsets.bottom + KabukTheme.spacingMd,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: KabukTheme.textSecondary.withAlpha(100),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: KabukTheme.spacingMd),
            Row(
              children: [
                Icon(
                  Icons.lock_rounded,
                  size: 20,
                  color: KabukTheme.accentGreen.withAlpha(180),
                ),
                const SizedBox(width: 8),
                Text('New Message', style: Theme.of(ctx).textTheme.titleLarge),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'End-to-end encrypted',
              style: TextStyle(color: KabukTheme.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: KabukTheme.spacingMd),
            TextField(
              controller: pubkeyCtrl,
              style: const TextStyle(
                color: KabukTheme.textPrimary,
                fontFamily: 'monospace',
                fontSize: 13,
              ),
              decoration: const InputDecoration(
                labelText: 'Recipient pubkey',
                prefixIcon: Icon(Icons.key_rounded, size: 20),
                hintText: 'npub1... or 64-char hex',
                hintStyle: TextStyle(
                  color: KabukTheme.textSecondary,
                  fontSize: 12,
                ),
              ),
            ),
            const SizedBox(height: KabukTheme.spacingSm),
            TextField(
              controller: nameCtrl,
              textCapitalization: TextCapitalization.words,
              style: const TextStyle(color: KabukTheme.textPrimary),
              decoration: const InputDecoration(
                labelText: 'Display name (optional)',
                prefixIcon: Icon(Icons.person_outline, size: 20),
              ),
            ),
            const SizedBox(height: KabukTheme.spacingLg),
            FilledButton.icon(
              onPressed: () async {
                final pubkey = _normalizeNostrPubkey(pubkeyCtrl.text.trim());
                if (pubkey == null || pubkey.isEmpty) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(
                      content: Text('Invalid pubkey — enter npub or hex'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                  return;
                }
                final name = nameCtrl.text.trim().isEmpty
                    ? '@${pubkey.substring(0, 8)}'
                    : nameCtrl.text.trim();
                Navigator.of(ctx).pop();
                await _startNostrDm(context, ref, pubkey, name);
              },
              icon: const Icon(Icons.send_rounded, size: 18),
              label: const Text('Start DM'),
            ),
            const SizedBox(height: KabukTheme.spacingSm),
          ],
        ),
      ),
    ).then((_) {
      pubkeyCtrl.dispose();
      nameCtrl.dispose();
    });
  }

  /// Creates or opens a Nostr DM and navigates to it.
  Future<void> _startNostrDm(
    BuildContext context,
    WidgetRef ref,
    String pubkey,
    String displayName,
  ) async {
    try {
      final db = ref.read(databaseProvider);

      var conversation = await db.findNostrDmConversation(pubkey);
      if (conversation == null) {
        final id = 'nostr_dm_$pubkey';
        await db.upsertConversation(
          ConversationsCompanion(
            id: Value(id),
            title: Value(displayName),
            type: const Value('nostr_dm'),
            nostrPubkey: Value(pubkey),
            createdAt: Value(DateTime.now()),
            updatedAt: Value(DateTime.now()),
          ),
        );
        conversation = await db.getConversation(id);
      }

      if (conversation != null && context.mounted) {
        ref.read(activeConversationProvider.notifier).state = conversation.id;
        unawaited(Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => NostrChatDetail(
              conversationId: conversation!.id,
              recipientPubkey: pubkey,
              displayName: displayName,
            ),
          ),
        ));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not create DM: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  /// Imports contacts from the user's NIP-02 kind-3 contact list on Nostr.
  ///
  /// Fetches the user's follow list, resolves profiles, and adds them to
  /// the local knowledge store if they don't already exist.
  Future<void> _importNostrContacts(BuildContext context, WidgetRef ref) async {
    final nostr = ref.read(nostrServiceProvider);
    final store = ref.read(knowledgeStoreProvider);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Fetching Nostr contacts…'),
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );

    try {
      final pubkeys = await nostr.fetchContactList();
      if (!context.mounted) return;

      if (pubkeys.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No Nostr contacts found on relays.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }

      var added = 0;
      for (final pubkey in pubkeys) {
        // Resolve the profile for display name.
        final profile = await nostr.fetchProfileCached(pubkey);
        final name =
            profile?.displayName ??
            profile?.name ??
            '${pubkey.substring(0, 8)}…';

        // Add to the local knowledge store (skip if nostrPubkey already known).
        final existing = await store.findPersonByNostrPubkey(pubkey);
        if (existing == null) {
          await store.createPerson(name: name, nostrPubkey: pubkey);
          added++;
        }
      }

      if (context.mounted) {
        ref.invalidate(contactsProvider);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              added > 0
                  ? 'Imported $added new contact${added == 1 ? '' : 's'} from Nostr.'
                  : 'All ${pubkeys.length} Nostr contacts are already imported.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } on Object catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Import failed: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Contacts horizontal row
// ---------------------------------------------------------------------------

/// Horizontal scrolling row of contact avatars at the top.
class _ContactsRow extends StatelessWidget {
  const _ContactsRow({required this.contacts});

  final List<PersonData> contacts;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 88,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
          horizontal: KabukTheme.spacingMd,
          vertical: KabukTheme.spacingSm,
        ),
        itemCount: contacts.length,
        separatorBuilder: (_, _) => const SizedBox(width: 14),
        itemBuilder: (context, index) =>
            _ContactAvatar(contact: contacts[index]),
      ),
    );
  }
}

/// A single contact avatar with name label.
///
/// Loads the contact's Nostr profile picture reactively when a
/// [PersonData.nostrPubkey] is available.
class _ContactAvatar extends ConsumerWidget {
  const _ContactAvatar({required this.contact});

  final PersonData contact;

  String get _initials {
    final name = contact.name ?? '?';
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    }
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pubkey = contact.nostrPubkey ?? '';
    final profile = ref.watch(nostrProfileProvider(pubkey)).valueOrNull;
    final pictureUrl = profile?.picture;

    return Semantics(
      label: (contact.name ?? 'Contact').split(' ').first,
      button: true,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: () {
          if (pubkey.isNotEmpty) {
            _openNostrDm(context, pubkey, contact.name ?? 'Contact');
            return;
          }
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => ContactDetailSheet(contact: contact),
            ),
          );
        },
        onLongPress: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ContactDetailSheet(contact: contact),
          ),
        ),
        child: SizedBox(
          width: 56,
          child: Column(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: _avatarColor(contact.name ?? ''),
                backgroundImage: pictureUrl != null
                    ? NetworkImage(pictureUrl)
                    : null,
                onBackgroundImageError: pictureUrl != null ? (_, _) {} : null,
                child: pictureUrl == null
                    ? Text(
                        _initials,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      )
                    : null,
              ),
              const SizedBox(height: 4),
              Text(
                (contact.name ?? '?').split(' ').first,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  color: KabukTheme.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Deterministic avatar color from name hash.
  Color _avatarColor(String name) {
    const palette = KabukTheme.avatarColors;
    if (name.isEmpty) return palette[0];
    final hash = name.codeUnits.fold<int>(0, (h, c) => h + c);
    return palette[hash % palette.length];
  }

  /// Opens or creates a Nostr DM conversation with [pubkey].
  Future<void> _openNostrDm(
    BuildContext context,
    String pubkey,
    String displayName,
  ) async {
    try {
      final container = ProviderScope.containerOf(context);
      final db = container.read(databaseProvider);

      // Find or create the DM conversation.
      var conversation = await db.findNostrDmConversation(pubkey);
      if (conversation == null) {
        final id = 'nostr_dm_$pubkey';
        await db.upsertConversation(
          ConversationsCompanion(
            id: Value(id),
            title: Value(displayName),
            type: const Value('nostr_dm'),
            nostrPubkey: Value(pubkey),
            createdAt: Value(DateTime.now()),
            updatedAt: Value(DateTime.now()),
          ),
        );
        conversation = await db.getConversation(id);
      }

      if (conversation != null && context.mounted) {
        container.read(activeConversationProvider.notifier).state =
            conversation.id;
        unawaited(Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => NostrChatDetail(
              conversationId: conversation!.id,
              recipientPubkey: pubkey,
              displayName: displayName,
            ),
          ),
        ));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not open DM: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Kabuk AI pinned tile
// ---------------------------------------------------------------------------

/// The pinned "Kabuk AI" contact at the top of the recent list.
class _KabukAiTile extends ConsumerWidget {
  const _KabukAiTile({required this.isConfigured});

  final bool isConfigured;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(
        horizontal: KabukTheme.spacingMd,
        vertical: 2,
      ),
      leading: CircleAvatar(
        radius: 22,
        backgroundColor: KabukTheme.primaryGreen.withAlpha(40),
        child: const Icon(
          Icons.smart_toy_rounded,
          color: KabukTheme.accentGreen,
          size: 22,
        ),
      ),
      title: const Text(
        'Kabuk AI',
        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
      ),
      subtitle: Text(
        isConfigured ? 'Your personal assistant' : 'Model downloading…',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: KabukTheme.textSecondary, fontSize: 13),
      ),
      trailing: const Icon(
        Icons.chevron_right,
        color: KabukTheme.textSecondary,
        size: 20,
      ),
      onTap: () => _openKabukAi(context, ref),
    );
  }

  void _openKabukAi(BuildContext context, WidgetRef ref) {
    final all = ref.read(conversationsProvider).valueOrNull ?? const [];
    // Only resume agent-type conversations; never open a Nostr DM as the AI.
    final agentConvos = all.where((c) => c.type == 'agent').toList();
    final conversationId = agentConvos.isNotEmpty ? agentConvos.first.id : null;

    ref.read(activeConversationProvider.notifier).state = conversationId;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ConversationDetail(
          title: 'Kabuk AI',
          isNewChat: conversationId == null,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Conversation tile
// ---------------------------------------------------------------------------

/// A single conversation entry in the list.
class _ConversationTile extends ConsumerWidget {
  const _ConversationTile({required this.conversation});

  final Conversation conversation;

  bool get _isNostrDm => conversation.type == 'nostr_dm';

  /// Returns a user-friendly display name for the conversation.
  /// If the stored title looks like a raw hex pubkey fragment (e.g. "ee5149c8..."),
  /// it's prefixed with "@" for readability.
  String get _displayTitle {
    final title = conversation.title;
    if (RegExp(r'^[0-9a-f]{8,}\.\.\.$', caseSensitive: false).hasMatch(title)) {
      return '@${title.replaceAll('...', '')}';
    }
    return title;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Resolve a better display name from Nostr profile metadata.
    final displayName = _resolveDisplayName(ref);

    return Dismissible(
      key: ValueKey(conversation.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: KabukTheme.spacingLg),
        color: KabukTheme.error,
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      confirmDismiss: (_) => _confirmDelete(context),
      onDismissed: (_) => _deleteConversation(context, ref),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: KabukTheme.spacingMd,
          vertical: 2,
        ),
        leading: _isNostrDm && conversation.nostrPubkey != null
            ? _NostrDmAvatar(
                pubkeyHex: conversation.nostrPubkey!,
                displayName: displayName,
              )
            : conversation.type == 'nostr_channel'
            ? CircleAvatar(
                radius: 22,
                backgroundColor: KabukTheme.accentGreen.withAlpha(40),
                child: const Icon(
                  Icons.tag_rounded,
                  color: KabukTheme.accentGreen,
                  size: 20,
                ),
              )
            : const CircleAvatar(
                radius: 22,
                backgroundColor: KabukTheme.surfaceVariant,
                child: Icon(
                  Icons.chat_outlined,
                  color: KabukTheme.textSecondary,
                  size: 20,
                ),
              ),
        title: Text(
          displayName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
        ),
        subtitle: Text(
          conversation.lastMessage ?? _formatTimestamp(conversation.updatedAt),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: KabukTheme.textSecondary, fontSize: 12),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (conversation.unreadCount > 0)
              Container(
                margin: const EdgeInsets.only(right: 6),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: KabukTheme.accentGreen,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  conversation.unreadCount > 99
                      ? '99+'
                      : '${conversation.unreadCount}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            if (_isNostrDm)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Icon(
                  Icons.bolt_rounded,
                  color: KabukTheme.accentGreen.withAlpha(150),
                  size: 14,
                ),
              ),
            Text(
              _formatTimestamp(
                conversation.lastMessageAt ?? conversation.updatedAt,
              ),
              style: const TextStyle(
                color: KabukTheme.textSecondary,
                fontSize: 11,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(
              Icons.chevron_right,
              color: KabukTheme.textSecondary,
              size: 20,
            ),
          ],
        ),
        onTap: () => _openConversation(context, ref, displayName),
        onLongPress: () => _showContextMenu(context, ref),
      ),
    );
  }

  /// Resolves the best display name for this conversation.
  ///
  /// For Nostr DMs, checks the profile metadata for a real name.
  /// Falls back to the stored title or formatted hex pubkey.
  String _resolveDisplayName(WidgetRef ref) {
    if (_isNostrDm && conversation.nostrPubkey != null) {
      final profile = ref
          .watch(nostrProfileProvider(conversation.nostrPubkey!))
          .valueOrNull;
      if (profile != null && profile.name.isNotEmpty) {
        return profile.name;
      }
    }
    return _displayTitle;
  }

  /// Opens the correct detail screen based on conversation type.
  void _openConversation(
    BuildContext context,
    WidgetRef ref,
    String displayName,
  ) {
    ref.read(activeConversationProvider.notifier).state = conversation.id;

    // Reset unread count on open.
    if (conversation.unreadCount > 0) {
      ref.read(databaseProvider).resetUnreadCount(conversation.id);
    }

    if (_isNostrDm && conversation.nostrPubkey != null) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => NostrChatDetail(
            conversationId: conversation.id,
            recipientPubkey: conversation.nostrPubkey!,
            displayName: displayName,
          ),
        ),
      );
    } else if (conversation.type == 'nostr_channel' &&
        conversation.nostrPubkey != null) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => NostrChannelDetail(
            conversationId: conversation.id,
            channelEventId: conversation.nostrPubkey!,
            channelName: conversation.title,
          ),
        ),
      );
    } else {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ConversationDetail(title: conversation.title),
        ),
      );
    }
  }

  /// Shows a context menu with conversation actions.
  void _showContextMenu(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: KabukTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(KabukTheme.radiusXl),
        ),
      ),
      builder: (ctx) => SafeArea(
        bottom: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(top: KabukTheme.spacingSm),
                decoration: BoxDecoration(
                  color: KabukTheme.textSecondary.withAlpha(100),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            if (conversation.unreadCount > 0)
              ListTile(
                leading: const Icon(
                  Icons.mark_email_read_outlined,
                  color: KabukTheme.textPrimary,
                ),
                title: const Text('Mark as read'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  ref
                      .read(databaseProvider)
                      .resetUnreadCount(conversation.id);
                },
              ),
            ListTile(
              leading: const Icon(
                Icons.delete_outline,
                color: KabukTheme.error,
              ),
              title: const Text(
                'Delete conversation',
                style: TextStyle(color: KabukTheme.error),
              ),
              onTap: () async {
                Navigator.of(ctx).pop();
                final confirm = await _confirmDelete(context);
                if (confirm == true && context.mounted) {
                  _deleteConversation(context, ref);
                }
              },
            ),
            const SizedBox(height: KabukTheme.spacingSm),
          ],
        ),
      ),
    );
  }

  Future<bool?> _confirmDelete(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: KabukTheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(KabukTheme.radiusMd),
        ),
        title: const Text('Delete conversation?'),
        content: Text(
          'This will permanently delete "${conversation.title}" '
          'and all its messages.',
          style: const TextStyle(color: KabukTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: KabukTheme.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _deleteConversation(BuildContext context, WidgetRef ref) {
    final db = ref.read(databaseProvider);
    db.deleteConversation(conversation.id);
    if (ref.read(activeConversationProvider) == conversation.id) {
      ref.read(activeConversationProvider.notifier).state = null;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('"${conversation.title}" deleted'),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  String _formatTimestamp(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${date.month}/${date.day}/${date.year}';
  }
}

// ---------------------------------------------------------------------------
// Nostr DM conversation avatar
// ---------------------------------------------------------------------------

/// Circular avatar for a Nostr DM conversation tile.
///
/// Loads the contact's profile picture reactively; falls back to
/// a deterministic initial-letter avatar when unavailable.
class _NostrDmAvatar extends ConsumerWidget {
  const _NostrDmAvatar({required this.pubkeyHex, required this.displayName});

  final String pubkeyHex;
  final String displayName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(nostrProfileProvider(pubkeyHex)).valueOrNull;
    final pictureUrl = profile?.picture;
    final name = profile?.displayName ?? displayName;

    const palette = KabukTheme.avatarColors;
    final hash = pubkeyHex.codeUnits.fold<int>(0, (h, c) => h + c);
    final bg = palette[hash % palette.length];

    final initials = () {
      final parts = name.trim().split(RegExp(r'\s+'));
      if (parts.length >= 2) {
        return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
      }
      return name.isNotEmpty ? name[0].toUpperCase() : '?';
    }();

    final isVerified = profile?.nip05 != null;

    final avatar = CircleAvatar(
      radius: 22,
      backgroundColor: bg,
      backgroundImage: pictureUrl != null ? NetworkImage(pictureUrl) : null,
      onBackgroundImageError: pictureUrl != null ? (_, _) {} : null,
      child: pictureUrl == null
          ? Text(
              initials,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            )
          : null,
    );

    if (!isVerified) return avatar;

    // Overlay a small verified badge for NIP-05-verified contacts.
    return Stack(
      clipBehavior: Clip.none,
      children: [
        avatar,
        Positioned(
          bottom: 0,
          right: 0,
          child: Container(
            width: 14,
            height: 14,
            decoration: const BoxDecoration(
              color: KabukTheme.background,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.verified_rounded,
              size: 12,
              color: KabukTheme.blueAccent,
            ),
          ),
        ),
      ],
    );
  }
}
