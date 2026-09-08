/// Unified channel page for displaying any [Channel].
///
/// A full-screen page with a collapsing header, content-type filter tabs,
/// and an infinite-scrolling content grid. Works with both plugin-backed
/// channels (Reddit, YouTube, RSS) and local knowledge store queries.
///
/// This is intended to eventually replace the current `ChannelView` and
/// `WebChannelView` with a single, unified implementation.
library;

import 'dart:developer' as dev;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kabuk/config/providers.dart';
import 'package:kabuk/knowledge/types/article.dart';
import 'package:kabuk/plugins/channel.dart';
import 'package:kabuk/plugins/content_item.dart';
import 'package:kabuk/plugins/plugin.dart';
import 'package:kabuk/plugins/registry.dart';
import 'package:kabuk/services/media_cache.dart';
import 'package:kabuk/ui/theme.dart';
import 'package:kabuk/ui/viewers/content_cards.dart';

// =============================================================================
// Content type filter
// =============================================================================

/// Subset of [ContentType] exposed as user-facing filter tabs.
enum _ContentFilter {
  all('All', Icons.dashboard_rounded),
  videos('Videos', Icons.videocam_rounded),
  images('Images', Icons.image_rounded),
  audio('Audio', Icons.audiotrack_rounded),
  articles('Articles', Icons.article_rounded);

  const _ContentFilter(this.label, this.icon);

  /// Human-readable tab label.
  final String label;

  /// Tab icon.
  final IconData icon;

  /// Returns `true` if [type] passes this filter.
  bool matches(ContentType type) {
    return switch (this) {
      _ContentFilter.all => true,
      _ContentFilter.videos => type == ContentType.video,
      _ContentFilter.images => type == ContentType.image,
      _ContentFilter.audio => type == ContentType.audio,
      _ContentFilter.articles => type == ContentType.article,
    };
  }
}

// =============================================================================
// ChannelPage
// =============================================================================

/// Displays a [Channel] with collapsing header, filter tabs, and content grid.
class ChannelPage extends ConsumerStatefulWidget {
  /// Creates a [ChannelPage] for the given [channel].
  const ChannelPage({required this.channel, super.key});

  /// The channel to display.
  final Channel channel;

  @override
  ConsumerState<ChannelPage> createState() => _ChannelPageState();
}

class _ChannelPageState extends ConsumerState<ChannelPage> {
  List<ContentItem> _items = [];
  _ContentFilter _filter = _ContentFilter.all;
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  String? _error;
  int _currentPage = 0;
  final ScrollController _scrollController = ScrollController();

  static const _pageSize = 20;

  Channel get _channel => widget.channel;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadContent();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Scroll / pagination
  // ---------------------------------------------------------------------------

  void _onScroll() {
    if (_isLoadingMore || !_hasMore) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.position.pixels;
    if (currentScroll >= maxScroll - 400) {
      _loadMore();
    }
  }

  // ---------------------------------------------------------------------------
  // Data loading
  // ---------------------------------------------------------------------------

  Future<void> _loadContent() async {
    setState(() {
      _isLoading = true;
      _error = null;
      _currentPage = 0;
      _hasMore = true;
    });

    try {
      final items = await _fetchPage(0);
      if (!mounted) return;
      setState(() {
        _items = items;
        _isLoading = false;
        _hasMore = items.length >= _pageSize;
      });
    } on Object catch (e, st) {
      dev.log(
        'ChannelPage load failed: $e',
        name: 'ChannelPage',
        error: e,
        stackTrace: st,
      );
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore) return;
    setState(() => _isLoadingMore = true);

    try {
      final nextPage = _currentPage + 1;
      final items = await _fetchPage(nextPage);
      if (!mounted) return;
      _currentPage = nextPage;
      setState(() {
        _items = [..._items, ...items];
        _isLoadingMore = false;
        _hasMore = items.length >= _pageSize;
      });
    } on Object catch (e) {
      dev.log('ChannelPage loadMore failed: $e', name: 'ChannelPage');
      if (!mounted) return;
      setState(() => _isLoadingMore = false);
    }
  }

  /// Fetches a page of content from the plugin or knowledge store.
  Future<List<ContentItem>> _fetchPage(int page) async {
    final pluginId = _channel.sourcePluginId;
    if (pluginId != null && _channel.externalEntityId != null) {
      return _fetchFromPlugin(pluginId, page);
    }
    // No plugin — query the knowledge store for content linked to this
    // channel's entity (by feedSource, tag, or author).
    return _fetchFromStore(page);
  }

  /// Queries the knowledge store for articles belonging to this channel.
  ///
  /// Tries, in order:
  /// 1. articles whose `kabuk:feedSource` matches the channel's entity URI,
  /// 2. articles tagged with the channel identifier (e.g. `r/flutter`,
  ///    `/g/`, `#topic`),
  /// 3. articles authored by the channel (for person channels).
  Future<List<ContentItem>> _fetchFromStore(int page) async {
    final store = ref.read(knowledgeStoreProvider);

    final bySource = await store.listArticles(
      feedSource: _channel.entityUri,
      limit: _pageSize * 4,
    );
    if (bySource.isNotEmpty) {
      return bySource.map(_articleToContentItem).toList();
    }

    final tag = _tagForChannel(_channel);
    if (tag != null) {
      final all = await store.listArticles(limit: 500);
      final tagged = all.where((a) => a.tags.contains(tag)).toList();
      if (tagged.isNotEmpty) {
        return tagged.map(_articleToContentItem).toList();
      }
    }

    if (_channel.entityType == ChannelEntityType.person) {
      final byAuthor = await store.listArticles(
        author: _channel.title,
        limit: _pageSize * 4,
      );
      if (byAuthor.isNotEmpty) {
        return byAuthor.map(_articleToContentItem).toList();
      }
    }

    return const [];
  }

  /// Derives a knowledge-store tag for a channel (e.g. `r/flutter`).
  static String? _tagForChannel(Channel channel) {
    final title = channel.title.trim();
    return switch (channel.entityType) {
      ChannelEntityType.subreddit =>
        title.startsWith('r/') ? title : 'r/$title',
      ChannelEntityType.board => title.startsWith('/') && title.endsWith('/')
          ? title
          : '/$title/',
      ChannelEntityType.topic => title.startsWith('#') ? title : '#$title',
      _ => null,
    };
  }

  /// Converts a stored [ArticleData] into a [ContentItem] for the card grid.
  static ContentItem _articleToContentItem(ArticleData a) => ContentItem(
    sourcePluginId: 'knowledge',
    externalId: a.uri,
    contentType: ContentType.article,
    title: a.name ?? 'Untitled',
    description: a.description,
    url: a.url,
    thumbnailUrl: a.image,
    author: a.author == null
        ? null
        : ContentAuthor(name: a.author),
    publishedAt: a.datePublished,
    tags: a.tags,
  );

  Future<List<ContentItem>> _fetchFromPlugin(String pluginId, int page) async {
    final registry = ref.read(pluginRegistryProvider);
    final plugin = registry.activePlugins
        .where((p) => p.id == pluginId)
        .firstOrNull;

    if (plugin == null) {
      throw StateError('Plugin "$pluginId" is not active');
    }

    if (!plugin.hasCapability(ContentCapability.channel)) {
      throw UnsupportedError(
        'Plugin "$pluginId" does not support channel fetching',
      );
    }

    return plugin.fetchChannel(
      _channel.externalEntityId!,
      page: page,
      perPage: _pageSize,
    );
  }

  // ---------------------------------------------------------------------------
  // Filtered items
  // ---------------------------------------------------------------------------

  List<ContentItem> get _filteredItems {
    if (_filter == _ContentFilter.all) return _items;
    return _items.where((i) => _filter.matches(i.contentType)).toList();
  }

  /// Whether the current filter suggests a 2-column grid layout.
  bool get _useGrid {
    return _filter == _ContentFilter.all ||
        _filter == _ContentFilter.videos ||
        _filter == _ContentFilter.images;
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.kabukBackground,
      body: RefreshIndicator(
        onRefresh: _loadContent,
        color: KabukTheme.accentGreen,
        child: CustomScrollView(
          controller: _scrollController,
          slivers: [
            _buildHeader(context),
            _buildFilterTabs(context),
            _buildBody(context),
            if (_isLoadingMore)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(KabukTheme.spacingLg),
                  child: Center(
                    child: CircularProgressIndicator(
                      color: KabukTheme.accentGreen,
                      strokeWidth: 2,
                    ),
                  ),
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 48)),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Header sliver
  // ---------------------------------------------------------------------------

  Widget _buildHeader(BuildContext context) {
    final hasBanner = _channel.bannerUrl != null;

    return SliverAppBar(
      expandedHeight: hasBanner ? 220 : 140,
      pinned: true,
      backgroundColor: context.kabukSurface,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_rounded),
        onPressed: () => Navigator.of(context).pop(),
      ),
      flexibleSpace: FlexibleSpaceBar(
        background: Stack(
          fit: StackFit.expand,
          children: [
            // Banner image or solid colour.
            if (hasBanner)
              CachedNetworkImage(
                imageUrl: _channel.bannerUrl!,
                cacheManager: KabukCacheManager.instance,
                fit: BoxFit.cover,
                placeholder: (_, _) =>
                    Container(color: context.kabukSurfaceVariant),
                errorWidget: (_, _, _) =>
                    Container(color: context.kabukSurfaceVariant),
              )
            else
              Container(color: context.kabukSurfaceVariant),

            // Gradient scrim for readability.
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    context.kabukSurface.withAlpha(220),
                    context.kabukSurface,
                  ],
                  stops: const [0.0, 0.7, 1.0],
                ),
              ),
            ),

            // Entity info overlay.
            Positioned(
              left: KabukTheme.spacingMd,
              right: KabukTheme.spacingMd,
              bottom: KabukTheme.spacingSm,
              child: _ChannelInfo(channel: _channel),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Filter tabs
  // ---------------------------------------------------------------------------

  Widget _buildFilterTabs(BuildContext context) {
    return SliverPersistentHeader(
      pinned: true,
      delegate: _FilterTabsDelegate(
        selectedFilter: _filter,
        onFilterChanged: (f) => setState(() => _filter = f),
        surface: context.kabukSurface,
        divider: context.kabukDivider,
        textPrimary: context.kabukTextPrimary,
        textSecondary: context.kabukTextSecondary,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Body — loading / error / empty / content
  // ---------------------------------------------------------------------------

  Widget _buildBody(BuildContext context) {
    if (_isLoading) return const _ContentSkeleton();

    if (_error != null && _items.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline_rounded,
                size: 48,
                color: context.kabukTextTertiary,
              ),
              const SizedBox(height: KabukTheme.spacingMd),
              Text(
                'Could not load content',
                style: TextStyle(
                  color: context.kabukTextSecondary,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: KabukTheme.spacingSm),
              TextButton.icon(
                onPressed: _loadContent,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final items = _filteredItems;

    if (items.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.inbox_rounded,
                size: 48,
                color: context.kabukTextTertiary,
              ),
              const SizedBox(height: KabukTheme.spacingMd),
              Text(
                _items.isEmpty
                    ? 'No content yet'
                    : 'No ${_filter.label.toLowerCase()} found',
                style: TextStyle(
                  color: context.kabukTextSecondary,
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_useGrid) {
      return SliverPadding(
        padding: const EdgeInsets.symmetric(
          horizontal: KabukTheme.spacingSm,
          vertical: KabukTheme.spacingSm,
        ),
        sliver: SliverGrid(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: KabukTheme.spacingSm,
            crossAxisSpacing: KabukTheme.spacingSm,
            childAspectRatio: 0.75,
          ),
          delegate: SliverChildBuilderDelegate(
            (context, index) => contentCardFor(items[index]),
            childCount: items.length,
          ),
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.symmetric(
        horizontal: KabukTheme.spacingSm,
        vertical: KabukTheme.spacingSm,
      ),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) => Padding(
            padding: const EdgeInsets.only(bottom: KabukTheme.spacingSm),
            child: contentCardFor(items[index]),
          ),
          childCount: items.length,
        ),
      ),
    );
  }
}

// =============================================================================
// Channel info row (avatar + title + description + metadata + plugin badge)
// =============================================================================

class _ChannelInfo extends StatelessWidget {
  const _ChannelInfo({required this.channel});

  final Channel channel;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // Avatar.
        CircleAvatar(
          radius: 28,
          backgroundColor: KabukTheme.accentGreen.withAlpha(40),
          backgroundImage: channel.imageUrl != null
              ? CachedNetworkImageProvider(
                  channel.imageUrl!,
                  cacheManager: KabukCacheManager.instance,
                )
              : null,
          child: channel.imageUrl == null
              ? Icon(
                  _iconForEntityType(channel.entityType),
                  color: KabukTheme.accentGreen,
                  size: 24,
                )
              : null,
        ),
        const SizedBox(width: KabukTheme.spacingSm),

        // Title + description + metadata.
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                channel.title,
                style: TextStyle(
                  color: context.kabukTextPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (channel.description != null) ...[
                const SizedBox(height: 2),
                Text(
                  channel.description!,
                  style: TextStyle(
                    color: context.kabukTextSecondary,
                    fontSize: 12,
                    height: 1.3,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              if (channel.metadata.isNotEmpty) ...[
                const SizedBox(height: 4),
                _MetadataRow(metadata: channel.metadata),
              ],
            ],
          ),
        ),

        // Plugin badge.
        if (channel.sourcePluginId != null) ...[
          const SizedBox(width: KabukTheme.spacingSm),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: KabukTheme.accentGreen.withAlpha(30),
              borderRadius: BorderRadius.circular(KabukTheme.radiusSm),
            ),
            child: Text(
              channel.sourcePluginId!,
              style: const TextStyle(
                color: KabukTheme.accentGreen,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ],
    );
  }

  static IconData _iconForEntityType(ChannelEntityType type) {
    return switch (type) {
      ChannelEntityType.website => Icons.language_rounded,
      ChannelEntityType.person => Icons.person_rounded,
      ChannelEntityType.organization => Icons.business_rounded,
      ChannelEntityType.subreddit => Icons.reddit_rounded,
      ChannelEntityType.board => Icons.forum_rounded,
      ChannelEntityType.videoChannel => Icons.videocam_rounded,
      ChannelEntityType.podcast => Icons.podcasts_rounded,
      ChannelEntityType.musicArtist => Icons.music_note_rounded,
      ChannelEntityType.topic => Icons.tag_rounded,
      ChannelEntityType.custom => Icons.dashboard_rounded,
    };
  }
}

// =============================================================================
// Metadata row
// =============================================================================

class _MetadataRow extends StatelessWidget {
  const _MetadataRow({required this.metadata});

  final Map<String, String> metadata;

  @override
  Widget build(BuildContext context) {
    final parts = metadata.entries
        .map((e) => '${e.value} ${e.key}')
        .toList();

    return Text(
      parts.join(' · '),
      style: TextStyle(
        color: context.kabukTextTertiary,
        fontSize: 11,
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

// =============================================================================
// Filter tabs persistent header delegate
// =============================================================================

class _FilterTabsDelegate extends SliverPersistentHeaderDelegate {
  _FilterTabsDelegate({
    required this.selectedFilter,
    required this.onFilterChanged,
    required this.surface,
    required this.divider,
    required this.textPrimary,
    required this.textSecondary,
  });

  final _ContentFilter selectedFilter;
  final ValueChanged<_ContentFilter> onFilterChanged;
  final Color surface;
  final Color divider;
  final Color textPrimary;
  final Color textSecondary;

  @override
  double get minExtent => 48;

  @override
  double get maxExtent => 48;

  @override
  bool shouldRebuild(covariant _FilterTabsDelegate oldDelegate) =>
      selectedFilter != oldDelegate.selectedFilter ||
      surface != oldDelegate.surface;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: surface,
        border: Border(bottom: BorderSide(color: divider, width: 0.5)),
      ),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
          horizontal: KabukTheme.spacingSm,
          vertical: KabukTheme.spacingSm,
        ),
        children: _ContentFilter.values.map((filter) {
          final selected = filter == selectedFilter;
          return Padding(
            padding: const EdgeInsets.only(right: KabukTheme.spacingXs),
            child: FilterChip(
              avatar: Icon(
                filter.icon,
                size: 16,
                color: selected ? KabukTheme.accentGreen : textSecondary,
              ),
              label: Text(
                filter.label,
                style: TextStyle(
                  color: selected ? textPrimary : textSecondary,
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
              selected: selected,
              onSelected: (_) => onFilterChanged(filter),
              showCheckmark: false,
              selectedColor: KabukTheme.accentGreen.withAlpha(30),
              padding: const EdgeInsets.symmetric(horizontal: 4),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
          );
        }).toList(),
      ),
    );
  }
}

// =============================================================================
// Content skeleton (shimmer loading)
// =============================================================================

/// Shimmer loading skeleton shown while channel content loads.
class _ContentSkeleton extends StatefulWidget {
  const _ContentSkeleton();

  @override
  State<_ContentSkeleton> createState() => _ContentSkeletonState();
}

class _ContentSkeletonState extends State<_ContentSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _anim = CurvedAnimation(parent: _controller, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: const EdgeInsets.all(KabukTheme.spacingSm),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: KabukTheme.spacingSm,
          crossAxisSpacing: KabukTheme.spacingSm,
          childAspectRatio: 0.75,
        ),
        delegate: SliverChildBuilderDelegate(
          (_, _) => AnimatedBuilder(
            animation: _anim,
            builder: (context, _) =>
                _SkeletonCard(shimmerValue: _anim.value),
          ),
          childCount: 6,
        ),
      ),
    );
  }
}

/// A single shimmer card placeholder.
class _SkeletonCard extends StatelessWidget {
  const _SkeletonCard({required this.shimmerValue});

  final double shimmerValue;

  @override
  Widget build(BuildContext context) {
    final base = context.kabukCardColor;
    final shimmer = Color.lerp(base, context.kabukDivider, shimmerValue * 0.6)!;

    return Container(
      decoration: BoxDecoration(
        color: base,
        borderRadius: BorderRadius.circular(KabukTheme.radiusMd),
        border: Border.all(color: context.kabukDivider, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Thumbnail placeholder.
          Expanded(
            flex: 3,
            child: Container(
              decoration: BoxDecoration(
                color: shimmer,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(KabukTheme.radiusMd),
                ),
              ),
            ),
          ),
          // Text placeholders.
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.all(KabukTheme.spacingSm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _box(double.infinity, 12, shimmer),
                  const SizedBox(height: 6),
                  _box(100, 12, shimmer),
                  const Spacer(),
                  _box(60, 10, shimmer),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _box(double w, double h, Color color) {
    return Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}
