/// Full release detail view for Usenet content.
///
/// When a user taps a `UsenetCard` in the Explore feed, this page shows
/// full details about the release — including NZB file breakdown, quality
/// attributes, and actions to stream, download, or share the content.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kabuk/config/providers.dart';
import 'package:kabuk/config/result.dart';
import 'package:kabuk/knowledge/types/usenet.dart';
import 'package:kabuk/services/usenet.dart';
import 'package:kabuk/ui/shared/time_format.dart';
import 'package:kabuk/ui/theme.dart';

// =============================================================================
// Providers
// =============================================================================

/// Fetches and parses the NZB file for a given NZB URL.
///
/// Returns `null` when the fetch fails so consumers can distinguish
/// loading (async value absent) from error (async value is null).
final usenetNzbProvider =
    FutureProvider.family<NzbFile?, String>((ref, nzbUrl) async {
  final service = ref.watch(usenetServiceProvider);
  final result = await service.fetchNzb(nzbUrl);
  return switch (result) {
    Success(:final value) => value,
    Failure() => null,
  };
});

// =============================================================================
// Navigation helper
// =============================================================================

/// Pushes the [UsenetDetailPage] onto the navigator with a slide-up
/// transition matching the article detail page.
Future<void> pushUsenetDetail(
  BuildContext context, {
  required UsenetReleaseData release,
}) {
  return Navigator.of(context).push<void>(
    PageRouteBuilder<void>(
      pageBuilder: (context, animation, secondaryAnimation) =>
          UsenetDetailPage(release: release),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final tween = Tween(begin: const Offset(0, 1), end: Offset.zero)
            .chain(CurveTween(curve: Curves.easeOutCubic));
        return SlideTransition(position: animation.drive(tween), child: child);
      },
      transitionDuration: const Duration(milliseconds: 300),
      reverseTransitionDuration: const Duration(milliseconds: 250),
    ),
  );
}

// =============================================================================
// UsenetDetailPage
// =============================================================================

/// Full-screen detail page for a single Usenet release.
///
/// Shows release metadata, quality attributes, the NZB file breakdown
/// (once fetched), and action buttons for streaming, downloading, and
/// sharing.
class UsenetDetailPage extends ConsumerStatefulWidget {
  /// Creates a [UsenetDetailPage] for the given [release].
  const UsenetDetailPage({super.key, required this.release});

  /// The release to display.
  final UsenetReleaseData release;

  @override
  ConsumerState<UsenetDetailPage> createState() => _UsenetDetailPageState();
}

class _UsenetDetailPageState extends ConsumerState<UsenetDetailPage> {
  StreamSession? _activeSession;
  bool _isStreaming = false;

  UsenetReleaseData get _release => widget.release;

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  Future<void> _startStream(NzbFile nzb) async {
    if (_isStreaming) return;
    setState(() => _isStreaming = true);

    final service = ref.read(usenetServiceProvider);
    final result = await service.startStream(nzb);

    if (!mounted) return;
    switch (result) {
      case Success(:final value):
        setState(() {
          _activeSession = value;
          _isStreaming = false;
        });
      case Failure(:final error):
        setState(() => _isStreaming = false);
        _showError('Failed to start stream: $error');
    }
  }

  Future<void> _stopStream() async {
    final session = _activeSession;
    if (session == null) return;

    final service = ref.read(usenetServiceProvider);
    await service.stopStream(session.id);
    if (!mounted) return;
    setState(() => _activeSession = null);
  }

  void _downloadContent(NzbFile nzb) {
    final service = ref.read(usenetServiceProvider);
    final title = _release.title ?? 'download';
    service.downloadContent(nzb, outputName: title).listen(
      (progress) {
        // Download progress is fire-and-forget for now.
      },
      onError: (Object e) => _showError('Download failed: $e'),
    );
    _showSnackBar('Download started');
  }

  void _shareNzbUrl() {
    final url = _release.nzbUrl;
    if (url == null) return;
    Clipboard.setData(ClipboardData(text: url));
    _showSnackBar('NZB URL copied to clipboard');
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: KabukTheme.error,
      ),
    );
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final nzbUrl = _release.nzbUrl;
    final nzbAsync =
        nzbUrl != null ? ref.watch(usenetNzbProvider(nzbUrl)) : null;

    return Scaffold(
      backgroundColor: context.kabukBackground,
      body: CustomScrollView(
        slivers: [
          // App bar.
          SliverAppBar(
            pinned: true,
            backgroundColor: context.kabukSurface,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              onPressed: () => Navigator.of(context).pop(),
            ),
            title: Text(
              _categoryLabel(_release.category),
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: context.kabukTextPrimary,
              ),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.share_rounded, size: 22),
                onPressed: _shareNzbUrl,
                tooltip: 'Share NZB URL',
              ),
            ],
          ),

          // Body content.
          SliverPadding(
            padding: const EdgeInsets.all(KabukTheme.spacingMd),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // ── Header section ────────────────────────────────
                _HeaderSection(release: _release),

                const SizedBox(height: KabukTheme.spacingLg),

                // ── Attributes section ────────────────────────────
                if (_release.attributes.isNotEmpty) ...[
                  _AttributesSection(release: _release),
                  const SizedBox(height: KabukTheme.spacingLg),
                ],

                // ── Newznab attributes section ────────────────────
                _NewznabAttributesSection(release: _release),

                const SizedBox(height: KabukTheme.spacingLg),

                // ── Stream status ─────────────────────────────────
                if (_activeSession != null) ...[
                  _StreamStatusSection(
                    session: _activeSession!,
                    onStop: _stopStream,
                  ),
                  const SizedBox(height: KabukTheme.spacingLg),
                ],

                // ── Action buttons ────────────────────────────────
                _ActionButtonsSection(
                  nzbAsync: nzbAsync,
                  isStreaming: _isStreaming,
                  hasActiveSession: _activeSession != null,
                  onStream: _startStream,
                  onDownload: _downloadContent,
                  onShareNzb: _shareNzbUrl,
                ),

                const SizedBox(height: KabukTheme.spacingLg),

                // ── NZB file list ─────────────────────────────────
                _NzbFileListSection(nzbAsync: nzbAsync),

                const SizedBox(height: KabukTheme.spacingXl),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Header Section
// =============================================================================

class _HeaderSection extends StatelessWidget {
  const _HeaderSection({required this.release});

  final UsenetReleaseData release;

  @override
  Widget build(BuildContext context) {
    final title = release.title;
    final cleanedTitle = title != null ? _cleanTitle(title) : 'Unknown Release';
    final catColor = _categoryColor(release.category);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Category chip.
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: catColor.withAlpha(30),
            borderRadius: BorderRadius.circular(KabukTheme.radiusSm),
            border: Border.all(color: catColor.withAlpha(60), width: 0.5),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_categoryIcon(release.category), size: 16, color: catColor),
              const SizedBox(width: 6),
              Text(
                _categoryLabel(release.category),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: catColor,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: KabukTheme.spacingSm),

        // Title.
        Text(
          cleanedTitle,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            height: 1.25,
            color: context.kabukTextPrimary,
          ),
        ),

        const SizedBox(height: KabukTheme.spacingSm),

        // Metadata row: size · date · indexer.
        Wrap(
          spacing: KabukTheme.spacingSm,
          runSpacing: KabukTheme.spacingXs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (release.sizeBytes != null)
              _MetadataBadge(
                icon: Icons.storage_rounded,
                label: _formatBytes(release.sizeBytes!),
                color: KabukTheme.accentGreen,
              ),
            if (release.publishedAt != null)
              _MetadataBadge(
                icon: Icons.schedule_rounded,
                label: timeAgoFromDateTime(release.publishedAt!),
              ),
            if (release.indexerRef != null)
              _MetadataBadge(
                icon: Icons.search_rounded,
                label: _indexerDisplayName(release.indexerRef!),
              ),
            if (release.poster != null)
              _MetadataBadge(
                icon: Icons.person_outline_rounded,
                label: release.poster!,
              ),
            if (release.group != null)
              _MetadataBadge(
                icon: Icons.forum_outlined,
                label: release.group!,
              ),
          ],
        ),
      ],
    );
  }
}

// =============================================================================
// Metadata Badge
// =============================================================================

class _MetadataBadge extends StatelessWidget {
  const _MetadataBadge({
    required this.icon,
    required this.label,
    this.color,
  });

  final IconData icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final fg = color ?? context.kabukTextSecondary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: (color ?? context.kabukTextTertiary).withAlpha(20),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: fg),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Quality Attributes Section
// =============================================================================

class _AttributesSection extends StatelessWidget {
  const _AttributesSection({required this.release});

  final UsenetReleaseData release;

  @override
  Widget build(BuildContext context) {
    final attrs = release.attributes
        .map((a) => a.trim())
        .where((a) => a.isNotEmpty)
        .toList();

    if (attrs.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Quality',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: context.kabukTextSecondary,
          ),
        ),
        const SizedBox(height: KabukTheme.spacingSm),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: attrs.map((a) {
            final isHighlight = _isHighlightAttribute(a);
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: isHighlight
                    ? KabukTheme.warmAccent.withAlpha(25)
                    : context.kabukSurfaceVariant,
                borderRadius: BorderRadius.circular(KabukTheme.radiusSm),
                border: Border.all(
                  color: isHighlight
                      ? KabukTheme.warmAccent.withAlpha(60)
                      : context.kabukDivider,
                  width: 0.5,
                ),
              ),
              child: Text(
                a,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isHighlight ? FontWeight.w600 : FontWeight.w500,
                  color: isHighlight
                      ? KabukTheme.warmAccent
                      : context.kabukTextPrimary,
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

// =============================================================================
// Newznab Attributes Section (IMDb, TVDB, Season/Episode, etc.)
// =============================================================================

class _NewznabAttributesSection extends StatelessWidget {
  const _NewznabAttributesSection({required this.release});

  final UsenetReleaseData release;

  @override
  Widget build(BuildContext context) {
    final entries = <_DetailEntry>[];

    if (release.imdbId != null) {
      entries.add(_DetailEntry('IMDb', release.imdbId!));
    }
    if (release.tvdbId != null) {
      entries.add(_DetailEntry('TVDB', release.tvdbId!));
    }
    if (release.description != null && release.description!.isNotEmpty) {
      entries.add(_DetailEntry('Description', release.description!));
    }

    if (entries.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Details',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: context.kabukTextSecondary,
          ),
        ),
        const SizedBox(height: KabukTheme.spacingSm),
        Container(
          decoration: BoxDecoration(
            color: context.kabukSurfaceElevated,
            borderRadius: BorderRadius.circular(KabukTheme.radiusMd),
            border: Border.all(color: context.kabukDivider),
          ),
          child: Column(
            children: [
              for (var i = 0; i < entries.length; i++) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: KabukTheme.spacingMd,
                    vertical: 10,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 90,
                        child: Text(
                          entries[i].label,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: context.kabukTextSecondary,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          entries[i].value,
                          style: TextStyle(
                            fontSize: 13,
                            color: context.kabukTextPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (i < entries.length - 1)
                  Divider(
                    height: 1,
                    color: context.kabukDivider,
                    indent: KabukTheme.spacingMd,
                    endIndent: KabukTheme.spacingMd,
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _DetailEntry {
  const _DetailEntry(this.label, this.value);
  final String label;
  final String value;
}

// =============================================================================
// Stream Status Section
// =============================================================================

class _StreamStatusSection extends StatelessWidget {
  const _StreamStatusSection({
    required this.session,
    required this.onStop,
  });

  final StreamSession session;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final progress = session.totalBytes > 0
        ? session.bytesStreamed / session.totalBytes
        : 0.0;
    final stateLabel = switch (session.state) {
      StreamState.buffering => 'Buffering…',
      StreamState.playing => 'Playing',
      StreamState.paused => 'Paused',
      StreamState.seeking => 'Seeking…',
      StreamState.stopped => 'Stopped',
      StreamState.error => 'Error',
    };
    final stateColor = switch (session.state) {
      StreamState.playing => KabukTheme.accentGreen,
      StreamState.buffering || StreamState.seeking => KabukTheme.blueAccent,
      StreamState.paused => KabukTheme.warmAccent,
      StreamState.error => KabukTheme.error,
      StreamState.stopped => KabukTheme.textSecondary,
    };

    return Container(
      padding: const EdgeInsets.all(KabukTheme.spacingMd),
      decoration: BoxDecoration(
        color: context.kabukSurfaceElevated,
        borderRadius: BorderRadius.circular(KabukTheme.radiusMd),
        border: Border.all(color: stateColor.withAlpha(60)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.stream_rounded, size: 18, color: stateColor),
              const SizedBox(width: 8),
              Text(
                stateLabel,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: stateColor,
                ),
              ),
              const Spacer(),
              Text(
                '${_formatBytes(session.bytesStreamed)} / '
                '${_formatBytes(session.totalBytes)}',
                style: TextStyle(
                  fontSize: 12,
                  color: context.kabukTextSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: KabukTheme.spacingSm),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: context.kabukSurfaceVariant,
              color: stateColor,
            ),
          ),
          const SizedBox(height: KabukTheme.spacingSm),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: onStop,
              icon: const Icon(Icons.stop_rounded, size: 18),
              label: const Text('Stop'),
              style: TextButton.styleFrom(
                foregroundColor: KabukTheme.error,
                textStyle: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Action Buttons Section
// =============================================================================

class _ActionButtonsSection extends StatelessWidget {
  const _ActionButtonsSection({
    required this.nzbAsync,
    required this.isStreaming,
    required this.hasActiveSession,
    required this.onStream,
    required this.onDownload,
    required this.onShareNzb,
  });

  final AsyncValue<NzbFile?>? nzbAsync;
  final bool isStreaming;
  final bool hasActiveSession;
  final void Function(NzbFile nzb) onStream;
  final void Function(NzbFile nzb) onDownload;
  final VoidCallback onShareNzb;

  @override
  Widget build(BuildContext context) {
    final nzb = nzbAsync?.valueOrNull;
    final isLoading =
        nzbAsync != null && nzbAsync!.isLoading || isStreaming;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Primary: Stream.
        FilledButton.icon(
          onPressed: nzb != null && !isStreaming && !hasActiveSession
              ? () => onStream(nzb)
              : null,
          icon: isStreaming
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white70,
                  ),
                )
              : const Icon(Icons.play_arrow_rounded, size: 22),
          label: Text(hasActiveSession ? 'Streaming…' : 'Stream'),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
            textStyle:
                const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ),

        const SizedBox(height: KabukTheme.spacingSm),

        // Secondary row: Download + Share.
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: nzb != null ? () => onDownload(nzb) : null,
                icon: const Icon(Icons.download_rounded, size: 20),
                label: const Text('Download'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  textStyle:
                      const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ),
            ),
            const SizedBox(width: KabukTheme.spacingSm),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onShareNzb,
                icon: const Icon(Icons.share_rounded, size: 20),
                label: const Text('Share NZB'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  textStyle:
                      const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),

        // Loading hint.
        if (isLoading)
          Padding(
            padding: const EdgeInsets.only(top: KabukTheme.spacingSm),
            child: Center(
              child: Text(
                isStreaming ? 'Starting stream…' : 'Fetching NZB…',
                style: TextStyle(
                  fontSize: 12,
                  color: context.kabukTextTertiary,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// =============================================================================
// NZB File List Section
// =============================================================================

class _NzbFileListSection extends StatelessWidget {
  const _NzbFileListSection({required this.nzbAsync});

  final AsyncValue<NzbFile?>? nzbAsync;

  @override
  Widget build(BuildContext context) {
    // Nothing to show until the provider is wired up.
    if (nzbAsync == null) return const SizedBox.shrink();

    return switch (nzbAsync!) {
      AsyncLoading() => _buildLoading(context),
      AsyncError(:final error) => _buildError(context, error),
      AsyncData(:final value) when value == null =>
        _buildError(context, 'Failed to load NZB'),
      AsyncData(:final value) => _buildFileList(context, value!),
      _ => const SizedBox.shrink(),
    };
  }

  Widget _buildLoading(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(KabukTheme.spacingLg),
      decoration: BoxDecoration(
        color: context.kabukSurfaceElevated,
        borderRadius: BorderRadius.circular(KabukTheme.radiusMd),
        border: Border.all(color: context.kabukDivider),
      ),
      child: Column(
        children: [
          const SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
          const SizedBox(height: KabukTheme.spacingSm),
          Text(
            'Fetching NZB…',
            style: TextStyle(
              fontSize: 13,
              color: context.kabukTextSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError(BuildContext context, Object error) {
    return Container(
      padding: const EdgeInsets.all(KabukTheme.spacingMd),
      decoration: BoxDecoration(
        color: KabukTheme.error.withAlpha(15),
        borderRadius: BorderRadius.circular(KabukTheme.radiusMd),
        border: Border.all(color: KabukTheme.error.withAlpha(40)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded,
              size: 20, color: KabukTheme.error),
          const SizedBox(width: KabukTheme.spacingSm),
          Expanded(
            child: Text(
              'Could not load NZB file details.',
              style: TextStyle(
                fontSize: 13,
                color: context.kabukTextSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFileList(BuildContext context, NzbFile nzb) {
    final files = List<NzbFileEntry>.from(nzb.files)
      ..sort((a, b) => b.bytes.compareTo(a.bytes));

    final hasPar2 = files.any((f) => f.isPar2);
    final hasRar = files.any((f) => f.isRar);
    final allObfuscated = files.every((f) => _isObfuscatedName(f.filename));
    final largestFile = files.isNotEmpty ? files.first : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section header with summary.
        Row(
          children: [
            Text(
              'Files',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: context.kabukTextSecondary,
              ),
            ),
            const Spacer(),
            Text(
              '${nzb.files.length} files · ${_formatBytes(nzb.totalBytes)}',
              style: TextStyle(
                fontSize: 12,
                color: context.kabukTextTertiary,
              ),
            ),
          ],
        ),

        const SizedBox(height: KabukTheme.spacingXs),

        // PAR2 / RAR indicators.
        if (hasPar2 || hasRar)
          Padding(
            padding: const EdgeInsets.only(bottom: KabukTheme.spacingSm),
            child: Row(
              children: [
                if (hasPar2)
                  const _StatusIndicator(
                    icon: Icons.healing_rounded,
                    label: 'PAR2',
                    color: KabukTheme.accentGreen,
                  ),
                if (hasPar2 && hasRar) const SizedBox(width: 8),
                if (hasRar)
                  const _StatusIndicator(
                    icon: Icons.archive_rounded,
                    label: 'RAR',
                    color: KabukTheme.blueAccent,
                  ),
              ],
            ),
          ),

        const SizedBox(height: KabukTheme.spacingXs),

        // Obfuscation notice when all filenames look like hashes.
        if (allObfuscated)
          Padding(
            padding: const EdgeInsets.only(bottom: KabukTheme.spacingSm),
            child: Text(
              'File names are obfuscated — content may differ from names shown',
              style: TextStyle(
                fontSize: 12,
                fontStyle: FontStyle.italic,
                color: context.kabukTextTertiary,
              ),
            ),
          ),

        // File entries.
        Container(
          decoration: BoxDecoration(
            color: context.kabukSurfaceElevated,
            borderRadius: BorderRadius.circular(KabukTheme.radiusMd),
            border: Border.all(color: context.kabukDivider),
          ),
          child: Column(
            children: [
              for (var i = 0; i < files.length; i++) ...[
                _FileEntryTile(
                  entry: files[i],
                  isPrimary: files[i] == largestFile &&
                      !files[i].isPar2 &&
                      !files[i].isRar,
                ),
                if (i < files.length - 1)
                  Divider(
                    height: 1,
                    color: context.kabukDivider,
                    indent: 44,
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// File Entry Tile
// =============================================================================

class _FileEntryTile extends StatelessWidget {
  const _FileEntryTile({required this.entry, this.isPrimary = false});

  final NzbFileEntry entry;
  final bool isPrimary;

  @override
  Widget build(BuildContext context) {
    final iconData = _fileIcon(entry);
    final iconColor =
        isPrimary ? KabukTheme.accentGreen : context.kabukTextSecondary;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: KabukTheme.spacingSm,
        vertical: KabukTheme.spacingSm,
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: iconColor.withAlpha(20),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(iconData, size: 18, color: iconColor),
          ),
          const SizedBox(width: KabukTheme.spacingSm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.filename,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: isPrimary ? FontWeight.w600 : FontWeight.w400,
                    color: context.kabukTextPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  _formatBytes(entry.bytes),
                  style: TextStyle(
                    fontSize: 11,
                    color: context.kabukTextTertiary,
                  ),
                ),
              ],
            ),
          ),
          if (isPrimary)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: KabukTheme.accentGreen.withAlpha(25),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'MAIN',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: KabukTheme.accentGreen,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// =============================================================================
// Status Indicator (PAR2 / RAR badges)
// =============================================================================

class _StatusIndicator extends StatelessWidget {
  const _StatusIndicator({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withAlpha(50), width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Helper functions
// =============================================================================

/// Formats [bytes] as a human-readable size string.
String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
}

/// Cleans a Usenet release title for display.
String _cleanTitle(String rawTitle) {
  var cleaned = rawTitle.replaceAll(RegExp(r'[._]'), ' ');
  cleaned = cleaned.replaceAll(RegExp(r'-[A-Z0-9]{2,}$'), '');
  return cleaned.trim();
}

/// Returns the Material icon for a Usenet content [category].
IconData _categoryIcon(String? category) {
  return switch (category?.toLowerCase()) {
    'movies' || 'movie' => Icons.movie_rounded,
    'tv' || 'tv shows' || 'television' => Icons.tv_rounded,
    'music' || 'audio' => Icons.music_note_rounded,
    'games' || 'gaming' => Icons.games_rounded,
    'software' || 'pc' || 'apps' => Icons.laptop_rounded,
    'books' || 'ebooks' => Icons.menu_book_rounded,
    'xxx' || 'adult' => Icons.eighteen_up_rating_rounded,
    _ => Icons.folder_rounded,
  };
}

/// Returns an accent color for a Usenet content [category].
Color _categoryColor(String? category) {
  return switch (category?.toLowerCase()) {
    'movies' || 'movie' => KabukTheme.blueAccent,
    'tv' || 'tv shows' || 'television' => KabukTheme.purpleAccent,
    'music' || 'audio' => const Color(0xFFE91E63),
    'games' || 'gaming' => KabukTheme.accentGreen,
    'software' || 'pc' || 'apps' => KabukTheme.warmAccent,
    'books' || 'ebooks' => const Color(0xFF8D6E63),
    _ => KabukTheme.textSecondary,
  };
}

/// Returns a human-readable label for a Usenet content [category].
String _categoryLabel(String? category) {
  return switch (category?.toLowerCase()) {
    'movies' || 'movie' => 'Movies',
    'tv' || 'tv shows' || 'television' => 'TV Shows',
    'music' => 'Music',
    'audio' => 'Audio',
    'games' || 'gaming' => 'Games',
    'software' || 'pc' || 'apps' => 'Software',
    'books' || 'ebooks' => 'Books',
    'xxx' || 'adult' => 'Adult',
    final String c => c,
    null => 'Usenet',
  };
}

/// Derives a short display name from an indexer URI.
String _indexerDisplayName(String ref) {
  if (ref.startsWith('kabuk:')) {
    return ref.substring(6).replaceAll('-', ' ');
  }
  final uri = Uri.tryParse(ref);
  if (uri != null && uri.host.isNotEmpty) return uri.host;
  return ref;
}

/// Returns the appropriate icon for an [NzbFileEntry] based on its type.
IconData _fileIcon(NzbFileEntry entry) {
  if (entry.isPar2) return Icons.healing_rounded;
  if (entry.isRar) return Icons.archive_rounded;

  final lower = entry.filename.toLowerCase();
  if (lower.endsWith('.mkv') ||
      lower.endsWith('.mp4') ||
      lower.endsWith('.avi') ||
      lower.endsWith('.wmv')) {
    return Icons.movie_rounded;
  }
  if (lower.endsWith('.mp3') ||
      lower.endsWith('.flac') ||
      lower.endsWith('.aac') ||
      lower.endsWith('.ogg')) {
    return Icons.music_note_rounded;
  }
  if (lower.endsWith('.nfo') || lower.endsWith('.txt')) {
    return Icons.info_outline_rounded;
  }
  if (lower.endsWith('.srt') || lower.endsWith('.sub') || lower.endsWith('.ass')) {
    return Icons.subtitles_rounded;
  }
  return Icons.insert_drive_file_rounded;
}

/// Whether a filename looks obfuscated (hex-hash or `hex$hex@domain`).
bool _isObfuscatedName(String name) {
  return RegExp(r'^[0-9a-fA-F]{8,}').hasMatch(name) ||
      (name.contains(r'$') && name.contains('@'));
}

/// Premium quality indicators that deserve a warm accent highlight.
bool _isHighlightAttribute(String attr) {
  const highlighted = {
    '2160p', '4K', 'HDR', 'HDR10', 'HDR10+', 'DV',
    'Dolby Vision', 'Remux', 'Atmos', 'DTS-X', 'TrueHD',
  };
  return highlighted.contains(attr);
}
