/// Article card widget — feed card showing source, title, media, and actions.
///
/// Contains [ArticleCard] and its private sub-widgets
/// [_SourceHeader] and [_ActionBar].
library;

import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kabuk/config/providers.dart';
import 'package:kabuk/knowledge/types/article.dart';
import 'package:kabuk/knowledge/types/bookmark.dart';
import 'package:kabuk/services/media_cache.dart';
import 'package:kabuk/services/feed.dart';
import 'package:kabuk/ui/explore/article_detail_page.dart';
import 'package:kabuk/ui/explore/nostr_providers.dart';
import 'package:kabuk/ui/explore/channel_view.dart';
import 'package:kabuk/ui/explore/profile_view.dart';
import 'package:kabuk/ui/explore/quick_peek_sheet.dart';
import 'package:kabuk/ui/shared/feed_image.dart';
import 'package:kabuk/ui/shared/video_thumbnail.dart';
import 'package:kabuk/ui/theme.dart';

// =============================================================================
// Article Card
// =============================================================================

/// A single article card in the feed — shows source, title, media, and actions.
class ArticleCard extends ConsumerWidget {
  /// Creates an [ArticleCard].
  const ArticleCard({
    required this.article,
    super.key,
    this.onBeforeOpen,
    this.onReturnFromDetail,
    this.articles,
    this.index,
  });

  /// The article data to display.
  final ArticleData article;

  /// Called just before the detail page is pushed (used by the feed to
  /// record which article was opened for scroll-restoration on return).
  final VoidCallback? onBeforeOpen;

  /// Called after the detail page pops with the final article index the user
  /// was viewing (used by the feed to scroll to the correct position).
  final ValueChanged<int>? onReturnFromDetail;

  /// Optional list of feed articles for swipe-to-next navigation.
  final List<ArticleData>? articles;

  /// Index of this article within [articles].
  final int? index;

  /// Returns the accent color for this article's source (used for borders).
  Color _sourceAccentColor() {
    final source = article.feedSource ?? '';
    final url = article.url ?? '';
    if (source.contains('reddit') || url.contains('reddit.com')) {
      return KabukTheme.redditOrange; // Reddit orange
    }
    if (source.startsWith('kabuk:') ||
        source.isEmpty ||
        url.startsWith('nostr:')) {
      return const Color(0xFF9C27B0); // Nostr purple
    }
    return KabukTheme.blueAccent; // RSS / generic
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasImage = FeedImage.isValidImageUrl(article.image);
    final isVideo = _isVideoContent(article);
    final isGif = _isGif(article);
    final hasGallery = article.galleryImages.length > 1;
    final hasMedia = hasImage || isVideo || hasGallery;

    return GestureDetector(
      onTap: () => _openDetail(context, ref),
      onLongPress: () => _quickPeek(context, ref),
      child: Dismissible(
      key: ValueKey(article.uri),
      direction: DismissDirection.horizontal,
      // Swipe right → bookmark
      background: Container(
        color: KabukTheme.accentGreen.withAlpha(200),
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 20),
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.bookmark_add_rounded, color: Colors.white, size: 28),
            SizedBox(height: 4),
            Text(
              'Bookmark',
              style: TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
      // Swipe left → mark as read
      secondaryBackground: Container(
        color: Colors.orange.withAlpha(200),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.check_circle_outline_rounded,
              color: Colors.white,
              size: 28,
            ),
            SizedBox(height: 4),
            Text(
              'Mark read',
              style: TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
      confirmDismiss: (direction) async {
        unawaited(HapticFeedback.lightImpact());
        final store = ref.read(knowledgeStoreProvider);
        if (direction == DismissDirection.startToEnd) {
          final url = article.url;
          if (url != null && url.isNotEmpty) {
            await store.createBookmark(
              name: article.name ?? url,
              url: url,
              description: article.description,
            );
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Saved to bookmarks'),
                  duration: Duration(seconds: 2),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            }
          }
        } else {
          await store.markArticleRead(article.uri);
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Marked as read'),
                duration: Duration(seconds: 1),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        }
        return false; // keep the card in the list
      },
      child: Opacity(
        opacity: article.read ? 0.7 : 1.0,
        child: Container(
          decoration: BoxDecoration(
            color: KabukTheme.cardColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: article.read ? Colors.transparent : KabukTheme.divider,
            ),
            boxShadow: const [
              BoxShadow(
                color: Colors.black12,
                blurRadius: 4,
                offset: Offset(0, 1),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Colored accent bar for text-only cards (no image/video/gallery).
              if (!hasMedia)
                Container(
                  height: 3,
                  decoration: BoxDecoration(
                    color: _sourceAccentColor().withAlpha(180),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(16),
                      topRight: Radius.circular(16),
                    ),
                  ),
                ),
              _SourceHeader(article: article),
              if (article.name != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                  child: Text(
                    _cleanTitle(article.name!),
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      height: 1.3,
                      color: article.read
                          ? KabukTheme.textSecondary
                          : KabukTheme.textPrimary,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              if (hasGallery)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                  child: _GalleryCarousel(images: article.galleryImages),
                )
              else if (isVideo)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                  child: VideoThumbnail(
                    videoUrl: article.videoUrl ?? article.url ?? '',
                    thumbnailUrl: article.image,
                    height: 200,
                    borderRadius: BorderRadius.circular(12),
                  ),
                )
              else if (isGif && hasImage)
                // Use CachedNetworkImage for GIFs — cached for offline access;
                // Flutter's codec animates them as usual.
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Stack(
                      children: [
                        CachedNetworkImage(
                          imageUrl: article.image!,
                          cacheManager: KabukCacheManager.instance,
                          height: 200,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          fadeInDuration: const Duration(milliseconds: 300),
                          placeholder: (_, _) => Container(
                            height: 200,
                            color: KabukTheme.surfaceVariant,
                          ),
                          errorWidget: (_, _, _) => const SizedBox.shrink(),
                        ),
                        // GIF badge.
                        const Positioned(
                          bottom: 6,
                          right: 6,
                          child: _MediaBadge(label: 'GIF'),
                        ),
                      ],
                    ),
                  ),
                )
              else if (hasImage)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                  child: FeedImage(
                    imageUrl: article.image!,
                    height: 200,
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              if (_shouldShowDescription(article))
                Builder(
                  builder: (context) {
                    final cleaned = _cleanDescription(article.description!);
                    if (cleaned.isEmpty) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                      child: Text(
                        cleaned,
                        style: const TextStyle(
                          fontSize: 13,
                          height: 1.4,
                          color: KabukTheme.textSecondary,
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  },
                ),
              _ActionBar(article: article),
            ],
          ),
        ),
      ),
      ),
    );
  }

  bool _isVideoContent(ArticleData article) {
    // Prefer the dedicated videoUrl field (parsed from Reddit API etc.).
    if (article.videoUrl != null && article.videoUrl!.isNotEmpty) return true;
    final url = (article.url ?? '').toLowerCase();
    return url.contains('v.redd.it') ||
        url.contains('youtube.com') ||
        url.contains('youtu.be') ||
        url.endsWith('.mp4') ||
        url.endsWith('.webm') ||
        url.endsWith('.gifv'); // gifv is mp4 wrapped in a .gifv extension
  }

  bool _isGif(ArticleData article) {
    final img = (article.image ?? '').toLowerCase();
    return img.endsWith('.gif');
  }

  bool _isStatsOnly(String desc) {
    final trimmed = desc.trim();
    return RegExp(r'^[⬆💬·\s\d,.|]+$').hasMatch(trimmed) ||
        RegExp(r'^[\d,]+\s+(upvotes?|points?)\s*[|·]').hasMatch(trimmed);
  }

  bool _shouldShowDescription(ArticleData article) {
    final desc = article.description;
    if (desc == null || desc.isEmpty) return false;
    if (_isStatsOnly(desc)) return false;
    final cleaned = _cleanDescription(desc);
    if (cleaned.isEmpty) return false;
    if (RegExp(r'^https?://\S+$').hasMatch(cleaned)) return false;
    return true;
  }

  String _cleanDescription(String desc) {
    return desc
        .replaceAll(RegExp(r'https?://\S+'), '') // strip raw URLs
        .replaceAll(
          RegExp(r'\s*[·|]?\s*⬆\s*[\d,]+\s*([·|]\s*💬\s*[\d,]+)?\s*$'),
          '',
        )
        .replaceAll(RegExp(r'\s*[·|]?\s*💬\s*[\d,]+\s*$'), '')
        .replaceAll(RegExp(r'\s{2,}'), ' ')
        .trim();
  }

  /// Strips raw URLs from a title string for clean display.
  ///
  /// For Nostr articles, if the stored title is just a bare hashtag token
  /// (e.g. "#V2EX" from mirror bots), extract a real title from the
  /// description instead.
  String _cleanTitle(String title) {
    final isNostrArticle = article.url?.startsWith('nostr:') ?? false;
    if (isNostrArticle) {
      final trimmed = title.trim();
      // Detect bare hashtag title: starts with '#', no spaces, or all tokens
      // are hashtags (e.g. "#V2EX" or "#bitcoin #nostr").
      final isBareHashtag = trimmed.startsWith('#') &&
          trimmed.split(RegExp(r'\s+')).every((w) => w.startsWith('#'));
      if (isBareHashtag) {
        final better = _extractTitleFromDescription(article.description ?? '');
        if (better.isNotEmpty) return better;
      }
    }
    final cleaned = title
        .replaceAll(RegExp(r'https?://\S+'), '')
        .replaceAll(RegExp(r'\s{2,}'), ' ')
        .trim();
    return cleaned.isEmpty ? 'Nostr post' : cleaned;
  }

  /// Extracts a meaningful title from a Nostr note description by skipping
  /// leading hashtag-only lines and markdown header markers.
  String _extractTitleFromDescription(String description) {
    if (description.isEmpty) return '';
    // Try line-by-line on newline-separated content first.
    final lines = description.split('\n');
    for (final line in lines) {
      final lineClean =
          line.replaceAll(RegExp(r'https?://\S+'), '').trim();
      if (lineClean.isEmpty) continue;
      // Skip lines whose tokens are ALL hashtags (e.g. "#V2EX").
      final words = lineClean.split(RegExp(r'\s+'));
      if (words.every((w) => w.startsWith('#') || w.isEmpty)) continue;
      // Strip leading markdown header markers (e.g. "### ") for display.
      final displayTitle =
          lineClean.replaceFirst(RegExp(r'^#{1,6}\s+'), '').trim();
      if (displayTitle.isEmpty) continue;
      return displayTitle.length > 120
          ? '${displayTitle.substring(0, 120)}…'
          : displayTitle;
    }
    // Fallback: strip leading "#WORD " tokens then markdown headers.
    final stripped = description
        .replaceAll(RegExp(r'^(#\w+\s+)+'), '')
        .replaceFirst(RegExp(r'^#{1,6}\s+'), '')
        .trim();
    return stripped.length > 120 ? '${stripped.substring(0, 120)}…' : stripped;
  }

  void _openDetail(BuildContext context, WidgetRef ref) {
    HapticFeedback.selectionClick();
    final store = ref.read(knowledgeStoreProvider);
    if (!article.read) {
      store.markArticleRead(article.uri);
    }
    onBeforeOpen?.call();
    pushArticleDetail(
      context,
      article: article,
      articles: articles,
      initialIndex: index ?? 0,
    ).then((finalIndex) {
      onReturnFromDetail?.call(finalIndex ?? index ?? 0);
    });
  }

  void _quickPeek(BuildContext context, WidgetRef ref) {
    final url = article.url;
    if (url == null || url.isEmpty) return;
    final store = ref.read(knowledgeStoreProvider);
    if (!article.read) {
      store.markArticleRead(article.uri);
    }
    QuickPeekSheet.show(context, url: url, title: article.name);
  }
}

// =============================================================================
// Source Header
// =============================================================================

/// Shows source icon, feed/subreddit name, author, and time.
///
/// The subreddit name (`r/xxx`) and author name are tappable — tapping
/// opens the corresponding Reddit page inside the in-app quick peek sheet.
/// For Nostr sources, tapping the author navigates to [ProfileView].
class _SourceHeader extends StatelessWidget {
  const _SourceHeader({required this.article});

  final ArticleData article;

  /// Whether the given string looks like a full Nostr hex pubkey.
  static bool _isHexPubkey(String value) =>
      RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(value);

  @override
  Widget build(BuildContext context) {
    final source = article.feedSource ?? '';
    final url = article.url ?? '';
    final isReddit =
        source.contains('reddit') || url.contains('reddit.com');
    final isNostr = !isReddit &&
        (url.startsWith('nostr:') ||
            source.startsWith('kabuk:') ||
            source.isEmpty);
    final timeAgo = _formatTimeAgo(article.datePublished);

    final Color iconColor;
    final IconData iconData;
    if (isReddit) {
      iconColor = KabukTheme.redditOrange;
      iconData = Icons.reddit;
    } else if (isNostr) {
      iconColor = KabukTheme.purpleAccent;
      iconData = Icons.hub_rounded;
    } else {
      iconColor = KabukTheme.blueAccent;
      iconData = Icons.rss_feed_rounded;
    }

    final subreddit = _subredditName(article);
    final author = article.author;
    final authorIsHexPubkey = author != null && _isHexPubkey(author);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 2),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: iconColor.withAlpha(30),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(iconData, size: 16, color: iconColor),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Subreddit / feed name — tappable for Reddit sources.
                GestureDetector(
                  onTap: isReddit && subreddit.startsWith('r/')
                      ? () => _openSubreddit(context, subreddit)
                      : null,
                  child: Text(
                    subreddit,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isReddit && subreddit.startsWith('r/')
                          ? KabukTheme.redditOrange
                          : KabukTheme.textSecondary,
                      decoration: isReddit && subreddit.startsWith('r/')
                          ? TextDecoration.none
                          : null,
                    ),
                  ),
                ),
                // Author — tappable for Reddit (opens QuickPeek) and
                // Nostr hex-pubkey authors (opens ProfileView).
                if (author != null)
                  GestureDetector(
                    onTap: isReddit
                        ? () => _openUserProfile(context, author)
                        : authorIsHexPubkey
                            ? () => _openNostrProfile(context, author)
                            : null,
                    child: Text(
                      isReddit
                          ? (author.startsWith('u/')
                              ? author
                              : 'u/$author')
                          : _formatNostrAuthor(author),
                      style: TextStyle(
                        fontSize: 11,
                        color: isReddit
                            ? KabukTheme.blueAccent.withAlpha(200)
                            : authorIsHexPubkey
                                ? KabukTheme.purpleAccent.withAlpha(200)
                                : KabukTheme.textTertiary,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (timeAgo != null)
            Opacity(
              opacity: 0.7,
              child: Text(
                timeAgo,
                style: const TextStyle(
                  fontSize: 12,
                  color: KabukTheme.textSecondary,
                ),
              ),
            ),
          if (!article.read) ...[
            const SizedBox(width: 6),
            Container(
              width: 7,
              height: 7,
              decoration: const BoxDecoration(
                color: KabukTheme.accentGreen,
                shape: BoxShape.circle,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Formats a Nostr author (hex pubkey) for display with `@` prefix.
  String _formatNostrAuthor(String author) {
    if (author.startsWith('@')) return author;
    final base = author.endsWith('…') ? author.substring(0, author.length - 1) : author;
    if (RegExp(r'^[0-9a-fA-F]{8,}$').hasMatch(base)) {
      return '@${base.length > 8 ? '${base.substring(0, 8)}…' : base}';
    }
    return author;
  }

  /// Extracts subreddit name (e.g. `r/flutter`) or Nostr topic from tags.
  String _subredditName(ArticleData article) {
    final tags = article.tags;
    for (final tag in tags) {
      if (tag.startsWith('r/')) return tag;
    }
    // Return first Nostr topic tag (e.g. "flutter" → "#flutter").
    for (final tag in tags) {
      if (tag.isNotEmpty && !tag.startsWith('kabuk:')) return '#$tag';
    }
    // Fall back: if feedSource is a kabuk URI, show "Nostr" instead of the UUID.
    final source = article.feedSource ?? '';
    if (source.startsWith('kabuk:') || source.isEmpty) return 'Nostr';
    return source.split('/').last.isNotEmpty ? source.split('/').last : 'Feed';
  }

  /// Opens the subreddit in the quick-peek in-app WebView.
  void _openSubreddit(BuildContext context, String subreddit) {
    final name = subreddit.startsWith('r/')
        ? subreddit.substring(2)
        : subreddit;
    QuickPeekSheet.show(
      context,
      url: 'https://www.reddit.com/r/$name',
      title: subreddit,
    );
  }

  /// Opens the Reddit user profile natively via [ChannelView].
  void _openUserProfile(BuildContext context, String author) {
    final name = author.startsWith('u/') ? author.substring(2) : author;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ChannelView(
          author: name,
          sourceType: FeedSourceType.reddit,
        ),
      ),
    );
  }

  /// Opens the Nostr user profile page for a hex pubkey.
  void _openNostrProfile(BuildContext context, String pubkey) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ProfileView(pubkey: pubkey),
      ),
    );
  }

  String? _formatTimeAgo(DateTime? date) {
    if (date == null) return null;
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 1) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';
    if (diff.inDays < 30) return '${diff.inDays ~/ 7}w';
    if (diff.inDays < 365) return '${diff.inDays ~/ 30}mo';
    return '${diff.inDays ~/ 365}y';
  }
}

// =============================================================================
// Action Bar
// =============================================================================

/// Bottom action row with inline Nostr social interactions on every article.
class _ActionBar extends ConsumerWidget {
  const _ActionBar({required this.article});

  final ArticleData article;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = _parseStats(article.description);
    final articleUrl = article.url;
    final hasUrl = articleUrl != null && articleUrl.isNotEmpty;

    final nostrStats = hasUrl
        ? ref.watch(nostrSocialStatsForUrlProvider(articleUrl))
        : null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      child: Row(
        children: [
          _socialButton(
            context: context,
            icon:
                nostrStats?.whenOrNull(
                  data: (s) => s.userReacted
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                ) ??
                Icons.favorite_border_rounded,
            label: _resolveStat(
              nostrStats?.whenOrNull(data: (s) => s.reactionCount),
              stats.upvotes,
            ),
            semanticLabel: 'React',
            color:
                nostrStats?.whenOrNull(
                  data: (s) => s.userReacted
                      ? const Color(0xFFE91E63)
                      : KabukTheme.textTertiary,
                ) ??
                KabukTheme.textTertiary,
            onTap: hasUrl ? () => _handleReaction(context, ref) : null,
          ),
          _socialButton(
            context: context,
            icon: Icons.chat_bubble_outline_rounded,
            label: _resolveStat(
              nostrStats?.whenOrNull(data: (s) => s.replyCount),
              stats.comments,
            ),
            semanticLabel: 'Comment',
            color: KabukTheme.textTertiary,
            onTap: hasUrl ? () => _handleComment(context, ref) : null,
          ),
          _socialButton(
            context: context,
            icon:
                nostrStats?.whenOrNull(
                  data: (s) => s.userReposted
                      ? Icons.repeat_on_rounded
                      : Icons.repeat_rounded,
                ) ??
                Icons.repeat_rounded,
            label: nostrStats?.whenOrNull(
              data: (s) =>
                  s.repostCount > 0 ? _formatCount(s.repostCount) : null,
            ),
            semanticLabel: 'Repost',
            color:
                nostrStats?.whenOrNull(
                  data: (s) => s.userReposted
                      ? KabukTheme.accentGreen
                      : KabukTheme.textTertiary,
                ) ??
                KabukTheme.textTertiary,
            onTap: hasUrl ? () => _handleRepost(context, ref) : null,
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(
              Icons.bookmark_add_outlined,
              size: 18,
              color: KabukTheme.textTertiary,
            ),
            tooltip: 'Save to bookmarks',
            onPressed: () => _saveBookmark(context, ref),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  Widget _socialButton({
    required BuildContext context,
    required IconData icon,
    String? label,
    String? semanticLabel,
    required Color color,
    VoidCallback? onTap,
  }) {
    final child = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        if (label != null) ...[
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 12, color: color)),
        ],
      ],
    );
    final button = InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: child,
      ),
    );
    final effectiveLabel =
        label != null ? '$semanticLabel $label' : semanticLabel;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: effectiveLabel != null
          ? Semantics(
              label: effectiveLabel,
              button: true,
              excludeSemantics: true,
              child: button,
            )
          : button,
    );
  }

  String? _resolveStat(int? nostrCount, int? sourceCount) {
    if (nostrCount != null && nostrCount > 0) return _formatCount(nostrCount);
    if (sourceCount != null && sourceCount > 0) {
      return _formatCount(sourceCount);
    }
    return null;
  }

  Future<void> _handleReaction(BuildContext context, WidgetRef ref) async {
    unawaited(HapticFeedback.lightImpact());
    final url = article.url;
    if (url == null) return;
    final success = await reactToUrl(ref, url: url);
    if (context.mounted && !success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Set up your identity in Settings to interact'),
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _handleComment(BuildContext context, WidgetRef ref) async {
    unawaited(HapticFeedback.lightImpact());
    final controller = TextEditingController();
    final comment = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: KabukTheme.surface,
        title: const Text('Comment on Nostr'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 4,
          decoration: InputDecoration(
            hintText: 'Write your comment...',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Post'),
          ),
        ],
      ),
    );
    controller.dispose();

    if (comment != null && comment.trim().isNotEmpty && context.mounted) {
      final url = article.url;
      if (url == null) return;
      final success = await commentOnUrl(
        ref,
        url: url,
        content: comment.trim(),
      );
      if (context.mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Comment posted to Nostr'),
              duration: Duration(seconds: 1),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Set up your identity in Settings to comment'),
              duration: Duration(seconds: 3),
            ),
          );
        }
      }
    }
  }

  Future<void> _handleRepost(BuildContext context, WidgetRef ref) async {
    unawaited(HapticFeedback.lightImpact());
    final url = article.url;
    if (url == null) return;
    final success = await repostUrl(ref, url: url);
    if (context.mounted && !success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Set up your identity in Settings to repost'),
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  _ArticleStats _parseStats(String? description) {
    if (description == null) return const _ArticleStats();
    int? upvotes;
    int? comments;
    final upMatch = RegExp(r'⬆\s*([\d,]+)').firstMatch(description);
    if (upMatch != null) {
      upvotes = int.tryParse(upMatch.group(1)!.replaceAll(',', ''));
    }
    final cmtMatch = RegExp(r'💬\s*([\d,]+)').firstMatch(description);
    if (cmtMatch != null) {
      comments = int.tryParse(cmtMatch.group(1)!.replaceAll(',', ''));
    }
    return _ArticleStats(upvotes: upvotes, comments: comments);
  }

  String _formatCount(int count) {
    if (count >= 1000000) return '${(count / 1000000).toStringAsFixed(1)}M';
    if (count >= 1000) return '${(count / 1000).toStringAsFixed(1)}k';
    return count.toString();
  }

  Future<void> _saveBookmark(BuildContext context, WidgetRef ref) async {
    final url = article.url;
    if (url == null || url.isEmpty) return;
    final store = ref.read(knowledgeStoreProvider);
    await store.createBookmark(
      name: article.name ?? url,
      url: url,
      description: article.description,
    );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Saved to bookmarks'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }
}

/// Parsed Reddit stats from the description field.
class _ArticleStats {
  const _ArticleStats({this.upvotes, this.comments});
  final int? upvotes;
  final int? comments;
}

// =============================================================================
// Media badge
// =============================================================================

/// Small overlay badge to label media types (GIF, VIDEO, etc.).
class _MediaBadge extends StatelessWidget {
  const _MediaBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(160),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: Colors.white,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

// =============================================================================
// Gallery Carousel
// =============================================================================

/// Swipeable horizontal image carousel for Reddit gallery posts.
///
/// Shows all images with a page indicator showing the current position.
/// Tapping navigates between images; the overall card tap still opens the
/// detail page.
class _GalleryCarousel extends StatefulWidget {
  const _GalleryCarousel({required this.images});

  final List<String> images;

  @override
  State<_GalleryCarousel> createState() => _GalleryCarouselState();
}

class _GalleryCarouselState extends State<_GalleryCarousel> {
  final _controller = PageController();
  int _current = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 220,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          children: [
            PageView.builder(
              controller: _controller,
              itemCount: widget.images.length,
              onPageChanged: (i) => setState(() => _current = i),
              itemBuilder: (context, i) {
                return CachedNetworkImage(
                  imageUrl: widget.images[i],
                  cacheManager: KabukCacheManager.instance,
                  fit: BoxFit.cover,
                  width: double.infinity,
                  fadeInDuration: const Duration(milliseconds: 300),
                  placeholder: (_, _) => Container(
                    color: KabukTheme.surfaceVariant,
                  ),
                  errorWidget: (_, _, _) => Container(
                    color: KabukTheme.cardColor,
                    child: const Icon(
                      Icons.broken_image_outlined,
                      color: KabukTheme.textTertiary,
                    ),
                  ),
                );
              },
            ),
            // Page counter pill.
            Positioned(
              bottom: 8,
              right: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.black.withAlpha(160),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${_current + 1} / ${widget.images.length}',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            // Dot indicator row.
            if (widget.images.length <= 10)
              Positioned(
                bottom: 8,
                left: 0,
                right: 0,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(widget.images.length, (i) {
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      width: i == _current ? 16 : 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: i == _current
                            ? Colors.white
                            : Colors.white.withAlpha(100),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    );
                  }),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
