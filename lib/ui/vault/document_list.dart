/// Document list view — displays notes in a searchable, sortable list.
///
/// Shows all user documents as cards with title, preview snippet, date,
/// and optional collection badge. Supports search, sort, and filtering
/// by collection. Tapping a document opens it in the [DocumentEditor].
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kabuk/config/providers.dart';
import 'package:kabuk/knowledge/types/note.dart';
import 'package:kabuk/ui/vault/vault_view.dart';
import 'package:kabuk/ui/vault/document_editor.dart' show DocumentEditor;
import 'package:kabuk/ui/shared/kabuk_keyboard.dart';
import 'package:kabuk/ui/theme.dart';

// ---------------------------------------------------------------------------
// Sort options
// ---------------------------------------------------------------------------

/// How documents are sorted.
enum _SortMode {
  /// Most recently modified first.
  modified,

  /// Most recently created first.
  created,

  /// Alphabetical by title.
  alphabetical,
}

// ---------------------------------------------------------------------------
// Document list view
// ---------------------------------------------------------------------------

/// Scrollable list of the user's documents.
///
/// Integrates with [notesListProvider] for reactive data and
/// [activeDocumentProvider] to open a document when tapped.
class DocumentListView extends ConsumerStatefulWidget {
  /// Creates a [DocumentListView].
  const DocumentListView({
    super.key,
    required this.onRefresh,
    required this.onNewDocument,
  });

  /// Called when the list should be refreshed after an external action.
  final VoidCallback onRefresh;

  /// Called when the user wants to create a new document.
  final VoidCallback onNewDocument;

  @override
  ConsumerState<DocumentListView> createState() => _DocumentListViewState();
}

class _DocumentListViewState extends ConsumerState<DocumentListView> {
  final _searchController = TextEditingController();
  _SortMode _sortMode = _SortMode.modified;
  bool _searchActive = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<NoteData> _sortAndFilter(List<NoteData> notes) {
    var result = List<NoteData>.of(notes);

    // Filter by search query.
    final query = _searchController.text.trim().toLowerCase();
    if (query.isNotEmpty) {
      result = result.where((n) {
        final title = (n.name ?? '').toLowerCase();
        final body = (n.text ?? '').toLowerCase();
        return title.contains(query) || body.contains(query);
      }).toList();
    }

    // Filter by active collection.
    final activeCollection = ref.read(activeCollectionProvider);
    if (activeCollection != null) {
      result = result
          .where((n) => n.parentCollection == activeCollection)
          .toList();
    }

    // Sort.
    switch (_sortMode) {
      case _SortMode.modified:
        result.sort(
          (a, b) => (b.dateModified ?? DateTime(0)).compareTo(
            a.dateModified ?? DateTime(0),
          ),
        );
      case _SortMode.created:
        result.sort(
          (a, b) => (b.dateCreated ?? DateTime(0)).compareTo(
            a.dateCreated ?? DateTime(0),
          ),
        );
      case _SortMode.alphabetical:
        result.sort(
          (a, b) => (a.name ?? '').toLowerCase().compareTo(
            (b.name ?? '').toLowerCase(),
          ),
        );
    }

    // Pinned documents always appear first.
    result.sort((a, b) {
      if (a.pinned && !b.pinned) return -1;
      if (!a.pinned && b.pinned) return 1;
      return 0;
    });

    return result;
  }

  @override
  Widget build(BuildContext context) {
    final notesAsync = ref.watch(notesListProvider);

    return Column(
      children: [
        // Search + sort toolbar.
        _Toolbar(
          searchController: _searchController,
          searchActive: _searchActive,
          sortMode: _sortMode,
          onSearchToggle: () => setState(() => _searchActive = !_searchActive),
          onSearchChanged: (_) => setState(() {}),
          onSortChanged: (mode) => setState(() => _sortMode = mode),
        ),

        // Document list.
        Expanded(
          child: notesAsync.when(
            data: (notes) {
              final sorted = _sortAndFilter(notes);
              if (sorted.isEmpty) {
                return _EmptyState(
                  hasFilter: _searchController.text.isNotEmpty,
                  onNewDocument: widget.onNewDocument,
                );
              }
              return RefreshIndicator(
                color: KabukTheme.accentGreen,
                backgroundColor: KabukTheme.surface,
                onRefresh: () async {
                  ref.invalidate(notesListProvider);
                  await ref.read(notesListProvider.future);
                  widget.onRefresh();
                },
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(
                    KabukTheme.spacingMd,
                    KabukTheme.spacingXs,
                    KabukTheme.spacingMd,
                    120,
                  ),
                  itemCount: sorted.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: KabukTheme.spacingSm),
                  itemBuilder: (context, index) {
                    final note = sorted[index];
                    return _DocumentCard(
                      note: note,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        ref.read(activeDocumentProvider.notifier).state =
                            note.uri;
                      },
                      onDelete: () => _deleteDocument(note.uri),
                    );
                  },
                ),
              );
            },
            loading: () => const Center(
              child: CircularProgressIndicator(color: KabukTheme.accentGreen),
            ),
            error: (error, _) => Center(
              child: Padding(
                padding: const EdgeInsets.all(KabukTheme.spacingLg),
                child: Text(
                  'Failed to load documents: $error',
                  style: const TextStyle(color: KabukTheme.error),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _deleteDocument(String uri) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: KabukTheme.surfaceElevated,
        title: const Text(
          'Delete document?',
          style: TextStyle(color: KabukTheme.textPrimary),
        ),
        content: const Text(
          'This action cannot be undone.',
          style: TextStyle(color: KabukTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: KabukTheme.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(
              'Delete',
              style: TextStyle(color: KabukTheme.error),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      final store = ref.read(knowledgeStoreProvider);
      await store.deleteNote(uri);
      ref.invalidate(notesListProvider);
      widget.onRefresh();
    }
  }
}

// ---------------------------------------------------------------------------
// Toolbar — search + sort
// ---------------------------------------------------------------------------

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.searchController,
    required this.searchActive,
    required this.sortMode,
    required this.onSearchToggle,
    required this.onSearchChanged,
    required this.onSortChanged,
  });

  final TextEditingController searchController;
  final bool searchActive;
  final _SortMode sortMode;
  final VoidCallback onSearchToggle;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<_SortMode> onSortChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: KabukTheme.spacingMd,
        vertical: KabukTheme.spacingXs,
      ),
      child: Row(
        children: [
          // Search bar (expandable).
          Expanded(
            child: AnimatedCrossFade(
              firstChild: GestureDetector(
                onTap: onSearchToggle,
                child: Container(
                  height: 36,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: KabukTheme.surface,
                    borderRadius: BorderRadius.circular(KabukTheme.radiusSm),
                  ),
                  child: const Row(
                    children: [
                      Icon(
                        Icons.search_rounded,
                        size: 18,
                        color: KabukTheme.textTertiary,
                      ),
                      SizedBox(width: 8),
                      Text(
                        'Search documents...',
                        style: TextStyle(
                          color: KabukTheme.textTertiary,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              secondChild: SizedBox(
                height: 36,
                child: KabukKeyboard(
                  simple: true,
                  controller: searchController,
                  onChanged: onSearchChanged,
                  autofocus: true,
                  hintText: 'Search...',
                ),
              ),
              crossFadeState: searchActive
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 200),
            ),
          ),

          const SizedBox(width: KabukTheme.spacingSm),

          // Sort toggle.
          PopupMenuButton<_SortMode>(
            onSelected: onSortChanged,
            color: KabukTheme.surfaceElevated,
            icon: const Icon(
              Icons.sort_rounded,
              size: 20,
              color: KabukTheme.textSecondary,
            ),
            itemBuilder: (_) => [
              _sortItem(_SortMode.modified, 'Last modified', sortMode),
              _sortItem(_SortMode.created, 'Date created', sortMode),
              _sortItem(_SortMode.alphabetical, 'Alphabetical', sortMode),
            ],
          ),
        ],
      ),
    );
  }

  PopupMenuItem<_SortMode> _sortItem(
    _SortMode mode,
    String label,
    _SortMode current,
  ) {
    final isSelected = mode == current;
    return PopupMenuItem(
      value: mode,
      child: Row(
        children: [
          if (isSelected)
            const Icon(
              Icons.check_rounded,
              size: 16,
              color: KabukTheme.accentGreen,
            )
          else
            const SizedBox(width: 16),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: isSelected
                  ? KabukTheme.accentGreen
                  : KabukTheme.textPrimary,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Document card
// ---------------------------------------------------------------------------

class _DocumentCard extends StatelessWidget {
  const _DocumentCard({
    required this.note,
    required this.onTap,
    required this.onDelete,
  });

  final NoteData note;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final title = (note.name ?? '').isEmpty ? 'Untitled' : note.name!;
    final preview = note.text ?? '';
    final date = note.dateModified ?? note.dateCreated;
    final dateStr = date != null ? _formatDate(date) : '';
    final icon = note.icon;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: KabukTheme.surface,
          borderRadius: BorderRadius.circular(KabukTheme.radiusMd),
          border: Border.all(color: KabukTheme.divider, width: 0.5),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(KabukTheme.radiusMd),
          child: Container(
            padding: const EdgeInsets.all(KabukTheme.spacingMd),
            decoration: const BoxDecoration(
              border: Border(
                left: BorderSide(
                  color: KabukTheme.accentGreen,
                  width: 4,
                ),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title row.
                Row(
                  children: [
                    if (icon != null && icon.isNotEmpty) ...[
                      Text(icon, style: const TextStyle(fontSize: 18)),
                      const SizedBox(width: 8),
                    ],
                    if (note.pinned)
                      const Padding(
                        padding: EdgeInsets.only(right: 6),
                        child: Icon(
                          Icons.push_pin_rounded,
                          size: 14,
                          color: KabukTheme.warmAccent,
                        ),
                      ),
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          color: KabukTheme.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    // Context menu.
                    PopupMenuButton<String>(
                      onSelected: (action) {
                        if (action == 'delete') onDelete();
                      },
                      color: KabukTheme.surfaceElevated,
                      icon: const Icon(
                        Icons.more_horiz_rounded,
                        size: 18,
                        color: KabukTheme.textTertiary,
                      ),
                      itemBuilder: (_) => [
                        const PopupMenuItem(
                          value: 'delete',
                          child: Row(
                            children: [
                              Icon(
                                Icons.delete_outline_rounded,
                                size: 16,
                                color: KabukTheme.error,
                              ),
                              SizedBox(width: 8),
                              Text(
                                'Delete',
                                style: TextStyle(
                                  color: KabukTheme.error,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),

                // Preview snippet.
                if (preview.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      preview,
                      style: const TextStyle(
                        color: KabukTheme.textSecondary,
                        fontSize: 13,
                        height: 1.4,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),

                // Date + tags.
                if (dateStr.isNotEmpty || note.tags.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(
                      children: [
                        if (dateStr.isNotEmpty)
                          Text(
                            dateStr,
                            style: TextStyle(
                              color: KabukTheme.textTertiary.withAlpha(180),
                              fontSize: 11,
                            ),
                          ),
                        if (note.tags.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Expanded(
                            child: Row(
                              children: [
                                ...note.tags
                                    .take(3)
                                    .map((tag) => _TagChip(tag: tag)),
                                if (note.tags.length > 3)
                                  Padding(
                                    padding: const EdgeInsets.only(left: 4),
                                    child: Text(
                                      '+${note.tags.length - 3}',
                                      style: TextStyle(
                                        color: KabukTheme.textTertiary
                                            .withAlpha(150),
                                        fontSize: 11,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${date.day}/${date.month}/${date.year}';
  }
}

// ---------------------------------------------------------------------------
// Tag chip
// ---------------------------------------------------------------------------

class _TagChip extends StatelessWidget {
  const _TagChip({required this.tag});

  final String tag;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 4),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: KabukTheme.accentGreen.withAlpha(20),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '#$tag',
        style: const TextStyle(
          color: KabukTheme.accentGreen,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Empty state
// ---------------------------------------------------------------------------

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.hasFilter, required this.onNewDocument});

  final bool hasFilter;
  final VoidCallback onNewDocument;

  @override
  Widget build(BuildContext context) {
    if (hasFilter) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(KabukTheme.spacingXl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.search_off_rounded,
                size: 48,
                color: KabukTheme.textTertiary,
              ),
              SizedBox(height: KabukTheme.spacingMd),
              Text(
                'No matching documents',
                style: TextStyle(
                  color: KabukTheme.textSecondary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(height: KabukTheme.spacingSm),
              Text(
                'Try a different search query',
                style: TextStyle(color: KabukTheme.textTertiary, fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(KabukTheme.spacingXl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.note_add_rounded,
              size: 64,
              color: KabukTheme.textSecondary.withAlpha(128),
            ),
            const SizedBox(height: KabukTheme.spacingMd),
            const Text(
              'Start capturing your thoughts',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: KabukTheme.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: KabukTheme.spacingSm),
            Text(
              'Notes, ideas, and reminders — all in one place',
              style: TextStyle(
                color: KabukTheme.textSecondary.withAlpha(180),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: KabukTheme.spacingLg),
            FilledButton.icon(
              onPressed: onNewDocument,
              icon: const Icon(Icons.add_rounded),
              label: const Text('New Note'),
              style: FilledButton.styleFrom(
                backgroundColor: KabukTheme.accentGreen,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
