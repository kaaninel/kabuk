/// ContentPlugin adapter for 4chan boards.
///
/// Fetches thread listings from the public 4chan JSON API (`a.4cdn.org`)
/// and maps them into [ContentItem] objects. No authentication is
/// required — 4chan's API is read-only and public.
///
/// Supported URL patterns:
/// - `https://boards.4chan.org/{board}/`
/// - `https://boards.4channel.org/{board}/`
/// - `https://4chan.org/{board}/`
/// - Thread URLs: `…/{board}/thread/{no}`
library;

import 'dart:convert';

import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart' show IconData;
import 'package:kabuk/plugins/content_item.dart';
import 'package:kabuk/plugins/context.dart';
import 'package:kabuk/plugins/plugin.dart';

/// Content plugin that adapts 4chan board catalogs into [ContentItem]s.
///
/// Capabilities: [ContentCapability.channel] (fetch board catalogs) and
/// [ContentCapability.urlResolve] (parse board/thread URLs). Search and
/// trending are not supported by 4chan's API.
class FourchanPlugin implements ContentPlugin {
  /// Creates a [FourchanPlugin].
  FourchanPlugin();

  static const _apiBase = 'https://a.4cdn.org';
  static const _imgBase = 'https://i.4cdn.org';
  static const _boardBase = 'https://boards.4chan.org';

  /// Hosts recognised as 4chan domains.
  static const _knownHosts = [
    'boards.4chan.org',
    'boards.4channel.org',
    '4chan.org',
  ];

  /// Pattern matching a board URL: `/{board}/` or `/{board}`.
  static final _boardUrlPattern = RegExp(r'^/([a-zA-Z0-9]+)/?$');

  /// Pattern matching a thread URL: `/{board}/thread/{no}`.
  static final _threadUrlPattern = RegExp(r'^/([a-zA-Z0-9]+)/thread/(\d+)');

  // ---------------------------------------------------------------------------
  // Plugin metadata
  // ---------------------------------------------------------------------------

  @override
  String get id => 'fourchan';

  @override
  String get name => '4chan';

  @override
  String get description =>
      'Browse 4chan boards. Fetches thread catalogs from the public JSON API.';

  @override
  String get version => '1.0.0';

  @override
  IconData get iconData => Icons.image_outlined;

  @override
  PluginCategory get category => PluginCategory.social;

  @override
  Set<ContentCapability> get capabilities => const {
        ContentCapability.channel,
        ContentCapability.urlResolve,
      };

  @override
  List<PluginConfigField> get configFields => const [];

  @override
  bool hasCapability(ContentCapability capability) =>
      capabilities.contains(capability);

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  /// Late-bound context set in [initialize].
  PluginContext? _context;

  PluginContext get _ctx {
    final c = _context;
    if (c == null) {
      throw StateError('FourchanPlugin has not been initialised.');
    }
    return c;
  }

  @override
  Future<void> initialize(PluginContext context) async {
    _context = context;
    context.log('4chan plugin initialised');
  }

  @override
  Future<void> dispose() async {
    _context = null;
  }

  // ---------------------------------------------------------------------------
  // URL handling
  // ---------------------------------------------------------------------------

  @override
  bool canHandleUrl(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null) return false;
    return _knownHosts.any((h) => uri.host == h);
  }

  @override
  Future<ResolvedContent> resolveUrl(String url) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null) return const ResolvedNotHandled();

    if (!_knownHosts.any((h) => uri.host == h)) {
      return const ResolvedNotHandled();
    }

    final path = uri.path;

    // Thread URL → fetch the single OP post and return as content item.
    final threadMatch = _threadUrlPattern.firstMatch(path);
    if (threadMatch != null) {
      final board = threadMatch.group(1)!;
      final threadNo = threadMatch.group(2)!;
      return _resolveThread(board, int.parse(threadNo));
    }

    // Board URL → return a channel reference.
    final boardMatch = _boardUrlPattern.firstMatch(path);
    if (boardMatch != null) {
      final board = boardMatch.group(1)!;
      return ResolvedChannel(
        entityUri: '4chan://$board',
        title: '/$board/',
      );
    }

    return const ResolvedNotHandled();
  }

  // ---------------------------------------------------------------------------
  // Unsupported capabilities
  // ---------------------------------------------------------------------------

  @override
  Future<List<ContentItem>> search(
    String query, {
    int page = 0,
    int perPage = 20,
  }) {
    throw UnsupportedError('4chan does not provide a search API.');
  }

  @override
  Future<List<ContentItem>> fetchTrending({
    int page = 0,
    int perPage = 20,
  }) {
    throw UnsupportedError('4chan does not provide a trending API.');
  }

  // ---------------------------------------------------------------------------
  // Channel fetch (board catalog)
  // ---------------------------------------------------------------------------

  @override
  Future<List<ContentItem>> fetchChannel(
    String entityId, {
    int page = 0,
    int perPage = 20,
  }) async {
    final board = entityId.replaceAll('/', '');
    final uri = Uri.parse('$_apiBase/$board/catalog.json');

    try {
      final response = await _ctx.httpClient.get(uri);

      if (response.statusCode != 200) {
        _ctx.log(
          'Failed to fetch /$board/ catalog',
          error: 'HTTP ${response.statusCode}',
        );
        return const [];
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! List) {
        _ctx.log('Unexpected catalog format for /$board/');
        return const [];
      }

      final items = <ContentItem>[];
      for (final catalogPage in decoded) {
        if (catalogPage is! Map<String, dynamic>) continue;
        final threads = catalogPage['threads'] as List<dynamic>? ?? [];
        for (final thread in threads) {
          if (thread is! Map<String, dynamic>) continue;
          final item = _parseThread(thread, board);
          if (item != null) items.add(item);
        }
      }

      // Apply simple pagination on the collected list.
      final start = page * perPage;
      if (start >= items.length) return const [];
      return items.sublist(start, (start + perPage).clamp(0, items.length));
    } on Object catch (e) {
      _ctx.log('Error fetching /$board/ catalog', error: e.toString());
      return const [];
    }
  }

  // ---------------------------------------------------------------------------
  // Thread resolution
  // ---------------------------------------------------------------------------

  /// Fetches a single thread's OP and returns it as a [ResolvedContentItem].
  Future<ResolvedContent> _resolveThread(String board, int threadNo) async {
    final uri = Uri.parse('$_apiBase/$board/thread/$threadNo.json');

    try {
      final response = await _ctx.httpClient.get(uri);

      if (response.statusCode != 200) {
        _ctx.log(
          'Failed to fetch thread $threadNo on /$board/',
          error: 'HTTP ${response.statusCode}',
        );
        return const ResolvedNotHandled();
      }

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final posts = decoded['posts'] as List<dynamic>? ?? [];
      if (posts.isEmpty) return const ResolvedNotHandled();

      final op = posts.first as Map<String, dynamic>;
      final item = _parseThread(op, board);
      if (item == null) return const ResolvedNotHandled();
      return ResolvedContentItem(item);
    } on Object catch (e) {
      _ctx.log(
        'Error resolving thread $threadNo on /$board/',
        error: e.toString(),
      );
      return const ResolvedNotHandled();
    }
  }

  // ---------------------------------------------------------------------------
  // Thread parsing
  // ---------------------------------------------------------------------------

  /// Converts a 4chan thread JSON object to a [ContentItem].
  ///
  /// Returns `null` if the thread lacks a post number.
  ContentItem? _parseThread(Map<String, dynamic> t, String board) {
    final no = t['no'] as int?;
    if (no == null) return null;

    final sub = t['sub'] as String?;
    final com = t['com'] as String? ?? '';
    final posterName = t['name'] as String? ?? 'Anonymous';
    final time = t['time'] as int?;
    final tim = t['tim'] as int?;
    final ext = t['ext'] as String?;
    final replies = t['replies'] as int? ?? 0;
    final images = t['images'] as int? ?? 0;
    final fsize = t['fsize'] as int?;
    final imgWidth = t['w'] as int?;
    final imgHeight = t['h'] as int?;

    final cleanComment = _stripHtml(com);

    final title = (sub != null && sub.isNotEmpty)
        ? _stripHtml(sub)
        : _truncate(cleanComment, 80);

    final thumbnailUrl =
        (tim != null && ext != null) ? '$_imgBase/$board/${tim}s.jpg' : null;

    final fullImageUrl =
        (tim != null && ext != null) ? '$_imgBase/$board/$tim$ext' : null;

    // Image-focused threads: have an image and no subject (the image IS the
    // content), or the board is primarily an image board with large files.
    final hasImage = tim != null && ext != null;
    final isImageFocused =
        hasImage && (sub == null || sub.isEmpty) && (fsize ?? 0) > 0;

    final contentType =
        isImageFocused ? ContentType.image : ContentType.article;

    final ContentMeta? meta;
    if (contentType == ContentType.image) {
      meta = ImageMeta(
        width: imgWidth,
        height: imgHeight,
        galleryUrls: fullImageUrl != null ? [fullImageUrl] : const [],
      );
    } else {
      meta = ArticleMeta(
        body: cleanComment.isNotEmpty ? cleanComment : null,
        bodyHtml: com.isNotEmpty ? com : null,
      );
    }

    return ContentItem(
      sourcePluginId: id,
      externalId: '$board-$no',
      contentType: contentType,
      title: title.isNotEmpty ? title : '/$board/ Thread #$no',
      description: cleanComment.isNotEmpty ? cleanComment : null,
      url: '$_boardBase/$board/thread/$no',
      thumbnailUrl: thumbnailUrl,
      author: ContentAuthor(name: posterName),
      publishedAt: time != null
          ? DateTime.fromMillisecondsSinceEpoch(time * 1000, isUtc: true)
          : null,
      metadata: meta,
      tags: [board],
      extra: {
        'replies': replies.toString(),
        'images': images.toString(),
        if (fullImageUrl case final url?) 'fullImageUrl': url,
      },
    );
  }

  // ---------------------------------------------------------------------------
  // HTML helpers
  // ---------------------------------------------------------------------------

  /// Strips HTML tags and decodes common HTML entities from 4chan API text.
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

  /// Truncates [text] to [maxLen] characters, appending `…` if shortened.
  static String _truncate(String text, int maxLen) {
    if (text.length <= maxLen) return text;
    return '${text.substring(0, maxLen)}…';
  }
}
