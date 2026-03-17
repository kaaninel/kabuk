/// Reddit comment thread fetcher and renderer.
///
/// Fetches comments using Reddit's public JSON API (no authentication required).
/// Appends `.json` to the post's permalink and parses the nested comment tree.
/// Renders inline inside the article detail page alongside Nostr comments.
library;

import 'dart:convert';
import 'dart:developer' as dev;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kabuk/config/providers.dart';
import 'package:kabuk/ui/explore/article_detail_page.dart' show ArticleDetailPage;
import 'package:kabuk/ui/theme.dart';

// =============================================================================
// Data model
// =============================================================================

/// Immutable representation of a single Reddit comment.
class RedditComment {
  /// Creates a [RedditComment].
  const RedditComment({
    required this.id,
    required this.author,
    required this.body,
    required this.score,
    required this.createdUtc,
    this.replies = const [],
    this.depth = 0,
  });

  /// Comment ID (e.g. `'abc123'`).
  final String id;

  /// Reddit username of the commenter.
  final String author;

  /// Raw text body of the comment (may contain markdown).
  final String body;

  /// Net vote score.
  final int score;

  /// UTC time the comment was created.
  final DateTime createdUtc;

  /// Nested reply comments (up to depth 3).
  final List<RedditComment> replies;

  /// Nesting depth — 0 = top-level.
  final int depth;
}

// =============================================================================
// Provider
// =============================================================================

/// Fetches Reddit comments for the given post URL.
///
/// Returns an empty list when:
/// - The URL is not a Reddit link.
/// - The network request fails.
/// - All comments are deleted/removed.
///
/// Uses the public Reddit JSON API — no API key required.
final redditCommentsProvider = FutureProvider.autoDispose
    .family<List<RedditComment>, String>((ref, postUrl) async {
      if (!postUrl.contains('reddit.com')) return [];

      final mesh = ref.read(meshServiceProvider);

      // Build the JSON API URL by appending .json to the post permalink.
      var jsonUrl = postUrl.trim();
      if (jsonUrl.endsWith('/')) {
        jsonUrl = jsonUrl.substring(0, jsonUrl.length - 1);
      }
      // Strip query params from the post URL so we control them.
      final qIdx = jsonUrl.indexOf('?');
      if (qIdx != -1) jsonUrl = jsonUrl.substring(0, qIdx);
      jsonUrl = '$jsonUrl.json?limit=100&raw_json=1';
      jsonUrl = jsonUrl.replaceAll('old.reddit.com', 'www.reddit.com');

      try {
        final response = await mesh.get(
          Uri.parse(jsonUrl),
          headers: {
            'Accept': 'application/json',
            'User-Agent':
                'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) '
                'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120 Safari/537.36',
          },
        );

        if (response.statusCode != 200) {
          dev.log(
            'Reddit comments HTTP ${response.statusCode} for $jsonUrl',
            name: 'RedditComments',
          );
          return [];
        }

        final json = jsonDecode(response.body);
        if (json is! List || json.length < 2) return [];

        // json[0] = post listing, json[1] = comment listing.
        final commentListing = json[1] as Map<String, dynamic>?;
        final data = commentListing?['data'] as Map<String, dynamic>?;
        final children = data?['children'] as List<dynamic>? ?? [];

        return _parseCommentList(children, depth: 0);
      } on Object catch (e) {
        dev.log(
          'Failed to fetch Reddit comments for $postUrl: $e',
          name: 'RedditComments',
        );
        return [];
      }
    });

// =============================================================================
// Parsing
// =============================================================================

List<RedditComment> _parseCommentList(
  List<dynamic> children, {
  required int depth,
}) {
  if (depth > 6) return [];

  final comments = <RedditComment>[];
  for (final child in children) {
    if (child is! Map<String, dynamic>) continue;
    final kind = child['kind'] as String?;
    if (kind != 't1') continue; // t1 = comment; skip "more" (kind: "more")

    final data = child['data'] as Map<String, dynamic>?;
    if (data == null) continue;

    final author = data['author'] as String?;
    final body = data['body'] as String?;
    if (author == null || body == null) continue;
    if (author == '[deleted]' || body == '[deleted]' || body == '[removed]') {
      continue;
    }

    // Parse nested replies.
    final repliesRaw = data['replies'];
    final replyComments = <RedditComment>[];
    if (repliesRaw is Map<String, dynamic>) {
      final repliesData = repliesRaw['data'] as Map<String, dynamic>?;
      final replyList = repliesData?['children'] as List<dynamic>? ?? [];
      replyComments.addAll(_parseCommentList(replyList, depth: depth + 1));
    }

    final createdUtc = data['created_utc'] as num?;
    comments.add(
      RedditComment(
        id: data['id'] as String? ?? '',
        author: author,
        body: body,
        score: data['score'] as int? ?? 0,
        createdUtc: createdUtc != null
            ? DateTime.fromMillisecondsSinceEpoch(
                (createdUtc * 1000).toInt(),
                isUtc: true,
              )
            : DateTime.now().toUtc(),
        replies: replyComments,
        depth: depth,
      ),
    );
  }
  return comments;
}

// =============================================================================
// Widget
// =============================================================================

/// Renders a Reddit comment thread inline.
///
/// Only shown for Reddit posts. Displayed below the Nostr section in
/// [ArticleDetailPage], giving users a unified comment experience.
class RedditCommentThread extends ConsumerWidget {
  /// Creates a [RedditCommentThread].
  const RedditCommentThread({required this.postUrl, super.key});

  /// The Reddit post URL (permalink, not the JSON endpoint).
  final String postUrl;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!postUrl.contains('reddit.com')) return const SizedBox.shrink();

    final commentsAsync = ref.watch(redditCommentsProvider(postUrl));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section header.
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
          child: Row(
            children: [
              const Icon(Icons.reddit, size: 18, color: KabukTheme.redditOrange),
              const SizedBox(width: 8),
              const Text(
                'Reddit Comments',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: KabukTheme.redditOrange,
                ),
              ),
              const Spacer(),
              Semantics(
                label: 'Refresh comments',
                button: true,
                child: GestureDetector(
                  onTap: () => ref.invalidate(redditCommentsProvider(postUrl)),
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
        // Comments / loading / error states.
        commentsAsync.when(
          data: (comments) {
            if (comments.isEmpty) {
              return const Padding(
                padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Text(
                  'No Reddit comments yet.',
                  style: TextStyle(
                    fontSize: 13,
                    color: KabukTheme.textTertiary,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: comments.take(20).map(_buildCommentTile).toList(),
            );
          },
          loading: () => const Padding(
            padding: EdgeInsets.all(16),
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: KabukTheme.redditOrange,
                ),
              ),
            ),
          ),
          error: (_, _) => const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Text(
              'Could not load Reddit comments.',
              style: TextStyle(fontSize: 13, color: KabukTheme.textTertiary),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCommentTile(RedditComment comment) =>
      _CommentTile(key: ValueKey(comment.id), comment: comment);
}

// =============================================================================
// Comment tile
// =============================================================================

/// A single Reddit comment with collapsible nested replies.
class _CommentTile extends StatefulWidget {
  const _CommentTile({required this.comment, super.key});

  final RedditComment comment;

  @override
  State<_CommentTile> createState() => _CommentTileState();
}

class _CommentTileState extends State<_CommentTile> {
  bool _showReplies = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.comment;
    final indent = c.depth * 14.0;
    final hasReplies = c.replies.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsetsDirectional.fromSTEB(16.0 + indent, 10, 16, 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Author row.
              Row(
                children: [
                  Text(
                    'u/${c.author}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: KabukTheme.blueAccent,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _timeAgo(c.createdUtc),
                    style: const TextStyle(
                      fontSize: 11,
                      color: KabukTheme.textTertiary,
                    ),
                  ),
                  const Spacer(),
                  const Icon(
                    Icons.arrow_upward_rounded,
                    size: 11,
                    color: KabukTheme.redditOrange,
                  ),
                  const SizedBox(width: 2),
                  Text(
                    _fmtScore(c.score),
                    style: const TextStyle(
                      fontSize: 11,
                      color: KabukTheme.textSecondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              // Comment body.
              Text(
                c.body,
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: KabukTheme.textPrimary,
                ),
                maxLines: 10,
                overflow: TextOverflow.ellipsis,
              ),
              // Replies toggle.
              if (hasReplies) ...[
                const SizedBox(height: 4),
                Semantics(
                  button: true,
                  label: _showReplies
                      ? 'Hide replies'
                      : '${c.replies.length} repl${c.replies.length == 1 ? 'y' : 'ies'}',
                  excludeSemantics: true,
                  child: GestureDetector(
                    onTap: () => setState(() => _showReplies = !_showReplies),
                    child: Text(
                      _showReplies
                          ? 'Hide replies'
                          : '${c.replies.length} repl${c.replies.length == 1 ? 'y' : 'ies'}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: KabukTheme.textTertiary,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        if (c.depth == 0)
          const Divider(
            height: 1,
            indent: 16,
            endIndent: 16,
            color: KabukTheme.divider,
          ),
        if (_showReplies)
          ...c.replies
              .take(5)
              .map((r) => _CommentTile(key: ValueKey(r.id), comment: r)),
      ],
    );
  }

  String _timeAgo(DateTime utc) {
    final diff = DateTime.now().toUtc().difference(utc);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 30) return '${diff.inDays}d ago';
    return '${diff.inDays ~/ 30}mo ago';
  }

  String _fmtScore(int score) {
    if (score.abs() >= 1000) return '${(score / 1000).toStringAsFixed(1)}k';
    return score.toString();
  }
}
