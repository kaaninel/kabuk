/// Device pairing page — pair devices via QR code for identity sync.
///
/// Two-tab layout:
/// - **My Code** — displays this device's pairing QR code for another
///   device to scan.
/// - **Scan** — opens the camera to scan another device's QR code
///   and establish a pairing.
///
/// Paired devices share the same Nostr identity and sync their
/// knowledge stores over the local network.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kabuk/config/providers.dart';
import 'package:kabuk/services/device_sync.dart';
import 'package:kabuk/ui/theme.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// Device pairing page with QR code exchange.
class DevicePairingPage extends ConsumerStatefulWidget {
  /// Creates a [DevicePairingPage].
  const DevicePairingPage({super.key});

  @override
  ConsumerState<DevicePairingPage> createState() => _DevicePairingPageState();
}

class _DevicePairingPageState extends ConsumerState<DevicePairingPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  bool _scanned = false;
  DevicePairingPayload? _payload;
  bool _generating = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _generatePayload();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _generatePayload() async {
    setState(() => _generating = true);
    try {
      final syncService = ref.read(deviceSyncServiceProvider);
      final payload = await syncService.generatePairingPayload();
      if (mounted) setState(() => _payload = payload);
    } on Object catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to generate pairing code: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Pair Device'),
        backgroundColor: theme.scaffoldBackgroundColor,
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.qr_code_2_rounded), text: 'My Code'),
            Tab(
              icon: Icon(Icons.qr_code_scanner_rounded),
              text: 'Scan',
            ),
          ],
          indicatorColor: KabukTheme.accentGreen,
          labelColor: KabukTheme.accentGreen,
          unselectedLabelColor: isDark
              ? KabukTheme.textSecondary
              : KabukTheme.lightTextSecondary,
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildMyCodeTab(context),
          _buildScanTab(context),
        ],
      ),
    );
  }

  Widget _buildMyCodeTab(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    if (_generating || _payload == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final payload = _payload!;
    final qrData = payload.encodeAsUri();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const SizedBox(height: 16),
          Text(
            'Show this QR code to your other device',
            style: TextStyle(
              fontSize: 16,
              color: isDark
                  ? KabukTheme.textSecondary
                  : KabukTheme.lightTextSecondary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          // QR Code
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(30),
                  blurRadius: 20,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: QrImageView(
              data: qrData,
              size: 220,
              backgroundColor: Colors.white,
              eyeStyle: const QrEyeStyle(
                eyeShape: QrEyeShape.square,
                color: Colors.black87,
              ),
              dataModuleStyle: const QrDataModuleStyle(
                dataModuleShape: QrDataModuleShape.circle,
                color: Colors.black87,
              ),
            ),
          ),
          const SizedBox(height: 24),
          // Verification code
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 24,
              vertical: 12,
            ),
            decoration: BoxDecoration(
              color: isDark
                  ? KabukTheme.cardColor
                  : KabukTheme.lightCardColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: KabukTheme.accentGreen.withAlpha(80),
              ),
            ),
            child: Column(
              children: [
                Text(
                  'Verification Code',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark
                        ? KabukTheme.textTertiary
                        : KabukTheme.lightTextTertiary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  payload.pairingCode,
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 4,
                    fontFamily: 'monospace',
                    color: KabukTheme.accentGreen,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Device info
          _infoRow(
            context,
            icon: Icons.devices_rounded,
            label: 'Device',
            value: payload.deviceName,
          ),
          _infoRow(
            context,
            icon: Icons.key_rounded,
            label: 'Identity',
            value: '${payload.publicKeyHex.substring(0, 8)}...',
          ),
          _infoRow(
            context,
            icon: Icons.timer_rounded,
            label: 'Expires',
            value: _formatExpiry(payload.pairingExpiry),
          ),
          const SizedBox(height: 24),
          // Refresh button
          OutlinedButton.icon(
            onPressed: _generatePayload,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Regenerate Code'),
            style: OutlinedButton.styleFrom(
              foregroundColor: KabukTheme.accentGreen,
              side: BorderSide(
                color: KabukTheme.accentGreen.withAlpha(80),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScanTab(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    if (_scanned) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.check_circle_rounded,
              color: KabukTheme.accentGreen,
              size: 64,
            ),
            const SizedBox(height: 16),
            Text(
              'Device Paired!',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: isDark
                    ? KabukTheme.textPrimary
                    : KabukTheme.lightTextPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Knowledge sync will start automatically\nwhen both devices are on the same network.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isDark
                    ? KabukTheme.textSecondary
                    : KabukTheme.lightTextSecondary,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.check_rounded),
              label: const Text('Done'),
              style: FilledButton.styleFrom(
                backgroundColor: KabukTheme.accentGreen,
              ),
            ),
          ],
        ),
      );
    }

    return Stack(
      children: [
        MobileScanner(
          onDetect: _onDetect,
        ),
        // Scan overlay
        Positioned.fill(
          child: CustomPaint(
            painter: _ScanOverlayPainter(
              borderColor: KabukTheme.accentGreen,
            ),
          ),
        ),
        // Instructions
        Positioned(
          bottom: 80,
          left: 24,
          right: 24,
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 12,
            ),
            decoration: BoxDecoration(
              color: Colors.black.withAlpha(180),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              'Scan the QR code shown on your other device.\n'
              'Both devices must share the same identity.',
              style: TextStyle(color: Colors.white, fontSize: 14),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_scanned) return;
    final barcode = capture.barcodes.firstOrNull;
    if (barcode == null || barcode.rawValue == null) return;

    final raw = barcode.rawValue!;
    final payload = DevicePairingPayload.tryParse(raw);
    if (payload == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Not a valid Kabuk pairing code')),
        );
      }
      return;
    }

    if (payload.isExpired) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('This pairing code has expired')),
        );
      }
      return;
    }

    setState(() => _scanned = true);
    unawaited(HapticFeedback.heavyImpact());

    // Show confirmation dialog.
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Pair Device?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Device: ${payload.deviceName}'),
            const SizedBox(height: 8),
            Text('Code: ${payload.pairingCode}'),
            const SizedBox(height: 8),
            Text(
              'Identity: ${payload.publicKeyHex.substring(0, 16)}...',
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
            const SizedBox(height: 12),
            const Text(
              'This will enable knowledge sync between\nyour devices.',
              style: TextStyle(fontSize: 13),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: KabukTheme.accentGreen,
            ),
            child: const Text('Pair'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      setState(() => _scanned = false);
      return;
    }

    try {
      final syncService = ref.read(deviceSyncServiceProvider);
      await syncService.confirmPairing(payload);
      unawaited(HapticFeedback.mediumImpact());
    } on Object catch (e) {
      if (mounted) {
        setState(() => _scanned = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Pairing failed: $e')),
        );
      }
    }
  }

  Widget _infoRow(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(
            icon,
            size: 18,
            color: isDark
                ? KabukTheme.textTertiary
                : KabukTheme.lightTextTertiary,
          ),
          const SizedBox(width: 12),
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              color: isDark
                  ? KabukTheme.textTertiary
                  : KabukTheme.lightTextTertiary,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: isDark
                  ? KabukTheme.textPrimary
                  : KabukTheme.lightTextPrimary,
            ),
          ),
        ],
      ),
    );
  }

  String _formatExpiry(DateTime expiry) {
    final remaining = expiry.difference(DateTime.now());
    if (remaining.isNegative) return 'Expired';
    if (remaining.inMinutes > 0) return '${remaining.inMinutes} min';
    return '${remaining.inSeconds} sec';
  }
}

/// Scan overlay painter — draws a semi-transparent overlay with a
/// cut-out square in the center.
class _ScanOverlayPainter extends CustomPainter {
  _ScanOverlayPainter({required this.borderColor});

  final Color borderColor;

  @override
  void paint(Canvas canvas, Size size) {
    final overlayPaint = Paint()..color = Colors.black.withAlpha(120);
    final cutoutSize = size.width * 0.65;
    final cutoutRect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2 - 40),
      width: cutoutSize,
      height: cutoutSize,
    );

    // Draw overlay with cutout.
    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(Offset.zero & size),
        Path()..addRRect(
          RRect.fromRectAndRadius(cutoutRect, const Radius.circular(16)),
        ),
      ),
      overlayPaint,
    );

    // Draw border around cutout.
    final borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawRRect(
      RRect.fromRectAndRadius(cutoutRect, const Radius.circular(16)),
      borderPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _ScanOverlayPainter old) =>
      borderColor != old.borderColor;
}

/// Settings section showing paired devices and management options.
class PairedDevicesSection extends ConsumerWidget {
  /// Creates a [PairedDevicesSection].
  const PairedDevicesSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final syncService = ref.read(deviceSyncServiceProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
          child: Row(
            children: [
              Icon(
                Icons.devices_rounded,
                size: 18,
                color: KabukTheme.accentGreen,
              ),
              const SizedBox(width: 8),
              Text(
                'PAIRED DEVICES',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.2,
                  color: isDark
                      ? KabukTheme.textTertiary
                      : KabukTheme.lightTextTertiary,
                ),
              ),
            ],
          ),
        ),
        // Paired devices stream
        StreamBuilder<List<PairedDevice>>(
          stream: syncService.watchPairedDevices(),
          builder: (context, snapshot) {
            final devices = snapshot.data ?? [];

            if (devices.isEmpty) {
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: isDark
                      ? KabukTheme.cardColor
                      : KabukTheme.lightCardColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Icon(
                      Icons.link_off_rounded,
                      size: 32,
                      color: isDark
                          ? KabukTheme.textTertiary
                          : KabukTheme.lightTextTertiary,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'No paired devices',
                      style: TextStyle(
                        color: isDark
                            ? KabukTheme.textSecondary
                            : KabukTheme.lightTextSecondary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Pair another device to sync your data',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark
                            ? KabukTheme.textTertiary
                            : KabukTheme.lightTextTertiary,
                      ),
                    ),
                  ],
                ),
              );
            }

            return Column(
              children: devices.map((device) {
                return _DeviceTile(
                  device: device,
                  onRemove: () async {
                    await syncService.removePairing(device.deviceId);
                  },
                  onSync: () async {
                    try {
                      final count = await syncService.syncWithDevice(
                        device.deviceId,
                      );
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Synced $count triples'),
                          ),
                        );
                      }
                    } on Object catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Sync failed: $e')),
                        );
                      }
                    }
                  },
                );
              }).toList(),
            );
          },
        ),
        // Pair new device button
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const DevicePairingPage(),
                  ),
                );
              },
              icon: const Icon(Icons.add_link_rounded),
              label: const Text('Pair New Device'),
              style: OutlinedButton.styleFrom(
                foregroundColor: KabukTheme.accentGreen,
                side: BorderSide(
                  color: KabukTheme.accentGreen.withAlpha(80),
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Individual device tile in the paired devices list.
class _DeviceTile extends StatelessWidget {
  const _DeviceTile({
    required this.device,
    required this.onRemove,
    required this.onSync,
  });

  final PairedDevice device;
  final VoidCallback onRemove;
  final VoidCallback onSync;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark
            ? KabukTheme.cardColor
            : KabukTheme.lightCardColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          // Status indicator
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: device.isOnline
                  ? KabukTheme.accentGreen
                  : isDark
                      ? KabukTheme.textTertiary
                      : KabukTheme.lightTextTertiary,
            ),
          ),
          const SizedBox(width: 12),
          // Device info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  device.deviceName,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: isDark
                        ? KabukTheme.textPrimary
                        : KabukTheme.lightTextPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  device.isOnline
                      ? 'Online'
                      : device.lastSeenAt != null
                          ? 'Last seen ${_timeAgo(device.lastSeenAt!)}'
                          : 'Never seen',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark
                        ? KabukTheme.textTertiary
                        : KabukTheme.lightTextTertiary,
                  ),
                ),
                if (device.lastSyncAt != null)
                  Text(
                    'Last sync: ${_timeAgo(device.lastSyncAt!)}',
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark
                          ? KabukTheme.textTertiary
                          : KabukTheme.lightTextTertiary,
                    ),
                  ),
              ],
            ),
          ),
          // Actions
          if (device.isOnline)
            IconButton(
              icon: const Icon(Icons.sync_rounded, size: 20),
              color: KabukTheme.accentGreen,
              onPressed: onSync,
              tooltip: 'Sync now',
            ),
          IconButton(
            icon: const Icon(Icons.link_off_rounded, size: 20),
            color: isDark
                ? KabukTheme.textTertiary
                : KabukTheme.lightTextTertiary,
            onPressed: () => _confirmRemove(context),
            tooltip: 'Remove pairing',
          ),
        ],
      ),
    );
  }

  Future<void> _confirmRemove(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Device?'),
        content: Text(
          'Stop syncing with "${device.deviceName}"?\n'
          'You can pair again later.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed == true) onRemove();
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}
