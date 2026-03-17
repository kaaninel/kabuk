/// Vault view — Private vault for personal knowledge and media.
///
/// The Vault is a full-featured workspace for creating, organizing,
/// and browsing personal content. It combines a document editor (with
/// block-based editing), a media gallery, and collection-based organization.
///
/// Three main tabs:
/// - **Documents**: List of notes/documents, organized by collections.
/// - **Media**: Unified gallery for photos, videos, and audio.
/// - **Collections**: Folder tree for organizing everything.
///
/// Quick-create actions let the user start a new document, capture a
/// photo/video, or record audio without leaving the vault.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kabuk/config/providers.dart';
import 'package:kabuk/knowledge/types/collection.dart';
import 'package:kabuk/knowledge/types/media.dart';
import 'package:kabuk/knowledge/types/note.dart';
import 'package:kabuk/ui/create/audio_capture.dart';
import 'package:kabuk/ui/create/camera_viewfinder.dart';
import 'package:kabuk/ui/create/capture_preview.dart';
import 'package:kabuk/ui/create/collection_manager.dart';
import 'package:kabuk/ui/create/document_editor.dart';
import 'package:kabuk/ui/create/document_list.dart';
import 'package:kabuk/ui/create/media_gallery.dart';
import 'package:kabuk/ui/shared/identity_quick_switcher.dart';
import 'package:kabuk/ui/theme.dart';

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------

/// The currently selected vault tab.
final workspaceTabProvider = StateProvider<int>((ref) => 0);

/// The document currently being edited (null = list view).
final activeDocumentProvider = StateProvider<String?>((ref) => null);

/// The active collection filter (null = all documents).
final activeCollectionProvider = StateProvider<String?>((ref) => null);

/// Provider for listing all notes (reactive).
final notesListProvider = FutureProvider<List<NoteData>>((ref) async {
  final store = ref.watch(knowledgeStoreProvider);
  return store.listNotes(limit: 100);
});

/// Provider for listing all media (reactive).
final mediaListProvider = FutureProvider<List<MediaData>>((ref) async {
  final store = ref.watch(knowledgeStoreProvider);
  return store.listMedia(limit: 100);
});

/// Provider for listing root collections.
final collectionsListProvider = FutureProvider<List<CollectionData>>((
  ref,
) async {
  final store = ref.watch(knowledgeStoreProvider);
  return store.listRootCollections(limit: 50);
});

// ---------------------------------------------------------------------------
// Vault view
// ---------------------------------------------------------------------------

/// The main vault view — private storage for personal knowledge and media.
///
/// Contains three tabs (Documents, Media, Collections) and supports
/// inline overlays for camera and audio capture.
class CreateView extends ConsumerStatefulWidget {
  /// Creates a [CreateView].
  const CreateView({super.key});

  @override
  ConsumerState<CreateView> createState() => _CreateViewState();
}

class _CreateViewState extends ConsumerState<CreateView> {
  bool _showOverlay = false;
  Widget? _overlayWidget;

  void _showCameraOverlay() {
    setState(() {
      _showOverlay = true;
      _overlayWidget = _CameraFlow(
        onSaved: () {
          _dismissOverlay();
          _showSavedFeedback();
          _refreshData();
        },
        onClose: _dismissOverlay,
      );
    });
  }

  void _showAudioOverlay() {
    setState(() {
      _showOverlay = true;
      _overlayWidget = AudioCapture(
        onSaved: () {
          _dismissOverlay();
          _showSavedFeedback();
          _refreshData();
        },
        onClose: _dismissOverlay,
      );
    });
  }

  void _dismissOverlay() {
    setState(() {
      _showOverlay = false;
      _overlayWidget = null;
    });
  }

  void _refreshData() {
    ref.invalidate(notesListProvider);
    ref.invalidate(mediaListProvider);
    ref.invalidate(collectionsListProvider);
  }

  void _showSavedFeedback() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
            SizedBox(width: 8),
            Text(
              'Saved to your vault',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        ),
        behavior: SnackBarBehavior.floating,
        backgroundColor: KabukTheme.accentGreen,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(KabukTheme.radiusMd),
        ),
        margin: const EdgeInsets.all(KabukTheme.spacingMd),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _createNewDocument() async {
    unawaited(HapticFeedback.mediumImpact());
    try {
      final store = ref.read(knowledgeStoreProvider);
      final collection = ref.read(activeCollectionProvider);
      final uri = await store.createNote(
        title: '',
        parentCollection: collection,
      );
      if (!mounted) return;
      ref.read(activeDocumentProvider.notifier).state = uri;
      _refreshData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not create document: $e'),
          backgroundColor: Colors.red.shade800,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeDoc = ref.watch(activeDocumentProvider);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: KabukTheme.background,
        body: Stack(
          fit: StackFit.expand,
          children: [
            // Main content — document editor or workspace shell.
            if (activeDoc != null)
              DocumentEditor(
                documentUri: activeDoc,
                onBack: () {
                  ref.read(activeDocumentProvider.notifier).state = null;
                  _refreshData();
                },
              )
            else
              _WorkspaceShell(
                onNewDocument: _createNewDocument,
                onShowCamera: _showCameraOverlay,
                onShowAudio: _showAudioOverlay,
                onRefresh: _refreshData,
              ),

            // Overlay for camera/audio capture.
            if (_showOverlay && _overlayWidget != null)
              Positioned.fill(child: _overlayWidget!),

            // Identity quick-switcher (hidden during overlays).
            if (!_showOverlay)
              Positioned(
                top: MediaQuery.of(context).padding.top + 8,
                right: 12,
                child: const IdentityQuickSwitcher(radius: 15),
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Workspace shell — tabbed Documents / Media / Collections
// ---------------------------------------------------------------------------

class _WorkspaceShell extends ConsumerWidget {
  const _WorkspaceShell({
    required this.onNewDocument,
    required this.onShowCamera,
    required this.onShowAudio,
    required this.onRefresh,
  });

  final VoidCallback onNewDocument;
  final VoidCallback onShowCamera;
  final VoidCallback onShowAudio;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentTab = ref.watch(workspaceTabProvider);
    final topPadding = MediaQuery.of(context).padding.top;

    return Column(
      children: [
        // Header.
        Padding(
          padding: EdgeInsets.fromLTRB(
            KabukTheme.spacingMd,
            topPadding + 8,
            80,
            0,
          ),
          child: Row(
            children: [
              const Text(
                'Vault',
                style: TextStyle(
                  color: KabukTheme.textPrimary,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
              ),
              const Spacer(),
              _QuickActionButton(
                icon: Icons.add_rounded,
                tooltip: 'New document',
                onTap: onNewDocument,
              ),
            ],
          ),
        ),
        const SizedBox(height: KabukTheme.spacingSm),

        // Tab bar.
        _WorkspaceTabBar(currentTab: currentTab),

        // Quick capture buttons (camera + audio) below tab bar.
        Padding(
          padding: const EdgeInsets.fromLTRB(
            KabukTheme.spacingMd,
            KabukTheme.spacingXs,
            KabukTheme.spacingMd,
            0,
          ),
          child: Row(
            children: [
              _QuickCaptureButton(
                icon: Icons.camera_alt_outlined,
                label: 'Camera',
                onTap: onShowCamera,
              ),
              const SizedBox(width: KabukTheme.spacingSm),
              _QuickCaptureButton(
                icon: Icons.mic_outlined,
                label: 'Audio',
                onTap: onShowAudio,
              ),
            ],
          ),
        ),

        const SizedBox(height: KabukTheme.spacingXs),

        // Tab content.
        Expanded(
          child: IndexedStack(
            index: currentTab,
            children: [
              DocumentListView(onRefresh: onRefresh, onNewDocument: onNewDocument),
              MediaGalleryView(
                onCapturePhoto: onShowCamera,
                onRecordAudio: onShowAudio,
                onRefresh: onRefresh,
              ),
              CollectionManagerView(onRefresh: onRefresh),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Tab bar
// ---------------------------------------------------------------------------

class _WorkspaceTabBar extends ConsumerWidget {
  const _WorkspaceTabBar({required this.currentTab});

  final int currentTab;

  static const _tabs = [
    (icon: Icons.description_outlined, label: 'Documents'),
    (icon: Icons.perm_media_outlined, label: 'Media'),
    (icon: Icons.folder_outlined, label: 'Collections'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: KabukTheme.spacingMd),
      child: Row(
        children: _tabs.asMap().entries.map((entry) {
          final index = entry.key;
          final tab = entry.value;
          final isActive = index == currentTab;

          return Expanded(
            child: Semantics(
              label: tab.label,
              button: true,
              selected: isActive,
              excludeSemantics: true,
              child: GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                ref.read(workspaceTabProvider.notifier).state = index;
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: isActive
                          ? KabukTheme.accentGreen
                          : Colors.transparent,
                      width: 2,
                    ),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      tab.icon,
                      size: 18,
                      color: isActive
                          ? KabukTheme.accentGreen
                          : KabukTheme.textTertiary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      tab.label,
                      style: TextStyle(
                        color: isActive
                            ? KabukTheme.accentGreen
                            : KabukTheme.textTertiary,
                        fontSize: 13,
                        fontWeight: isActive
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Quick action button
// ---------------------------------------------------------------------------

class _QuickActionButton extends StatelessWidget {
  const _QuickActionButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: tooltip,
      button: true,
      excludeSemantics: true,
      child: Tooltip(
        message: tooltip,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            HapticFeedback.lightImpact();
            onTap();
          },
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: KabukTheme.accentGreen.withAlpha(20),
              borderRadius: BorderRadius.circular(KabukTheme.radiusSm),
            ),
            child: Icon(icon, size: 20, color: KabukTheme.accentGreen),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Quick capture button — small icon+label button for camera/audio capture
// ---------------------------------------------------------------------------

/// A compact quick-capture button shown below the Vault tab bar.
class _QuickCaptureButton extends StatelessWidget {
  const _QuickCaptureButton({
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
      child: Tooltip(
        message: label,
        child: Material(
          color: KabukTheme.accentGreen.withAlpha(38),
          borderRadius: BorderRadius.circular(KabukTheme.radiusSm),
          child: InkWell(
            borderRadius: BorderRadius.circular(KabukTheme.radiusSm),
            onTap: () {
              HapticFeedback.lightImpact();
              onTap();
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 16, color: KabukTheme.accentGreen),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: const TextStyle(
                      color: KabukTheme.accentGreen,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Camera flow — full-screen camera overlay with capture + preview
// ---------------------------------------------------------------------------

class _CameraFlow extends ConsumerStatefulWidget {
  const _CameraFlow({required this.onSaved, required this.onClose});

  final VoidCallback onSaved;
  final VoidCallback onClose;

  @override
  ConsumerState<_CameraFlow> createState() => _CameraFlowState();
}

class _CameraFlowState extends ConsumerState<_CameraFlow> {
  String? _capturedPath;
  CaptureType? _captureType;
  bool _isVideoMode = false;

  @override
  Widget build(BuildContext context) {
    // Show preview if we have a capture.
    if (_capturedPath != null && _captureType != null) {
      return CapturePreview(
        filePath: _capturedPath!,
        captureType: _captureType!,
        onDiscard: () => setState(() {
          _capturedPath = null;
          _captureType = null;
        }),
        onSaved: widget.onSaved,
      );
    }

    final topPadding = MediaQuery.of(context).viewPadding.top;

    return Container(
      color: KabukTheme.background,
      child: Column(
        children: [
          // Top bar with close button and mode toggle.
          Padding(
            padding: EdgeInsets.fromLTRB(8, topPadding + 8, 8, 0),
            child: Row(
              children: [
                IconButton(
                  onPressed: widget.onClose,
                  icon: const Icon(Icons.close_rounded),
                  color: KabukTheme.textSecondary,
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () => setState(() => _isVideoMode = !_isVideoMode),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: KabukTheme.surfaceVariant,
                      borderRadius: BorderRadius.circular(KabukTheme.radiusXl),
                    ),
                    child: Text(
                      _isVideoMode ? 'VIDEO' : 'PHOTO',
                      style: const TextStyle(
                        color: KabukTheme.textPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                ),
                const Spacer(),
                const SizedBox(width: 48),
              ],
            ),
          ),
          // Camera viewfinder.
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: CameraViewfinder(
                isVideoMode: _isVideoMode,
                onPhotoCaptured: (path) => setState(() {
                  _capturedPath = path;
                  _captureType = CaptureType.photo;
                }),
                onVideoCaptured: (path) => setState(() {
                  _capturedPath = path;
                  _captureType = CaptureType.video;
                }),
              ),
            ),
          ),
          const SizedBox(height: 80),
        ],
      ),
    );
  }
}
