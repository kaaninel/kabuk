/// 4chan feed source implementation.
///
/// Fetches threads from public 4chan boards using 4chan's read-only JSON API.
/// No authentication required. Does not support posting.
///
/// Supported URL formats:
/// - `4chan://g` — canonical Kabuk format
/// - `4chan:g`
/// - `https://boards.4chan.org/g/`
/// - `https://boards.4channel.org/g/`
library;

import 'dart:convert';
import 'dart:developer' as dev;

import 'package:kabuk/services/feed.dart';
import 'package:kabuk/services/mesh.dart';

/// [FeedSource] implementation for 4chan board catalogs.
///
/// Uses the public 4chan JSON API (`a.4cdn.org`) to fetch thread listings.
/// Images are served from `i.4cdn.org`.
class FourchanFeedSource implements FeedSource {
  /// Creates a [FourchanFeedSource].
  FourchanFeedSource({required MeshService mesh}) : _mesh = mesh;

  final MeshService _mesh;

  static const _apiBase = 'https://a.4cdn.org';
  static const _imgBase = 'https://i.4cdn.org';
  static const _boardBase = 'https://boards.4chan.org';
  static const _userAgent =
      'Mozilla/5.0 (compatible; Kabuk/1.0; +https://kabuk.app)';

  @override
  FeedSourceType get type => FeedSourceType.fourchan;

  @override
  Future<List<FeedItem>> fetch(String url) async {
    final board = _extractBoard(url);
    if (board == null) {
      throw FourchanException('Cannot extract board from URL: $url');
    }

    final uri = Uri.parse('$_apiBase/$board/catalog.json');

    try {
      final response = await _mesh.get(
        uri,
        headers: {'User-Agent': _userAgent, 'Accept': 'application/json'},
      );

      if (response.statusCode != 200) {
        throw FourchanException(
          'HTTP ${response.statusCode} fetching /$board/ catalog',
        );
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! List) {
        throw const FourchanException('Unexpected catalog format');
      }

      final items = <FeedItem>[];
      for (final page in decoded) {
        if (page is! Map<String, dynamic>) continue;
        final threads = page['threads'] as List<dynamic>? ?? [];
        for (final thread in threads) {
          if (thread is! Map<String, dynamic>) continue;
          final item = _parseThread(thread, board);
          if (item != null) items.add(item);
        }
      }
      return items;
    } on FourchanException {
      rethrow;
    } on Object catch (e) {
      dev.log('FourchanFeedSource.fetch error: $e', name: 'FourchanSource');
      throw FourchanException('Failed to fetch /$board/: $e');
    }
  }

  @override
  Future<bool> validate(String url) async {
    return _extractBoard(url) != null;
  }

  // ---------------------------------------------------------------------------
  // Thread parsing
  // ---------------------------------------------------------------------------

  FeedItem? _parseThread(Map<String, dynamic> t, String board) {
    final no = t['no'] as int?;
    if (no == null) return null;

    final sub = t['sub'] as String?; // thread subject
    final com = t['com'] as String? ?? ''; // OP comment (HTML)
    final name = t['name'] as String? ?? 'Anonymous';
    final time = t['time'] as int?;
    final tim = t['tim'] as int?; // image timestamp (used for CDN filename)
    final ext = t['ext'] as String?; // image extension
    final replies = t['replies'] as int? ?? 0;
    final images = t['images'] as int? ?? 0;

    final cleanCom = _stripHtml(com);

    // Use subject as title; fall back to first ~80 chars of OP text.
    final title = (sub != null && sub.isNotEmpty)
        ? _stripHtml(sub)
        : _truncate(cleanCom, 80);

    // Thumbnail URL (suffixed with 's' = small).
    final imageUrl = (tim != null && ext != null)
        ? '$_imgBase/$board/${tim}s.jpg'
        : null;

    final metaSuffix = replies > 0
        ? '  \n⬆ $replies replies · $images images'
        : '';

    return FeedItem(
      title: title.isNotEmpty ? title : '/$board/ Thread #$no',
      url: '$_boardBase/$board/thread/$no',
      description: cleanCom.isNotEmpty ? '$cleanCom$metaSuffix' : null,
      author: name,
      imageUrl: imageUrl,
      datePublished: time != null
          ? DateTime.fromMillisecondsSinceEpoch(time * 1000, isUtc: true)
          : null,
      identifier: '$board-$no',
      categories: ['/$board/'],
    );
  }

  // ---------------------------------------------------------------------------
  // URL helpers
  // ---------------------------------------------------------------------------

  /// Extracts the board name from a Kabuk or standard 4chan URL.
  ///
  /// Returns `null` if the board cannot be determined.
  static String? _extractBoard(String url) {
    final trimmed = url.trim();

    // Kabuk canonical formats.
    if (trimmed.startsWith('4chan://')) {
      final board = trimmed.substring('4chan://'.length).split('/').first;
      return board.isNotEmpty ? board : null;
    }
    if (trimmed.startsWith('4chan:')) {
      final board = trimmed.substring('4chan:'.length).split('/').first;
      return board.isNotEmpty ? board : null;
    }

    // Standard board URLs.
    final uri = Uri.tryParse(trimmed);
    if (uri == null) return null;

    if (uri.host.contains('4chan') || uri.host.contains('4channel')) {
      final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
      return segments.isNotEmpty ? segments.first : null;
    }

    return null;
  }

  // ---------------------------------------------------------------------------
  // HTML stripping (4chan uses HTML entities + <br> in API responses)
  // ---------------------------------------------------------------------------

  /// Strips HTML tags and decodes common HTML entities.
  static String _stripHtml(String html) {
    return html
        .replaceAll(RegExp(r'<br\s*/?>'), '\n')
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll('&gt;', '>')
        .replaceAll('&lt;', '<')
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#039;', "'")
        .replaceAll('&nbsp;', ' ')
        .trim();
  }

  static String _truncate(String text, int maxLen) {
    if (text.length <= maxLen) return text;
    return '${text.substring(0, maxLen)}…';
  }
}

/// Exception thrown by [FourchanFeedSource].
class FourchanException implements Exception {
  /// Creates a [FourchanException] with a descriptive [message].
  const FourchanException(this.message);

  /// The error message.
  final String message;

  @override
  String toString() => 'FourchanException: $message';
}
