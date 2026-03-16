/// QR contact exchange screen — add contacts by scanning or showing QR codes.
///
/// Two-tab layout:
/// - **My Code** — displays the current user's identity as a QR code
///   that others can scan to add them as a contact.
/// - **Scan** — opens the camera to scan another user's QR code and
///   immediately creates a contact + opens a DM conversation.
library;

import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kabuk/config/providers.dart';
import 'package:kabuk/knowledge/database.dart';
import 'package:kabuk/knowledge/types/person.dart';
import 'package:kabuk/services/peer_exchange.dart';
import 'package:kabuk/ui/chat/nostr_chat_detail.dart';
import 'package:kabuk/ui/theme.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// Full-screen QR code contact exchange.
///
/// Accessed from the Chat tab's "+" menu via "Add via QR".
/// Uses [DefaultTabController] for the My Code / Scan split.
class QrContactExchange extends ConsumerStatefulWidget {
  /// Creates a [QrContactExchange].
  const QrContactExchange({super.key});

  @override
  ConsumerState<QrContactExchange> createState() => _QrContactExchangeState();
}

class _QrContactExchangeState extends ConsumerState<QrContactExchange>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  bool _scanned = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KabukTheme.background,
      appBar: AppBar(
        title: const Text('Add Contact'),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: KabukTheme.accentGreen,
          labelColor: KabukTheme.accentGreen,
          unselectedLabelColor: KabukTheme.textSecondary,
          tabs: const [
            Tab(icon: Icon(Icons.qr_code_rounded), text: 'My Code'),
            Tab(icon: Icon(Icons.qr_code_scanner_rounded), text: 'Scan'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _MyCodeTab(),
          _ScanTab(
            onScanned: _handleScanned,
            alreadyScanned: _scanned,
          ),
        ],
      ),
    );
  }

  /// Processes a successfully scanned QR payload.
  Future<void> _handleScanned(PeerExchangePayload payload) async {
    if (_scanned) return;
    setState(() => _scanned = true);

    // Haptic feedback on successful scan.
    unawaited(HapticFeedback.mediumImpact());

    final hexPubkey = payload.publicKeyHex ?? _npubToHex(payload.npub);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Invalid QR code — could not decode public key'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        setState(() => _scanned = false);
      }
      return;
    }

    final displayName =
        payload.name ?? '${hexPubkey.substring(0, 8)}...';

    // Save as contact in knowledge store.
    final store = ref.read(knowledgeStoreProvider);
    await store.createPerson(
      name: displayName,
      nostrPubkey: hexPubkey,
    );
    ref.invalidate(contactsProvider);

    // Create or find the Nostr DM conversation.
    final db = ref.read(databaseProvider);
    var conversation = await db.findNostrDmConversation(hexPubkey);
    if (conversation == null) {
      final id = 'nostr_dm_$hexPubkey';
      await db.upsertConversation(
        ConversationsCompanion(
          id: Value(id),
          title: Value(displayName),
          type: const Value('nostr_dm'),
          nostrPubkey: Value(hexPubkey),
          createdAt: Value(DateTime.now()),
          updatedAt: Value(DateTime.now()),
        ),
      );
      conversation = await db.getConversation(id);
    }

    if (conversation != null && mounted) {
      ref.read(activeConversationProvider.notifier).state = conversation.id;

      // Replace current route with the DM detail.
      unawaited(Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => NostrChatDetail(
            conversationId: conversation!.id,
            recipientPubkey: hexPubkey,
            displayName: displayName,
          ),
        ),
      ));
    }
  }

  /// Minimal npub → hex decoder.
  static String? _npubToHex(String npub) {
    if (!npub.startsWith('npub1')) return null;
    const charset = 'qpzry9x8gf2tvdw0s3jn54khce6mua7l';
    final pos = npub.lastIndexOf('1');
    if (pos < 1 || pos + 7 > npub.length) return null;
    final data = <int>[];
    for (var i = pos + 1; i < npub.length; i++) {
      final idx = charset.indexOf(npub[i].toLowerCase());
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
    if (result.length != 32) return null;
    return result.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}

// =============================================================================
// My Code Tab
// =============================================================================

/// Displays the current user's identity as a scannable QR code.
class _MyCodeTab extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final identityAsync = ref.watch(currentIdentityProvider);

    return identityAsync.when(
      data: (identity) {
        if (identity == null) {
          return _NoIdentityMessage();
        }

        final payload = PeerExchangePayload(
          npub: identity.npub ?? '',
          name: identity.displayName,
          publicKeyHex: identity.publicKeyHex,
        );

        if (payload.npub.isEmpty) {
          return _NoIdentityMessage();
        }

        final qrData = payload.encode();

        return SingleChildScrollView(
          padding: const EdgeInsets.all(KabukTheme.spacingLg),
          child: Column(
            children: [
              const SizedBox(height: KabukTheme.spacingLg),

              // Identity card.
              Container(
                padding: const EdgeInsets.all(KabukTheme.spacingLg),
                decoration: BoxDecoration(
                  color: KabukTheme.surfaceElevated,
                  borderRadius: BorderRadius.circular(KabukTheme.radiusXl),
                  border: Border.all(
                    color: KabukTheme.accentGreen.withAlpha(40),
                  ),
                ),
                child: Column(
                  children: [
                    // Avatar.
                    CircleAvatar(
                      radius: 32,
                      backgroundColor: KabukTheme.accentGreen.withAlpha(30),
                      child: Text(
                        identity.displayName.isNotEmpty
                            ? identity.displayName[0].toUpperCase()
                            : '?',
                        style: const TextStyle(
                          color: KabukTheme.accentGreen,
                          fontSize: 28,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: KabukTheme.spacingSm),
                    Text(
                      identity.displayName.isNotEmpty
                          ? identity.displayName
                          : 'Anonymous',
                      style: const TextStyle(
                        color: KabukTheme.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      identity.npub ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: KabukTheme.textSecondary,
                        fontSize: 11,
                        fontFamily: 'monospace',
                      ),
                    ),

                    const SizedBox(height: KabukTheme.spacingLg),

                    // QR code.
                    Container(
                      padding: const EdgeInsets.all(KabukTheme.spacingMd),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius:
                            BorderRadius.circular(KabukTheme.radiusMd),
                      ),
                      child: QrImageView(
                        data: qrData,
                        version: QrVersions.auto,
                        size: 220,
                        backgroundColor: Colors.white,
                        errorCorrectionLevel: QrErrorCorrectLevel.M,
                        eyeStyle: const QrEyeStyle(
                          eyeShape: QrEyeShape.square,
                          color: Color(0xFF1A1A1A),
                        ),
                        dataModuleStyle: const QrDataModuleStyle(
                          dataModuleShape: QrDataModuleShape.square,
                          color: Color(0xFF1A1A1A),
                        ),
                      ),
                    ),

                    const SizedBox(height: KabukTheme.spacingMd),

                    // Copy button.
                    TextButton.icon(
                      onPressed: () {
                        Clipboard.setData(
                          ClipboardData(text: identity.npub ?? ''),
                        );
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Public key copied'),
                            duration: Duration(seconds: 2),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      },
                      icon: const Icon(Icons.copy_rounded, size: 16),
                      label: const Text('Copy public key'),
                      style: TextButton.styleFrom(
                        foregroundColor: KabukTheme.accentGreen,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: KabukTheme.spacingLg),

              // Instructions.
              const Text(
                'Show this code to another Kabuk user so they can\n'
                'scan it and start an encrypted conversation with you.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: KabukTheme.textSecondary,
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
            ],
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Text('Error: $e', style: const TextStyle(color: KabukTheme.error)),
      ),
    );
  }
}

/// Shown when no identity has been generated yet.
class _NoIdentityMessage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(KabukTheme.spacingLg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.key_off_rounded,
              size: 48,
              color: KabukTheme.textSecondary.withAlpha(120),
            ),
            const SizedBox(height: KabukTheme.spacingMd),
            const Text(
              'No Identity',
              style: TextStyle(
                color: KabukTheme.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: KabukTheme.spacingSm),
            const Text(
              'Generate an identity first from the identity\n'
              'switcher in the top-left corner.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: KabukTheme.textSecondary,
                fontSize: 13,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Scan Tab
// =============================================================================

/// Camera-based QR code scanner tab.
class _ScanTab extends StatefulWidget {
  const _ScanTab({
    required this.onScanned,
    required this.alreadyScanned,
  });

  final Future<void> Function(PeerExchangePayload) onScanned;
  final bool alreadyScanned;

  @override
  State<_ScanTab> createState() => _ScanTabState();
}

class _ScanTabState extends State<_ScanTab> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
    torchEnabled: false,
  );
  bool _processing = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.alreadyScanned) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_rounded, color: KabukTheme.accentGreen, size: 48),
            SizedBox(height: KabukTheme.spacingMd),
            Text(
              'Contact added!',
              style: TextStyle(
                color: KabukTheme.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: KabukTheme.spacingSm),
            Text(
              'Opening conversation...',
              style: TextStyle(color: KabukTheme.textSecondary, fontSize: 13),
            ),
          ],
        ),
      );
    }

    return Stack(
      children: [
        // Camera preview.
        MobileScanner(
          controller: _controller,
          onDetect: _handleDetect,
        ),

        // Scan overlay.
        _ScanOverlay(isProcessing: _processing),

        // Torch toggle.
        Positioned(
          bottom: KabukTheme.spacingLg,
          left: 0,
          right: 0,
          child: Center(
            child: IconButton.filled(
              onPressed: _controller.toggleTorch,
              icon: ValueListenableBuilder(
                valueListenable: _controller,
                builder: (context, state, child) {
                  return Icon(
                    state.torchState == TorchState.on
                        ? Icons.flash_on_rounded
                        : Icons.flash_off_rounded,
                  );
                },
              ),
              style: IconButton.styleFrom(
                backgroundColor: KabukTheme.surface.withAlpha(180),
                foregroundColor: KabukTheme.textPrimary,
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _handleDetect(BarcodeCapture capture) {
    if (_processing || widget.alreadyScanned) return;
    final barcode = capture.barcodes.firstOrNull;
    if (barcode == null || barcode.rawValue == null) return;

    final raw = barcode.rawValue!;
    final payload = PeerExchangePayload.tryParse(raw);
    if (payload == null) {
      // Not a Kabuk QR code — ignore silently.
      return;
    }

    setState(() => _processing = true);
    widget.onScanned(payload);
  }
}

/// Semi-transparent overlay with a scan window cutout.
class _ScanOverlay extends StatelessWidget {
  const _ScanOverlay({required this.isProcessing});

  final bool isProcessing;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Column(
        children: [
          const SizedBox(height: KabukTheme.spacingLg),

          // Instructions text.
          Container(
            margin: const EdgeInsets.symmetric(horizontal: KabukTheme.spacingLg),
            padding: const EdgeInsets.symmetric(
              horizontal: KabukTheme.spacingMd,
              vertical: KabukTheme.spacingSm,
            ),
            decoration: BoxDecoration(
              color: KabukTheme.surface.withAlpha(200),
              borderRadius: BorderRadius.circular(KabukTheme.radiusMd),
            ),
            child: Text(
              isProcessing
                  ? 'Adding contact...'
                  : 'Point your camera at a Kabuk QR code',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: KabukTheme.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),

          const Spacer(),

          // Scan frame indicator.
          if (!isProcessing)
            Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                border: Border.all(
                  color: KabukTheme.accentGreen.withAlpha(150),
                  width: 2,
                ),
                borderRadius: BorderRadius.circular(KabukTheme.radiusMd),
              ),
            )
          else
            const SizedBox(
              width: 48,
              height: 48,
              child: CircularProgressIndicator(
                color: KabukTheme.accentGreen,
                strokeWidth: 3,
              ),
            ),

          const Spacer(),
          const SizedBox(height: 80), // Space for torch button.
        ],
      ),
    );
  }
}
