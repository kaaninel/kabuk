/// Full-screen article detail page.
///
/// Shows a single article with full content, Nostr social bar, and
/// discussion section. Slides up from the bottom; press back to return
/// to the feed.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kabuk/knowledge/types/article.dart';
import 'package:kabuk/knowledge/types/nostr_social.dart';
import 'package:kabuk/ui/explore/browse_session.dart';
import 'package:kabuk/ui/explore/explore_view.dart' show friendlyError;
import 'package:kabuk/ui/explore/fourchan_comments.dart';
import 'package:kabuk/ui/explore/nostr_providers.dart';
import 'package:kabuk/ui/explore/reddit_comments.dart';
import 'package:kabuk/ui/shared/feed_image.dart';
import 'package:kabuk/ui/shared/fullscreen_image_viewer.dart';
import 'package:kabuk/ui/shared/video_thumbnail.dart';
import 'package:kabuk/ui/theme.dart';
import 'package:url_launcher/url_launcher.dart';

// =============================================================================
// Route helper
// =============================================================================

/// Navigation helper — pushes [ArticleDetailPage] on the navigator.
///
/// Uses a slide-up transition for a smooth Reddit-like feel.
/// Returns the navigator's future so callers can react when the page is popped.
Future<void> pushArticleDetail(
  BuildContext context, {
  required ArticleData article,
}) {
  return Navigator.of(context).push(
    PageRouteBuilder<void>(
      pageBuilder: (context, animation, secondaryAnimation) =>
          ArticleDetailPage(article: article),
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
class ArticleDetailPage extends ConsumerWidget {
  /// Creates an [ArticleDetailPage].
  const ArticleDetailPage({required this.article, super.key});

  /// The article to display.
  final ArticleData article;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: KabukTheme.background,
      appBar: AppBar(
        backgroundColor: KabukTheme.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'Back to feed',
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: _ArticleDetailContent(
        article: article,
        onViewInBrowser: () {
          final url = article.url;
          if (url == null) return;
          final uri = Uri.tryParse(url);
          if (uri != null) {
            launchUrl(uri, mode: LaunchMode.externalApplication).ignore();
          }
        },
      ),
    );
  }
}

// =============================================================================
// Article Detail Content (single scrollable page)
// =============================================================================

/// Scrollable content for a single article in the [ArticleDetailPage].
class _ArticleDetailContent extends ConsumerWidget {
  const _ArticleDetailContent({
    required this.article,
    required this.onViewInBrowser,
  });

  final ArticleData article;
  final VoidCallback onViewInBrowser;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasImage = FeedImage.isValidImageUrl(article.image);
    final isVideo = _isVideoUrl(article.url);

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        // ── Media ──────────────────────────────────────────────────────────
        if (isVideo)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: VideoThumbnail(
              videoUrl: article.url ?? '',
              thumbnailUrl: article.image,
              height: 260,
              borderRadius: BorderRadius.circular(14),
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
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Hero(
                tag: 'article_img_${article.uri}',
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Stack(
                    children: [
                      FeedImage(
                        imageUrl: article.image!,
                        height: 260,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      // Zoom hint badge.
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Colors.black.withAlpha(130),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.zoom_in_rounded,
                            color: Colors.white70,
                            size: 16,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

        // ── Title ──────────────────────────────────────────────────────────
        if (article.name != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Text(
              _cleanTitle(article.name!),
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                height: 1.3,
                color: KabukTheme.textPrimary,
              ),
            ),
          ),

        // ── Meta row ───────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: Row(
            children: [
              if (article.author != null) ...[
                const Icon(
                  Icons.person_outline_rounded,
                  size: 14,
                  color: KabukTheme.textTertiary,
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: Semantics(
                    button: _isRedditArticle(article),
                    label: _isRedditArticle(article)
                        ? 'View profile of ${article.author!.startsWith('u/') ? article.author! : 'u/${article.author!}'}'
                        : null,
                    excludeSemantics: _isRedditArticle(article),
                    child: GestureDetector(
                      onTap: _isRedditArticle(article)
                          ? () => _openUserProfile(context, article.author!)
                          : null,
                      child: Text(
                        _isRedditArticle(article)
                            ? (article.author!.startsWith('u/')
                                ? article.author!
                                : 'u/${article.author!}')
                            : _formatAuthor(article.author!),
                        style: TextStyle(
                          fontSize: 13,
                          color: _isRedditArticle(article)
                              ? KabukTheme.blueAccent
                              : KabukTheme.textSecondary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
              ],
              if (article.datePublished != null) ...[
                const Icon(
                  Icons.schedule_rounded,
                  size: 14,
                  color: KabukTheme.textTertiary,
                ),
                const SizedBox(width: 4),
                Text(
                  _formatDate(article.datePublished!),
                  style: const TextStyle(
                    fontSize: 13,
                    color: KabukTheme.textSecondary,
                  ),
                ),
              ],
            ],
          ),
        ),

        // ── Description ────────────────────────────────────────────────────
        if (article.description != null && article.description!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
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
                      final uri = Uri.tryParse(href);
                      if (uri != null) {
                        launchUrl(uri, mode: LaunchMode.externalApplication);
                      }
                    },
                  )
                : _RedditLinkText(
                    text: _cleanDescription(article.description!),
                    onSubredditTap: (sub) {
                      // Navigate in-app to the subreddit rather than opening browser.
                      ref
                          .read(browseSessionProvider.notifier)
                          .browse('r/$sub', 'r/$sub', 'reddit');
                      Navigator.of(context).popUntil(
                        (route) => route.isFirst,
                      );
                    },
                    onUserTap: (user) {
                      final uri = Uri.tryParse(
                        'https://www.reddit.com/user/$user',
                      );
                      if (uri != null) {
                        launchUrl(
                          uri,
                          mode: LaunchMode.externalApplication,
                        ).ignore();
                      }
                    },
                  ),
          ),

        // ── Tags ───────────────────────────────────────────────────────────
        if (article.tags.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: article.tags.map((tag) {
                final isSubreddit = tag.startsWith('r/');
                return GestureDetector(
                  onTap: isSubreddit
                      ? () {
                          HapticFeedback.selectionClick();
                          // Navigate in-app rather than opening external browser.
                          final sub = tag.startsWith('r/') ? tag : 'r/$tag';
                          ref
                              .read(browseSessionProvider.notifier)
                              .browse(sub, sub, 'reddit');
                          Navigator.of(context).popUntil(
                            (route) => route.isFirst,
                          );
                        }
                      : null,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: isSubreddit
                          ? KabukTheme.redditOrange.withAlpha(20)
                          : KabukTheme.accentGreen.withAlpha(25),
                      borderRadius: BorderRadius.circular(12),
                      border: isSubreddit
                          ? Border.all(
                              color: KabukTheme.redditOrange.withAlpha(60),
                            )
                          : null,
                    ),
                    child: Text(
                      tag,
                      style: TextStyle(
                        fontSize: 12,
                        color: isSubreddit
                            ? KabukTheme.redditOrange
                            : KabukTheme.accentGreen,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),

        // ── Source link (external web/RSS only, not for Nostr/internal) ───
        if (article.url != null && !_isInternalUrl(article.url!))
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: GestureDetector(
              onTap: onViewInBrowser,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: KabukTheme.cardColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: KabukTheme.divider),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.open_in_new_rounded,
                      size: 12,
                      color: KabukTheme.textTertiary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _truncateUrl(article.url!),
                      style: const TextStyle(
                        fontSize: 12,
                        color: KabukTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

        // ── Unified discussion (Nostr + Reddit + 4chan) ────────────────────
        _DiscussionSection(article: article),

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
    if (url == null) return false;
    final lower = url.toLowerCase();
    return lower.contains('v.redd.it') ||
        lower.contains('youtube.com') ||
        lower.contains('youtu.be') ||
        lower.endsWith('.mp4') ||
        lower.endsWith('.webm');
  }

  /// Returns true for Nostr or other internal URLs that have no external web page.
  bool _isInternalUrl(String url) {
    return url.startsWith('nostr:') ||
        url.startsWith('kabuk:') ||
        url.isEmpty;
  }

  /// Formats an author for display — prefixes hex pubkeys with `@`.
  String _formatAuthor(String author) {
    if (author.startsWith('@')) return author; // already formatted
    // Strip trailing ellipsis before checking for hex pubkey pattern.
    final base = author.endsWith('…') ? author.substring(0, author.length - 1) : author;
    if (RegExp(r'^[0-9a-fA-F]{8,}$').hasMatch(base)) {
      return '@${base.length > 8 ? '${base.substring(0, 8)}…' : base}';
    }
    return author;
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

  bool _isRedditArticle(ArticleData article) {
    final source = article.feedSource ?? '';
    return source.contains('reddit') ||
        (article.url ?? '').contains('reddit.com');
  }

  void _openUserProfile(BuildContext context, String author) {
    final name = author.startsWith('u/') ? author.substring(2) : author;
    final uri = Uri.tryParse('https://www.reddit.com/user/$name');
    if (uri != null) {
      launchUrl(uri, mode: LaunchMode.externalApplication).ignore();
    }
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
  const _DiscussionSection({required this.article});

  final ArticleData article;

  @override
  ConsumerState<_DiscussionSection> createState() =>
      _DiscussionSectionState();
}

class _DiscussionSectionState extends ConsumerState<_DiscussionSection> {
  bool _expanded = false;

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
    final hasActivity = unified.isNotEmpty ||
        stats.reactionCount > 0 ||
        stats.repostCount > 0;

    // When no activity and not expanded, show collapsed "Add a comment" button.
    if (!hasActivity && !_expanded && !isLoading) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(height: 32, indent: 16, endIndent: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: GestureDetector(
              onTap: () => setState(() => _expanded = true),
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
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 32, indent: 16, endIndent: 16),

        // ── Nostr engagement stats bar ─────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
          child: statsAsync.when(
            data: (s) => _buildStatsBar(context, ref, url, s),
            loading: () =>
                _buildStatsBar(context, ref, url, const NostrSocialStats()),
            error: (e, _) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                friendlyError(e),
                style: const TextStyle(
                  color: KabukTheme.textTertiary,
                  fontSize: 12,
                ),
              ),
            ),
          ),
        ),

        // ── Discussion header ──────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
          child: Row(
            children: [
              const Icon(
                Icons.forum_rounded,
                size: 18,
                color: KabukTheme.textSecondary,
              ),
              const SizedBox(width: 8),
              const Text(
                'Discussion',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: KabukTheme.textSecondary,
                ),
              ),
              const SizedBox(width: 8),
              // Source badges in header.
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
          child: _CommentInput(url: url),
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
            children: unified
                .take(50)
                .map((c) => _UnifiedCommentTile(comment: c))
                .toList(),
          ),
      ],
    );
  }

  Widget _buildStatsBar(
    BuildContext context,
    WidgetRef ref,
    String url,
    NostrSocialStats stats,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: KabukTheme.purpleAccent.withAlpha(12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: KabukTheme.purpleAccent.withAlpha(30)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.bolt_rounded,
            size: 16,
            color: KabukTheme.purpleAccent.withAlpha(160),
          ),
          const SizedBox(width: 10),
          _statChip(
            label: 'React',
            icon: stats.userReacted
                ? Icons.favorite_rounded
                : Icons.favorite_border_rounded,
            count: stats.reactionCount,
            active: stats.userReacted,
            activeColor: const Color(0xFFE91E63),
            onTap: () => reactToUrl(ref, url: url),
          ),
          const SizedBox(width: 8),
          _statChip(
            label: 'Reply',
            icon: Icons.chat_bubble_outline_rounded,
            count: stats.replyCount,
            active: false,
            activeColor: KabukTheme.blueAccent,
            onTap: () {},
          ),
          const SizedBox(width: 8),
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
        ],
      ),
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
            Icon(icon, size: 16, color: color),
            if (count > 0) ...[
              const SizedBox(width: 3),
              Text(
                count.toString(),
                style: TextStyle(fontSize: 12, color: color),
              ),
            ],
          ],
        ),
      ),
    );
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: Opacity(
            opacity: c.isPending ? 0.6 : 1.0,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Avatar / source badge stack.
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: _sourceColor(c.source).withAlpha(25),
                      backgroundImage: c.authorPicture != null
                          ? NetworkImage(c.authorPicture!)
                          : null,
                      child: c.authorPicture == null
                          ? Icon(
                              Icons.person_rounded,
                              size: 18,
                              color: _sourceColor(c.source).withAlpha(140),
                            )
                          : null,
                    ),
                    // Source badge chip — bottom-right of avatar.
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
                          Text(
                            c.displayAuthor,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: _authorColor(c.source),
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
                      const SizedBox(height: 3),
                      Text(
                        c.content,
                        style: const TextStyle(
                          fontSize: 13,
                          height: 1.5,
                          color: KabukTheme.textPrimary,
                        ),
                        maxLines: 10,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (hasReplies) ...[
                        const SizedBox(height: 4),
                        GestureDetector(
                          onTap: () =>
                              setState(() => _showReplies = !_showReplies),
                          child: Text(
                            _showReplies
                                ? 'Hide replies'
                                : '${c.redditReplies.length} '
                                      'repl${c.redditReplies.length == 1 ? 'y' : 'ies'}',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: KabukTheme.textTertiary,
                            ),
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
        const Divider(
          height: 1,
          indent: 16,
          endIndent: 16,
          color: KabukTheme.divider,
        ),
        // Reddit nested replies (collapsed by default).
        if (_showReplies)
          ...c.redditReplies
              .take(5)
              .map(
                (r) =>
                    _UnifiedCommentTile(comment: _UnifiedComment.fromReddit(r)),
              ),
      ],
    );
  }

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
// Comment input (Nostr only)
// =============================================================================

class _CommentInput extends ConsumerStatefulWidget {
  const _CommentInput({required this.url});

  final String url;

  @override
  ConsumerState<_CommentInput> createState() => _CommentInputState();
}

class _CommentInputState extends ConsumerState<_CommentInput> {
  final _controller = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
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
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _controller,
            enabled: !_sending,
            maxLines: 1,
            style: const TextStyle(fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Write a comment…',
              hintStyle: const TextStyle(
                fontSize: 14,
                color: KabukTheme.textTertiary,
              ),
              filled: true,
              fillColor: KabukTheme.surfaceVariant,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 10,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(20),
                borderSide: BorderSide.none,
              ),
              isDense: true,
            ),
            onSubmitted: (_) => _submit(),
          ),
        ),
        const SizedBox(width: 8),
        _sending
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : IconButton(
                onPressed: _submit,
                tooltip: 'Publish Nostr comment',
                icon: const Icon(
                  Icons.send_rounded,
                  size: 18,
                  color: KabukTheme.purpleAccent,
                ),
                style: IconButton.styleFrom(
                  backgroundColor: KabukTheme.purpleAccent.withAlpha(30),
                  fixedSize: const Size(34, 34),
                  padding: EdgeInsets.zero,
                ),
              ),
      ],
    );
  }
}
