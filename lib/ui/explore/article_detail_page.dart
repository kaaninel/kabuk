/// Full-screen article detail page.
///
/// Shows a single article with full content, Nostr social bar, and
/// discussion section. Slides up from the bottom; press back to return
/// to the feed.
library;

import 'dart:async' show unawaited;
import 'dart:developer' as dev;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kabuk/config/providers.dart';
import 'package:kabuk/knowledge/types/article.dart';
import 'package:kabuk/knowledge/types/bookmark.dart';
import 'package:kabuk/knowledge/types/content_block.dart';
import 'package:kabuk/knowledge/types/nostr_social.dart';
import 'package:kabuk/services/feed.dart';
import 'package:kabuk/services/media_cache.dart';
import 'package:kabuk/services/reader_mode.dart';
import 'package:kabuk/ui/explore/article_card.dart' show bookmarkStatusProvider;
import 'package:kabuk/ui/explore/browse_session.dart';
import 'package:kabuk/ui/explore/fourchan_comments.dart';
import 'package:kabuk/ui/explore/channel_view.dart';
import 'package:kabuk/ui/explore/nostr_providers.dart';
import 'package:kabuk/ui/explore/profile_view.dart';
import 'package:kabuk/ui/explore/quick_peek_sheet.dart';
import 'package:kabuk/ui/explore/reddit_comments.dart';
import 'package:kabuk/ui/shared/feed_image.dart';
import 'package:kabuk/ui/shared/fullscreen_image_viewer.dart';
import 'package:kabuk/ui/shared/kabuk_keyboard.dart';
import 'package:kabuk/ui/shared/video_thumbnail.dart';
import 'package:kabuk/ui/theme.dart';

// =============================================================================
// Route helper
// =============================================================================

/// Regex patterns for detecting in-app navigable URLs.
final _redditSubPattern = RegExp(r'reddit\.com/r/(\w+)', caseSensitive: false);
final _redditUserPattern = RegExp(r'reddit\.com/u(?:ser)?/(\w+)', caseSensitive: false);

/// Opens a URL intelligently: routes Reddit subreddit/user URLs to native
/// ChannelView, and everything else to the in-app browser (QuickPeekSheet).
void openUrlSmart(BuildContext context, String url, {String? title}) {
  // Reddit subreddit → native ChannelView
  final subMatch = _redditSubPattern.firstMatch(url);
  if (subMatch != null) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ChannelView(
          channel: subMatch.group(1)!,
          sourceType: FeedSourceType.reddit,
        ),
      ),
    );
    return;
  }

  // Reddit user → native ChannelView
  final userMatch = _redditUserPattern.firstMatch(url);
  if (userMatch != null) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ChannelView(
          author: userMatch.group(1)!,
          sourceType: FeedSourceType.reddit,
        ),
      ),
    );
    return;
  }

  // Everything else → in-app browser
  QuickPeekSheet.show(context, url: url, title: title);
}

/// Navigation helper — pushes [ArticleDetailPage] on the navigator.
///
/// Uses a slide-up transition for a smooth Reddit-like feel.
/// Returns the navigator's future so callers can react when the page is popped.
///
/// When [articles] and [initialIndex] are provided, the detail page supports
/// Reddit-style swipe-to-next-article navigation via overscroll detection.
///
/// Returns the final article index the user was viewing when they popped back,
/// or `null` if no article list was provided.
Future<int?> pushArticleDetail(
  BuildContext context, {
  required ArticleData article,
  List<ArticleData>? articles,
  int initialIndex = 0,
}) {
  return Navigator.of(context).push<int>(
    PageRouteBuilder<int>(
      pageBuilder: (context, animation, secondaryAnimation) =>
          ArticleDetailPage(
        article: article,
        articles: articles,
        initialIndex: initialIndex,
      ),
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
// ArticleDetailPage
// =============================================================================

/// Full-screen article detail page.
///
/// When [articles] is provided, supports Reddit-style swipe-to-next-article
/// navigation via overscroll detection at the top/bottom of the content.
class ArticleDetailPage extends ConsumerStatefulWidget {
  /// Creates an [ArticleDetailPage].
  const ArticleDetailPage({
    required this.article,
    this.articles,
    this.initialIndex = 0,
    super.key,
  });

  /// The article to display (or the initial article when [articles] is set).
  final ArticleData article;

  /// Optional list of articles for swipe navigation.
  final List<ArticleData>? articles;

  /// Starting index within [articles].
  final int initialIndex;

  @override
  ConsumerState<ArticleDetailPage> createState() => _ArticleDetailPageState();
}

class _ArticleDetailPageState extends ConsumerState<ArticleDetailPage> {
  late int _currentIndex;
  late ArticleData _currentArticle;
  final _scrollController = ScrollController();

  /// True = slide from right (next), false = slide from left (previous).
  bool _slideForward = true;

  bool get _hasNext =>
      widget.articles != null &&
      _currentIndex < widget.articles!.length - 1;

  bool get _hasPrevious =>
      widget.articles != null && _currentIndex > 0;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _currentArticle = widget.article;
    // Dismiss any active keyboard when entering article detail.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(keyboardModeProvider.notifier).state = KeyboardMode.none;
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _goToNextArticle() {
    if (!_hasNext) return;
    HapticFeedback.mediumImpact();
    final store = ref.read(knowledgeStoreProvider);
    if (!_currentArticle.read) {
      store.markArticleRead(_currentArticle.uri);
    }
    ref.read(keyboardModeProvider.notifier).state = KeyboardMode.none;
    setState(() {
      _slideForward = true;
      _currentIndex++;
      _currentArticle = widget.articles![_currentIndex];
    });
    _scrollController.jumpTo(0);
  }

  void _goToPreviousArticle() {
    if (!_hasPrevious) return;
    HapticFeedback.mediumImpact();
    ref.read(keyboardModeProvider.notifier).state = KeyboardMode.none;
    setState(() {
      _currentIndex--;
      _currentArticle = widget.articles![_currentIndex];
    });
    _scrollController.jumpTo(0);
  }

  /// Handle horizontal swipe to navigate between articles.
  void _onHorizontalDragEnd(DragEndDetails details) {
    if (widget.articles == null) return;
    final velocity = details.primaryVelocity ?? 0;
    // Swipe left (negative velocity) → next article.
    if (velocity < -300 && _hasNext) {
      _goToNextArticle();
    }
    // Swipe right (positive velocity) → previous article.
    else if (velocity > 300 && _hasPrevious) {
      _goToPreviousArticle();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_currentIndex);
      },
      child: Scaffold(
      backgroundColor: KabukTheme.background,
      appBar: _ArticleOmniBar(
        article: _currentArticle,
        onBack: () => Navigator.of(context).pop(_currentIndex),
      ),
      body: GestureDetector(
        onHorizontalDragEnd: _onHorizontalDragEnd,
        behavior: HitTestBehavior.translucent,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          transitionBuilder: (child, animation) {
            final begin = _slideForward
                ? const Offset(1, 0)
                : const Offset(-1, 0);
            return SlideTransition(
              position: Tween<Offset>(begin: begin, end: Offset.zero)
                  .animate(CurvedAnimation(
                parent: animation,
                curve: Curves.easeOutCubic,
              )),
              child: FadeTransition(opacity: animation, child: child),
            );
          },
          child: _ArticleDetailContent(
            key: ValueKey(_currentArticle.uri),
            article: _currentArticle,
            scrollController: _scrollController,
            onViewInBrowser: () {
              final url = _currentArticle.url;
              if (url == null) return;
              QuickPeekSheet.show(
                context,
                url: url,
                title: _currentArticle.name,
              );
            },
          ),
        ),
      ),
      ),
    );
  }
}

// =============================================================================
// Article Detail Content (single scrollable page)
// =============================================================================

/// Scrollable content for a single article in the [ArticleDetailPage].
///
/// When the article has no description and a URL (multi-article stub),
/// automatically fetches full content via reader mode.
class _ArticleDetailContent extends ConsumerStatefulWidget {
  const _ArticleDetailContent({
    required this.article,
    required this.onViewInBrowser,
    this.scrollController,
    super.key,
  });

  final ArticleData article;
  final VoidCallback onViewInBrowser;

  /// Scroll controller shared with the parent.
  final ScrollController? scrollController;

  @override
  ConsumerState<_ArticleDetailContent> createState() =>
      _ArticleDetailContentState();
}

class _ArticleDetailContentState extends ConsumerState<_ArticleDetailContent> {
  bool _isFetchingContent = false;
  bool _fetchAttempted = false;
  ArticleData? _enrichedArticle;
  List<ContentBlockData>? _contentBlocks;

  /// Whether this article is a stub that needs content fetching.
  bool get _isStub {
    final a = widget.article;
    return (a.description == null || a.description!.isEmpty) &&
        a.url != null &&
        a.url!.startsWith('http');
  }

  @override
  void initState() {
    super.initState();
    if (_isStub) {
      _fetchContent();
    }
  }

  @override
  void didUpdateWidget(covariant _ArticleDetailContent old) {
    super.didUpdateWidget(old);
    if (old.article.uri != widget.article.uri) {
      _isFetchingContent = false;
      _fetchAttempted = false;
      _enrichedArticle = null;
      _contentBlocks = null;
      if (_isStub) _fetchContent();
    }
  }

  Future<void> _fetchContent() async {
    if (_fetchAttempted || _isFetchingContent) return;
    setState(() => _isFetchingContent = true);
    _fetchAttempted = true;

    try {
      final readerMode = ref.read(readerModeServiceProvider);
      final store = ref.read(knowledgeStoreProvider);

      // Process through reader mode — this creates content blocks.
      await readerMode.processUrl(
        widget.article.url!,
        feedSource: widget.article.feedSource,
      );

      if (!mounted) return;

      // Re-fetch the updated article and its content blocks.
      final updatedArticle = await store.getArticleData(widget.article.uri);
      final blocks = await store.listDocumentBlocks(widget.article.uri);

      if (!mounted) return;
      setState(() {
        _enrichedArticle = updatedArticle;
        _contentBlocks = blocks;
        _isFetchingContent = false;
      });
    } on Object catch (e, st) {
      dev.log(
        'Lazy content fetch failed for ${widget.article.url}',
        name: 'ArticleDetail',
        error: e,
        stackTrace: st,
      );
      if (mounted) setState(() => _isFetchingContent = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final article = _enrichedArticle ?? widget.article;
    final hasImage = FeedImage.isValidImageUrl(article.image);
    final isVideo = _hasVideo(article);
    final hasGallery = article.galleryImages.length > 1;

    return ListView(
      controller: widget.scrollController,
      padding: EdgeInsets.zero,
      children: [
        // ── Media ──────────────────────────────────────────────────────────
        if (hasGallery)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: _DetailGalleryCarousel(
              images: article.galleryImages,
              articleUri: article.uri,
            ),
          )
        else if (isVideo)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: VideoThumbnail(
              videoUrl: _videoUrl(article),
              thumbnailUrl: article.image,
              height: 240,
              borderRadius: BorderRadius.circular(12),
            ),
          )
        else if (hasImage)
          GestureDetector(
            onTap: () => FullscreenImageViewer.show(
              context,
              imageUrl: article.image!,
              tag: 'article_img_${article.uri}',
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Hero(
                tag: 'article_img_${article.uri}',
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Stack(
                    children: [
                      FeedImage(
                        imageUrl: article.image!,
                        height: 240,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.all(5),
                          decoration: BoxDecoration(
                            color: Colors.black.withAlpha(130),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.zoom_in_rounded,
                            color: Colors.white70,
                            size: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

        // ── Title + date ─────────────────────────────────────────────────
        if (article.name != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Text(
              _cleanTitle(article.name!),
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                height: 1.25,
                color: KabukTheme.textPrimary,
              ),
            ),
          ),

        // ── Compact meta: date + source link ───────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
          child: Row(
            children: [
              if (article.datePublished != null) ...[
                Text(
                  _formatDate(article.datePublished!),
                  style: const TextStyle(
                    fontSize: 12,
                    color: KabukTheme.textTertiary,
                  ),
                ),
              ],
              if (article.url != null && !_isInternalUrl(article.url!)) ...[
                if (article.datePublished != null)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6),
                    child: Text('·',
                        style: TextStyle(
                            fontSize: 12, color: KabukTheme.textTertiary)),
                  ),
                GestureDetector(
                  onTap: widget.onViewInBrowser,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.open_in_new_rounded,
                          size: 11, color: KabukTheme.textTertiary),
                      const SizedBox(width: 3),
                      Text(
                        _truncateUrl(article.url!),
                        style: const TextStyle(
                          fontSize: 12,
                          color: KabukTheme.blueAccent,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),

        // ── Description ────────────────────────────────────────────────────
        if (article.description != null && article.description!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: _hasMarkdown(article.description!)
                ? MarkdownBody(
                    data: _cleanDescription(_stripStatsLine(article.description!)),
                    styleSheet: MarkdownStyleSheet(
                      p: const TextStyle(
                        fontSize: 15,
                        height: 1.65,
                        color: KabukTheme.textPrimary,
                      ),
                      code: const TextStyle(
                        fontSize: 13,
                        fontFamily: 'monospace',
                        color: KabukTheme.accentGreen,
                        backgroundColor: Color(0xFF1A1A1A),
                      ),
                      codeblockDecoration: BoxDecoration(
                        color: const Color(0xFF1A1A1A),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      blockquote: const TextStyle(
                        fontSize: 14,
                        height: 1.6,
                        color: KabukTheme.textSecondary,
                        fontStyle: FontStyle.italic,
                      ),
                      blockquoteDecoration: BoxDecoration(
                        border: Border(
                          left: BorderSide(
                            color: KabukTheme.textTertiary.withAlpha(120),
                            width: 3,
                          ),
                        ),
                      ),
                      h1: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: KabukTheme.textPrimary,
                      ),
                      h2: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: KabukTheme.textPrimary,
                      ),
                      h3: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: KabukTheme.textPrimary,
                      ),
                      a: const TextStyle(color: KabukTheme.blueAccent),
                    ),
                    onTapLink: (text, href, title) {
                      if (href == null) return;
                      openUrlSmart(context, href, title: text.isNotEmpty ? text : null);
                    },
                  )
                : _RedditLinkText(
                    text: _cleanDescription(_stripStatsLine(article.description!)),
                    onSubredditTap: (sub) {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => ChannelView(
                            channel: sub,
                            sourceType: FeedSourceType.reddit,
                          ),
                        ),
                      );
                    },
                    onUserTap: (user) {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => ChannelView(
                            author: user,
                            sourceType: FeedSourceType.reddit,
                          ),
                        ),
                      );
                    },
                  ),
          ),

        // ── Content blocks (from reader mode) ─────────────────────────────
        if (_contentBlocks != null && _contentBlocks!.isNotEmpty)
          for (final block in _contentBlocks!)
            _renderContentBlock(context, block),

        // ── Loading indicator for lazy content fetch ──────────────────────
        if (_isFetchingContent)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(
              child: Column(
                children: [
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: KabukTheme.accentGreen,
                    ),
                  ),
                  SizedBox(height: 12),
                  Text(
                    'Loading full article…',
                    style: TextStyle(
                      color: KabukTheme.textTertiary,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),

        // ── Unified discussion (Nostr + Reddit + 4chan) ────────────────────
        _DiscussionSection(key: ValueKey(article.uri), article: article),

        // ── Next-article hint ─────────────────────────────────────────────
        // ── Swipe navigation hint ─────────────────────────────────────────
        Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.swipe_rounded,
                color: KabukTheme.textTertiary,
                size: 16,
              ),
              const SizedBox(width: 6),
              const Text(
                'Swipe left/right for more articles',
                style: TextStyle(
                  color: KabukTheme.textTertiary,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 48),
      ],
    );
  }

  /// Returns `true` if the text contains meaningful markdown syntax.
  static bool _hasMarkdown(String text) {
    // Only treat as markdown when signature patterns are present.
    return text.contains('\n\n') ||
        text.contains('**') ||
        text.contains('##') ||
        text.contains('* ') ||
        text.contains('- ') ||
        text.contains('> ') ||
        text.contains('`') ||
        RegExp(r'\[.+\]\(https?://').hasMatch(text);
  }

  /// Removes the trailing ⬆ score · 💬 count stats line from selftext.
  static String _stripStatsLine(String text) {
    return text
        .replaceAll(
          RegExp(r'\s*[·|]?\s*⬆\s*[\d,]+\s*([·|]\s*💬\s*[\d,]+)?\s*$'),
          '',
        )
        .trim();
  }

  bool _isVideoUrl(String? url) {
    if (url == null || url.isEmpty) return false;
    final lower = url.toLowerCase();
    return lower.contains('v.redd.it') ||
        lower.contains('youtube.com') ||
        lower.contains('youtu.be') ||
        lower.endsWith('.mp4') ||
        lower.endsWith('.webm') ||
        lower.endsWith('.gifv');
  }

  /// Whether this article has playable video content.
  bool _hasVideo(ArticleData article) {
    if (article.videoUrl != null && article.videoUrl!.isNotEmpty) return true;
    return _isVideoUrl(article.url);
  }

  /// The best video URL for playback.
  String _videoUrl(ArticleData article) {
    return article.videoUrl ?? article.url ?? '';
  }

  /// Returns true for Nostr or other internal URLs that have no external web page.
  bool _isInternalUrl(String url) {
    return url.startsWith('nostr:') ||
        url.startsWith('kabuk:') ||
        url.isEmpty;
  }

  /// Strips raw URLs from a title for clean display.
  String _cleanTitle(String title) {
    final cleaned = title
        .replaceAll(RegExp(r'https?://\S+'), '')
        .replaceAll(RegExp(r'\s{2,}'), ' ')
        .trim();
    return cleaned.isEmpty ? 'Nostr post' : cleaned;
  }

  /// Strips raw URLs and normalises whitespace in description text.
  String _cleanDescription(String text) {
    return text
        .replaceAll(RegExp(r'https?://\S+'), '')
        .replaceAll(RegExp(r'\s{2,}'), ' ')
        .trim();
  }

  /// Truncates a URL for compact display (shows domain only).
  String _truncateUrl(String url) {
    try {
      final uri = Uri.parse(url);
      return uri.host.replaceFirst('www.', '');
    } catch (_) {
      return url.length > 40 ? '${url.substring(0, 40)}…' : url;
    }
  }

  String _formatDate(DateTime date) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  /// Renders a single content block as a widget.
  Widget _renderContentBlock(BuildContext context, ContentBlockData block) {
    return switch (block.type) {
      BlockType.heading => Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(
            block.content ?? '',
            style: TextStyle(
              fontSize: switch (block.level) {
                1 => 22.0,
                2 => 18.0,
                _ => 16.0,
              },
              fontWeight: FontWeight.w700,
              color: KabukTheme.textPrimary,
            ),
          ),
        ),
      BlockType.text => Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: _hasMarkdown(block.content ?? '')
              ? MarkdownBody(
                  data: block.content ?? '',
                  styleSheet: MarkdownStyleSheet(
                    p: const TextStyle(
                      fontSize: 15,
                      height: 1.65,
                      color: KabukTheme.textPrimary,
                    ),
                    a: const TextStyle(color: KabukTheme.blueAccent),
                  ),
                  onTapLink: (text, href, title) {
                    if (href == null) return;
                    openUrlSmart(context, href,
                        title: text.isNotEmpty ? text : null);
                  },
                )
              : Text(
                  block.content ?? '',
                  style: const TextStyle(
                    fontSize: 15,
                    height: 1.65,
                    color: KabukTheme.textPrimary,
                  ),
                ),
        ),
      BlockType.image => Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (block.mediaUri != null)
                GestureDetector(
                  onTap: () => FullscreenImageViewer.show(
                    context,
                    imageUrl: block.mediaUri!,
                    tag: 'block_img_${block.uri}',
                  ),
                  child: Hero(
                    tag: 'block_img_${block.uri}',
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: FeedImage(
                        imageUrl: block.mediaUri!,
                        height: 240,
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              if (block.caption != null && block.caption!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    block.caption!,
                    style: const TextStyle(
                      fontSize: 12,
                      color: KabukTheme.textTertiary,
                      fontStyle: FontStyle.italic,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
            ],
          ),
        ),
      BlockType.video => Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: block.mediaUri != null
              ? VideoThumbnail(
                  videoUrl: block.mediaUri!,
                  height: 240,
                  borderRadius: BorderRadius.circular(12),
                )
              : const SizedBox.shrink(),
        ),
      BlockType.quote => Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(
                  color: KabukTheme.textTertiary.withAlpha(120),
                  width: 3,
                ),
              ),
            ),
            child: Text(
              block.content ?? '',
              style: const TextStyle(
                fontSize: 14,
                height: 1.6,
                color: KabukTheme.textSecondary,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ),
      BlockType.code => Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1A),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              block.content ?? '',
              style: const TextStyle(
                fontSize: 13,
                fontFamily: 'monospace',
                color: KabukTheme.accentGreen,
              ),
            ),
          ),
        ),
      BlockType.divider => const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Divider(color: KabukTheme.textTertiary, height: 1),
        ),
      _ => const SizedBox.shrink(),
    };
  }
}

// =============================================================================
// Article OmniBar — Breadcrumb navigation bar
// =============================================================================

/// Breadcrumb-style AppBar for article detail pages.
///
/// Shows a left-to-right hierarchy from general to specific:
/// `Source › Channel › Author › Title` — each segment is tappable and
/// navigates to that context in Explore.
class _ArticleOmniBar extends ConsumerWidget implements PreferredSizeWidget {
  const _ArticleOmniBar({
    required this.article,
    required this.onBack,
  });

  final ArticleData article;
  final VoidCallback onBack;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  // ── Source detection ──────────────────────────────────────────────────

  bool get _isReddit {
    final source = article.feedSource ?? '';
    return source.contains('reddit') ||
        (article.url ?? '').contains('reddit.com');
  }

  bool get _isFourchan {
    final source = article.feedSource ?? '';
    return source.contains('4chan') ||
        (article.url ?? '').contains('4chan.org') ||
        (article.url ?? '').contains('4channel.org');
  }

  bool get _isNostr {
    final source = article.feedSource ?? '';
    return source.contains('nostr') ||
        (article.url ?? '').startsWith('nostr:');
  }

  Color get _sourceColor {
    if (_isReddit) return KabukTheme.redditOrange;
    if (_isFourchan) return const Color(0xFF789922);
    if (_isNostr) return KabukTheme.nostrPurple;
    return KabukTheme.accentGreen;
  }

  IconData get _sourceIcon {
    if (_isReddit) return Icons.forum_rounded;
    if (_isFourchan) return Icons.tag_rounded;
    if (_isNostr) return Icons.bolt_rounded;
    return Icons.rss_feed_rounded;
  }

  String get _sourceName {
    if (_isReddit) return 'Reddit';
    if (_isFourchan) return '4chan';
    if (_isNostr) return 'Nostr';
    final url = article.url;
    if (url != null) {
      try {
        return Uri.parse(url).host.replaceFirst('www.', '');
      } catch (_) {}
    }
    return 'Feed';
  }

  String get _authorDisplay {
    final author = article.author;
    if (author == null) return '';
    if (_isReddit) {
      final name = author.startsWith('u/') ? author.substring(2) : author;
      return name;
    }
    if (RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(author)) {
      return '${author.substring(0, 8)}…';
    }
    return author;
  }

  /// The channel (subreddit, board, etc.) if known.
  String? get _channelDisplay {
    for (final tag in article.tags) {
      if (tag.startsWith('r/')) return tag;
    }
    if (_isFourchan) {
      final match = RegExp(r'/(\w+)/').firstMatch(article.url ?? '');
      if (match != null) return '/${match.group(1)}/';
    }
    return null;
  }

  String get _titleShort {
    final name = article.name;
    if (name == null || name.isEmpty) return '';
    final cleaned = name
        .replaceAll(RegExp(r'https?://\S+'), '')
        .replaceAll(RegExp(r'\s{2,}'), ' ')
        .trim();
    if (cleaned.length <= 28) return cleaned;
    return '${cleaned.substring(0, 26)}…';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final channel = _channelDisplay;
    final author = _authorDisplay;
    final title = _titleShort;
    const chevron = _BreadcrumbChevron();

    // Build breadcrumb segments: Source › Channel › Author › Title
    final segments = <Widget>[];

    // 1. Source (e.g. Reddit, Nostr, 4chan)
    segments.add(
      _BreadcrumbSegment(
        icon: _sourceIcon,
        label: _sourceName,
        color: _sourceColor,
        onTap: () {
          // Clear any browse session and pop back to main Explore feed.
          ref.read(browseSessionProvider.notifier).clear();
          Navigator.of(context).popUntil((route) => route.isFirst);
        },
      ),
    );

    // 2. Channel (e.g. r/technology, /g/)
    if (channel != null) {
      segments.add(chevron);
      segments.add(
        _BreadcrumbSegment(
          label: channel,
          color: _sourceColor.withAlpha(210),
          onTap: () {
            if (_isReddit) {
              final sub = channel.startsWith('r/')
                  ? channel.substring(2)
                  : channel;
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ChannelView(
                    channel: sub,
                    sourceType: FeedSourceType.reddit,
                  ),
                ),
              );
            } else if (_isFourchan) {
              final board = channel.replaceAll('/', '');
              ref
                  .read(browseSessionProvider.notifier)
                  .browse('4chan://$board', channel, 'fourchan');
              Navigator.of(context).popUntil((route) => route.isFirst);
            }
          },
        ),
      );
    }

    // 3. Author (e.g. u/kaan, @abcdef01…)
    if (author.isNotEmpty) {
      segments.add(chevron);
      segments.add(
        _BreadcrumbSegment(
          label: _isReddit ? 'u/$author' : author,
          color: KabukTheme.textSecondary,
          onTap: () {
            if (_isReddit) {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ChannelView(
                    author: author,
                    sourceType: FeedSourceType.reddit,
                  ),
                ),
              );
            } else if (_isNostr && article.author != null) {
              final pubkey = article.author!;
              if (RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(pubkey)) {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ProfileView(pubkey: pubkey),
                  ),
                );
              }
            }
          },
        ),
      );
    }

    // 4. Article title (truncated, not tappable — already here)
    if (title.isNotEmpty) {
      segments.add(chevron);
      segments.add(
        Flexible(
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 12,
              color: KabukTheme.textTertiary,
              fontWeight: FontWeight.w400,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );
    }

    return AppBar(
      backgroundColor: KabukTheme.background,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      leadingWidth: 36,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_rounded, size: 20),
        tooltip: 'Back to feed',
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(),
        onPressed: onBack,
      ),
      titleSpacing: 0,
      title: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: KabukTheme.surfaceVariant,
          borderRadius: BorderRadius.circular(17),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: segments,
        ),
      ),
    );
  }
}

/// A single tappable breadcrumb segment (icon + label).
class _BreadcrumbSegment extends StatelessWidget {
  const _BreadcrumbSegment({
    required this.label,
    required this.color,
    this.icon,
    this.onTap,
  });

  final IconData? icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 13, color: color),
              const SizedBox(width: 3),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

/// Chevron separator between breadcrumb segments.
class _BreadcrumbChevron extends StatelessWidget {
  const _BreadcrumbChevron();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 3),
      child: Icon(
        Icons.chevron_right_rounded,
        size: 14,
        color: KabukTheme.textTertiary,
      ),
    );
  }
}

// =============================================================================
// Reddit Link Text
// =============================================================================

/// Renders plain text with tappable `r/subreddit` and `u/user` links.
///
/// Matches patterns like `r/flutter`, `/r/flutter`, `u/username`, `/u/username`
/// and renders them as tappable spans in an otherwise unstyled paragraph.
class _RedditLinkText extends StatelessWidget {
  const _RedditLinkText({
    required this.text,
    required this.onSubredditTap,
    required this.onUserTap,
  });

  final String text;
  final void Function(String subredditName) onSubredditTap;
  final void Function(String username) onUserTap;

  static final _pattern = RegExp(r'/?([ru])/(\w+)', caseSensitive: false);

  @override
  Widget build(BuildContext context) {
    final spans = <InlineSpan>[];
    int cursor = 0;

    for (final match in _pattern.allMatches(text)) {
      if (match.start > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, match.start)));
      }
      final type = match.group(1)!.toLowerCase(); // 'r' or 'u'
      final name = match.group(2)!;
      final label = '${type == 'r' ? 'r' : 'u'}/$name';
      final color = type == 'r'
          ? KabukTheme.redditOrange
          : KabukTheme.blueAccent;

      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          child: GestureDetector(
            onTap: () => type == 'r' ? onSubredditTap(name) : onUserTap(name),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 15,
                height: 1.65,
                color: color,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      );

      cursor = match.end;
    }

    if (cursor < text.length) {
      spans.add(TextSpan(text: text.substring(cursor)));
    }

    return Text.rich(
      TextSpan(
        children: spans,
        style: const TextStyle(
          fontSize: 15,
          height: 1.65,
          color: KabukTheme.textPrimary,
        ),
      ),
    );
  }
}

// =============================================================================
// Unified Discussion Section
// =============================================================================

/// Source of a comment in the unified discussion stream.
enum _CommentSource { nostr, reddit, fourchan }

/// A normalised comment from any source, ready for unified rendering.
class _UnifiedComment {
  const _UnifiedComment({
    required this.id,
    required this.displayAuthor,
    required this.content,
    required this.timestamp,
    required this.source,
    this.score,
    this.authorPicture,
    this.isPending = false,
    this.redditReplies = const [],
    this.depth = 0,
  });

  final String id;
  final String displayAuthor;
  final String content;
  final DateTime timestamp;
  final _CommentSource source;
  final int? score;
  final String? authorPicture;
  final bool isPending;
  final List<RedditComment> redditReplies; // only for Reddit top-level
  final int depth;

  static _UnifiedComment fromNostr(NostrComment c) => _UnifiedComment(
    id: c.eventId,
    displayAuthor: c.authorName ?? '${c.pubkey.substring(0, 8)}…',
    content: c.content,
    timestamp: c.createdAt,
    source: _CommentSource.nostr,
    authorPicture: c.authorPicture,
    isPending: c.isPending,
  );

  static _UnifiedComment fromReddit(RedditComment c) => _UnifiedComment(
    id: c.id,
    displayAuthor: 'u/${c.author}',
    content: c.body,
    timestamp: c.createdUtc,
    source: _CommentSource.reddit,
    score: c.score,
    redditReplies: c.replies,
    depth: c.depth,
  );

  static _UnifiedComment fromFourchan(FourchanPost p) => _UnifiedComment(
    id: '4ch-${p.no}',
    displayAuthor: p.author,
    content: p.content,
    timestamp: p.createdAt,
    source: _CommentSource.fourchan,
  );
}

/// A unified multi-source discussion section.
///
/// Merges Nostr comments, Reddit comments (for Reddit posts), and 4chan
/// replies (for 4chan posts) into a single chronological stream.
/// Each comment is badged with its source icon.
class _DiscussionSection extends ConsumerStatefulWidget {
  const _DiscussionSection({super.key, required this.article});

  final ArticleData article;

  @override
  ConsumerState<_DiscussionSection> createState() =>
      _DiscussionSectionState();
}

class _DiscussionSectionState extends ConsumerState<_DiscussionSection> {
  bool _expanded = false;
  final _commentFocusNode = FocusNode();

  @override
  void dispose() {
    _commentFocusNode.dispose();
    super.dispose();
  }

  void _focusCommentInput() {
    setState(() => _expanded = true);
    _commentFocusNode.requestFocus();
    ref.read(keyboardModeProvider.notifier).state = KeyboardMode.text;
  }

  @override
  Widget build(BuildContext context) {
    final article = widget.article;
    final url = article.url;
    if (url == null || url.isEmpty) return const SizedBox.shrink();

    final isReddit =
        url.contains('reddit.com') ||
        (article.feedSource ?? '').contains('reddit');
    final isFourchan =
        url.contains('4chan.org') || url.contains('4channel.org');

    // Watch all relevant providers.
    final statsAsync = ref.watch(nostrSocialStatsForUrlProvider(url));
    final nostrAsync = ref.watch(nostrCommentsForUrlProvider(url));
    final redditAsync = isReddit
        ? ref.watch(redditCommentsProvider(url))
        : null;
    final fourchanAsync = isFourchan
        ? ref.watch(fourchanCommentsProvider(url))
        : null;

    // Merge available data into a unified list.
    final nostrList = nostrAsync.valueOrNull ?? [];
    final redditList = redditAsync?.valueOrNull ?? [];
    final fourchanList = fourchanAsync?.valueOrNull ?? [];

    final unified = <_UnifiedComment>[
      ...nostrList.map(_UnifiedComment.fromNostr),
      ...redditList.map(_UnifiedComment.fromReddit),
      ...fourchanList.map(_UnifiedComment.fromFourchan),
    ]..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    final isLoading =
        nostrAsync.isLoading ||
        (redditAsync?.isLoading ?? false) ||
        (fourchanAsync?.isLoading ?? false);

    final hasError =
        nostrAsync.hasError ||
        (redditAsync?.hasError ?? false) ||
        (fourchanAsync?.hasError ?? false);

    final stats = statsAsync.valueOrNull ?? const NostrSocialStats();
    // Parse Reddit post-level stats from description for merging.
    final redditUpvotes = _parseRedditStat(article.description, r'⬆\s*([\d,]+)');
    final redditComments = _parseRedditStat(article.description, r'💬\s*([\d,]+)');
    final mergedReactCount = stats.reactionCount + (redditUpvotes ?? 0);
    final mergedReplyCount = stats.replyCount + (redditComments ?? 0);

    final hasActivity = unified.isNotEmpty ||
        mergedReactCount > 0 ||
        mergedReplyCount > 0 ||
        stats.repostCount > 0;

    final showComments = hasActivity || _expanded || isLoading;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),

        // ── Engagement stats bar (always visible) ──────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
          child: statsAsync.when(
            skipLoadingOnRefresh: true,
            data: (s) => _buildStatsBar(
              context, ref, url, s,
              redditUpvotes: redditUpvotes,
              redditComments: redditComments,
            ),
            loading: () => _buildStatsBar(
              context, ref, url, const NostrSocialStats(),
              redditUpvotes: redditUpvotes,
              redditComments: redditComments,
            ),
            error: (e, _) => _buildStatsBar(
              context, ref, url, const NostrSocialStats(),
              redditUpvotes: redditUpvotes,
              redditComments: redditComments,
            ),
          ),
        ),

        // ── Collapsed "Add a comment" when no activity ─────────────────────
        if (!showComments)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: GestureDetector(
              onTap: _focusCommentInput,
              child: Row(
                children: [
                  Icon(
                    Icons.add_comment_rounded,
                    size: 16,
                    color: KabukTheme.textTertiary.withAlpha(180),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Add a comment',
                    style: TextStyle(
                      fontSize: 13,
                      color: KabukTheme.textTertiary.withAlpha(180),
                    ),
                  ),
                ],
              ),
            ),
          ),

        // ── Full discussion section ────────────────────────────────────────
        if (showComments) ...[

        // ── Discussion header ──────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Row(
            children: [
              Text(
                '${unified.isNotEmpty ? unified.length : ''} '
                    'Comment${unified.length != 1 ? 's' : ''}',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: KabukTheme.textSecondary,
                ),
              ),
              const SizedBox(width: 6),
              // Source badges.
              const _SourceBadge(source: _CommentSource.nostr),
              if (isReddit) ...[
                const SizedBox(width: 4),
                const _SourceBadge(source: _CommentSource.reddit),
              ],
              if (isFourchan) ...[
                const SizedBox(width: 4),
                const _SourceBadge(source: _CommentSource.fourchan),
              ],
              const Spacer(),
              if (isLoading)
                const Padding(
                  padding: EdgeInsets.only(right: 8),
                  child: SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 1.5),
                  ),
                ),
              Semantics(
                label: 'Refresh comments',
                button: true,
                child: GestureDetector(
                  onTap: () {
                    refreshNostrSocial(ref, url);
                    if (isReddit) ref.invalidate(redditCommentsProvider(url));
                    if (isFourchan) {
                      ref.invalidate(fourchanCommentsProvider(url));
                    }
                  },
                  child: const Icon(
                    Icons.refresh_rounded,
                    size: 18,
                    color: KabukTheme.textTertiary,
                    semanticLabel: '',
                  ),
                ),
              ),
            ],
          ),
        ),

        // ── Nostr comment input ────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: _CommentInput(url: url, focusNode: _commentFocusNode),
        ),

        // ── Merged comment list ────────────────────────────────────────────
        if (unified.isEmpty && !isLoading && hasError)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Column(
              children: [
                const Icon(
                  Icons.cloud_off_rounded,
                  size: 32,
                  color: KabukTheme.textTertiary,
                ),
                const SizedBox(height: 8),
                const Text(
                  "Couldn't load comments",
                  style: TextStyle(
                    fontSize: 13,
                    color: KabukTheme.textTertiary,
                    fontStyle: FontStyle.italic,
                  ),
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: () {
                    refreshNostrSocial(ref, url);
                    if (isReddit) ref.invalidate(redditCommentsProvider(url));
                    if (isFourchan) {
                      ref.invalidate(fourchanCommentsProvider(url));
                    }
                  },
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: const Text('Try again'),
                ),
              ],
            ),
          )
        else if (unified.isEmpty && !isLoading)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Text(
              'No comments yet — be the first!',
              style: TextStyle(
                fontSize: 13,
                color: KabukTheme.textTertiary,
                fontStyle: FontStyle.italic,
              ),
            ),
          )
        else
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ...unified
                  .take(100)
                  .map((c) => _UnifiedCommentTile(comment: c)),
              if (unified.length > 100)
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
                  child: Text(
                    'Showing 100 of ${unified.length} comments',
                    style: const TextStyle(
                      fontSize: 12,
                      color: KabukTheme.textTertiary,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
            ],
          ),

        ], // end showComments
      ],
    );
  }

  Widget _buildStatsBar(
    BuildContext context,
    WidgetRef ref,
    String url,
    NostrSocialStats stats, {
    int? redditUpvotes,
    int? redditComments,
  }) {
    final mergedReacts = stats.reactionCount + (redditUpvotes ?? 0);
    final mergedReplies = stats.replyCount + (redditComments ?? 0);
    return Row(
      children: [
        _statChip(
          label: 'React',
          icon: stats.userReacted
              ? Icons.favorite_rounded
              : Icons.favorite_border_rounded,
          count: mergedReacts,
          active: stats.userReacted,
          activeColor: const Color(0xFFE91E63),
          onTap: () => reactToUrl(ref, url: url),
        ),
        const SizedBox(width: 16),
        _statChip(
          label: 'Reply',
          icon: Icons.chat_bubble_outline_rounded,
          count: mergedReplies,
          active: false,
          activeColor: KabukTheme.blueAccent,
          onTap: _focusCommentInput,
        ),
        const SizedBox(width: 16),
        _statChip(
          label: 'Repost',
          icon: stats.userReposted
              ? Icons.repeat_on_rounded
              : Icons.repeat_rounded,
          count: stats.repostCount,
          active: stats.userReposted,
          activeColor: KabukTheme.accentGreen,
          onTap: () => repostUrl(ref, url: url),
        ),
        const Spacer(),
        _BookmarkButton(
          article: widget.article,
          url: url,
        ),
        const SizedBox(width: 12),
        IconButton(
          icon: const Icon(Icons.share_outlined, size: 18),
          color: KabukTheme.textTertiary,
          onPressed: () {
            Clipboard.setData(ClipboardData(text: url));
            HapticFeedback.lightImpact();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Link copied'),
                duration: Duration(seconds: 2),
              ),
            );
          },
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
        ),
      ],
    );
  }

  Widget _statChip({
    required String label,
    required IconData icon,
    required int count,
    required bool active,
    required Color activeColor,
    required VoidCallback onTap,
  }) {
    final color = active ? activeColor : KabukTheme.textTertiary;
    return Semantics(
      label: count > 0 ? '$label $count' : label,
      button: true,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: color),
            if (count > 0) ...[
              const SizedBox(width: 4),
              Text(
                _fmtCount(count),
                style: TextStyle(fontSize: 13, color: color),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _fmtCount(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}k';
    return n.toString();
  }

  /// Parses a numeric stat from the article description using a regex.
  static int? _parseRedditStat(String? description, String pattern) {
    if (description == null) return null;
    final match = RegExp(pattern).firstMatch(description);
    if (match == null) return null;
    return int.tryParse(match.group(1)!.replaceAll(',', ''));
  }
}

// =============================================================================
// Bookmark button (detail page)
// =============================================================================

/// Bookmark toggle button that reflects saved state in the knowledge store.
class _BookmarkButton extends ConsumerWidget {
  const _BookmarkButton({required this.article, required this.url});

  final ArticleData article;
  final String url;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookmarkAsync = ref.watch(bookmarkStatusProvider(url));
    final isBookmarked =
        bookmarkAsync.whenOrNull(data: (uri) => uri != null) ?? false;

    return IconButton(
      icon: Icon(
        isBookmarked ? Icons.bookmark_rounded : Icons.bookmark_outlined,
        size: 18,
      ),
      color: isBookmarked ? KabukTheme.warmAccent : KabukTheme.textTertiary,
      onPressed: () => _toggleBookmark(context, ref),
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(),
    );
  }

  Future<void> _toggleBookmark(BuildContext context, WidgetRef ref) async {
    unawaited(HapticFeedback.mediumImpact());
    final store = ref.read(knowledgeStoreProvider);

    final existing = await store.listBookmarks();
    final match = existing.where((b) => b.url == url).firstOrNull;

    if (match != null) {
      await store.deleteBookmark(match.uri);
      ref.invalidate(bookmarkStatusProvider(url));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Bookmark removed'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } else {
      await store.createBookmark(
        name: article.name ?? url,
        url: url,
        description: article.description,
      );
      ref.invalidate(bookmarkStatusProvider(url));
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
}

// =============================================================================
// Source badge
// =============================================================================

/// A small coloured icon badge indicating the comment's origin.
class _SourceBadge extends StatelessWidget {
  const _SourceBadge({required this.source});

  final _CommentSource source;

  @override
  Widget build(BuildContext context) {
    final (icon, color, label) = switch (source) {
      _CommentSource.nostr => (
        Icons.bolt_rounded,
        KabukTheme.purpleAccent,
        'Nostr',
      ),
      _CommentSource.reddit => (
        Icons.reddit,
        KabukTheme.redditOrange,
        'Reddit',
      ),
      _CommentSource.fourchan => (
        Icons.grid_view_rounded,
        const Color(0xFF00B300),
        '4chan',
      ),
    };

    return Tooltip(
      message: label,
      child: Icon(icon, size: 13, color: color),
    );
  }
}

// =============================================================================
// Unified comment tile
// =============================================================================

/// Renders a single comment from any source with a source badge.
class _UnifiedCommentTile extends StatefulWidget {
  const _UnifiedCommentTile({required this.comment});

  final _UnifiedComment comment;

  @override
  State<_UnifiedCommentTile> createState() => _UnifiedCommentTileState();
}

class _UnifiedCommentTileState extends State<_UnifiedCommentTile> {
  bool _showReplies = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.comment;
    final hasReplies = c.redditReplies.isNotEmpty;
    final indent = c.depth * 16.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: EdgeInsets.only(left: 16 + indent),
          padding: const EdgeInsets.fromLTRB(0, 10, 16, 10),
          decoration: BoxDecoration(
            color: c.depth > 0
                ? KabukTheme.surfaceVariant.withAlpha(15)
                : null,
            border: c.depth > 0
                ? Border(
                    left: BorderSide(
                      color: _threadColor(c.depth),
                      width: 2,
                    ),
                  )
                : null,
          ),
          child: Padding(
            padding: EdgeInsets.only(left: c.depth > 0 ? 12 : 0),
            child: Opacity(
              opacity: c.isPending ? 0.6 : 1.0,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Avatar with source badge.
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      CircleAvatar(
                        radius: c.depth > 0 ? 12 : 16,
                        backgroundColor: _sourceColor(c.source).withAlpha(25),
                        backgroundImage: c.authorPicture != null
                            ? NetworkImage(c.authorPicture!)
                            : null,
                        child: c.authorPicture == null
                            ? Icon(
                                Icons.person_rounded,
                                size: c.depth > 0 ? 14 : 18,
                                color: _sourceColor(c.source).withAlpha(140),
                              )
                            : null,
                      ),
                      if (c.depth == 0)
                        Positioned(
                          bottom: -2,
                          right: -4,
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: const BoxDecoration(
                              color: KabukTheme.surface,
                              shape: BoxShape.circle,
                            ),
                            child: _SourceBadge(source: c.source),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                c.displayAuthor,
                                style: TextStyle(
                                  fontSize: c.depth > 0 ? 12 : 13,
                                  fontWeight: FontWeight.w600,
                                  color: _authorColor(c.source),
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 6),
                            if (c.isPending)
                              const SizedBox(
                                width: 10,
                                height: 10,
                                child: CircularProgressIndicator(
                                  strokeWidth: 1.5,
                                ),
                              )
                            else
                              Text(
                                _timeAgo(c.timestamp),
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: KabukTheme.textTertiary,
                                ),
                              ),
                            if (c.score != null) ...[
                              const Spacer(),
                              Icon(
                                Icons.arrow_upward_rounded,
                                size: 11,
                                color: _sourceColor(c.source).withAlpha(180),
                              ),
                              const SizedBox(width: 2),
                              Text(
                                _fmtScore(c.score!),
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: KabukTheme.textSecondary,
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          c.content,
                          style: TextStyle(
                            fontSize: c.depth > 0 ? 12.5 : 13,
                            height: 1.5,
                            color: KabukTheme.textPrimary,
                          ),
                          maxLines: c.depth > 1 ? 6 : 10,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (hasReplies) ...[
                          const SizedBox(height: 6),
                          GestureDetector(
                            onTap: () =>
                                setState(() => _showReplies = !_showReplies),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _showReplies
                                      ? Icons.expand_less_rounded
                                      : Icons.expand_more_rounded,
                                  size: 16,
                                  color: KabukTheme.blueAccent,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  _showReplies
                                      ? 'Hide replies'
                                      : '${c.redditReplies.length} '
                                            'repl${c.redditReplies.length == 1 ? 'y' : 'ies'}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: KabukTheme.blueAccent,
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
        // Nested replies with proper threading.
        if (_showReplies) ...[
          ...c.redditReplies
              .take(20)
              .map(
                (r) =>
                    _UnifiedCommentTile(comment: _UnifiedComment.fromReddit(r)),
              ),
          if (c.redditReplies.length > 20)
            _ShowMoreRepliesButton(
              comment: c,
              count: c.redditReplies.length - 20,
            ),
        ],
      ],
    );
  }

  static Color _threadColor(int depth) => switch (depth % 4) {
    0 => KabukTheme.blueAccent.withAlpha(80),
    1 => KabukTheme.purpleAccent.withAlpha(80),
    2 => KabukTheme.accentGreen.withAlpha(80),
    _ => KabukTheme.redditOrange.withAlpha(80),
  };

  static Color _sourceColor(_CommentSource source) => switch (source) {
    _CommentSource.nostr => KabukTheme.purpleAccent,
    _CommentSource.reddit => KabukTheme.redditOrange,
    _CommentSource.fourchan => const Color(0xFF00B300),
  };

  static Color _authorColor(_CommentSource source) => switch (source) {
    _CommentSource.nostr => KabukTheme.textSecondary,
    _CommentSource.reddit => KabukTheme.blueAccent,
    _CommentSource.fourchan => const Color(0xFF00B300),
  };

  static String _timeAgo(DateTime utc) {
    final diff = DateTime.now().toUtc().difference(utc);
    if (diff.inMinutes < 1) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';
    if (diff.inDays < 30) return '${diff.inDays ~/ 7}w';
    return '${diff.inDays ~/ 30}mo';
  }

  static String _fmtScore(int score) {
    if (score.abs() >= 1000) return '${(score / 1000).toStringAsFixed(1)}k';
    return score.toString();
  }
}

// =============================================================================
// Show more replies (expands hidden comments inline)
// =============================================================================

class _ShowMoreRepliesButton extends StatefulWidget {
  const _ShowMoreRepliesButton({required this.comment, required this.count});

  final _UnifiedComment comment;
  final int count;

  @override
  State<_ShowMoreRepliesButton> createState() => _ShowMoreRepliesButtonState();
}

class _ShowMoreRepliesButtonState extends State<_ShowMoreRepliesButton> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final indent = 16 + (widget.comment.depth + 1) * 16.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_expanded)
          ...widget.comment.redditReplies
              .skip(20)
              .map(
                (r) =>
                    _UnifiedCommentTile(comment: _UnifiedComment.fromReddit(r)),
              ),
        if (!_expanded)
          Padding(
            padding: EdgeInsets.only(left: indent),
            child: GestureDetector(
              onTap: () => setState(() => _expanded = true),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  'Show ${widget.count} more replies…',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: KabukTheme.blueAccent,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// =============================================================================
// Comment input (Nostr only)
// =============================================================================

class _CommentInput extends ConsumerStatefulWidget {
  const _CommentInput({required this.url, this.focusNode});

  final String url;

  /// Optional external focus node (e.g. from Reply button).
  final FocusNode? focusNode;

  @override
  ConsumerState<_CommentInput> createState() => _CommentInputState();
}

class _CommentInputState extends ConsumerState<_CommentInput> {
  final _controller = TextEditingController();
  late final FocusNode _focusNode;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _focusNode = widget.focusNode ?? FocusNode();
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _controller.dispose();
    // Only dispose if we created it ourselves.
    if (widget.focusNode == null) _focusNode.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (_focusNode.hasFocus) {
      // Auto-open custom keyboard when comment input gets focus.
      ref.read(keyboardModeProvider.notifier).state = KeyboardMode.text;
    }
  }

  Future<void> _submit() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    setState(() => _sending = true);
    final success = await commentOnUrl(ref, url: widget.url, content: text);
    if (mounted) {
      setState(() => _sending = false);
      if (success) {
        _controller.clear();
        _focusNode.unfocus();
        ref.read(keyboardModeProvider.notifier).state = KeyboardMode.none;
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

  @override
  Widget build(BuildContext context) {
    return KabukKeyboard(
      controller: _controller,
      focusNode: _focusNode,
      enabled: !_sending,
      maxLines: 3,
      hintText: 'Write a comment\u2026',
      onSend: _submit,
      onSubmitted: (_) => _submit(),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Gallery Carousel for Article Detail
// ═══════════════════════════════════════════════════════════════════════════════

/// Swipeable gallery carousel for the article detail page.
///
/// Shows all images with a page counter and dot indicators.
/// Tapping an image opens it in the fullscreen viewer.
class _DetailGalleryCarousel extends StatefulWidget {
  const _DetailGalleryCarousel({
    required this.images,
    required this.articleUri,
  });

  final List<String> images;
  final String articleUri;

  @override
  State<_DetailGalleryCarousel> createState() => _DetailGalleryCarouselState();
}

class _DetailGalleryCarouselState extends State<_DetailGalleryCarousel> {
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
      height: 300,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          children: [
            PageView.builder(
              controller: _controller,
              itemCount: widget.images.length,
              onPageChanged: (i) => setState(() => _current = i),
              itemBuilder: (context, i) {
                return GestureDetector(
                  onTap: () => FullscreenImageViewer.show(
                    context,
                    imageUrl: widget.images[i],
                    tag: 'gallery_${widget.articleUri}_$i',
                  ),
                  child: Hero(
                    tag: 'gallery_${widget.articleUri}_$i',
                    child: CachedNetworkImage(
                      imageUrl: widget.images[i],
                      cacheManager: KabukCacheManager.instance,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      fadeInDuration: const Duration(milliseconds: 300),
                      placeholder: (_, _) => Container(
                        color: KabukTheme.surfaceVariant,
                        child: const Center(
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: KabukTheme.textTertiary,
                          ),
                        ),
                      ),
                      errorWidget: (_, _, _) => Container(
                        color: KabukTheme.cardColor,
                        child: const Icon(
                          Icons.broken_image_outlined,
                          color: KabukTheme.textTertiary,
                          size: 32,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
            // Page counter pill.
            Positioned(
              top: 8,
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
            // Fullscreen hint icon.
            Positioned(
              top: 8,
              left: 8,
              child: Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: Colors.black.withAlpha(130),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.zoom_in_rounded,
                  color: Colors.white70,
                  size: 14,
                ),
              ),
            ),
            // Dot indicator row or compact counter.
            if (widget.images.length <= 15)
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
              )
            else
              Positioned(
                bottom: 8,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.black.withAlpha(160),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${_current + 1}/${widget.images.length}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
