/// Article detail bottom sheet — full article view with Nostr social section.
///
/// Contains [ArticleDetailSheet] and its private sub-widgets
/// [_SocialSection], [_CommentInput], and [_CommentTile].
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kabuk/knowledge/types/article.dart';
import 'package:kabuk/knowledge/types/nostr_social.dart';
import 'package:kabuk/ui/explore/nostr_providers.dart';
import 'package:kabuk/ui/shared/feed_image.dart';
import 'package:kabuk/ui/shared/video_thumbnail.dart';
import 'package:kabuk/ui/theme.dart';
import 'package:url_launcher/url_launcher.dart';

// =============================================================================
// Article Detail Sheet
// =============================================================================

/// Full article detail in a draggable bottom sheet.
class ArticleDetailSheet extends ConsumerWidget {
  /// Creates an [ArticleDetailSheet].
  const ArticleDetailSheet({required this.article, super.key});

  /// The article to display.
  final ArticleData article;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasImage = FeedImage.isValidImageUrl(article.image);
    final isVideo = _isVideoUrl(article.url);

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: KabukTheme.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Fixed drag handle + close button — always visible, never scrolls away.
              Padding(
                padding: const EdgeInsets.only(top: 8, left: 16, right: 4),
                child: Row(
                  children: [
                    const Spacer(),
                    Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: KabukTheme.textTertiary.withAlpha(80),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 22),
                      color: KabukTheme.textSecondary,
                      tooltip: 'Close',
                      onPressed: () => Navigator.of(context).pop(),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
              ),
              // Scrollable article content.
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: EdgeInsets.zero,
                  children: [
              // Media.
              if (isVideo)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: VideoThumbnail(
                    videoUrl: article.url ?? '',
                    thumbnailUrl: article.image,
                    height: 240,
                    borderRadius: BorderRadius.circular(12),
                  ),
                )
              else if (hasImage)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: FeedImage(
                    imageUrl: article.image!,
                    height: 240,
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              // Title.
              if (article.name != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Text(
                    article.name!,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      height: 1.3,
                    ),
                  ),
                ),
              // Meta row.
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
                      Text(
                        article.author!,
                        style: const TextStyle(
                          fontSize: 13,
                          color: KabukTheme.textSecondary,
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
              // Description / body.
              if (article.description != null &&
                  article.description!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Text(
                    article.description!,
                    style: const TextStyle(
                      fontSize: 14,
                      height: 1.6,
                      color: KabukTheme.textPrimary,
                    ),
                  ),
                ),
              // Tags.
              if (article.tags.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: article.tags.map((tag) {
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: KabukTheme.accentGreen.withAlpha(25),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          tag,
                          style: const TextStyle(
                            fontSize: 12,
                            color: KabukTheme.accentGreen,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              // Open in browser button.
              if (article.url != null)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final uri = Uri.tryParse(article.url!);
                      if (uri != null) {
                        await launchUrl(
                          uri,
                          mode: LaunchMode.externalApplication,
                        );
                      }
                    },
                    icon: const Icon(Icons.open_in_new_rounded, size: 18),
                    label: const Text('Open in Browser'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: KabukTheme.accentGreen,
                      side: const BorderSide(color: KabukTheme.accentGreen),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                    ),
                  ),
                ),
              // Social interaction bar + comments.
              _SocialSection(article: article),
              const SizedBox(height: 32),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
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

  String _formatDate(DateTime date) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }
}

// =============================================================================
// Social Section (inline comments + interactions)
// =============================================================================

/// Full social interaction section shown in the article detail sheet.
class _SocialSection extends ConsumerWidget {
  const _SocialSection({required this.article});

  final ArticleData article;

  /// Returns true if the article originates from Reddit.
  bool get _isReddit {
    final url = article.url ?? '';
    final feedSource = article.feedSource ?? '';
    return url.contains('reddit.com') ||
        url.contains('redd.it') ||
        feedSource.contains('reddit');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final url = article.url;
    if (url == null || url.isEmpty) return const SizedBox.shrink();

    final statsAsync = ref.watch(nostrSocialStatsForUrlProvider(url));
    final hasNostrThread = article.nostrEventId != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Nostr reaction bar — always shown for any content.
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: statsAsync.when(
            data: (stats) => _buildStatsBar(context, ref, stats),
            loading: () =>
                _buildStatsBar(context, ref, const NostrSocialStats()),
            error: (_, _) => const SizedBox.shrink(),
          ),
        ),

        // Reddit: show a "View on Reddit" button instead of empty comments.
        if (_isReddit)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: OutlinedButton.icon(
              onPressed: () async {
                final uri = Uri.tryParse(url);
                if (uri != null) await launchUrl(uri);
              },
              icon: const Icon(Icons.open_in_new_rounded, size: 16),
              label: const Text('View comments on Reddit'),
              style: OutlinedButton.styleFrom(
                foregroundColor: KabukTheme.warmAccent,
                side: BorderSide(
                  color: KabukTheme.warmAccent.withAlpha(100),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
              ),
            ),
          )

        // Articles with a Nostr event ID: show full threaded comments.
        else if (hasNostrThread) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Icon(
                  Icons.forum_rounded,
                  size: 18,
                  color: KabukTheme.purpleAccent.withAlpha(180),
                ),
                const SizedBox(width: 8),
                Text(
                  'Nostr Comments',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: KabukTheme.purpleAccent.withAlpha(200),
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () => refreshNostrSocial(ref, url),
                  child: const Icon(
                    Icons.refresh_rounded,
                    size: 18,
                    color: KabukTheme.textTertiary,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _CommentInput(url: url),
          ),
          ref.watch(nostrCommentsForUrlProvider(url)).when(
            data: (comments) => comments.isEmpty
                ? const Padding(
                    padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: Text(
                      'No comments yet — be the first!',
                      style: TextStyle(
                        fontSize: 13,
                        color: KabukTheme.textTertiary,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  )
                : Column(
                    children: comments
                        .take(20)
                        .map((c) => _CommentTile(comment: c))
                        .toList(),
                  ),
            loading: () => const Padding(
              padding: EdgeInsets.all(16),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
            error: (_, _) => const Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Text(
                'Could not load comments',
                style: TextStyle(fontSize: 13, color: KabukTheme.textTertiary),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildStatsBar(
    BuildContext context,
    WidgetRef ref,
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
          const SizedBox(width: 6),
          Text(
            'Nostr',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: KabukTheme.purpleAccent.withAlpha(180),
            ),
          ),
          const SizedBox(width: 12),
          _statChip(
            icon: stats.userReacted
                ? Icons.favorite_rounded
                : Icons.favorite_border_rounded,
            count: stats.reactionCount,
            active: stats.userReacted,
            activeColor: const Color(0xFFE91E63),
            onTap: () => _react(context, ref),
          ),
          const SizedBox(width: 8),
          _statChip(
            icon: Icons.chat_bubble_outline_rounded,
            count: stats.replyCount,
            active: false,
            activeColor: KabukTheme.blueAccent,
            onTap: () {},
          ),
          const SizedBox(width: 8),
          _statChip(
            icon: stats.userReposted
                ? Icons.repeat_on_rounded
                : Icons.repeat_rounded,
            count: stats.repostCount,
            active: stats.userReposted,
            activeColor: KabukTheme.accentGreen,
            onTap: () => _repost(context, ref),
          ),
        ],
      ),
    );
  }

  Widget _statChip({
    required IconData icon,
    required int count,
    required bool active,
    required Color activeColor,
    required VoidCallback onTap,
  }) {
    final color = active ? activeColor : KabukTheme.textTertiary;
    return GestureDetector(
      onTap: onTap,
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
    );
  }

  Future<void> _react(BuildContext context, WidgetRef ref) async {
    final url = article.url;
    if (url == null) return;
    await reactToUrl(ref, url: url);
  }

  Future<void> _repost(BuildContext context, WidgetRef ref) async {
    final url = article.url;
    if (url == null) return;
    await repostUrl(ref, url: url);
  }
}

/// Inline comment input field.
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
              hintText: 'Write a comment...',
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
                tooltip: 'Send comment',
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

/// A single comment tile showing author, time, and content.
class _CommentTile extends StatelessWidget {
  const _CommentTile({required this.comment});

  final NostrComment comment;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Opacity(
        opacity: comment.isPending ? 0.6 : 1.0,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: KabukTheme.purpleAccent.withAlpha(30),
              backgroundImage: comment.authorPicture != null
                  ? NetworkImage(comment.authorPicture!)
                  : null,
              child: comment.authorPicture == null
                  ? Icon(
                      Icons.person_rounded,
                      size: 18,
                      color: KabukTheme.purpleAccent.withAlpha(140),
                    )
                  : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        comment.authorName ??
                            '${comment.pubkey.substring(0, 8)}...',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: KabukTheme.textSecondary,
                        ),
                      ),
                      const SizedBox(width: 6),
                      if (comment.isPending)
                        const SizedBox(
                          width: 10,
                          height: 10,
                          child: CircularProgressIndicator(strokeWidth: 1.5),
                        )
                      else
                        Text(
                          _timeAgo(comment.createdAt),
                          style: const TextStyle(
                            fontSize: 11,
                            color: KabukTheme.textTertiary,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    comment.content,
                    style: const TextStyle(
                      fontSize: 14,
                      height: 1.4,
                      color: KabukTheme.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _timeAgo(DateTime date) {
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 1) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';
    if (diff.inDays < 30) return '${diff.inDays ~/ 7}w';
    return '${diff.inDays ~/ 30}mo';
  }
}
