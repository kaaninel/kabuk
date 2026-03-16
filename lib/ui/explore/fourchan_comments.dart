/// 4chan thread comment fetcher.
///
/// Fetches posts from a 4chan thread using the public JSON API.
/// No authentication required.
library;

import 'dart:convert';
import 'dart:developer' as dev;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kabuk/config/providers.dart';

// =============================================================================
// Data model
// =============================================================================

/// A single post in a 4chan thread.
class FourchanPost {
  /// Creates a [FourchanPost].
  const FourchanPost({
    required this.no,
    required this.author,
    required this.content,
    required this.createdAt,
    this.imageUrl,
  });

  /// Post number (unique within the board).
  final int no;

  /// Poster name (usually "Anonymous").
  final String author;

  /// Plain-text content (HTML tags stripped).
  final String content;

  /// When the post was submitted.
  final DateTime createdAt;

  /// Thumbnail URL (if the post includes an image).
  final String? imageUrl;
}

// =============================================================================
// Provider
// =============================================================================

/// Fetches all replies in a 4chan thread for the given post URL.
///
/// Accepts URLs in the form `https://boards.4chan.org/{board}/thread/{no}`.
/// Returns an empty list for non-4chan URLs or on network errors.
/// The OP post is excluded — it is already shown in the article detail header.
final fourchanCommentsProvider = FutureProvider.autoDispose
    .family<List<FourchanPost>, String>((ref, postUrl) async {
      final parsed = _parseBoardAndThread(postUrl);
      if (parsed == null) return [];

      final (board, threadNo) = parsed;
      final mesh = ref.read(meshServiceProvider);
      final apiUrl = 'https://a.4cdn.org/$board/thread/$threadNo.json';

      try {
        final response = await mesh.get(
          Uri.parse(apiUrl),
          headers: {
            'Accept': 'application/json',
            'User-Agent':
                'Mozilla/5.0 (compatible; Kabuk/1.0; +https://kabuk.app)',
          },
        );

        if (response.statusCode != 200) {
          dev.log(
            'Fourchan comments HTTP ${response.statusCode} for $apiUrl',
            name: 'FourchanComments',
          );
          return [];
        }

        final json = jsonDecode(response.body) as Map<String, dynamic>?;
        final posts = json?['posts'] as List<dynamic>? ?? [];

        return posts
            .whereType<Map<String, dynamic>>()
            .skip(1) // skip OP — already shown in article detail
            .map(_parsePost)
            .whereType<FourchanPost>()
            .toList();
      } on Object catch (e) {
        dev.log(
          'Failed to fetch 4chan comments for $postUrl: $e',
          name: 'FourchanComments',
        );
        return [];
      }
    });

// =============================================================================
// Parsing helpers
// =============================================================================

/// Extracts (board, threadNo) from a 4chan thread URL.
///
/// Supports:
/// - `https://boards.4chan.org/g/thread/12345`
/// - `https://boards.4channel.org/g/thread/12345`
(String board, String threadNo)? _parseBoardAndThread(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) return null;

  if (!uri.host.contains('4chan') && !uri.host.contains('4channel')) {
    return null;
  }

  // Path: /{board}/thread/{no}[/...]
  final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  if (segments.length < 3) return null;

  final board = segments[0];
  if (segments[1] != 'thread') return null;
  final threadNo = segments[2];

  return (board, threadNo);
}

FourchanPost? _parsePost(Map<String, dynamic> post) {
  final no = post['no'] as int?;
  if (no == null) return null;

  final com = post['com'] as String? ?? '';
  final name = post['name'] as String? ?? 'Anonymous';
  final time = post['time'] as int?;
  final tim = post['tim'] as int?;
  final ext = post['ext'] as String?;

  // Determine board from the thread's context (not available per-post, so
  // image URLs are reconstructed from the catalog thumbnail pattern elsewhere).
  // For in-thread posts we use the full image URL if available.
  final board =
      post['board'] as String?; // injected during enrichment when possible
  final imageUrl = (tim != null && ext != null && board != null)
      ? 'https://i.4cdn.org/$board/${tim}s.jpg'
      : null;

  return FourchanPost(
    no: no,
    author: name,
    content: _stripHtml(com),
    createdAt: time != null
        ? DateTime.fromMillisecondsSinceEpoch(time * 1000, isUtc: true)
        : DateTime.now().toUtc(),
    imageUrl: imageUrl,
  );
}

/// Strips HTML tags and decodes common HTML entities from 4chan API text.
String _stripHtml(String html) {
  return html
      .replaceAll(RegExp(r'<br\s*/?>'), '\n')
      .replaceAll(RegExp(r'<s>.*?</s>', dotAll: true), '[spoiler]')
      .replaceAll(RegExp(r'<[^>]+>'), '')
      .replaceAll('&gt;', '>')
      .replaceAll('&lt;', '<')
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('&#039;', "'")
      .replaceAll('&nbsp;', ' ')
      .trim();
}
