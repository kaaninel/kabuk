/// Capture preview — full-screen preview after photo/video capture.
///
/// Shows the captured media with overlay controls for adding a caption,
/// tags, saving to the knowledge store, or sharing privately.
/// Inspired by Instagram/Snapchat's post-capture flow.
library;

import 'dart:async';
import 'dart:io'
    show File; // Required by Flutter's Image.file & VideoPlayerController.file

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kabuk/config/providers.dart';
import 'package:kabuk/knowledge/types/media.dart';
import 'package:kabuk/ui/theme.dart';
import 'package:video_player/video_player.dart';

/// The type of captured content.
enum CaptureType {
  /// A still photo.
  photo,

  /// A video recording.
  video,
}

/// Full-screen preview of captured media with save/share controls.
///
/// Displays the captured photo or video with a translucent overlay
/// at the bottom for caption input, tags, and action buttons.
/// Users can save privately to their device or share.
class CapturePreview extends ConsumerStatefulWidget {
  /// Creates a [CapturePreview].
  const CapturePreview({
    super.key,
    required this.filePath,
    required this.captureType,
    required this.onDiscard,
    required this.onSaved,
  });

  /// Path to the captured file.
  final String filePath;

  /// Whether this is a photo or video.
  final CaptureType captureType;

  /// Called when the user discards the capture.
  final VoidCallback onDiscard;

  /// Called after the media is saved successfully.
  final VoidCallback onSaved;

  @override
  ConsumerState<CapturePreview> createState() => _CapturePreviewState();
}

class _CapturePreviewState extends ConsumerState<CapturePreview> {
  final _captionController = TextEditingController();
  final _tagController = TextEditingController();
  final _captionFocus = FocusNode();
  final _tags = <String>[];
  bool _showTags = false;
  bool _saving = false;
  VideoPlayerController? _videoController;

  @override
  void initState() {
    super.initState();
    if (widget.captureType == CaptureType.video) {
      _initVideo();
    }
  }

  Future<void> _initVideo() async {
    final controller = VideoPlayerController.file(File(widget.filePath));
    _videoController = controller;
    try {
      await controller.initialize();
      await controller.setLooping(true);
      await controller.play();
      if (mounted) setState(() {});
    } on Object catch (e, st) {
      debugPrint('Video init failed: $e\n$st');
      // Dispose the controller to avoid leaking native resources.
      unawaited(_videoController?.dispose());
      _videoController = null;
      // Still set state so the UI shows a placeholder instead of spinner.
      if (mounted) setState(() {});
    }
  }

  @override
  void dispose() {
    _captionController.dispose();
    _tagController.dispose();
    _captionFocus.dispose();
    _videoController?.dispose();
    super.dispose();
  }

  void _addTag() {
    final tag = _tagController.text.trim();
    if (tag.isNotEmpty && !_tags.contains(tag)) {
      HapticFeedback.lightImpact();
      setState(() => _tags.add(tag));
      _tagController.clear();
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    unawaited(HapticFeedback.mediumImpact());

    try {
      final store = ref.read(knowledgeStoreProvider);
      final caption = _captionController.text.trim();
      final isVideo = widget.captureType == CaptureType.video;

      final name = caption.isEmpty
          ? '${isVideo ? 'Video' : 'Photo'} ${DateTime.now().toIso8601String()}'
          : caption;

      await store.createMediaObject(
        name: name,
        type: isVideo ? MediaType.video : MediaType.image,
        contentUrl: widget.filePath,
        encodingFormat: isVideo ? 'video/mp4' : 'image/jpeg',
      );

      if (mounted) {
        unawaited(HapticFeedback.heavyImpact());
        widget.onSaved();
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const bottomPadding = 0.0;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Media preview — fills the screen.
          _buildMediaPreview(),

          // Top bar — discard and save.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.fromLTRB(
                8,
                MediaQuery.of(context).viewPadding.top + 8,
                8,
                12,
              ),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black54, Colors.transparent],
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Discard.
                  _TopBarButton(
                    icon: Icons.close_rounded,
                    label: 'Discard',
                    onTap: widget.onDiscard,
                  ),
                  // Video play/pause toggle.
                  if (widget.captureType == CaptureType.video &&
                      _videoController != null)
                    _TopBarButton(
                      icon: _videoController!.value.isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      onTap: () {
                        final vc = _videoController!;
                        if (vc.value.isPlaying) {
                          vc.pause();
                        } else {
                          vc.play();
                        }
                        setState(() {});
                      },
                    ),
                ],
              ),
            ),
          ),

          // Bottom controls — caption, tags, save.
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.fromLTRB(
                KabukTheme.spacingMd,
                KabukTheme.spacingLg,
                KabukTheme.spacingMd,
                bottomPadding + KabukTheme.spacingMd,
              ),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Colors.black87, Colors.black54, Colors.transparent],
                  stops: [0.0, 0.7, 1.0],
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Caption input.
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withAlpha(20),
                      borderRadius: BorderRadius.circular(KabukTheme.radiusMd),
                      border: Border.all(
                        color: Colors.white.withAlpha(30),
                        width: 0.5,
                      ),
                    ),
                    child: TextField(
                      controller: _captionController,
                      focusNode: _captionFocus,
                      style: const TextStyle(color: Colors.white, fontSize: 15),
                      maxLines: 3,
                      minLines: 1,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        hintText: 'Add a caption...',
                        hintStyle: TextStyle(
                          color: Colors.white.withAlpha(120),
                          fontSize: 15,
                        ),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        filled: false,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: KabukTheme.spacingMd,
                          vertical: KabukTheme.spacingSm + 4,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: KabukTheme.spacingSm),

                  // Tags row.
                  if (_showTags) ...[
                    _buildTagInput(),
                    if (_tags.isNotEmpty) ...[
                      const SizedBox(height: KabukTheme.spacingXs),
                      _buildTagChips(),
                    ],
                    const SizedBox(height: KabukTheme.spacingSm),
                  ],

                  // Action row.
                  Row(
                    children: [
                      // Tags toggle.
                      GestureDetector(
                        onTap: () => setState(() => _showTags = !_showTags),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withAlpha(15),
                            borderRadius: BorderRadius.circular(
                              KabukTheme.radiusMd,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _showTags
                                    ? Icons.expand_more_rounded
                                    : Icons.tag_rounded,
                                color: Colors.white70,
                                size: 18,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                _tags.isEmpty
                                    ? 'Tags'
                                    : '${_tags.length} tag${_tags.length == 1 ? '' : 's'}',
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const Spacer(),
                      // Save to device button.
                      _SaveButton(saving: _saving, onTap: _save),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMediaPreview() {
    if (widget.captureType == CaptureType.photo) {
      return Image.file(
        File(widget.filePath),
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
      );
    }

    final controller = _videoController;
    if (controller == null || !controller.value.isInitialized) {
      return Container(
        color: Colors.black,
        child: const Center(
          child: CircularProgressIndicator(
            color: KabukTheme.accentGreen,
            strokeWidth: 2,
          ),
        ),
      );
    }

    return FittedBox(
      fit: BoxFit.cover,
      child: SizedBox(
        width: controller.value.size.width,
        height: controller.value.size.height,
        child: VideoPlayer(controller),
      ),
    );
  }

  Widget _buildTagInput() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(15),
        borderRadius: BorderRadius.circular(KabukTheme.radiusMd),
        border: Border.all(color: Colors.white.withAlpha(20), width: 0.5),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _tagController,
              onSubmitted: (_) => _addTag(),
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Add tags...',
                hintStyle: TextStyle(
                  color: Colors.white.withAlpha(80),
                  fontSize: 13,
                ),
                prefixIcon: Icon(
                  Icons.tag_rounded,
                  size: 16,
                  color: Colors.white.withAlpha(80),
                ),
                prefixIconConstraints: const BoxConstraints(minWidth: 36),
                isDense: true,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  vertical: KabukTheme.spacingSm,
                ),
              ),
            ),
          ),
          GestureDetector(
            onTap: _addTag,
            child: const Padding(
              padding: EdgeInsets.all(8),
              child: Icon(Icons.add_rounded, size: 18, color: Colors.white70),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTagChips() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Wrap(
        spacing: KabukTheme.spacingXs,
        runSpacing: KabukTheme.spacingXs,
        children: _tags
            .map(
              (tag) => Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: KabukTheme.accentGreen.withAlpha(30),
                  borderRadius: BorderRadius.circular(KabukTheme.radiusSm),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      tag,
                      style: const TextStyle(
                        fontSize: 12,
                        color: KabukTheme.accentGreen,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 4),
                    GestureDetector(
                      onTap: () => setState(() => _tags.remove(tag)),
                      child: Icon(
                        Icons.close_rounded,
                        size: 14,
                        color: KabukTheme.accentGreen.withAlpha(180),
                      ),
                    ),
                  ],
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sub-widgets
// ---------------------------------------------------------------------------

/// A translucent top bar button with icon and optional label.
class _TopBarButton extends StatelessWidget {
  const _TopBarButton({required this.icon, required this.onTap, this.label});

  final IconData icon;
  final VoidCallback onTap;
  final String? label;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black38,
          borderRadius: BorderRadius.circular(KabukTheme.radiusMd),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 22),
            if (label != null) ...[
              const SizedBox(width: 6),
              Text(
                label!,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Animated save button.
class _SaveButton extends StatelessWidget {
  const _SaveButton({required this.saving, required this.onTap});

  final bool saving;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: saving ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        decoration: BoxDecoration(
          color: saving
              ? KabukTheme.accentGreen.withAlpha(150)
              : KabukTheme.accentGreen,
          borderRadius: BorderRadius.circular(KabukTheme.radiusXl),
          boxShadow: saving
              ? null
              : [
                  BoxShadow(
                    color: KabukTheme.accentGreen.withAlpha(80),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
        ),
        child: saving
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.save_alt_rounded, color: Colors.white, size: 18),
                  SizedBox(width: 8),
                  Text(
                    'Save',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
