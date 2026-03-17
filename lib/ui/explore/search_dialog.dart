/// Enhanced search dialog — local + Nostr search with save capability.
///
/// Provides a two-tab search experience: local article search and
/// Nostr relay search (NIP-50 text / hashtag). Searches can be saved
/// for later as SavedSearch entries.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kabuk/config/providers.dart';
import 'package:kabuk/knowledge/types/article.dart';
import 'package:kabuk/knowledge/types/saved_search.dart';
import 'package:kabuk/services/nostr.dart';
import 'package:kabuk/services/nostr_utils.dart';
import 'package:kabuk/ui/explore/article_detail_page.dart';
import 'package:kabuk/ui/explore/discovery_providers.dart';
import 'package:kabuk/ui/shared/feed_image.dart';
import 'package:kabuk/ui/theme.dart';

/// Enhanced search dialog with local + Nostr search and save capability.
class SearchDialog extends ConsumerStatefulWidget {
  /// Creates a [SearchDialog].
  const SearchDialog({super.key});

  @override
  ConsumerState<SearchDialog> createState() => _SearchDialogState();
}

class _SearchDialogState extends ConsumerState<SearchDialog> {
  final _controller = TextEditingController();
  List<ArticleData> _localResults = [];
  List<NostrEvent> _nostrResults = [];
  bool _searching = false;
  bool _nostrSearching = false;
  String _activeQuery = '';

  /// 0 = local, 1 = nostr
  int _searchTab = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search(String query) async {
    _activeQuery = query.trim();
    if (_activeQuery.isEmpty) {
      setState(() {
        _localResults = [];
        _nostrResults = [];
      });
      return;
    }
    setState(() => _searching = true);

    final store = ref.read(knowledgeStoreProvider);
    final all = await store.listArticles(limit: 500);
    final q = _activeQuery.toLowerCase();
    final local = all.where((a) {
      return (a.name?.toLowerCase().contains(q) ?? false) ||
          (a.description?.toLowerCase().contains(q) ?? false) ||
          (a.author?.toLowerCase().contains(q) ?? false) ||
          a.tags.any((t) => t.toLowerCase().contains(q));
    }).toList();

    setState(() {
      _localResults = local;
      _searching = false;
    });

    unawaited(_searchNostr(_activeQuery));
  }

  Future<void> _searchNostr(String query) async {
    setState(() => _nostrSearching = true);
    try {
      final nostr = ref.read(nostrServiceProvider);

      final isHashtag = query.startsWith('#') || !query.contains(' ');
      final cleanQuery = query.replaceFirst('#', '').trim();

      final stream = (isHashtag && cleanQuery.isNotEmpty)
          ? nostr.searchByHashtag([cleanQuery.toLowerCase()], limit: 20)
          : nostr.searchContent(query, limit: 20);

      final events = await collectNostrEvents(
        stream,
        where: (e) => e.kind == NostrKind.textNote,
        timeout: const Duration(seconds: 6),
      );

      final seen = <String>{};
      events.removeWhere((e) => !seen.add(e.id));
      events.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      if (mounted) {
        setState(() {
          _nostrResults = events;
          _nostrSearching = false;
        });
      }
    } on Object {
      if (mounted) setState(() => _nostrSearching = false);
    }
  }

  Future<void> _saveSearch() async {
    if (_activeQuery.isEmpty) return;
    final source = _searchTab == 0 ? 'local' : 'nostr_hashtag';
    final store = ref.read(knowledgeStoreProvider);
    await store.createSavedSearch(
      name: _activeQuery,
      queryText: _activeQuery,
      source: source,
    );
    ref.invalidate(savedSearchesProvider);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Saved search "$_activeQuery"'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: KabukTheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.75,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      autofocus: true,
                      onChanged: _search,
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        hintText: 'Search articles & Nostr...',
                        prefixIcon: const Icon(Icons.search_rounded),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        fillColor: KabukTheme.surfaceVariant,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                    ),
                  ),
                  if (_activeQuery.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.bookmark_add_outlined, size: 22),
                      tooltip: 'Save this search',
                      onPressed: _saveSearch,
                      style: IconButton.styleFrom(
                        backgroundColor: KabukTheme.accentGreen.withAlpha(20),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (_activeQuery.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                child: Row(
                  children: [
                    _tabChip(
                      label: 'Local (${_localResults.length})',
                      icon: Icons.storage_rounded,
                      isSelected: _searchTab == 0,
                      onTap: () => setState(() => _searchTab = 0),
                    ),
                    const SizedBox(width: 8),
                    _tabChip(
                      label: _nostrSearching
                          ? 'Nostr...'
                          : 'Nostr (${_nostrResults.length})',
                      icon: Icons.bolt_rounded,
                      isSelected: _searchTab == 1,
                      onTap: () => setState(() => _searchTab = 1),
                      color: KabukTheme.purpleAccent,
                    ),
                  ],
                ),
              ),
            if (_searching && _searchTab == 0)
              const Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              )
            else if (_searchTab == 0)
              _buildLocalResults()
            else
              _buildNostrResults(),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _tabChip({
    required String label,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
    Color? color,
  }) {
    final c = color ?? KabukTheme.accentGreen;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? c.withAlpha(30) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? c.withAlpha(80) : KabukTheme.divider,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: isSelected ? c : KabukTheme.textTertiary,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                color: isSelected ? c : KabukTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLocalResults() {
    if (_localResults.isEmpty && _activeQuery.isNotEmpty) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'No local results found',
          style: TextStyle(color: KabukTheme.textSecondary),
        ),
      );
    }
    return Flexible(
      child: ListView.builder(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        itemCount: _localResults.length,
        itemBuilder: (context, index) {
          final article = _localResults[index];
          return ListTile(
            dense: true,
            leading: article.image != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: SizedBox(
                      width: 44,
                      height: 44,
                      child: FeedImage(
                        imageUrl: article.image!,
                        width: 44,
                        height: 44,
                      ),
                    ),
                  )
                : Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: KabukTheme.surfaceVariant,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(
                      Icons.article_outlined,
                      size: 20,
                      color: KabukTheme.textTertiary,
                    ),
                  ),
            title: Text(
              article.name ?? 'Untitled',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14),
            ),
            subtitle: article.author != null
                ? Text(
                    article.author!,
                    style: const TextStyle(
                      fontSize: 12,
                      color: KabukTheme.textTertiary,
                    ),
                  )
                : null,
            onTap: () {
              Navigator.of(context).pop();
              pushArticleDetail(
                context,
                articles: _localResults,
                initialIndex: index,
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildNostrResults() {
    if (_nostrSearching) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text(
              'Searching Nostr relays...',
              style: TextStyle(color: KabukTheme.textSecondary, fontSize: 13),
            ),
          ],
        ),
      );
    }
    if (_nostrResults.isEmpty && _activeQuery.isNotEmpty) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'No Nostr results found.\nNot all relays support NIP-50 search.',
          textAlign: TextAlign.center,
          style: TextStyle(color: KabukTheme.textSecondary),
        ),
      );
    }
    return Flexible(
      child: ListView.builder(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        itemCount: _nostrResults.length,
        itemBuilder: (context, index) {
          final event = _nostrResults[index];
          final date = DateTime.fromMillisecondsSinceEpoch(
            event.createdAt * 1000,
          );
          final author = event.pubkey.substring(0, 8);
          final preview = event.content.length > 200
              ? '${event.content.substring(0, 200)}...'
              : event.content;
          return ListTile(
            dense: true,
            leading: CircleAvatar(
              radius: 18,
              backgroundColor: KabukTheme.purpleAccent.withAlpha(40),
              child: const Icon(
                Icons.bolt_rounded,
                size: 16,
                color: KabukTheme.purpleAccent,
              ),
            ),
            title: Text(
              preview,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13),
            ),
            subtitle: Text(
              '$author... \u2022 ${_formatDate(date)}',
              style: const TextStyle(
                fontSize: 11,
                color: KabukTheme.textTertiary,
              ),
            ),
          );
        },
      ),
    );
  }

  static String _formatDate(DateTime date) {
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${date.month}/${date.day}/${date.year}';
  }
}
