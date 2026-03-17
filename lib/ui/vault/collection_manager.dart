/// Collection manager view — tree-based folder organization.
///
/// Displays collections in a hierarchical list with expand/collapse
/// behavior. Supports creating, renaming, and deleting collections.
/// Tapping a collection filters the document list to that folder.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kabuk/config/providers.dart';
import 'package:kabuk/knowledge/types/collection.dart';
import 'package:kabuk/ui/vault/vault_view.dart';
import 'package:kabuk/ui/theme.dart';

// ---------------------------------------------------------------------------
// Collection manager view
// ---------------------------------------------------------------------------

/// A collection/folder manager widget for organizing content.
///
/// Shows root collections with expandable children. New collections
/// can be created at the root or nested inside existing ones.
class CollectionManagerView extends ConsumerStatefulWidget {
  /// Creates a [CollectionManagerView].
  const CollectionManagerView({super.key, required this.onRefresh});

  /// Called to refresh the collection list.
  final VoidCallback onRefresh;

  @override
  ConsumerState<CollectionManagerView> createState() =>
      _CollectionManagerViewState();
}

class _CollectionManagerViewState extends ConsumerState<CollectionManagerView> {
  final Set<String> _expandedUris = {};

  @override
  Widget build(BuildContext context) {
    final collectionsAsync = ref.watch(collectionsListProvider);

    return Column(
      children: [
        // Toolbar.
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: KabukTheme.spacingMd,
            vertical: KabukTheme.spacingXs,
          ),
          child: Row(
            children: [
              const Text(
                'Collections',
                style: TextStyle(
                  color: KabukTheme.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => _createCollection(null),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: KabukTheme.accentGreen.withAlpha(20),
                    borderRadius: BorderRadius.circular(KabukTheme.radiusSm),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.create_new_folder_outlined,
                        size: 14,
                        color: KabukTheme.accentGreen,
                      ),
                      SizedBox(width: 4),
                      Text(
                        'New folder',
                        style: TextStyle(
                          color: KabukTheme.accentGreen,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),

        // Collection list.
        Expanded(
          child: collectionsAsync.when(
            data: (collections) {
              if (collections.isEmpty) return const _CollectionEmptyState();
              return RefreshIndicator(
                color: KabukTheme.accentGreen,
                backgroundColor: KabukTheme.surface,
                onRefresh: () async {
                  ref.invalidate(collectionsListProvider);
                  widget.onRefresh();
                },
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(
                    KabukTheme.spacingMd,
                    0,
                    KabukTheme.spacingMd,
                    120,
                  ),
                  itemCount: collections.length,
                  itemBuilder: (context, index) {
                    return _CollectionTile(
                      collection: collections[index],
                      depth: 0,
                      isExpanded: _expandedUris.contains(
                        collections[index].uri,
                      ),
                      onToggleExpand: () =>
                          _toggleExpand(collections[index].uri),
                      onTap: () => _selectCollection(collections[index].uri),
                      onCreateChild: () =>
                          _createCollection(collections[index].uri),
                      onRename: () => _renameCollection(collections[index]),
                      onDelete: () => _deleteCollection(collections[index].uri),
                    );
                  },
                ),
              );
            },
            loading: () => const Center(
              child: CircularProgressIndicator(color: KabukTheme.accentGreen),
            ),
            error: (error, _) => Center(
              child: Text(
                'Failed to load collections: $error',
                style: const TextStyle(color: KabukTheme.error),
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _toggleExpand(String uri) {
    setState(() {
      if (_expandedUris.contains(uri)) {
        _expandedUris.remove(uri);
      } else {
        _expandedUris.add(uri);
      }
    });
  }

  void _selectCollection(String uri) {
    HapticFeedback.selectionClick();
    final current = ref.read(activeCollectionProvider);
    // Toggle filter: tapping the same collection clears the filter.
    ref.read(activeCollectionProvider.notifier).state = current == uri
        ? null
        : uri;
    // Switch to documents tab.
    ref.read(workspaceTabProvider.notifier).state = 0;
  }

  Future<void> _createCollection(String? parentUri) async {
    unawaited(HapticFeedback.mediumImpact());
    final name = await _showNameDialog('New Collection', '');
    if (name == null || name.isEmpty || !mounted) return;

    final store = ref.read(knowledgeStoreProvider);
    await store.createCollection(name: name, parentCollection: parentUri);
    ref.invalidate(collectionsListProvider);
    widget.onRefresh();
  }

  Future<void> _renameCollection(CollectionData collection) async {
    final name = await _showNameDialog(
      'Rename Collection',
      collection.name ?? '',
    );
    if (name == null || !mounted) return;

    final store = ref.read(knowledgeStoreProvider);
    await store.updateCollection(collection.uri, name: name);
    ref.invalidate(collectionsListProvider);
    widget.onRefresh();
  }

  Future<void> _deleteCollection(String uri) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: KabukTheme.surfaceElevated,
        title: const Text(
          'Delete collection?',
          style: TextStyle(color: KabukTheme.textPrimary),
        ),
        content: const Text(
          'Documents inside will not be deleted, but will become uncategorized.',
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
      await store.deleteCollection(uri);
      // Clear filter if the deleted collection was active.
      if (ref.read(activeCollectionProvider) == uri) {
        ref.read(activeCollectionProvider.notifier).state = null;
      }
      ref.invalidate(collectionsListProvider);
      widget.onRefresh();
    }
  }

  Future<String?> _showNameDialog(String title, String initialValue) {
    final controller = TextEditingController(text: initialValue);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: KabukTheme.surfaceElevated,
        title: Text(
          title,
          style: const TextStyle(color: KabukTheme.textPrimary),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: KabukTheme.textPrimary),
          decoration: InputDecoration(
            hintText: 'Collection name',
            hintStyle: const TextStyle(color: KabukTheme.textTertiary),
            filled: true,
            fillColor: KabukTheme.surface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(KabukTheme.radiusSm),
              borderSide: BorderSide.none,
            ),
          ),
          onSubmitted: (value) => Navigator.of(ctx).pop(value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text(
              'Cancel',
              style: TextStyle(color: KabukTheme.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text(
              'Save',
              style: TextStyle(color: KabukTheme.accentGreen),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Collection tile
// ---------------------------------------------------------------------------

class _CollectionTile extends StatelessWidget {
  const _CollectionTile({
    required this.collection,
    required this.depth,
    required this.isExpanded,
    required this.onToggleExpand,
    required this.onTap,
    required this.onCreateChild,
    required this.onRename,
    required this.onDelete,
  });

  final CollectionData collection;
  final int depth;
  final bool isExpanded;
  final VoidCallback onToggleExpand;
  final VoidCallback onTap;
  final VoidCallback onCreateChild;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final icon = collection.icon;
    final name = (collection.name ?? '').isEmpty
        ? 'Untitled collection'
        : collection.name!;

    return Padding(
      padding: EdgeInsets.only(left: depth * 16.0),
      child: Column(
        children: [
          GestureDetector(
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: KabukTheme.spacingSm,
                vertical: 10,
              ),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: KabukTheme.divider.withAlpha(60),
                    width: 0.5,
                  ),
                ),
              ),
              child: Row(
                children: [
                  // Expand/collapse icon.
                  GestureDetector(
                    onTap: onToggleExpand,
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: Icon(
                        isExpanded
                            ? Icons.keyboard_arrow_down_rounded
                            : Icons.keyboard_arrow_right_rounded,
                        size: 18,
                        color: KabukTheme.textTertiary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),

                  // Collection icon.
                  if (icon != null && icon.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Text(icon, style: const TextStyle(fontSize: 16)),
                    )
                  else
                    const Padding(
                      padding: EdgeInsets.only(right: 8),
                      child: Icon(
                        Icons.folder_outlined,
                        size: 18,
                        color: KabukTheme.textTertiary,
                      ),
                    ),

                  // Name.
                  Expanded(
                    child: Text(
                      name,
                      style: const TextStyle(
                        color: KabukTheme.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),

                  // Pinned indicator.
                  if (collection.pinned)
                    const Padding(
                      padding: EdgeInsets.only(right: 4),
                      child: Icon(
                        Icons.push_pin_rounded,
                        size: 12,
                        color: KabukTheme.warmAccent,
                      ),
                    ),

                  // Context menu.
                  PopupMenuButton<String>(
                    onSelected: (action) {
                      switch (action) {
                        case 'subfolder':
                          onCreateChild();
                        case 'rename':
                          onRename();
                        case 'delete':
                          onDelete();
                      }
                    },
                    color: KabukTheme.surfaceElevated,
                    icon: const Icon(
                      Icons.more_horiz_rounded,
                      size: 16,
                      color: KabukTheme.textTertiary,
                    ),
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                        value: 'subfolder',
                        child: Row(
                          children: [
                            Icon(
                              Icons.create_new_folder_outlined,
                              size: 14,
                              color: KabukTheme.textPrimary,
                            ),
                            SizedBox(width: 8),
                            Text(
                              'New subfolder',
                              style: TextStyle(
                                color: KabukTheme.textPrimary,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'rename',
                        child: Row(
                          children: [
                            Icon(
                              Icons.edit_outlined,
                              size: 14,
                              color: KabukTheme.textPrimary,
                            ),
                            SizedBox(width: 8),
                            Text(
                              'Rename',
                              style: TextStyle(
                                color: KabukTheme.textPrimary,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(
                              Icons.delete_outline_rounded,
                              size: 14,
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
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Empty state
// ---------------------------------------------------------------------------

class _CollectionEmptyState extends StatelessWidget {
  const _CollectionEmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(KabukTheme.spacingXl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.folder_open_rounded,
              size: 64,
              color: KabukTheme.textSecondary.withAlpha(128),
            ),
            const SizedBox(height: KabukTheme.spacingMd),
            const Text(
              'Organize with collections',
              style: TextStyle(
                color: KabukTheme.textSecondary,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: KabukTheme.spacingSm),
            Text(
              'Group your notes and media into folders\nfor easy access',
              style: TextStyle(
                color: KabukTheme.textSecondary.withAlpha(180),
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
