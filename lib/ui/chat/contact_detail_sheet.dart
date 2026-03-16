/// Contact detail sheet — unified contact management with Nostr identity merging.
///
/// Shows a contact's local data (name, description, email, phone) together with
/// all their associated Nostr public keys and live profile data fetched from
/// relays. Users can:
/// - Edit the contact's name and basic info.
/// - Add labeled Nostr keys (personal, work, etc.).
/// - Remove individual keys.
/// - Tap a key to start a DM with that identity.
/// - Tap a key's Nostr profile icon to view their full public profile.
library;

import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kabuk/config/providers.dart';
import 'package:kabuk/knowledge/database.dart';
import 'package:kabuk/knowledge/store.dart';
import 'package:kabuk/knowledge/types/person.dart';
import 'package:kabuk/ui/chat/contact_profile_sheet.dart';
import 'package:kabuk/ui/chat/nostr_chat_detail.dart';
import 'package:kabuk/ui/theme.dart';

// ---------------------------------------------------------------------------
// Public entry point
// ---------------------------------------------------------------------------

/// Full-screen contact detail page with Nostr identity management.
///
/// Push this route when a user long-presses a contact avatar.
/// After edits are saved the contact list is invalidated automatically.
class ContactDetailSheet extends ConsumerStatefulWidget {
  /// Creates a [ContactDetailSheet].
  const ContactDetailSheet({required this.contact, super.key});

  /// The local [PersonData] being viewed/edited.
  final PersonData contact;

  @override
  ConsumerState<ContactDetailSheet> createState() => _ContactDetailSheetState();
}

class _ContactDetailSheetState extends ConsumerState<ContactDetailSheet> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _descCtrl;
  late final ProviderContainer _container;

  /// Local copy of the contact, updated directly after mutations instead of
  /// relying on [contactsProvider] invalidation mid-animation.
  late PersonData _currentContact;

  bool _editing = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _container = ProviderScope.containerOf(context, listen: false);
    _currentContact = widget.contact;
    _nameCtrl = TextEditingController(text: widget.contact.name ?? '');
    _emailCtrl = TextEditingController(text: widget.contact.email ?? '');
    _phoneCtrl = TextEditingController(text: widget.contact.telephone ?? '');
    _descCtrl = TextEditingController(text: widget.contact.description ?? '');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _descCtrl.dispose();
    Future<void>.microtask(() => _container.invalidate(contactsProvider));
    super.dispose();
  }

  // ── Actions ────────────────────────────────────────────────────────────

  Future<void> _saveEdits() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final store = ref.read(knowledgeStoreProvider);
      await store.updatePerson(
        widget.contact.uri,
        name: _nameCtrl.text.trim().isEmpty ? null : _nameCtrl.text.trim(),
        email: _emailCtrl.text.trim().isEmpty ? null : _emailCtrl.text.trim(),
        telephone: _phoneCtrl.text.trim().isEmpty
            ? null
            : _phoneCtrl.text.trim(),
        description: _descCtrl.text.trim().isEmpty
            ? null
            : _descCtrl.text.trim(),
      );
      // Refresh local contact state directly — no provider invalidation needed
      // here (done in dispose() when leaving the sheet).
      final updated = await _reloadContact(store);
      if (mounted) {
        setState(() {
          if (updated != null) _currentContact = updated;
          _editing = false;
        });
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _removeKey(NostrKeyEntry key) async {
    final store = ref.read(knowledgeStoreProvider);
    await store.removePersonNostrKey(widget.contact.uri, pubkey: key.pubkey);
    // Refresh local state directly — safe because we're still mounted and
    // no overlay animation is in flight.
    final updated = await _reloadContact(store);
    if (mounted) {
      setState(() {
        if (updated != null) _currentContact = updated;
      });
    }
  }

  /// Deletes this contact entirely from the knowledge store after confirmation.
  Future<void> _deleteContact(BuildContext context) async {
    final name = _currentContact.name ?? 'this contact';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: KabukTheme.surface,
        title: const Text('Delete Contact'),
        content: Text(
          'Are you sure you want to delete $name? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final store = ref.read(knowledgeStoreProvider);
    await store.mutate((ctx) => ctx.remove(subject: widget.contact.uri));
    if (context.mounted) Navigator.of(context).pop();
  }

  /// Re-reads this contact from the knowledge store and returns the updated
  /// [PersonData], or `null` if not found.
  Future<PersonData?> _reloadContact(KnowledgeStore store) async {
    final all = await store.listPersons(limit: 100);
    return all.firstWhere(
      (c) => c.uri == widget.contact.uri,
      orElse: () => _currentContact,
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Use local _currentContact rather than watching contactsProvider so that
    // mutations inside this sheet never trigger Riverpod provider rebuilds
    // while overlay dismiss animations are still in flight (which causes the
    // "_dependents.isEmpty" assertion crash).  The provider is invalidated
    // once in dispose() so callers see fresh data after the sheet is gone.
    final liveContact = _currentContact;

    return Scaffold(
      backgroundColor: KabukTheme.background,
      appBar: AppBar(
        backgroundColor: KabukTheme.surface,
        title: const Text('Contact'),
        actions: [
          if (!_editing) ...[
            IconButton(
              icon: const Icon(Icons.edit_rounded, size: 20),
              tooltip: 'Edit',
              onPressed: () => setState(() => _editing = true),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded, size: 20),
              tooltip: 'Delete contact',
              color: Colors.redAccent,
              onPressed: () => _deleteContact(context),
            ),
          ],
          if (_editing) ...[
            TextButton(
              onPressed: () => setState(() => _editing = false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: _saving ? null : _saveEdits,
              child: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save'),
            ),
          ],
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(KabukTheme.spacingMd),
        children: [
          // ── Avatar + name ──────────────────────────────────────────────
          _ContactHeroSection(
            contact: liveContact,
            editing: _editing,
            nameCtrl: _nameCtrl,
          ),
          const SizedBox(height: KabukTheme.spacingMd),

          // ── Basic info (edit mode) ─────────────────────────────────────
          if (_editing) ...[
            _EditField(
              controller: _emailCtrl,
              label: 'Email',
              icon: Icons.email_outlined,
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: KabukTheme.spacingSm),
            _EditField(
              controller: _phoneCtrl,
              label: 'Phone',
              icon: Icons.phone_outlined,
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: KabukTheme.spacingSm),
            _EditField(
              controller: _descCtrl,
              label: 'Description',
              icon: Icons.notes_rounded,
              maxLines: 3,
            ),
            const SizedBox(height: KabukTheme.spacingMd),
          ],

          // ── Nostr identities section ────────────────────────────────────
          _SectionHeader(
            icon: Icons.key_rounded,
            label: 'Nostr Identities',
            trailing: IconButton(
              icon: const Icon(Icons.add_rounded, size: 18),
              style: IconButton.styleFrom(
                backgroundColor: KabukTheme.purpleAccent.withAlpha(30),
                foregroundColor: KabukTheme.purpleAccent,
                padding: const EdgeInsets.all(6),
                minimumSize: const Size(28, 28),
              ),
              tooltip: 'Add Nostr key',
              onPressed: () => _showAddKeySheet(context, liveContact),
            ),
          ),
          const SizedBox(height: KabukTheme.spacingSm),

          if (liveContact.nostrKeys.isEmpty)
            _EmptyKeys(onAdd: () => _showAddKeySheet(context, liveContact))
          else
            ...liveContact.nostrKeys.map(
              (key) => _NostrKeyCard(
                nostrKey: key,
                contact: liveContact,
                onRemove: () => _removeKey(key),
                onStartDm: () => _startDm(context, liveContact, key),
                onViewProfile: () =>
                    _viewPublicProfile(context, key, liveContact),
              ),
            ),

          const SizedBox(height: KabukTheme.spacingXl),
        ],
      ),
    );
  }

  // ── Navigation helpers ─────────────────────────────────────────────────

  void _viewPublicProfile(
    BuildContext context,
    NostrKeyEntry key,
    PersonData contact,
  ) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ContactProfileSheet(
          pubkeyHex: key.pubkey,
          displayName: contact.name ?? 'Contact',
        ),
      ),
    );
  }

  Future<void> _startDm(
    BuildContext context,
    PersonData contact,
    NostrKeyEntry key,
  ) async {
    final pubkey = key.pubkey;
    final label = key.label.isNotEmpty ? ' (${key.label})' : '';
    final name = '${contact.name ?? 'Contact'}$label';

    try {
      final db = ref.read(databaseProvider);
      var conversation = await db.findNostrDmConversation(pubkey);
      if (conversation == null) {
        final id = 'nostr_dm_$pubkey';
        await db.upsertConversation(
          ConversationsCompanion(
            id: Value(id),
            title: Value(name),
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
        unawaited(Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) => NostrChatDetail(
              conversationId: conversation!.id,
              recipientPubkey: pubkey,
              displayName: name,
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

  // ── Add key sheet ──────────────────────────────────────────────────────

  void _showAddKeySheet(BuildContext context, PersonData contact) {
    showModalBottomSheet<PersonData?>(
      context: context,
      backgroundColor: KabukTheme.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(KabukTheme.radiusXl),
        ),
      ),
      builder: (ctx) => _AddKeySheet(
        contact: contact,
        knowledgeStore: ref.read(knowledgeStoreProvider),
      ),
    ).then((updatedContact) {
      // updatedContact is non-null only if a key was successfully added.
      // By the time .then() fires the modal route is popped but the animation
      // may still be running — do NOT dispose anything or call setState here.
      // Instead, the _AddKeySheet already called _reloadContact and returned
      // the updated PersonData as the pop result.
      if (updatedContact != null && mounted) {
        setState(() => _currentContact = updatedContact);
      }
    });
  }
}

// ---------------------------------------------------------------------------
// Add key bottom sheet — manages its own TextEditingControllers
// ---------------------------------------------------------------------------

/// Self-contained bottom sheet widget for adding a Nostr key.
///
/// Manages its own [TextEditingController]s so they are disposed by the
/// widget's [State.dispose] method — safely, after the overlay animation
/// has fully completed and the element has been fully unmounted.
class _AddKeySheet extends StatefulWidget {
  const _AddKeySheet({required this.contact, required this.knowledgeStore});

  final PersonData contact;
  final KnowledgeStore knowledgeStore;

  @override
  State<_AddKeySheet> createState() => _AddKeySheetState();
}

class _AddKeySheetState extends State<_AddKeySheet> {
  final _keyCtrl = TextEditingController();
  final _labelCtrl = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _keyCtrl.dispose();
    _labelCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_saving) return;
    final raw = _keyCtrl.text.trim();
    final pubkey = _normalizeNostrPubkey(raw);
    if (pubkey == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Invalid pubkey — enter npub or hex'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final label = _labelCtrl.text.trim();
      await widget.knowledgeStore.addPersonNostrKey(
        widget.contact.uri,
        pubkey: pubkey,
        label: label.isEmpty ? '' : label.toLowerCase(),
      );
      // Re-read the updated contact from the store BEFORE popping so the
      // parent can update its local state synchronously (avoiding any
      // setState calls from async callbacks during the modal's exit animation).
      final all = await widget.knowledgeStore.listPersons(limit: 100);
      final updated = all.firstWhere(
        (c) => c.uri == widget.contact.uri,
        orElse: () => widget.contact,
      );
      if (mounted) {
        // Pop and pass the updated contact back to the caller.
        Navigator.of(context).pop(updated);
      }
    } on Object {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        KabukTheme.spacingMd,
        KabukTheme.spacingMd,
        KabukTheme.spacingMd,
        MediaQuery.of(context).viewInsets.bottom + KabukTheme.spacingMd,
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
          Text(
            'Add Nostr Identity',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: KabukTheme.spacingXs),
          const Text(
            'Add multiple identities — e.g. separate personal and work keys.',
            style: TextStyle(color: KabukTheme.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: KabukTheme.spacingMd),
          TextField(
            controller: _keyCtrl,
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
            controller: _labelCtrl,
            textCapitalization: TextCapitalization.words,
            style: const TextStyle(color: KabukTheme.textPrimary),
            decoration: const InputDecoration(
              labelText: 'Label (optional)',
              prefixIcon: Icon(Icons.label_outline_rounded, size: 20),
              hintText: 'e.g. Personal, Work',
              hintStyle: TextStyle(
                color: KabukTheme.textSecondary,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(height: KabukTheme.spacingLg),
          FilledButton.icon(
            onPressed: _saving ? null : _submit,
            icon: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.add_rounded, size: 18),
            label: const Text('Add Key'),
          ),
          const SizedBox(height: KabukTheme.spacingSm),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Hero section (avatar + name in view/edit modes)
// ---------------------------------------------------------------------------

class _ContactHeroSection extends ConsumerWidget {
  const _ContactHeroSection({
    required this.contact,
    required this.editing,
    required this.nameCtrl,
  });

  final PersonData contact;
  final bool editing;
  final TextEditingController nameCtrl;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pubkey = contact.nostrPubkey ?? '';
    final profile = ref.watch(nostrProfileProvider(pubkey)).valueOrNull;
    final pictureUrl = profile?.picture;
    final displayName = profile?.displayName ?? contact.name ?? 'Contact';
    final avatarColor = _avatarColor(contact.name ?? '');

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Avatar
        CircleAvatar(
          radius: 34,
          backgroundColor: avatarColor,
          backgroundImage: pictureUrl != null ? NetworkImage(pictureUrl) : null,
          onBackgroundImageError: pictureUrl != null ? (_, _) {} : null,
          child: pictureUrl == null
              ? Text(
                  _initials(displayName),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                )
              : null,
        ),
        const SizedBox(width: KabukTheme.spacingMd),

        // Name
        Expanded(
          child: editing
              ? TextField(
                  controller: nameCtrl,
                  textCapitalization: TextCapitalization.words,
                  style: const TextStyle(
                    color: KabukTheme.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                  decoration: const InputDecoration(
                    hintText: 'Display name',
                    border: UnderlineInputBorder(),
                    contentPadding: EdgeInsets.zero,
                  ),
                )
              : Text(
                  displayName,
                  style: const TextStyle(
                    color: KabukTheme.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Nostr key card
// ---------------------------------------------------------------------------

/// Card showing a single Nostr identity for a contact.
///
/// Loads the live profile name/picture from relays.
class _NostrKeyCard extends ConsumerWidget {
  const _NostrKeyCard({
    required this.nostrKey,
    required this.contact,
    required this.onRemove,
    required this.onStartDm,
    required this.onViewProfile,
  });

  final NostrKeyEntry nostrKey;
  final PersonData contact;
  final VoidCallback onRemove;
  final VoidCallback onStartDm;
  final VoidCallback onViewProfile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(nostrProfileProvider(nostrKey.pubkey));
    final profile = profileAsync.valueOrNull;
    final nostrName = profile?.displayName;
    final pictureUrl = profile?.picture;
    final nip05 = profile?.nip05;
    final avatarColor = _pubkeyColor(nostrKey.pubkey);

    return Container(
      margin: const EdgeInsets.only(bottom: KabukTheme.spacingSm),
      decoration: BoxDecoration(
        color: KabukTheme.surface,
        borderRadius: BorderRadius.circular(KabukTheme.radiusMd),
        border: Border.all(color: KabukTheme.divider, width: 0.5),
      ),
      child: Column(
        children: [
          // Header row: avatar + names + label badge
          Padding(
            padding: const EdgeInsets.all(KabukTheme.spacingMd),
            child: Row(
              children: [
                // Nostr profile avatar
                GestureDetector(
                  onTap: onViewProfile,
                  child: CircleAvatar(
                    radius: 22,
                    backgroundColor: avatarColor,
                    backgroundImage: pictureUrl != null
                        ? NetworkImage(pictureUrl)
                        : null,
                    onBackgroundImageError: pictureUrl != null
                        ? (_, _) {}
                        : null,
                    child: pictureUrl == null
                        ? Text(
                            (nostrName ?? nostrKey.pubkey).isNotEmpty
                                ? (nostrName ?? nostrKey.pubkey)[0]
                                      .toUpperCase()
                                : '?',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                            ),
                          )
                        : null,
                  ),
                ),
                const SizedBox(width: KabukTheme.spacingMd),

                // Profile name + key abbrev + NIP-05
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (nostrName != null) ...[
                            Flexible(
                              child: Text(
                                nostrName,
                                style: const TextStyle(
                                  color: KabukTheme.textPrimary,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 4),
                          ],
                          if (nip05 != null)
                            const Icon(
                              Icons.verified_rounded,
                              size: 13,
                              color: KabukTheme.accentGreen,
                            ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      // Key abbreviation (copyable)
                      GestureDetector(
                        onTap: () {
                          Clipboard.setData(
                            ClipboardData(text: nostrKey.pubkey),
                          );
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Public key copied'),
                              behavior: SnackBarBehavior.floating,
                              duration: Duration(seconds: 2),
                            ),
                          );
                        },
                        child: Text(
                          '${nostrKey.pubkey.substring(0, 8)}…'
                          '${nostrKey.pubkey.substring(nostrKey.pubkey.length - 8)}',
                          style: const TextStyle(
                            color: KabukTheme.textSecondary,
                            fontSize: 11,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Label chip
                if (nostrKey.label.isNotEmpty) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: KabukTheme.purpleAccent.withAlpha(40),
                      borderRadius: BorderRadius.circular(KabukTheme.radiusSm),
                    ),
                    child: Text(
                      nostrKey.label,
                      style: const TextStyle(
                        color: KabukTheme.purpleAccent,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Action buttons row
          Container(
            decoration: const BoxDecoration(
              border: Border(
                top: BorderSide(color: KabukTheme.divider, width: 0.5),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _ActionButton(
                    icon: Icons.chat_bubble_outline_rounded,
                    label: 'Message',
                    onPressed: onStartDm,
                  ),
                ),
                Container(width: 0.5, height: 36, color: KabukTheme.divider),
                Expanded(
                  child: _ActionButton(
                    icon: Icons.person_outline_rounded,
                    label: 'Profile',
                    onPressed: onViewProfile,
                  ),
                ),
                Container(width: 0.5, height: 36, color: KabukTheme.divider),
                Expanded(
                  child: _ActionButton(
                    icon: Icons.delete_outline_rounded,
                    label: 'Remove',
                    color: KabukTheme.textSecondary,
                    onPressed: () => _confirmRemove(context),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _confirmRemove(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: KabukTheme.surface,
        title: const Text('Remove identity?'),
        content: Text(
          'Remove ${nostrKey.displayLabel} key '
          '${nostrKey.pubkey.substring(0, 8)}… from this contact?',
          style: const TextStyle(color: KabukTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () {
              Navigator.of(ctx).pop();
              onRemove();
            },
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Small helper widgets
// ---------------------------------------------------------------------------

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.icon,
    required this.label,
    required this.trailing,
  });

  final IconData icon;
  final String label;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 14, color: KabukTheme.textSecondary),
        const SizedBox(width: 6),
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            color: KabukTheme.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.8,
          ),
        ),
        const Spacer(),
        trailing,
      ],
    );
  }
}

class _EditField extends StatelessWidget {
  const _EditField({
    required this.controller,
    required this.label,
    required this.icon,
    this.keyboardType,
    this.maxLines = 1,
  });

  final TextEditingController controller;
  final String label;
  final IconData icon;
  final TextInputType? keyboardType;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      style: const TextStyle(color: KabukTheme.textPrimary),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 20),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.color,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? KabukTheme.purpleAccent;
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: c,
        padding: const EdgeInsets.symmetric(vertical: 8),
        shape: const RoundedRectangleBorder(),
        minimumSize: const Size(0, 36),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 14, color: c),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 12, color: c)),
        ],
      ),
    );
  }
}

class _EmptyKeys extends StatelessWidget {
  const _EmptyKeys({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onAdd,
      child: Container(
        padding: const EdgeInsets.all(KabukTheme.spacingLg),
        decoration: BoxDecoration(
          color: KabukTheme.surface,
          borderRadius: BorderRadius.circular(KabukTheme.radiusMd),
          border: Border.all(
            color: KabukTheme.purpleAccent.withAlpha(60),
            width: 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.add_circle_outline_rounded,
              size: 28,
              color: KabukTheme.purpleAccent.withAlpha(180),
            ),
            const SizedBox(height: 8),
            const Text(
              'No Nostr identities yet',
              style: TextStyle(color: KabukTheme.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 4),
            const Text(
              'Tap to add a Nostr key',
              style: TextStyle(color: KabukTheme.purpleAccent, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Deterministic color from pubkey hash.
Color _pubkeyColor(String pubkey) {
  const palette = [
    Color(0xFF5C6BC0),
    Color(0xFF26A69A),
    Color(0xFFEF5350),
    Color(0xFFAB47BC),
    Color(0xFF42A5F5),
    Color(0xFF66BB6A),
  ];
  if (pubkey.isEmpty) return palette[0];
  final hash = pubkey.codeUnits.fold<int>(0, (h, c) => h + c);
  return palette[hash % palette.length];
}

/// Deterministic color from name hash.
Color _avatarColor(String name) {
  const palette = [
    Color(0xFF5C6BC0),
    Color(0xFF26A69A),
    Color(0xFFEF5350),
    Color(0xFFAB47BC),
    Color(0xFF42A5F5),
    Color(0xFF66BB6A),
    Color(0xFFFF7043),
    Color(0xFFFFCA28),
  ];
  if (name.isEmpty) return palette[0];
  final hash = name.codeUnits.fold<int>(0, (h, c) => h + c);
  return palette[hash % palette.length];
}

/// Two-letter initials from a display name.
String _initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+'));
  if (parts.length >= 2) {
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }
  return name.isNotEmpty ? name[0].toUpperCase() : '?';
}

/// Normalizes a Nostr public key input (npub or hex) to 64-char hex.
String? _normalizeNostrPubkey(String input) {
  if (input.isEmpty) return null;
  if (input.length == 64 && RegExp(r'^[0-9a-fA-F]+$').hasMatch(input)) {
    return input.toLowerCase();
  }
  if (input.startsWith('npub1')) {
    try {
      final decoded = _bech32Decode(input);
      if (decoded != null && decoded.length == 32) {
        return decoded.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      }
    } on Object {
      // Invalid npub.
    }
  }
  return null;
}

/// Minimal bech32 decoder for npub1… strings.
List<int>? _bech32Decode(String bech32) {
  const charset = 'qpzry9x8gf2tvdw0s3jn54khce6mua7l';
  // For npub1 pubkeys, the HRP is always 'npub' and separator is at position 4.
  // Using lastIndexOf('1') is incorrect because the data part may contain '1'
  // (the bech32 charset includes 'q','p','z','r','y','9','x','8','g','f','2',
  // 't','v','d','w','0','s','3','j','n','5','4','k','h','c','e','6','m','u',
  // 'a','7','l' – '1' is NOT in the charset but the separator itself is '1').
  // The bech32 data part only uses charset chars (no '1'), so lastIndexOf('1')
  // correctly finds the hrp/data separator. However, we force pos=4 for npub.
  final int pos;
  if (bech32.toLowerCase().startsWith('npub1')) {
    pos = 4;
  } else {
    pos = bech32.lastIndexOf('1');
  }
  if (pos < 1 || pos + 7 > bech32.length) return null;
  final data = <int>[];
  for (int i = pos + 1; i < bech32.length - 6; i++) {
    final c = charset.indexOf(bech32[i].toLowerCase());
    if (c < 0) return null;
    data.add(c);
  }
  // Convert 5-bit groups to 8-bit bytes.
  final decoded = <int>[];
  int acc = 0, bits = 0;
  for (final v in data) {
    acc = ((acc << 5) | v) & 0xffff;
    bits += 5;
    if (bits >= 8) {
      bits -= 8;
      decoded.add((acc >> bits) & 0xff);
    }
  }
  return decoded;
}
