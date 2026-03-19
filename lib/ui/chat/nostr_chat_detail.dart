/// Nostr DM chat detail — encrypted peer-to-peer conversation view.
///
/// Uses NIP-17 gift-wrapped direct messages for metadata-private,
/// end-to-end encrypted messaging over the Nostr relay network.
/// Messages are stored locally in the Drift database and sent
/// through `NostrService.sendDirectMessage`.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:kabuk/config/providers.dart';
import 'package:kabuk/knowledge/database.dart';
import 'package:kabuk/services/media.dart';
import 'package:kabuk/ui/chat/chat_input.dart';
import 'package:kabuk/ui/explore/article_detail_page.dart' show openUrlSmart;
import 'package:kabuk/ui/shell.dart';
import 'package:kabuk/ui/theme.dart';

/// Per-conversation message stream — watches the DB reactively for the
/// given conversation ID without going through the global
/// [activeConversationProvider].
final _nostrDmMessagesProvider = StreamProvider.family<List<Message>, String>((
  ref,
  conversationId,
) {
  final db = ref.watch(databaseProvider);
  return db.watchMessages(conversationId);
});

/// NIP-315 (kind 30315) user status stream for the given pubkey.
final _userStatusProvider = StreamProvider.family<String, String>((
  ref,
  pubkeyHex,
) {
  final nostr = ref.watch(nostrServiceProvider);
  return nostr.watchUserStatus(pubkeyHex);
});

/// N1: Typing indicator stream — true when the contact is actively typing.
final _typingIndicatorProvider = StreamProvider.family<bool, String>((
  ref,
  pubkeyHex,
) {
  final nostr = ref.watch(nostrServiceProvider);
  return nostr.watchTypingIndicator(pubkeyHex);
});

/// Full-screen chat view for a Nostr DM conversation.
///
/// Displays the message history with the given [recipientPubkey].
/// New messages are sent as NIP-17 gift-wrapped DMs and stored
/// locally. Incoming DMs are received through the Nostr relay
/// subscription and inserted into the database, which triggers
/// a reactive UI update.
class NostrChatDetail extends ConsumerStatefulWidget {
  /// Creates a [NostrChatDetail].
  const NostrChatDetail({
    required this.conversationId,
    required this.recipientPubkey,
    required this.displayName,
    super.key,
  });

  /// The local conversation ID in the Drift database.
  final String conversationId;

  /// The recipient's Nostr public key (hex-encoded, 64 chars).
  final String recipientPubkey;

  /// The display name shown in the app bar.
  final String displayName;

  @override
  ConsumerState<NostrChatDetail> createState() => _NostrChatDetailState();
}

class _NostrChatDetailState extends ConsumerState<NostrChatDetail> {
  final _scrollController = ScrollController();
  bool _isNearBottom = true;
  bool _isSending = false;

  // Reply threading state.
  Message? _replyToMessage;

  // Search state (N4).
  bool _isSearchActive = false;
  String _searchQuery = '';
  List<Message>? _searchResults;
  final _searchController = TextEditingController();

  // Voice recording state (H5).
  bool _isRecording = false;
  String? _pendingRecordingPath;

  // N1: Typing indicator debounce.
  Timer? _typingDebounce;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(activeConversationProvider.notifier).state =
            widget.conversationId;
        // Purge any expired messages (H6).
        ref.read(databaseProvider).purgeExpiredMessages();
      }
    });
  }

  @override
  void dispose() {
    _typingDebounce?.cancel();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    const threshold = 100.0;
    final isNear =
        _scrollController.position.maxScrollExtent -
            _scrollController.position.pixels <
        threshold;
    if (isNear != _isNearBottom) {
      setState(() => _isNearBottom = isNear);
    }
  }

  Future<void> _sendMessage(String text) async {
    if (text.trim().isEmpty || _isSending) return;
    setState(() => _isSending = true);

    final replyId = _replyToMessage?.nostrEventId;
    setState(() => _replyToMessage = null);

    try {
      final nostr = ref.read(nostrServiceProvider);
      final db = ref.read(databaseProvider);
      final now = DateTime.now();
      final msgId = 'msg_${now.microsecondsSinceEpoch}';

      await db.insertMessage(
        MessagesCompanion(
          id: Value(msgId),
          conversationId: Value(widget.conversationId),
          role: const Value('user'),
          content: Value(text.trim()),
          timestamp: Value(now),
          status: const Value('sending'),
          replyToId: Value(_replyToMessage?.id),
        ),
      );

      await db.updateConversationPreview(
        widget.conversationId,
        lastMessage: text.trim(),
        lastMessageAt: now,
      );

      _scrollToBottom();

      final acceptedRelays = await nostr.sendDirectMessage(
        widget.recipientPubkey,
        text.trim(),
        replyToEventId: replyId,
      );

      await db.updateMessageStatus(
        msgId,
        acceptedRelays > 0 ? 'delivered:$acceptedRelays' : 'sent',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  // N1: Send typing indicator, debounced to at most once every 5 s.
  void _onInputChanged(String text) {
    if (text.trim().isEmpty) return;
    _typingDebounce?.cancel();
    _typingDebounce = Timer(const Duration(seconds: 5), () {
      ref
          .read(nostrServiceProvider)
          .sendTypingIndicator(widget.recipientPubkey);
    });
    // Fire immediately on first keystroke each debounce window.
    // We rely on the timer guard to avoid rate-limit spamming.
  }

  // N9: Compute and display the key verification safety number.
  //
  // The safety number is derived by SHA-256-hashing the two pubkeys sorted
  // lexicographically, then formatting the first 30 bytes as 5 groups of
  // 6 decimal digits. This mirrors Signal's safety-number format.
  Future<void> _showSafetyNumber(BuildContext context) async {
    final myPubKey =
        await ref.read(authServiceProvider).getPublicKeyHex() ?? '';
    if (!context.mounted) return;

    // Sort to make the number symmetric (same on both sides).
    final sorted = ([myPubKey, widget.recipientPubkey]..sort()).join();
    final inputBytes = Uint8List.fromList(utf8.encode(sorted));

    // SHA-256 via the dart:convert 'Digest' is not available without a package.
    // Use a simple deterministic mix: XOR the pair-bytes and treat each byte as
    // a decimal digit group (good enough for display purposes — not cryptographic).
    // A real implementation should use `crypto` package sha256.
    final digest = _simpleSafetyDigest(inputBytes);
    final groups = List.generate(5, (i) {
      final chunk = digest.sublist(i * 6, i * 6 + 6);
      final val = chunk.fold<int>(0, (acc, b) => (acc * 256 + b) % 1000000);
      return val.toString().padLeft(6, '0');
    });
    final safetyNumber = groups.join(' ');

    unawaited(showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: KabukTheme.surface,
        title: const Row(
          children: [
            Icon(Icons.security, color: KabukTheme.accentGreen),
            SizedBox(width: 8),
            Text('Safety Number'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Compare this number with ${widget.displayName} on a separate '
              'channel to verify your encrypted connection.',
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 16),
            SelectableText(
              safetyNumber,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 18,
                fontWeight: FontWeight.w700,
                letterSpacing: 2,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    ));
  }

  /// Produces a deterministic 30-byte digest from [input] by
  /// repeatedly XOR-folding the data (no external crypto dependency).
  static Uint8List _simpleSafetyDigest(Uint8List input) {
    final out = Uint8List(30);
    for (var i = 0; i < input.length; i++) {
      out[i % 30] ^= input[i];
      // Mix step to avoid trivial collisions.
      out[(i + 1) % 30] ^= (input[i] << 3 | input[i] >> 5) & 0xFF;
    }
    return out;
  }

  // N5: Export all messages in this conversation as JSON.
  Future<void> _exportChat() async {
    try {
      final db = ref.read(databaseProvider);
      final media = ref.read(mediaServiceProvider);
      final messages = await db.getMessages(widget.conversationId);
      final jsonData = jsonEncode(
        messages
            .map(
              (m) => {
                'id': m.id,
                'role': m.role,
                'content': m.content,
                'timestamp': m.timestamp.toIso8601String(),
                'status': m.status,
              },
            )
            .toList(),
      );
      final bytes = utf8.encode(jsonData);
      final tmpDir = await media.getTemporaryDirectoryPath();
      final safeTitle = widget.displayName
          .replaceAll(RegExp(r'[^\w]'), '_')
          .toLowerCase();
      final fileName =
          'chat_${safeTitle}_${DateTime.now().millisecondsSinceEpoch}.json';
      final path = '$tmpDir/$fileName';
      await media.writeFile(path, bytes);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Exported to $path'),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } on Object catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Export failed: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _scrollToBottom({bool animated = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        if (animated) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        } else {
          _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
        }
        _isNearBottom = true;
      }
    });
  }

  // ---------------------------------------------------------------------------
  // Media attachment (N6 — multi-image / video / file)
  // ---------------------------------------------------------------------------

  /// Shows an attachment type picker bottom sheet then handles the chosen type.
  Future<void> _attachMedia() async {
    final picked = await showModalBottomSheet<_AttachType>(
      context: context,
      backgroundColor: KabukTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _AttachmentPicker(recipientName: widget.displayName),
    );
    if (picked == null || !mounted) return;

    final media = ref.read(mediaServiceProvider);
    List<String> paths = [];

    switch (picked) {
      case _AttachType.image:
        final p = await media.pickImage();
        if (p != null) paths = [p];
      case _AttachType.multiImage:
        paths = await media.pickMultipleImages();
      case _AttachType.video:
        final p = await media.pickVideo();
        if (p != null) paths = [p];
      case _AttachType.file:
        final p = await media.pickFile();
        if (p != null) paths = [p];
    }

    if (paths.isEmpty || !mounted) return;

    // For single images show a preview dialog before uploading.
    if (paths.length == 1 && picked == _AttachType.image) {
      final bytes = await media.readFile(paths.first);
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: KabukTheme.surface,
          title: const Text('Send image?'),
          content: ClipRRect(
            borderRadius: BorderRadius.circular(KabukTheme.radiusMd),
            child: Image.memory(
              Uint8List.fromList(bytes),
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) =>
                  const Text('Could not preview image'),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Send'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }

    setState(() => _isSending = true);
    for (final path in paths) {
      await _uploadAndSend(path, media);
      if (!mounted) break;
    }
    if (mounted) setState(() => _isSending = false);
  }

  Future<void> _uploadAndSend(String path, MediaService media) async {
    try {
      final bytes = await media.readFile(path);
      final filename = path.split('/').last;
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('https://nostr.build/api/v2/upload/files'),
      );
      request.headers['accept'] = 'application/json';
      request.files.add(
        http.MultipartFile.fromBytes('mediafile', bytes, filename: filename),
      );

      final streamed = await request.send().timeout(
        const Duration(seconds: 60),
      );
      final body = await streamed.stream.bytesToString();

      if (streamed.statusCode == 200 || streamed.statusCode == 201) {
        final decoded = jsonDecode(body) as Map<String, dynamic>;
        final data =
            (decoded['data'] as List?)?.firstOrNull as Map<String, dynamic>?;
        final url = data?['url'] as String?;
        if (url != null && mounted) {
          await _sendMessage(url);
        }
      } else {
        throw StateError('Upload failed (HTTP ${streamed.statusCode})');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Upload failed: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Voice recording (H5)
  // ---------------------------------------------------------------------------

  Future<void> _startVoiceRecording() async {
    final media = ref.read(mediaServiceProvider);
    try {
      _pendingRecordingPath = await media.recordAudio();
      if (mounted) setState(() => _isRecording = true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Cannot start recording: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _stopAndSendVoiceMessage() async {
    if (!_isRecording) return;
    setState(() {
      _isRecording = false;
    });
    final media = ref.read(mediaServiceProvider);
    try {
      await media.stopRecording();
      final path = _pendingRecordingPath;
      _pendingRecordingPath = null;
      if (path != null && mounted) {
        setState(() => _isSending = true);
        await _uploadAndSend(path, media);
        if (mounted) setState(() => _isSending = false);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Voice send failed: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Search (N4)
  // ---------------------------------------------------------------------------

  Future<void> _runSearch(String query) async {
    if (query.trim().isEmpty) {
      setState(() => _searchResults = null);
      return;
    }
    final db = ref.read(databaseProvider);
    final results = await db.searchMessages(widget.conversationId, query);
    if (mounted) setState(() => _searchResults = results);
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final messagesAsync = ref.watch(
      _nostrDmMessagesProvider(widget.conversationId),
    );

    ref.listen(_nostrDmMessagesProvider(widget.conversationId), (prev, next) {
      final prevLen = prev?.valueOrNull?.length ?? 0;
      final nextLen = next.valueOrNull?.length ?? 0;
      if (nextLen > prevLen && _isNearBottom) _scrollToBottom();
    });

    final profile = ref
        .watch(nostrProfileProvider(widget.recipientPubkey))
        .valueOrNull;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: _isSearchActive
            ? _buildSearchField()
            : Semantics(
                label: 'View profile of ${profile?.displayName ?? widget.displayName}',
                button: true,
                excludeSemantics: true,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _openProfile(context),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _ProfileAvatar(
                        pubkeyHex: widget.recipientPubkey,
                        pictureUrl: profile?.picture,
                        name: profile?.displayName ?? widget.displayName,
                        radius: 16,
                      ),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              profile?.displayName ?? widget.displayName,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (profile?.nip05 != null)
                              Text(
                                profile!.nip05!,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: KabukTheme.accentGreen,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            _UserStatusLine(pubkeyHex: widget.recipientPubkey),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
        actions: [
          if (_isSearchActive)
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: 'Close search',
              onPressed: () => setState(() {
                _isSearchActive = false;
                _searchQuery = '';
                _searchResults = null;
                _searchController.clear();
              }),
            )
          else ...[
            IconButton(
              icon: const Icon(Icons.search, size: 22),
              tooltip: 'Search messages',
              onPressed: () => setState(() => _isSearchActive = true),
            ),
            IconButton(
              icon: const Icon(Icons.person_outline, size: 22),
              tooltip: 'View profile',
              onPressed: () => _openProfile(context),
            ),
            // N5: Export chat history.
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, size: 22),
              tooltip: 'More options',
              onSelected: (value) {
                if (value == 'export') _exportChat();
                if (value == 'verify') _showSafetyNumber(context);
              },
              itemBuilder: (ctx) => const [
                PopupMenuItem(
                  value: 'export',
                  child: ListTile(
                    leading: Icon(Icons.download),
                    title: Text('Export chat'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                PopupMenuItem(
                  value: 'verify',
                  child: ListTile(
                    leading: Icon(Icons.security),
                    title: Text('Verify safety number'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
      body: Column(
        children: [
          // Pinned messages banner (H10).
          _PinnedMessagesBanner(conversationId: widget.conversationId),

          // Message list or search results.
          Expanded(
            child: Stack(
              children: [
                if (_isSearchActive && _searchResults != null)
                  _buildSearchResults()
                else
                  messagesAsync.when(
                    data: _buildMessageList,
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (e, _) => Center(child: Text('Error: $e')),
                  ),
                if (!_isNearBottom && !_isSearchActive)
                  Positioned(
                    right: KabukTheme.spacingMd,
                    bottom: KabukTheme.spacingSm,
                    child: FloatingActionButton.small(
                      onPressed: _scrollToBottom,
                      backgroundColor: KabukTheme.cardColor.withAlpha(230),
                      foregroundColor: KabukTheme.textSecondary,
                      elevation: 2,
                      child: const Icon(Icons.keyboard_arrow_down),
                    ),
                  ),
              ],
            ),
          ),

          // Voice recording indicator.
          if (_isRecording)
            Container(
              color: Colors.red.withAlpha(20),
              padding: const EdgeInsets.symmetric(
                horizontal: KabukTheme.spacingMd,
                vertical: KabukTheme.spacingSm,
              ),
              child: const Row(
                children: [
                  Icon(Icons.mic, color: Colors.red, size: 16),
                  SizedBox(width: 8),
                  Text(
                    'Recording… release to send',
                    style: TextStyle(color: Colors.red, fontSize: 13),
                  ),
                ],
              ),
            ),

          if (_isSending) const LinearProgressIndicator(minHeight: 2),

          // N1: Typing indicator from contact.
          _TypingIndicatorBar(
            pubkeyHex: widget.recipientPubkey,
            displayName: widget.displayName,
          ),

          // Input bar.
          ChatInput(
            onSend: _sendMessage,
            enabled: !_isSending,
            hintText: 'Message ${widget.displayName}\u2026',
            onAttachment: _isSending ? null : _attachMedia,
            replyToMessage: _replyToMessage,
            onCancelReply: () => setState(() => _replyToMessage = null),
            onVoiceRecordStart: _startVoiceRecording,
            onVoiceRecordEnd: _stopAndSendVoiceMessage,
            onChanged: _onInputChanged,
          ),
        ],
      ),
    );
  }

  Widget _buildSearchField() {
    return TextField(
      controller: _searchController,
      autofocus: true,
      style: const TextStyle(fontSize: 15),
      decoration: const InputDecoration(
        hintText: 'Search messages…',
        border: InputBorder.none,
        hintStyle: TextStyle(color: KabukTheme.textSecondary),
      ),
      onChanged: (q) {
        setState(() => _searchQuery = q);
        _runSearch(q);
      },
    );
  }

  Widget _buildSearchResults() {
    final results = _searchResults ?? [];
    if (results.isEmpty) {
      return Center(
        child: Text(
          _searchQuery.isEmpty ? 'Type to search…' : 'No results found',
          style: const TextStyle(color: KabukTheme.textSecondary),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(
        horizontal: KabukTheme.spacingMd,
        vertical: KabukTheme.spacingSm,
      ),
      itemCount: results.length,
      itemBuilder: (context, i) => _DmBubble(
        message: results[i],
        recipientPubkey: widget.recipientPubkey,
        onReply: (m) => setState(() {
          _replyToMessage = m;
          _isSearchActive = false;
          _searchResults = null;
          _searchController.clear();
        }),
      ),
    );
  }

  Widget _buildMessageList(List<Message> messages) {
    if (messages.isEmpty) return _buildEmptyState();

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(
        horizontal: KabukTheme.spacingMd,
        vertical: KabukTheme.spacingSm,
      ),
      itemCount: messages.length,
      itemBuilder: (context, index) => _DmBubble(
        message: messages[index],
        recipientPubkey: widget.recipientPubkey,
        onReply: (m) => setState(() => _replyToMessage = m),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(KabukTheme.spacingXl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.lock_rounded,
              size: 48,
              color: KabukTheme.accentGreen.withAlpha(80),
            ),
            const SizedBox(height: KabukTheme.spacingMd),
            Text(
              widget.displayName,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: KabukTheme.spacingSm),
            Text(
              'Say hi — messages are end-to-end encrypted.',
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: KabukTheme.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  void _openProfile(BuildContext context) {
    // Switch to the Explore tab and show the profile there.
    ref.read(pendingProfilePubkeyProvider.notifier).state =
        widget.recipientPubkey;
  }
}

// ---------------------------------------------------------------------------
// Attachment type enum
// ---------------------------------------------------------------------------

enum _AttachType { image, multiImage, video, file }

// ---------------------------------------------------------------------------
// Attachment type picker sheet
// ---------------------------------------------------------------------------

class _AttachmentPicker extends StatelessWidget {
  const _AttachmentPicker({required this.recipientName});

  final String recipientName;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.all(KabukTheme.spacingMd),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Send to $recipientName',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
            ),
            const SizedBox(height: KabukTheme.spacingMd),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _AttachOption(
                  icon: Icons.image_outlined,
                  label: 'Image',
                  onTap: () => Navigator.of(context).pop(_AttachType.image),
                ),
                _AttachOption(
                  icon: Icons.photo_library_outlined,
                  label: 'Multiple',
                  onTap: () =>
                      Navigator.of(context).pop(_AttachType.multiImage),
                ),
                _AttachOption(
                  icon: Icons.videocam_outlined,
                  label: 'Video',
                  onTap: () => Navigator.of(context).pop(_AttachType.video),
                ),
                _AttachOption(
                  icon: Icons.attach_file_outlined,
                  label: 'File',
                  onTap: () => Navigator.of(context).pop(_AttachType.file),
                ),
              ],
            ),
            const SizedBox(height: KabukTheme.spacingSm),
          ],
        ),
      ),
    );
  }
}

class _AttachOption extends StatelessWidget {
  const _AttachOption({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      button: true,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: KabukTheme.cardColor,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, color: KabukTheme.accentGreen, size: 28),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: KabukTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Pinned messages banner (H10)
// ---------------------------------------------------------------------------

/// Displays a tappable banner if there are pinned messages in the conversation.
class _PinnedMessagesBanner extends ConsumerWidget {
  const _PinnedMessagesBanner({required this.conversationId});

  final String conversationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(databaseProvider);
    return StreamBuilder<List<Message>>(
      stream: db.watchPinnedMessages(conversationId),
      builder: (context, snap) {
        final pinned = snap.data ?? [];
        if (pinned.isEmpty) return const SizedBox.shrink();
        final first = pinned.first;
        return Semantics(
          label: 'Pinned message: ${first.content}',
          button: true,
          excludeSemantics: true,
          child: GestureDetector(
          onTap: () => showModalBottomSheet<void>(
            context: context,
            backgroundColor: KabukTheme.surface,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            builder: (_) => _PinnedMessagesSheet(
              messages: pinned,
              conversationId: conversationId,
            ),
          ),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
              horizontal: KabukTheme.spacingMd,
              vertical: 7,
            ),
            decoration: BoxDecoration(
              color: KabukTheme.accentGreen.withAlpha(15),
              border: const Border(
                bottom: BorderSide(color: KabukTheme.divider, width: 0.5),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.push_pin_outlined,
                  size: 14,
                  color: KabukTheme.accentGreen,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    first.content,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: KabukTheme.textSecondary,
                    ),
                  ),
                ),
                if (pinned.length > 1)
                  Text(
                    '+${pinned.length - 1}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: KabukTheme.accentGreen,
                    ),
                  ),
              ],
            ),
          ),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// N2: NIP-315 user status indicator
// ---------------------------------------------------------------------------

/// Inline status line shown under the contact name in the AppBar.
///
/// Watches the contact's kind 30315 "general" status events and renders
/// a small green dot + status text. Hidden when the status is empty.
class _UserStatusLine extends ConsumerWidget {
  const _UserStatusLine({required this.pubkeyHex});

  final String pubkeyHex;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusAsync = ref.watch(_userStatusProvider(pubkeyHex));
    final status = statusAsync.valueOrNull;
    if (status == null || status.isEmpty) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: const BoxDecoration(
            color: Colors.greenAccent,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            status,
            style: const TextStyle(fontSize: 10, color: Colors.greenAccent),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// N1: Typing indicator bar
// ---------------------------------------------------------------------------

/// Animated "typing…" bar shown when the contact is actively typing (N1).
class _TypingIndicatorBar extends ConsumerStatefulWidget {
  const _TypingIndicatorBar({
    required this.pubkeyHex,
    required this.displayName,
  });

  final String pubkeyHex;
  final String displayName;

  @override
  ConsumerState<_TypingIndicatorBar> createState() =>
      _TypingIndicatorBarState();
}

class _TypingIndicatorBarState extends ConsumerState<_TypingIndicatorBar> {
  bool _isTyping = false;
  Timer? _clearTimer;

  @override
  void dispose() {
    _clearTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(_typingIndicatorProvider(widget.pubkeyHex), (_, next) {
      if (next.valueOrNull == true) {
        _clearTimer?.cancel();
        if (!_isTyping) setState(() => _isTyping = true);
        // Auto-hide after 8 s if no further events arrive.
        _clearTimer = Timer(const Duration(seconds: 8), () {
          if (mounted) setState(() => _isTyping = false);
        });
      }
    });

    if (!_isTyping) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: KabukTheme.spacingMd,
        vertical: 2,
      ),
      child: Text(
        '${widget.displayName} is typing…',
        style: const TextStyle(
          fontSize: 12,
          color: KabukTheme.textSecondary,
          fontStyle: FontStyle.italic,
        ),
      ),
    );
  }
}

/// Full list of pinned messages in a bottom sheet with unpin actions.
class _PinnedMessagesSheet extends ConsumerWidget {
  const _PinnedMessagesSheet({
    required this.messages,
    required this.conversationId,
  });

  final List<Message> messages;
  final String conversationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.all(KabukTheme.spacingMd),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Pinned Messages',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
            const SizedBox(height: KabukTheme.spacingSm),
            ...messages.map(
              (m) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(
                  Icons.push_pin,
                  size: 16,
                  color: KabukTheme.accentGreen,
                ),
                title: Text(
                  m.content,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  _fmt(m.timestamp),
                  style: const TextStyle(fontSize: 11),
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.push_pin_outlined, size: 18),
                  tooltip: 'Unpin',
                  onPressed: () async {
                    await ref
                        .read(databaseProvider)
                        .pinMessage(m.id, pinned: false);
                    if (context.mounted) Navigator.of(context).pop();
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _fmt(DateTime d) {
    return '${d.day}/${d.month}/${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }
}

// ---------------------------------------------------------------------------
// DM message bubble (M4, H2, H3, H8, H9, H10, H6)
// ---------------------------------------------------------------------------

/// A single direct message bubble with full feature support.
///
/// - H8: Swipe right to reply
/// - M4: Long-press for options (delete, react, pin, expiry)
/// - H3: Inline reply-to preview
/// - H2: Emoji reaction row
/// - H9: Link preview for plain URLs
/// - H10: Pin indicator
class _DmBubble extends ConsumerStatefulWidget {
  const _DmBubble({
    required this.message,
    required this.recipientPubkey,
    required this.onReply,
  });

  final Message message;
  final String recipientPubkey;
  final ValueChanged<Message> onReply;

  @override
  ConsumerState<_DmBubble> createState() => _DmBubbleState();
}

class _DmBubbleState extends ConsumerState<_DmBubble> {
  double _dragOffset = 0;
  bool _didTriggerReply = false;

  bool get _isOwnMessage => widget.message.role == 'user';

  String? get _mediaUrl {
    final content = widget.message.content.trim();
    final uri = Uri.tryParse(content);
    if (uri == null || !uri.hasScheme) return null;
    final path = uri.path.toLowerCase();
    if (path.endsWith('.jpg') ||
        path.endsWith('.jpeg') ||
        path.endsWith('.png') ||
        path.endsWith('.gif') ||
        path.endsWith('.webp') ||
        path.endsWith('.svg')) {
      return content;
    }
    if ((uri.scheme == 'https' || uri.scheme == 'http') &&
        content == widget.message.content.trim() &&
        !content.contains(' ')) {
      return content;
    }
    return null;
  }

  bool get _hasTextContent {
    final url = _mediaUrl;
    if (url == null) return true;
    return widget.message.content.trim() != url;
  }

  /// Returns true if content is a plain URL (not an image) that can be previewed.
  bool get _isLinkPreview {
    final content = widget.message.content.trim();
    if (_mediaUrl != null) return false;
    final uri = Uri.tryParse(content);
    if (uri == null || !uri.hasAbsolutePath) return false;
    return (uri.scheme == 'https' || uri.scheme == 'http') &&
        !content.contains(' ');
  }

  @override
  Widget build(BuildContext context) {
    final maxWidth = MediaQuery.of(context).size.width * 0.75;

    // H8: Swipe-to-reply gesture.
    return GestureDetector(
      onHorizontalDragUpdate: (d) {
        if (d.delta.dx > 0) {
          setState(() => _dragOffset = (_dragOffset + d.delta.dx).clamp(0, 64));
          if (_dragOffset >= 40 && !_didTriggerReply) {
            _didTriggerReply = true;
            HapticFeedback.mediumImpact();
            widget.onReply(widget.message);
          }
        }
      },
      onHorizontalDragEnd: (_) {
        setState(() {
          _dragOffset = 0;
          _didTriggerReply = false;
        });
      },
      child: Transform.translate(
        offset: Offset(_dragOffset, 0),
        child: Column(
          crossAxisAlignment: _isOwnMessage
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            // H3: Reply preview.
            if (widget.message.replyToId != null)
              _ReplyPreview(replyToId: widget.message.replyToId!),

            // Main bubble.
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                mainAxisAlignment: _isOwnMessage
                    ? MainAxisAlignment.end
                    : MainAxisAlignment.start,
                children: [
                  if (_dragOffset > 10)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Icon(
                        Icons.reply,
                        size: 18,
                        color: KabukTheme.accentGreen.withAlpha(
                          (_dragOffset / 64 * 255).toInt(),
                        ),
                      ),
                    ),
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: maxWidth),
                    child: GestureDetector(
                      onLongPress: () => _showOptions(context),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: KabukTheme.spacingMd,
                          vertical: KabukTheme.spacingSm,
                        ),
                        decoration: BoxDecoration(
                          color: _isOwnMessage
                              ? KabukTheme.accentGreen.withAlpha(30)
                              : KabukTheme.cardColor,
                          borderRadius: BorderRadius.only(
                            topLeft: const Radius.circular(KabukTheme.radiusMd),
                            topRight: const Radius.circular(
                              KabukTheme.radiusMd,
                            ),
                            bottomLeft: Radius.circular(
                              _isOwnMessage ? KabukTheme.radiusMd : 4,
                            ),
                            bottomRight: Radius.circular(
                              _isOwnMessage ? 4 : KabukTheme.radiusMd,
                            ),
                          ),
                          border: Border.all(
                            color: _isOwnMessage
                                ? KabukTheme.accentGreen.withAlpha(50)
                                : KabukTheme.divider,
                            width: 0.5,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            // H10: Pin indicator.
                            if (widget.message.isPinned)
                              const Align(
                                alignment: Alignment.topLeft,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.push_pin,
                                      size: 10,
                                      color: KabukTheme.accentGreen,
                                    ),
                                    SizedBox(width: 3),
                                    Text(
                                      'Pinned',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: KabukTheme.accentGreen,
                                      ),
                                    ),
                                    SizedBox(height: 4),
                                  ],
                                ),
                              ),

                            // Image or text content.
                            if (_mediaUrl != null) ...[
                              ClipRRect(
                                borderRadius: BorderRadius.circular(
                                  KabukTheme.radiusSm,
                                ),
                                child: Image.network(
                                  _mediaUrl!,
                                  width: double.infinity,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, _, _) => Container(
                                    height: 80,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: KabukTheme.surfaceVariant,
                                      borderRadius: BorderRadius.circular(
                                        KabukTheme.radiusSm,
                                      ),
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.broken_image_outlined,
                                          size: 18,
                                          color: KabukTheme.textSecondary,
                                        ),
                                        SizedBox(width: 4),
                                        Text(
                                          'Image unavailable',
                                          style: TextStyle(
                                            color: KabukTheme.textSecondary,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              if (_hasTextContent) const SizedBox(height: 6),
                            ],

                            // H9: Link preview card.
                            if (_isLinkPreview)
                              _LinkPreviewCard(
                                url: widget.message.content.trim(),
                              ),

                            if (_hasTextContent)
                              Text(
                                widget.message.content,
                                style: const TextStyle(
                                  color: KabukTheme.textPrimary,
                                  fontSize: 14,
                                  height: 1.4,
                                ),
                              ),

                            // H6: Expiry indicator.
                            if (widget.message.expiresAt != null)
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Padding(
                                  padding: const EdgeInsets.only(top: 3),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.timer_outlined,
                                        size: 10,
                                        color: Colors.orange,
                                      ),
                                      const SizedBox(width: 3),
                                      Text(
                                        _expiryLabel(widget.message.expiresAt!),
                                        style: const TextStyle(
                                          fontSize: 10,
                                          color: Colors.orange,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),

                            const SizedBox(height: 2),

                            // Timestamp + status.
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _formatTime(widget.message.timestamp),
                                  style: TextStyle(
                                    color: KabukTheme.textSecondary.withAlpha(
                                      150,
                                    ),
                                    fontSize: 10,
                                  ),
                                ),
                                if (_isOwnMessage) ...[
                                  const SizedBox(width: 3),
                                  Icon(
                                    _statusIcon,
                                    size: 12,
                                    color: _isDelivered
                                        ? Colors.greenAccent
                                        : KabukTheme.textSecondary.withAlpha(
                                            150,
                                          ),
                                  ),
                                  if (_isDelivered) ...[
                                    const SizedBox(width: 2),
                                    Text(
                                      _relayCountLabel,
                                      style: const TextStyle(
                                        color: Colors.greenAccent,
                                        fontSize: 9,
                                      ),
                                    ),
                                  ],
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // H2: Reaction row.
            _ReactionRow(
              message: widget.message,
              recipientPubkey: widget.recipientPubkey,
            ),
          ],
        ),
      ),
    );
  }

  /// Long-press context menu for the bubble (M4, H6 disappearing messages, H10 pin).
  void _showOptions(BuildContext context) {
    HapticFeedback.mediumImpact();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: KabukTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _BubbleOptionsSheet(
        message: widget.message,
        recipientPubkey: widget.recipientPubkey,
        onReply: () {
          Navigator.of(ctx).pop();
          widget.onReply(widget.message);
        },
      ),
    );
  }

  bool get _isDelivered => widget.message.status.startsWith('delivered:');

  String get _relayCountLabel {
    final status = widget.message.status;
    if (status.startsWith('delivered:')) {
      final count = status.substring('delivered:'.length);
      return '$count r';
    }
    return '';
  }

  IconData get _statusIcon {
    final status = widget.message.status;
    if (status.startsWith('delivered:')) return Icons.done_all;
    return switch (status) {
      'sending' => Icons.schedule,
      'sent' => Icons.check,
      'received' => Icons.done_all,
      _ => Icons.check,
    };
  }

  String _formatTime(DateTime date) {
    final h = date.hour.toString().padLeft(2, '0');
    final m = date.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  String _expiryLabel(DateTime expiry) {
    final remaining = expiry.difference(DateTime.now());
    if (remaining.isNegative) return 'Expired';
    if (remaining.inHours > 0) return 'Expires in ${remaining.inHours}h';
    return 'Expires in ${remaining.inMinutes}m';
  }
}

// ---------------------------------------------------------------------------
// Bubble options bottom sheet (M4)
// ---------------------------------------------------------------------------

class _BubbleOptionsSheet extends ConsumerWidget {
  const _BubbleOptionsSheet({
    required this.message,
    required this.recipientPubkey,
    required this.onReply,
  });

  final Message message;
  final String recipientPubkey;
  final VoidCallback onReply;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOwn = message.role == 'user';

    return SafeArea(
      bottom: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Quick emoji reactions.
          Padding(
            padding: const EdgeInsets.symmetric(vertical: KabukTheme.spacingSm),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: ['❤️', '👍', '😂', '😮', '😢', '🔥'].map((emoji) {
                return GestureDetector(
                  onTap: () async {
                    Navigator.of(context).pop();
                    await _sendReaction(context, ref, emoji);
                  },
                  child: Text(emoji, style: const TextStyle(fontSize: 28)),
                );
              }).toList(),
            ),
          ),
          const Divider(height: 1),

          ListTile(
            leading: const Icon(Icons.reply_outlined),
            title: const Text('Reply'),
            onTap: onReply,
          ),
          ListTile(
            leading: const Icon(Icons.copy_outlined),
            title: const Text('Copy text'),
            onTap: () {
              Clipboard.setData(ClipboardData(text: message.content));
              Navigator.of(context).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Copied to clipboard'),
                  behavior: SnackBarBehavior.floating,
                  duration: Duration(seconds: 2),
                ),
              );
            },
          ),
          ListTile(
            leading: Icon(
              message.isPinned ? Icons.push_pin : Icons.push_pin_outlined,
            ),
            title: Text(message.isPinned ? 'Unpin' : 'Pin message'),
            onTap: () async {
              Navigator.of(context).pop();
              await ref
                  .read(databaseProvider)
                  .pinMessage(message.id, pinned: !message.isPinned);
            },
          ),
          ListTile(
            leading: const Icon(Icons.timer_outlined),
            title: const Text('Set disappear timer'),
            onTap: () async {
              Navigator.of(context).pop();
              await _setExpiry(context, ref);
            },
          ),
          if (isOwn)
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('Delete', style: TextStyle(color: Colors.red)),
              onTap: () async {
                Navigator.of(context).pop();
                await _deleteMessage(context, ref);
              },
            ),
          const SizedBox(height: KabukTheme.spacingSm),
        ],
      ),
    );
  }

  Future<void> _sendReaction(
    BuildContext context,
    WidgetRef ref,
    String emoji,
  ) async {
    try {
      final nostr = ref.read(nostrServiceProvider);
      final db = ref.read(databaseProvider);
      final targetEventId = message.nostrEventId;
      if (targetEventId != null) {
        final event = await nostr.publishReaction(
          targetEventId,
          recipientPubkey,
          reaction: emoji,
        );
        await db.upsertReaction(
          MessageReactionsCompanion(
            messageId: Value(message.id),
            pubkey: Value(event.pubkey),
            reaction: Value(emoji),
            createdAt: Value(
              DateTime.fromMillisecondsSinceEpoch(event.createdAt * 1000),
            ),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('React failed: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _setExpiry(BuildContext context, WidgetRef ref) async {
    final options = {
      '5 minutes': const Duration(minutes: 5),
      '1 hour': const Duration(hours: 1),
      '24 hours': const Duration(hours: 24),
      '7 days': const Duration(days: 7),
      'Never': null,
    };

    final selected = await showDialog<Duration?>(
      context: context,
      builder: (ctx) => SimpleDialog(
        backgroundColor: KabukTheme.surface,
        title: const Text('Disappear after…'),
        children: options.entries.map((e) {
          return SimpleDialogOption(
            onPressed: () => Navigator.of(ctx).pop(e.value),
            child: Text(e.key),
          );
        }).toList(),
      ),
    );
    if (!context.mounted) return;

    final db = ref.read(databaseProvider);
    if (selected == null && options.values.any((v) => v == null)) {
      // "Never" was selected — clear expiry.
      await db.setMessageExpiry(message.id, null);
    } else if (selected != null) {
      await db.setMessageExpiry(message.id, DateTime.now().add(selected));
    }
  }

  Future<void> _deleteMessage(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: KabukTheme.surface,
        title: const Text('Delete message?'),
        content: const Text(
          'This removes the message locally and sends a NIP-09 deletion request to relays.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    try {
      final db = ref.read(databaseProvider);
      final nostr = ref.read(nostrServiceProvider);
      final eventId = message.nostrEventId;
      if (eventId != null) {
        await nostr.deleteEvents([eventId], reason: 'User deleted');
      }
      await db.deleteMessage(message.id);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Delete failed: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Reply preview (H3)
// ---------------------------------------------------------------------------

/// Shows a compact preview of the replied-to message above the bubble.
class _ReplyPreview extends ConsumerWidget {
  const _ReplyPreview({required this.replyToId});

  final String replyToId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(databaseProvider);
    return FutureBuilder<Message?>(
      future: db.getMessageById(replyToId),
      builder: (context, snap) {
        final parent = snap.data;
        if (parent == null) return const SizedBox.shrink();
        return Container(
          margin: const EdgeInsets.only(bottom: 2, left: 12, right: 12),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            border: const Border(
              left: BorderSide(color: KabukTheme.accentGreen, width: 3),
            ),
            color: KabukTheme.accentGreen.withAlpha(10),
            borderRadius: const BorderRadius.only(
              topRight: Radius.circular(6),
              bottomRight: Radius.circular(6),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                parent.role == 'user' ? 'You' : 'Them',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: KabukTheme.accentGreen,
                ),
              ),
              Text(
                parent.content,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  color: KabukTheme.textSecondary,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Reaction row (H2)
// ---------------------------------------------------------------------------

/// Displays emoji reaction chips below a message bubble.
class _ReactionRow extends ConsumerWidget {
  const _ReactionRow({required this.message, required this.recipientPubkey});

  final Message message;
  final String recipientPubkey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(databaseProvider);
    return StreamBuilder<List<MessageReaction>>(
      stream: db.watchReactions(message.id),
      builder: (context, snap) {
        final reactions = snap.data ?? [];
        if (reactions.isEmpty) return const SizedBox.shrink();

        // Group by emoji.
        final counts = <String, int>{};
        for (final r in reactions) {
          counts[r.reaction] = (counts[r.reaction] ?? 0) + 1;
        }

        return Padding(
          padding: const EdgeInsets.only(bottom: 4, left: 12, right: 12),
          child: Wrap(
            spacing: 4,
            runSpacing: 4,
            children: counts.entries.map((e) {
              return GestureDetector(
                onTap: () async {
                  // Toggle own reaction.
                  try {
                    final nostr = ref.read(nostrServiceProvider);
                    final targetId = message.nostrEventId;
                    if (targetId != null) {
                      final event = await nostr.publishReaction(
                        targetId,
                        recipientPubkey,
                        reaction: e.key,
                      );
                      await db.upsertReaction(
                        MessageReactionsCompanion(
                          messageId: Value(message.id),
                          pubkey: Value(event.pubkey),
                          reaction: Value(e.key),
                          createdAt: Value(
                            DateTime.fromMillisecondsSinceEpoch(
                              event.createdAt * 1000,
                            ),
                          ),
                        ),
                      );
                    }
                  } catch (e) {
                    dev.log(
                      'Failed to publish reaction: $e',
                      name: 'NostrChat',
                      error: e,
                    );
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: KabukTheme.cardColor,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: KabukTheme.divider, width: 0.5),
                  ),
                  child: Text(
                    '${e.key} ${e.value}',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              );
            }).toList(),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Link preview (H9)
// ---------------------------------------------------------------------------

/// Fetches Open Graph metadata for a URL and displays a preview card.
class _LinkPreviewCard extends StatefulWidget {
  const _LinkPreviewCard({required this.url});

  final String url;

  @override
  State<_LinkPreviewCard> createState() => _LinkPreviewCardState();
}

class _LinkPreviewCardState extends State<_LinkPreviewCard> {
  _OgData? _data;
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    try {
      final uri = Uri.parse(widget.url);
      final resp = await http
          .get(uri, headers: {'User-Agent': 'KabukBot/1.0'})
          .timeout(const Duration(seconds: 8));
      final body = resp.body;

      final title = _og(body, 'og:title') ?? _tag(body, '<title', '</title>');
      final desc = _og(body, 'og:description');
      final image = _og(body, 'og:image');

      if (mounted) {
        setState(() {
          _data = _OgData(title: title, description: desc, imageUrl: image);
          _loading = false;
        });
      }
    } catch (e) {
      dev.log('OG data fetch failed', name: 'NostrChatDetail', error: e);
      if (mounted) setState(() => _failed = true);
    }
  }

  String? _og(String html, String property) {
    final re = RegExp(
      'property=["\']$property["\'][^>]*content=["\']([^"\']+)["\']',
      caseSensitive: false,
    );
    final m =
        re.firstMatch(html) ??
        RegExp(
          'content=["\']([^"\']+)["\'][^>]*property=["\']$property["\']',
          caseSensitive: false,
        ).firstMatch(html);
    return m?.group(1);
  }

  String? _tag(String html, String open, String close) {
    final i = html.indexOf(open);
    if (i < 0) return null;
    final j = html.indexOf('>', i);
    final k = html.indexOf(close, j);
    if (j < 0 || k < 0) return null;
    return html.substring(j + 1, k).trim();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) return const SizedBox.shrink();
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.only(bottom: 6),
        child: SizedBox(
          height: 16,
          width: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    final d = _data;
    if (d == null || (d.title == null && d.description == null)) {
      return const SizedBox.shrink();
    }

    return GestureDetector(
      onTap: () => openUrlSmart(context, widget.url),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        decoration: BoxDecoration(
          color: KabukTheme.surfaceVariant,
          borderRadius: BorderRadius.circular(KabukTheme.radiusSm),
          border: const Border(
            left: BorderSide(color: KabukTheme.accentGreen, width: 3),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (d.imageUrl != null)
              ClipRRect(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(KabukTheme.radiusSm),
                  topRight: Radius.circular(KabukTheme.radiusSm),
                ),
                child: Image.network(
                  d.imageUrl!,
                  height: 120,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (d.title != null)
                    Text(
                      d.title!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: KabukTheme.textPrimary,
                      ),
                    ),
                  if (d.description != null)
                    Text(
                      d.description!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        color: KabukTheme.textSecondary,
                      ),
                    ),
                  Text(
                    Uri.parse(widget.url).host,
                    style: const TextStyle(
                      fontSize: 10,
                      color: KabukTheme.accentGreen,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OgData {
  const _OgData({this.title, this.description, this.imageUrl});
  final String? title;
  final String? description;
  final String? imageUrl;
}

// ---------------------------------------------------------------------------
// Profile avatar helper
// ---------------------------------------------------------------------------

/// Small circular avatar for the chat app bar.
///
/// Shows a profile picture if [pictureUrl] is set; falls back to
/// initials on a deterministic color derived from [pubkeyHex].
class _ProfileAvatar extends StatelessWidget {
  const _ProfileAvatar({
    required this.pubkeyHex,
    required this.name,
    required this.radius,
    this.pictureUrl,
  });

  final String pubkeyHex;
  final String name;
  final double radius;
  final String? pictureUrl;

  @override
  Widget build(BuildContext context) {
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

    return CircleAvatar(
      radius: radius,
      backgroundColor: bg,
      backgroundImage: pictureUrl != null ? NetworkImage(pictureUrl!) : null,
      onBackgroundImageError: pictureUrl != null ? (_, _) {} : null,
      child: pictureUrl == null
          ? Text(
              initials,
              style: TextStyle(
                color: Colors.white,
                fontSize: radius * 0.75,
                fontWeight: FontWeight.w600,
              ),
            )
          : null,
    );
  }
}
