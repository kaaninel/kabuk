/// Apps view — Personal app launcher with pinned bookmarks, saved AI views,
/// and built-in tools.
///
/// Users pin webapp bookmarks, save AI-generated RFW views from chat,
/// and (in the future) install apps from a marketplace. Built-in tools
/// like Notes, Calendar, and Contacts are accessible but not the focus.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kabuk/config/providers.dart';
import 'package:kabuk/knowledge/triple.dart';
import 'package:kabuk/knowledge/types/bookmark.dart';
import 'package:kabuk/knowledge/types/event.dart';
import 'package:kabuk/knowledge/types/note.dart';
import 'package:kabuk/knowledge/types/person.dart';
import 'package:kabuk/knowledge/types/saved_view.dart';
import 'package:kabuk/ui/settings/settings_view.dart';
import 'package:kabuk/ui/shared/identity_quick_switcher.dart';
import 'package:kabuk/ui/shared/kabuk_markdown.dart';
import 'package:kabuk/ui/theme.dart';
import 'package:url_launcher/url_launcher.dart';

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------

/// Bookmarks list — re-fetched on invalidation.
final _bookmarksProvider = FutureProvider<List<BookmarkData>>((ref) {
  final store = ref.watch(knowledgeStoreProvider);
  return store.listBookmarks();
});

/// Saved AI views list.
final _savedViewsProvider = FutureProvider<List<SavedViewData>>((ref) {
  final store = ref.watch(knowledgeStoreProvider);
  return store.listSavedViews();
});

/// Recent notes — last 5 notes from the knowledge store.
final _recentNotesProvider = FutureProvider.autoDispose<List<NoteData>>((ref) {
  final store = ref.watch(knowledgeStoreProvider);
  return store.listNotes(limit: 5);
});

// ---------------------------------------------------------------------------
// Main view
// ---------------------------------------------------------------------------

/// Apps view — pinned bookmarks, saved views, tools, and marketplace.
class AppsView extends ConsumerWidget {
  /// Creates an [AppsView].
  const AppsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookmarks = ref.watch(_bookmarksProvider);
    final savedViews = ref.watch(_savedViewsProvider);
    final recentNotes = ref.watch(_recentNotesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Apps'),
        actions: [const IdentityQuickSwitcher()],
      ),
      body: CustomScrollView(
        slivers: [
          // ─── Pinned Bookmarks ─────────────────────────────────────
          SliverToBoxAdapter(
            child: _SectionHeader(
              icon: Icons.push_pin_rounded,
              title: 'Pinned',
              color: KabukTheme.warmAccent,
              trailing: IconButton(
                icon: const Icon(Icons.add_rounded, size: 20),
                tooltip: 'Add bookmark',
                color: KabukTheme.textSecondary,
                onPressed: () => _showAddBookmarkSheet(context, ref),
              ),
            ),
          ),
          bookmarks.when(
            data: (items) => items.isEmpty
                ? const SliverToBoxAdapter(child: _EmptyPinnedHint())
                : SliverPadding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: KabukTheme.spacingMd,
                    ),
                    sliver: SliverGrid.count(
                      crossAxisCount: 4,
                      mainAxisSpacing: KabukTheme.spacingSm,
                      crossAxisSpacing: KabukTheme.spacingSm,
                      childAspectRatio: 0.85,
                      children: [
                        for (final bm in items)
                          _BookmarkTile(
                            bookmark: bm,
                            onLongPress: () =>
                                _confirmDeleteBookmark(context, ref, bm),
                          ),
                      ],
                    ),
                  ),
            loading: () => const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(KabukTheme.spacingLg),
                child: Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ),
            ),
            error: (_, _) => const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(KabukTheme.spacingMd),
                child: Text(
                  'Could not load bookmarks.',
                  style: TextStyle(color: KabukTheme.textSecondary),
                ),
              ),
            ),
          ),

          // ─── Saved AI Views (shown only when views exist) ─────────
          savedViews.when(
            data: (items) => items.isEmpty
                ? const SliverToBoxAdapter(child: SizedBox.shrink())
                : SliverMainAxisGroup(
                    slivers: [
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.only(
                            top: KabukTheme.spacingMd,
                          ),
                          child: _SectionHeader(
                            icon: Icons.auto_awesome_rounded,
                            title: 'Saved Views',
                            color: KabukTheme.purpleAccent,
                          ),
                        ),
                      ),
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: KabukTheme.spacingMd,
                        ),
                        sliver: SliverList.separated(
                          itemCount: items.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: KabukTheme.spacingSm),
                          itemBuilder: (_, index) => _SavedViewCard(
                            view: items[index],
                            onDelete: () => _confirmDeleteSavedView(
                              context,
                              ref,
                              items[index],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
            loading: () => const SliverToBoxAdapter(child: SizedBox.shrink()),
            error: (_, _) =>
                const SliverToBoxAdapter(child: SizedBox.shrink()),
          ),

          // ─── Recent Notes ─────────────────────────────────────────
          // Shows the last 5 notes created via the agent or Create tab.
          recentNotes.when(
            data: (notes) => notes.isEmpty
                ? const SliverToBoxAdapter(child: SizedBox.shrink())
                : SliverMainAxisGroup(
                    slivers: [
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.only(
                            top: KabukTheme.spacingMd,
                          ),
                          child: _SectionHeader(
                            icon: Icons.sticky_note_2_rounded,
                            title: 'Recent Notes',
                            color: KabukTheme.warmAccent,
                            trailing: TextButton(
                              onPressed: () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => const _NotesAppView(),
                                ),
                              ),
                              child: const Text('See all'),
                            ),
                          ),
                        ),
                      ),
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: KabukTheme.spacingMd,
                        ),
                        sliver: SliverList.separated(
                          itemCount: notes.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: KabukTheme.spacingSm),
                          itemBuilder: (_, index) =>
                              _NoteListTile(note: notes[index]),
                        ),
                      ),
                    ],
                  ),
            loading: () => const SliverToBoxAdapter(child: SizedBox.shrink()),
            error: (_, _) =>
                const SliverToBoxAdapter(child: SizedBox.shrink()),
          ),

          // ─── Built-in Tools ───────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: KabukTheme.spacingLg),
              child: _SectionHeader(
                icon: Icons.handyman_rounded,
                title: 'Tools',
                color: KabukTheme.accentGreen,
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 84,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                  horizontal: KabukTheme.spacingMd,
                ),
                children: [
                  _ToolChip(
                    icon: Icons.sticky_note_2_rounded,
                    label: 'Notes',
                    color: KabukTheme.warmAccent,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const _NotesAppView(),
                      ),
                    ),
                  ),
                  _ToolChip(
                    icon: Icons.event_rounded,
                    label: 'Calendar',
                    color: KabukTheme.purpleAccent,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const _CalendarAppView(),
                      ),
                    ),
                  ),
                  _ToolChip(
                    icon: Icons.people_rounded,
                    label: 'Contacts',
                    color: KabukTheme.blueAccent,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const _ContactsAppView(),
                      ),
                    ),
                  ),
                  _ToolChip(
                    icon: Icons.search_rounded,
                    label: 'Search',
                    color: const Color(0xFF78909C),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const _SearchAppView(),
                      ),
                    ),
                  ),
                  _ToolChip(
                    icon: Icons.settings_rounded,
                    label: 'Settings',
                    color: KabukTheme.textSecondary,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const SettingsView(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ─── Developer (hidden by default) ─────────────────────────
          const SliverToBoxAdapter(child: _DevSection()),

          // ─── Marketplace ──────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: KabukTheme.spacingLg),
              child: _SectionHeader(
                icon: Icons.storefront_rounded,
                title: 'Marketplace',
                color: const Color(0xFF78909C),
              ),
            ),
          ),
          const SliverToBoxAdapter(child: _MarketplaceBanner()),

          // Bottom padding.
          const SliverPadding(padding: EdgeInsets.only(bottom: 100)),
        ],
      ),
    );
  }

  // ── Add bookmark bottom sheet ──────────────────────────────────────────

  void _showAddBookmarkSheet(BuildContext context, WidgetRef ref) {
    final nameCtrl = TextEditingController();
    final urlCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    var selectedColor = 'FF6D00';
    var selectedIcon = 'language';

    const colorOptions = <String, Color>{
      'FF6D00': Color(0xFFFF6D00),
      'FF4500': Color(0xFFFF4500),
      'E91E63': Color(0xFFE91E63),
      'AB47BC': Color(0xFFAB47BC),
      '42A5F5': Color(0xFF42A5F5),
      '26A69A': Color(0xFF26A69A),
      '66BB6A': Color(0xFF66BB6A),
      '78909C': Color(0xFF78909C),
    };

    const iconOptions = <String, IconData>{
      'language': Icons.language_rounded,
      'forum': Icons.forum_rounded,
      'article': Icons.article_rounded,
      'video_library': Icons.video_library_rounded,
      'code': Icons.code_rounded,
      'shopping_cart': Icons.shopping_cart_rounded,
      'music_note': Icons.music_note_rounded,
      'image': Icons.image_rounded,
      'sports_esports': Icons.sports_esports_rounded,
      'rss_feed': Icons.rss_feed_rounded,
      'work': Icons.work_rounded,
      'school': Icons.school_rounded,
    };

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: KabukTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          return Padding(
            padding: EdgeInsets.only(
              left: KabukTheme.spacingLg,
              right: KabukTheme.spacingLg,
              top: KabukTheme.spacingLg,
              bottom:
                  MediaQuery.of(ctx).viewInsets.bottom + KabukTheme.spacingLg,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.add_link_rounded,
                      color: KabukTheme.warmAccent,
                      size: 22,
                    ),
                    const SizedBox(width: KabukTheme.spacingSm),
                    Text(
                      'Pin a Bookmark',
                      style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: KabukTheme.spacingLg),
                TextField(
                  controller: nameCtrl,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Name',
                    hintText: 'e.g. Reddit',
                  ),
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: KabukTheme.spacingSm),
                TextField(
                  controller: urlCtrl,
                  decoration: const InputDecoration(
                    labelText: 'URL',
                    hintText: 'https://...',
                  ),
                  keyboardType: TextInputType.url,
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: KabukTheme.spacingSm),
                TextField(
                  controller: descCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Description (optional)',
                  ),
                  textInputAction: TextInputAction.done,
                ),
                const SizedBox(height: KabukTheme.spacingMd),
                // Icon picker.
                Text(
                  'Icon',
                  style: TextStyle(
                    color: KabukTheme.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: KabukTheme.spacingXs),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: iconOptions.entries.map((e) {
                    final isSelected = selectedIcon == e.key;
                    return Semantics(
                      label: e.key.replaceAll('_', ' '),
                      button: true,
                      selected: isSelected,
                      excludeSemantics: true,
                      child: GestureDetector(
                      onTap: () => setSheetState(() => selectedIcon = e.key),
                      child: Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: isSelected
                              ? KabukTheme.accentGreen.withAlpha(25)
                              : KabukTheme.surfaceVariant,
                          borderRadius: BorderRadius.circular(8),
                          border: isSelected
                              ? Border.all(
                                  color: KabukTheme.accentGreen,
                                  width: 1.5,
                                )
                              : null,
                        ),
                        child: Icon(
                          e.value,
                          size: 18,
                          color: isSelected
                              ? KabukTheme.accentGreen
                              : KabukTheme.textSecondary,
                        ),
                      ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: KabukTheme.spacingMd),
                // Color picker.
                Text(
                  'Color',
                  style: TextStyle(
                    color: KabukTheme.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: KabukTheme.spacingXs),
                Wrap(
                  spacing: 10,
                  children: colorOptions.entries.map((e) {
                    final isSelected = selectedColor == e.key;
                    return Semantics(
                      label: 'Color ${e.key}',
                      button: true,
                      selected: isSelected,
                      excludeSemantics: true,
                      child: GestureDetector(
                        onTap: () => setSheetState(() => selectedColor = e.key),
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: e.value,
                            shape: BoxShape.circle,
                            border: isSelected
                                ? Border.all(color: Colors.white, width: 2.5)
                                : null,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: KabukTheme.spacingLg),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () async {
                      final name = nameCtrl.text.trim();
                      final url = urlCtrl.text.trim();
                      if (name.isEmpty || url.isEmpty) return;
                      if (Uri.tryParse(url)?.hasScheme != true) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(
                            content: Text('Please enter a valid URL'),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                        return;
                      }
                      final store = ref.read(knowledgeStoreProvider);
                      await store.createBookmark(
                        name: name,
                        url: url,
                        description: descCtrl.text.trim().isNotEmpty
                            ? descCtrl.text.trim()
                            : null,
                        iconName: selectedIcon,
                        color: selectedColor,
                      );
                      ref.invalidate(_bookmarksProvider);
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
                    icon: const Icon(Icons.push_pin_rounded, size: 18),
                    label: const Text('Pin'),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    ).then((_) {
      nameCtrl.dispose();
      urlCtrl.dispose();
      descCtrl.dispose();
    });
  }

  void _confirmDeleteBookmark(
    BuildContext context,
    WidgetRef ref,
    BookmarkData bm,
  ) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: KabukTheme.surface,
        title: const Text('Remove Bookmark?'),
        content: Text('Unpin "${bm.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              final store = ref.read(knowledgeStoreProvider);
              await store.deleteBookmark(bm.uri);
              ref.invalidate(_bookmarksProvider);
              if (context.mounted) Navigator.pop(context);
            },
            style: TextButton.styleFrom(foregroundColor: KabukTheme.error),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteSavedView(
    BuildContext context,
    WidgetRef ref,
    SavedViewData view,
  ) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: KabukTheme.surface,
        title: const Text('Delete Saved View?'),
        content: Text('Remove "${view.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              final store = ref.read(knowledgeStoreProvider);
              await store.deleteSavedView(view.uri);
              ref.invalidate(_savedViewsProvider);
              if (context.mounted) Navigator.pop(context);
            },
            style: TextButton.styleFrom(foregroundColor: KabukTheme.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Section header
// ---------------------------------------------------------------------------

/// Section header with icon, title, and optional trailing widget.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.icon,
    required this.title,
    required this.color,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final Color color;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: KabukTheme.spacingMd,
        vertical: KabukTheme.spacingXs,
      ),
      child: Row(
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: color.withAlpha(20),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Icon(icon, size: 14, color: color),
          ),
          const SizedBox(width: KabukTheme.spacingSm),
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const Spacer(),
          ?trailing,
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Bookmark tile (compact, 4-column grid)
// ---------------------------------------------------------------------------

/// Icon name → IconData mapping for stored bookmarks.
IconData _resolveIcon(String? name) {
  const map = <String, IconData>{
    'language': Icons.language_rounded,
    'forum': Icons.forum_rounded,
    'article': Icons.article_rounded,
    'video_library': Icons.video_library_rounded,
    'code': Icons.code_rounded,
    'shopping_cart': Icons.shopping_cart_rounded,
    'music_note': Icons.music_note_rounded,
    'image': Icons.image_rounded,
    'sports_esports': Icons.sports_esports_rounded,
    'rss_feed': Icons.rss_feed_rounded,
    'work': Icons.work_rounded,
    'school': Icons.school_rounded,
  };
  return map[name] ?? Icons.language_rounded;
}

/// Parses a stored hex color string to a [Color].
Color _resolveColor(String? hex) {
  if (hex == null || hex.length < 6) return const Color(0xFF42A5F5);
  return Color(int.parse('FF$hex', radix: 16));
}

/// Compact bookmark tile for the 4-column grid.
class _BookmarkTile extends StatelessWidget {
  const _BookmarkTile({required this.bookmark, this.onLongPress});

  final BookmarkData bookmark;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final color = _resolveColor(bookmark.color);
    final icon = _resolveIcon(bookmark.iconName);

    return GestureDetector(
      excludeFromSemantics: true,
      onLongPress: onLongPress,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(KabukTheme.radiusMd),
          onTap: () async {
            final url = bookmark.url;
            if (url == null) return;
            final uri = Uri.parse(url);
            if (await canLaunchUrl(uri)) {
              await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
            }
          },
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: color.withAlpha(20),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, size: 26, color: color),
              ),
              const SizedBox(height: 6),
              Text(
                bookmark.name ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: KabukTheme.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Empty state hints
// ---------------------------------------------------------------------------

/// Shown when no bookmarks are pinned.
class _EmptyPinnedHint extends StatelessWidget {
  const _EmptyPinnedHint();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: KabukTheme.spacingLg,
        vertical: KabukTheme.spacingMd,
      ),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(KabukTheme.spacingMd),
        decoration: BoxDecoration(
          color: KabukTheme.warmAccent.withAlpha(8),
          borderRadius: BorderRadius.circular(KabukTheme.radiusMd),
          border: Border.all(color: KabukTheme.warmAccent.withAlpha(25)),
        ),
        child: Row(
          children: [
            Icon(
              Icons.push_pin_outlined,
              size: 20,
              color: KabukTheme.warmAccent.withAlpha(160),
            ),
            const SizedBox(width: KabukTheme.spacingSm),
            Expanded(
              child: Text(
                'Pin your favorite web apps and sites here for quick access.',
                style: TextStyle(
                  color: KabukTheme.warmAccent.withAlpha(180),
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Saved view card
// ---------------------------------------------------------------------------

/// Card for a saved AI-generated RFW view.
class _SavedViewCard extends StatelessWidget {
  const _SavedViewCard({required this.view, this.onDelete});

  final SavedViewData view;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: KabukTheme.cardColor,
        borderRadius: BorderRadius.circular(KabukTheme.radiusMd),
        border: Border.all(color: KabukTheme.divider, width: 0.5),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(KabukTheme.radiusMd),
          onTap: () {
            if (view.rfwSource == null) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('This view has no template source.'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
              return;
            }
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => _SavedViewPage(view: view),
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(KabukTheme.spacingMd),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: KabukTheme.purpleAccent.withAlpha(18),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.auto_awesome_rounded,
                    size: 20,
                    color: KabukTheme.purpleAccent,
                  ),
                ),
                const SizedBox(width: KabukTheme.spacingSm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        view.name ?? 'Untitled View',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      if (view.description != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          view.description!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: KabukTheme.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (view.dateCreated != null)
                  Text(
                    _formatAge(view.dateCreated!),
                    style: const TextStyle(
                      color: KabukTheme.textTertiary,
                      fontSize: 11,
                    ),
                  ),
                if (onDelete != null) ...[
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(Icons.close, size: 16),
                    color: KabukTheme.textTertiary,
                    onPressed: onDelete,
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 28,
                      minHeight: 28,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatAge(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 30) return '${diff.inDays}d ago';
    return '${dt.month}/${dt.day}';
  }
}

// ---------------------------------------------------------------------------
// Tool chip (horizontal scroll row)
// ---------------------------------------------------------------------------

/// Compact chip for built-in tools.
class _ToolChip extends StatelessWidget {
  const _ToolChip({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: KabukTheme.spacingSm),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(KabukTheme.radiusMd),
          onTap: onTap,
          child: Container(
            width: 72,
            padding: const EdgeInsets.symmetric(vertical: KabukTheme.spacingSm),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: color.withAlpha(18),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, size: 22, color: color),
                ),
                const SizedBox(height: 6),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11,
                    color: KabukTheme.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Developer section (collapsed)
// ---------------------------------------------------------------------------

/// Collapsed developer tools section.
class _DevSection extends ConsumerWidget {
  const _DevSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final registry = ref.watch(rfwRegistryProvider);
    final libraries = registry.libraries.toList();
    final runtime = ref.watch(agentRuntimeProvider);
    final agents = runtime.registeredAgents;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        KabukTheme.spacingMd,
        KabukTheme.spacingLg,
        KabukTheme.spacingMd,
        0,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: KabukTheme.cardColor,
          borderRadius: BorderRadius.circular(KabukTheme.radiusMd),
          border: Border.all(color: KabukTheme.divider, width: 0.5),
        ),
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(
              horizontal: KabukTheme.spacingMd,
            ),
            leading: Icon(
              Icons.code_rounded,
              size: 18,
              color: KabukTheme.blueAccent.withAlpha(180),
            ),
            title: Text(
              'Developer  ·  ${libraries.length} ${libraries.length == 1 ? 'library' : 'libraries'}  ·  '
              '${agents.length} ${agents.length == 1 ? 'agent' : 'agents'}',
              style: const TextStyle(
                fontSize: 13,
                color: KabukTheme.textSecondary,
              ),
            ),
            children: [
              const Divider(height: 1, color: KabukTheme.divider),
              if (libraries.isNotEmpty) ...[
                for (final lib in libraries)
                  ListTile(
                    dense: true,
                    leading: Icon(
                      Icons.extension_rounded,
                      size: 16,
                      color: KabukTheme.accentGreen,
                    ),
                    title: Text(lib.name, style: const TextStyle(fontSize: 13)),
                    subtitle: Text(
                      '${lib.widgets.length} ${lib.widgets.length == 1 ? 'widget' : 'widgets'}  ·  v${lib.version}',
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
              ],
              if (agents.isNotEmpty) ...[
                const Divider(height: 1, color: KabukTheme.divider),
                for (final agent in agents)
                  ListTile(
                    dense: true,
                    leading: Icon(
                      Icons.smart_toy_rounded,
                      size: 16,
                      color: KabukTheme.purpleAccent,
                    ),
                    title: Text(
                      agent.name,
                      style: const TextStyle(fontSize: 13),
                    ),
                    subtitle: Text(
                      '${agent.toolCount} ${agent.toolCount == 1 ? 'tool' : 'tools'}  ·  ${agent.description}',
                      style: const TextStyle(fontSize: 11),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Marketplace banner
// ---------------------------------------------------------------------------

/// Placeholder banner for the future marketplace.
class _MarketplaceBanner extends StatelessWidget {
  const _MarketplaceBanner();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: KabukTheme.spacingMd),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(KabukTheme.spacingLg),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              KabukTheme.accentGreen.withAlpha(10),
              KabukTheme.blueAccent.withAlpha(10),
            ],
          ),
          borderRadius: BorderRadius.circular(KabukTheme.radiusLg),
          border: Border.all(color: KabukTheme.divider, width: 0.5),
        ),
        child: Column(
          children: [
            Icon(
              Icons.storefront_rounded,
              size: 36,
              color: KabukTheme.textTertiary.withAlpha(120),
            ),
            const SizedBox(height: KabukTheme.spacingSm),
            Text(
              'App Marketplace',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(color: KabukTheme.textSecondary),
            ),
            const SizedBox(height: 4),
            const Text(
              'Install apps built for Kabuk. Coming soon.',
              textAlign: TextAlign.center,
              style: TextStyle(color: KabukTheme.textTertiary, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Mini app views (Notes, Calendar, Contacts, Files, Search)
// ---------------------------------------------------------------------------

/// Notes list app view.
class _NotesAppView extends ConsumerWidget {
  const _NotesAppView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(knowledgeStoreProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Notes')),
      body: FutureBuilder<List<NoteData>>(
        future: store.listNotes(limit: 100),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final notes = snapshot.data!;
          if (notes.isEmpty) {
            return const _EmptyAppState(
              icon: Icons.sticky_note_2_rounded,
              label: 'No notes yet',
              hint: 'Create notes in the Create tab or via Chat',
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(KabukTheme.spacingMd),
            itemCount: notes.length,
            separatorBuilder: (_, _) =>
                const SizedBox(height: KabukTheme.spacingSm),
            itemBuilder: (_, index) {
              final note = notes[index];
              return _NoteListTile(note: note);
            },
          );
        },
      ),
    );
  }
}

/// Single note list tile.
class _NoteListTile extends StatelessWidget {
  const _NoteListTile({required this.note});

  final NoteData note;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: KabukTheme.cardColor,
        borderRadius: BorderRadius.circular(KabukTheme.radiusMd),
        border: Border.all(color: KabukTheme.divider, width: 0.5),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: KabukTheme.spacingMd,
          vertical: KabukTheme.spacingSm,
        ),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => _NoteDetailView(note: note),
            ),
          );
        },
        title: Text(
          note.name ?? 'Untitled',
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        ),
        subtitle: note.text != null
            ? Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  note.text!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: KabukTheme.textSecondary,
                    fontSize: 13,
                  ),
                ),
              )
            : null,
        trailing: note.dateCreated != null
            ? Text(
                _formatDate(note.dateCreated!),
                style: const TextStyle(
                  color: KabukTheme.textTertiary,
                  fontSize: 11,
                ),
              )
            : null,
      ),
    );
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 30) return '${diff.inDays}d';
    return '${dt.month}/${dt.day}';
  }
}

/// Full note detail view with markdown rendering.
class _NoteDetailView extends StatelessWidget {
  const _NoteDetailView({required this.note});

  final NoteData note;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(note.name ?? 'Untitled')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(KabukTheme.spacingLg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (note.dateCreated != null) ...[
              Text(
                _formatFullDate(note.dateCreated!),
                style: const TextStyle(
                  color: KabukTheme.textTertiary,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: KabukTheme.spacingMd),
            ],
            if (note.text != null)
              KabukMarkdown(data: note.text!)
            else
              const Text(
                'No content.',
                style: TextStyle(
                  color: KabukTheme.textSecondary,
                  fontStyle: FontStyle.italic,
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _formatFullDate(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-'
        '${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
  }
}

/// Calendar app view.
class _CalendarAppView extends ConsumerWidget {
  const _CalendarAppView();

  void _showAddEventDialog(BuildContext context, WidgetRef ref) {
    final nameController = TextEditingController();
    final descController = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: KabukTheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(KabukTheme.radiusMd),
        ),
        title: const Text('Add Event'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Event name',
                hintText: 'What\'s happening?',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: descController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Description',
                hintText: 'Optional',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final name = nameController.text.trim();
              if (name.isEmpty) return;
              final store = ref.read(knowledgeStoreProvider);
              await store.createEvent(
                name: name,
                description: descController.text.trim().isNotEmpty
                    ? descController.text.trim()
                    : null,
                startDate: DateTime.now(),
              );
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(knowledgeStoreProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Calendar')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddEventDialog(context, ref),
        backgroundColor: KabukTheme.purpleAccent,
        child: const Icon(Icons.add_rounded),
      ),
      body: FutureBuilder<List<EventData>>(
        future: store.listEvents(limit: 100),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final events = snapshot.data!;
          if (events.isEmpty) {
            return const _EmptyAppState(
              icon: Icons.event_rounded,
              label: 'No events yet',
              hint: 'Ask the Calendar agent to create events',
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(KabukTheme.spacingMd),
            itemCount: events.length,
            separatorBuilder: (_, _) =>
                const SizedBox(height: KabukTheme.spacingSm),
            itemBuilder: (_, index) {
              final event = events[index];
              return Container(
                padding: const EdgeInsets.all(KabukTheme.spacingMd),
                decoration: BoxDecoration(
                  color: KabukTheme.cardColor,
                  borderRadius: BorderRadius.circular(KabukTheme.radiusMd),
                  border: Border.all(color: KabukTheme.divider, width: 0.5),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      event.name ?? 'Untitled Event',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                    if (event.description != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        event.description!,
                        maxLines: 2,
                        style: const TextStyle(
                          color: KabukTheme.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                    ],
                    if (event.startDate != null) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(
                            Icons.schedule_rounded,
                            size: 14,
                            color: KabukTheme.purpleAccent.withAlpha(180),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            event.startDate.toString(),
                            style: TextStyle(
                              color: KabukTheme.purpleAccent.withAlpha(200),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (event.location != null) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.place_outlined,
                            size: 14,
                            color: KabukTheme.accentGreen.withAlpha(180),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            event.location!,
                            style: TextStyle(
                              color: KabukTheme.accentGreen.withAlpha(200),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// Contacts app view.
class _ContactsAppView extends ConsumerWidget {
  const _ContactsAppView();

  void _showAddContactDialog(BuildContext context, WidgetRef ref) {
    final nameController = TextEditingController();
    final emailController = TextEditingController();
    final phoneController = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: KabukTheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(KabukTheme.radiusMd),
        ),
        title: const Text('Add Contact'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Name',
                hintText: 'Contact name',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Email',
                hintText: 'Optional',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: phoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Phone',
                hintText: 'Optional',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final name = nameController.text.trim();
              if (name.isEmpty) return;
              final store = ref.read(knowledgeStoreProvider);
              await store.createPerson(
                name: name,
                email: emailController.text.trim().isNotEmpty
                    ? emailController.text.trim()
                    : null,
                telephone: phoneController.text.trim().isNotEmpty
                    ? phoneController.text.trim()
                    : null,
              );
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(knowledgeStoreProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Contacts')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddContactDialog(context, ref),
        backgroundColor: KabukTheme.blueAccent,
        child: const Icon(Icons.person_add_rounded),
      ),
      body: FutureBuilder<List<PersonData>>(
        future: store.listPersons(limit: 100),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final people = snapshot.data!;
          if (people.isEmpty) {
            return const _EmptyAppState(
              icon: Icons.people_rounded,
              label: 'No contacts yet',
              hint: 'Ask the Contact agent to create contacts',
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(KabukTheme.spacingMd),
            itemCount: people.length,
            separatorBuilder: (_, _) =>
                const SizedBox(height: KabukTheme.spacingSm),
            itemBuilder: (_, index) {
              final person = people[index];
              return Container(
                padding: const EdgeInsets.all(KabukTheme.spacingMd),
                decoration: BoxDecoration(
                  color: KabukTheme.cardColor,
                  borderRadius: BorderRadius.circular(KabukTheme.radiusMd),
                  border: Border.all(color: KabukTheme.divider, width: 0.5),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 22,
                      backgroundColor: KabukTheme.blueAccent.withAlpha(30),
                      child: Text(
                        (person.name ?? '?').substring(0, 1).toUpperCase(),
                        style: const TextStyle(
                          color: KabukTheme.blueAccent,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: KabukTheme.spacingSm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            person.name ?? 'Unknown',
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                          ),
                          if (person.email != null)
                            Text(
                              person.email!,
                              style: const TextStyle(
                                color: KabukTheme.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                          if (person.telephone != null)
                            Text(
                              person.telephone!,
                              style: const TextStyle(
                                color: KabukTheme.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// Search app view.
class _SearchAppView extends ConsumerStatefulWidget {
  const _SearchAppView();

  @override
  ConsumerState<_SearchAppView> createState() => _SearchAppViewState();
}

class _SearchAppViewState extends ConsumerState<_SearchAppView> {
  final _controller = TextEditingController();
  List<Triple>? _results;
  bool _loading = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search(String query) async {
    if (query.trim().isEmpty) return;
    setState(() => _loading = true);
    try {
      final store = ref.read(knowledgeStoreProvider);
      _results = await store.search(query.trim(), limit: 50);
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Search')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(KabukTheme.spacingMd),
            child: TextField(
              controller: _controller,
              autofocus: true,
              onSubmitted: _search,
              decoration: InputDecoration(
                hintText: 'Search your knowledge...',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _loading
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : null,
              ),
            ),
          ),
          if (_results != null)
            Expanded(
              child: _results!.isEmpty
                  ? const _EmptyAppState(
                      icon: Icons.search_off_rounded,
                      label: 'No results',
                      hint: 'Try a different search term',
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(
                        horizontal: KabukTheme.spacingMd,
                      ),
                      itemCount: _results!.length,
                      separatorBuilder: (_, _) =>
                          const Divider(height: 1, color: KabukTheme.divider),
                      itemBuilder: (_, index) {
                        final triple = _results![index];
                        return ListTile(
                          title: Text(
                            triple.objectValue.toString(),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 14),
                          ),
                          subtitle: Text(
                            triple.subject.split('/').last,
                            style: const TextStyle(
                              fontSize: 11,
                              color: KabukTheme.textTertiary,
                            ),
                          ),
                        );
                      },
                    ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared empty state
// ---------------------------------------------------------------------------

/// Empty state placeholder with icon, label, and hint.
class _EmptyAppState extends StatelessWidget {
  const _EmptyAppState({
    required this.icon,
    required this.label,
    required this.hint,
  });

  final IconData icon;
  final String label;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(KabukTheme.spacingXl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: KabukTheme.accentGreen.withAlpha(15),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                icon,
                size: 32,
                color: KabukTheme.accentGreen.withAlpha(150),
              ),
            ),
            const SizedBox(height: KabukTheme.spacingMd),
            Text(label, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: KabukTheme.spacingXs),
            Text(
              hint,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Saved RFW view rendering
// ---------------------------------------------------------------------------

/// Full-screen page that renders a saved RFW view.
class _SavedViewPage extends ConsumerWidget {
  const _SavedViewPage({required this.view});

  final SavedViewData view;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final runtime = ref.read(rfwRuntimeProvider);
    return Scaffold(
      appBar: AppBar(title: Text(view.name ?? 'Saved View')),
      body: FutureBuilder<Widget>(
        future: runtime.renderRaw(source: view.rfwSource!),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Text(
                'Failed to render view: ${snapshot.error}',
                style: const TextStyle(color: Colors.red),
              ),
            );
          }
          return snapshot.data!;
        },
      ),
    );
  }
}
