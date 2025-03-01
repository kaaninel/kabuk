import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../widgets/editors/markdown_editor.dart';
import '../widgets/editors/metadata_editor.dart';
import '../widgets/editors/asset_manager.dart';
import '../widgets/editors/command_palette.dart';
import '../widgets/editors/markdown_preview.dart';
import '../widgets/editors/media_editor.dart';
import '../widgets/editors/editor_shortcuts.dart';
import '../services/auto_save_service.dart';
import '../services/media_transcoding_service.dart';
import '../services/change_tracker.dart';
import 'package:flutter_dropzone/flutter_dropzone.dart';

class CreateView extends StatefulWidget {
  const CreateView({super.key});

  @override
  State<CreateView> createState() => _CreateViewState();
}

class _CreateViewState extends State<CreateView> {
  bool _isLeftPanelOpen = true;
  bool _isRightPanelOpen = true;
  double _leftPanelWidth = 250;
  double _rightPanelWidth = 300;
  double _previewSplitRatio = 0.5;
  String _contentType = 'text';
  String? _content;
  Map<String, dynamic> _metadata = {};
  bool _isCommandPaletteVisible = false;

  late DropzoneViewController _dropzoneController;
  late AutoSaveService _autoSaveService;
  late MediaTranscodingService _mediaTranscodingService;
  late ChangeTracker _changeTracker;
  bool _isDragging = false;
  String? _mediaUrl;
  Map<String, dynamic>? _mediaConfig;

  List<Command> get _commands => [
        Command(
          id: 'save',
          label: 'Save',
          category: 'File',
          shortcut: '⌘S',
          icon: Icons.save,
          onExecute: _handleSave,
        ),
        Command(
          id: 'toggle_left_panel',
          label: 'Toggle Asset Panel',
          category: 'View',
          shortcut: '⌘\\',
          icon: Icons.vertical_split,
          onExecute: () => setState(() => _isLeftPanelOpen = !_isLeftPanelOpen),
        ),
        Command(
          id: 'toggle_right_panel',
          label: 'Toggle Properties Panel',
          category: 'View',
          shortcut: '⌘]',
          icon: Icons.settings,
          onExecute: () =>
              setState(() => _isRightPanelOpen = !_isRightPanelOpen),
        ),
        Command(
          id: 'toggle_preview',
          label: 'Toggle Preview',
          category: 'View',
          shortcut: '⌘P',
          icon: Icons.preview,
          onExecute: _togglePreview,
        ),
      ];

  @override
  void initState() {
    super.initState();
    _initializeServices();
    _changeTracker = ChangeTracker()..addListener(_handleChanges);
  }

  Future<void> _initializeServices() async {
    _autoSaveService = await AutoSaveService.init();
    _mediaTranscodingService = MediaTranscodingService();
    _loadLastDraft();

    _autoSaveService.startAutoSave('current', _getCurrentContent);
  }

  void _handleChanges() {
    // Update status bar with save state
    setState(() {});
  }

  Future<void> _loadLastDraft() async {
    final draft = _autoSaveService.loadDraft('current');
    if (draft != null) {
      setState(() {
        _content = draft['content'] as String?;
        _metadata = draft['metadata'] as Map<String, dynamic>;
        _contentType = draft['type'] as String;
      });
    }
  }

  Map<String, dynamic> _getCurrentContent() {
    return {
      'content': _content,
      'metadata': _metadata,
      'type': _contentType,
      'mediaConfig': _mediaConfig,
    };
  }

  @override
  void dispose() {
    _autoSaveService.stopAutoSave();
    _changeTracker.dispose();
    super.dispose();
  }

  Future<void> _handleDrop(dynamic event) async {
    setState(() => _isDragging = false);

    final name = event.name as String;
    final mime = await _dropzoneController.getFileMIME(event);
    final bytes = await _dropzoneController.getFileData(event);

    if (mime.startsWith('image/')) {
      final optimizedBytes = await _mediaTranscodingService.optimizeImage(
        bytes,
        maxWidth: 1920,
        maxHeight: 1080,
      );
      // TODO: Handle optimized image data
      _changeTracker.markChanged(ChangeType.media);
    } else if (mime.startsWith('text/')) {
      setState(() {
        _content = String.fromCharCodes(bytes);
        _changeTracker.markChanged(ChangeType.content);
      });
    }
  }

  Future<void> _handleSave() async {
    // Save current content
    await _autoSaveService.saveDraft('current', _getCurrentContent());
    _changeTracker.clearChanges();
  }

  void _togglePreview() {
    setState(() {
      _previewSplitRatio = _previewSplitRatio == 1.0 ? 0.5 : 1.0;
    });
  }

  @override
  Widget build(BuildContext context) {
    return EditorShortcuts(
      onSave: _handleSave,
      onUndo: () {
        // TODO: Implement undo
      },
      onRedo: () {
        // TODO: Implement redo
      },
      onTogglePreview: () {
        setState(() {
          _previewSplitRatio = _previewSplitRatio == 1.0 ? 0.5 : 1.0;
        });
      },
      onToggleLeftPanel: () {
        setState(() => _isLeftPanelOpen = !_isLeftPanelOpen);
      },
      onToggleRightPanel: () {
        //setState(() => _isaRightPanelOpen = !_isRightPanelOpen);
      },
      child: WillPopScope(
        onWillPop: () async {
          if (_changeTracker.hasUnsavedChanges()) {
            final result = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Unsaved Changes'),
                content: const Text(
                    'Do you want to save your changes before leaving?'),
                actions: [
                  TextButton(
                    child: const Text('Discard'),
                    onPressed: () => Navigator.of(context).pop(true),
                  ),
                  TextButton(
                    child: const Text('Cancel'),
                    onPressed: () => Navigator.of(context).pop(false),
                  ),
                  ElevatedButton(
                    child: const Text('Save'),
                    onPressed: () async {
                      await _handleSave();
                      Navigator.of(context).pop(true);
                    },
                  ),
                ],
              ),
            );
            return result ?? false;
          }
          return true;
        },
        child: Scaffold(
          body: Stack(
            children: [
              Column(
                children: [
                  _buildToolbar(),
                  Expanded(
                    child: Row(
                      children: [
                        if (_isLeftPanelOpen) _buildLeftPanel(),
                        Expanded(
                          child: _buildEditor(),
                        ),
                        if (_isRightPanelOpen) _buildRightPanel(),
                      ],
                    ),
                  ),
                  _buildStatusBar(),
                ],
              ),
              CommandPalette(
                commands: _commands,
                onVisibilityChanged: (visible) =>
                    setState(() => _isCommandPaletteVisible = visible),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildToolbar() {
    return Material(
      elevation: 2,
      child: Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            IconButton(
              icon: Icon(
                  _isLeftPanelOpen ? Icons.chevron_left : Icons.chevron_right),
              onPressed: () =>
                  setState(() => _isLeftPanelOpen = !_isLeftPanelOpen),
            ),
            const SizedBox(width: 8),
            DropdownButton<String>(
              value: _contentType,
              items: const [
                DropdownMenuItem(value: 'text', child: Text('Text Document')),
                DropdownMenuItem(value: 'image', child: Text('Image')),
                DropdownMenuItem(value: 'video', child: Text('Video')),
                DropdownMenuItem(value: 'audio', child: Text('Audio')),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() => _contentType = value);
                }
              },
            ),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.save),
              onPressed: _handleSave,
              tooltip: 'Save (⌘S)',
            ),
            IconButton(
              icon: const Icon(Icons.undo),
              onPressed: () {},
              tooltip: 'Undo (⌘Z)',
            ),
            IconButton(
              icon: const Icon(Icons.redo),
              onPressed: () {},
              tooltip: 'Redo (⌘Y)',
            ),
            const SizedBox(width: 16),
            IconButton(
              icon: Icon(
                  _isRightPanelOpen ? Icons.chevron_right : Icons.chevron_left),
              onPressed: () =>
                  setState(() => _isRightPanelOpen = !_isRightPanelOpen),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLeftPanel() {
    return GestureDetector(
      onHorizontalDragUpdate: (details) {
        setState(() {
          _leftPanelWidth = (_leftPanelWidth + details.delta.dx)
              .clamp(200.0, MediaQuery.of(context).size.width * 0.4);
        });
      },
      child: SizedBox(
        width: _leftPanelWidth,
        child: Card(
          margin: EdgeInsets.zero,
          shape: const RoundedRectangleBorder(),
          child: AssetManager(
            onAssetSelected: (asset) {
              // Handle asset selection
            },
          ),
        ),
      ),
    );
  }

  Widget _buildEditor() {
    return Row(
      children: [
        Expanded(
          flex: (_previewSplitRatio * 100).round(),
          child: Card(
            margin: const EdgeInsets.all(8),
            child: _contentType == 'text'
                ? _buildMarkdownEditor()
                : _buildMediaEditor(),
          ),
        ),
        if (_previewSplitRatio < 1.0) ...[
          _buildPreviewSplitter(),
          Expanded(
            flex: ((1 - _previewSplitRatio) * 100).round(),
            child: Card(
              margin: const EdgeInsets.all(8),
              child: _buildPreviewPanel(),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildMarkdownEditor() {
    return Stack(
      children: [
        MarkdownEditor(
          initialContent: _content ?? '',
          showLineNumbers: true,
          onChanged: (content) {
            setState(() {
              _content = content;
              _changeTracker.markChanged(ChangeType.content);
            });
          },
        ),
        if (_isDragging) _buildDropOverlay(),
      ],
    );
  }

  Widget _buildMediaEditor() {
    return Stack(
      children: [
        MediaEditor(
          type: _contentType,
          initialUrl: _mediaUrl,
          initialConfig: _mediaConfig,
          onConfigChanged: (config) {
            setState(() {
              _mediaConfig = config;
              _changeTracker.markChanged(ChangeType.media);
            });
          },
        ),
        if (_isDragging) _buildDropOverlay(),
      ],
    );
  }

  Widget _buildDropOverlay() {
    return DropzoneView(
      onCreated: (controller) => _dropzoneController = controller,
      onDrop: _handleDrop,
      onHover: () => setState(() => _isDragging = true),
      onLeave: () => setState(() => _isDragging = false),
    );
  }

  Widget _buildPreviewSplitter() {
    return GestureDetector(
      onHorizontalDragUpdate: (details) {
        setState(() {
          _previewSplitRatio = (_previewSplitRatio -
                  details.delta.dx / MediaQuery.of(context).size.width)
              .clamp(0.3, 0.7);
        });
      },
      child: Container(
        width: 16,
        margin: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: Colors.grey.shade200,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.drag_indicator, color: Colors.grey.shade600),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewPanel() {
    if (_contentType == 'text') {
      return MarkdownPreview(
        content: _content ?? '',
        fontSize: 14,
        darkMode: Theme.of(context).brightness == Brightness.dark,
      );
    }
    return const Center(
      child: Text('Preview not available for this content type'),
    );
  }

  Widget _buildRightPanel() {
    return GestureDetector(
      onHorizontalDragUpdate: (details) {
        setState(() {
          _rightPanelWidth = (_rightPanelWidth - details.delta.dx)
              .clamp(200.0, MediaQuery.of(context).size.width * 0.4);
        });
      },
      child: SizedBox(
        width: _rightPanelWidth,
        child: Card(
          margin: EdgeInsets.zero,
          shape: const RoundedRectangleBorder(),
          child: MetadataEditor(
            initialMetadata: _metadata,
            onChanged: (metadata) => _metadata = metadata,
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBar() {
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      color: Colors.grey.shade200,
      child: Row(
        children: [
          if (_changeTracker.hasUnsavedChanges())
            const Text('Unsaved changes',
                style: TextStyle(fontStyle: FontStyle.italic)),
          if (!_changeTracker.hasUnsavedChanges())
            Text(
                'Last saved: ${_autoSaveService.getLastSaveTime()?.toString() ?? 'Never'}'),
          const Spacer(),
          if (_contentType == 'text' && _content != null)
            Text('Words: ${_content!.split(RegExp(r'\s+')).length}'),
        ],
      ),
    );
  }
}
