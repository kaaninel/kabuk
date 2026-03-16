/// RSS/Atom feed source implementation.
///
/// Parses both RSS 2.0 and Atom feeds using `package:xml`.
/// Uses [MeshService] for HTTP requests to stay within the
/// Virtual OS service abstraction.
library;

import 'package:kabuk/services/feed.dart';
import 'package:kabuk/services/mesh.dart';
import 'package:xml/xml.dart';

/// [FeedSource] implementation for RSS 2.0 feeds.
class RssFeedSource implements FeedSource {
  /// Creates an [RssFeedSource] with the given [mesh] service for HTTP.
  RssFeedSource({required MeshService mesh}) : _mesh = mesh;

  final MeshService _mesh;

  @override
  FeedSourceType get type => FeedSourceType.rss;

  @override
  Future<List<FeedItem>> fetch(String url) async {
    final response = await _mesh.get(
      Uri.parse(url),
      headers: {
        'Accept': 'application/rss+xml, application/xml, text/xml, */*',
        'User-Agent': 'Kabuk/0.1',
      },
    );

    if (response.statusCode != 200) {
      throw FeedFetchException('HTTP ${response.statusCode} fetching $url');
    }

    final document = XmlDocument.parse(response.body);
    final root = document.rootElement;

    // Detect Atom vs RSS
    if (root.name.local == 'feed') {
      return _parseAtom(root);
    }

    // RSS 2.0: <rss><channel><item>...</item></channel></rss>
    final channel = root.findAllElements('channel').firstOrNull;
    if (channel == null) {
      throw const FeedParseException('No <channel> element found in RSS feed');
    }

    return _parseRss(channel);
  }

  List<FeedItem> _parseRss(XmlElement channel) {
    final items = channel.findAllElements('item');
    return items.map((item) {
      final title = _text(item, 'title') ?? 'Untitled';
      final link = _text(item, 'link') ?? '';
      final description = _text(item, 'description');
      final author = _text(item, 'author') ?? _text(item, 'dc:creator');
      final pubDate = _text(item, 'pubDate');
      final guid = _text(item, 'guid');
      final categories = item
          .findAllElements('category')
          .map((e) => e.innerText.trim())
          .where((s) => s.isNotEmpty)
          .toList();

      // Try to extract image from media:content, media:thumbnail, or enclosure
      final imageUrl = _extractImageUrl(item);

      return FeedItem(
        title: title,
        url: link,
        description: _stripHtml(description),
        author: author,
        imageUrl: imageUrl,
        datePublished: _tryParseDate(pubDate),
        identifier: guid ?? link,
        categories: categories,
      );
    }).toList();
  }

  List<FeedItem> _parseAtom(XmlElement feed) {
    final entries = feed.findAllElements('entry');
    return entries.map((entry) {
      final title = _text(entry, 'title') ?? 'Untitled';

      // Atom links: <link rel="alternate" href="..."/>
      final links = entry.findAllElements('link');
      final link =
          links
              .where(
                (l) =>
                    l.getAttribute('rel') == 'alternate' ||
                    l.getAttribute('rel') == null,
              )
              .firstOrNull
              ?.getAttribute('href') ??
          '';

      final summary = _text(entry, 'summary') ?? _text(entry, 'content');
      final author = entry
          .findAllElements('author')
          .firstOrNull
          ?.findAllElements('name')
          .firstOrNull
          ?.innerText
          .trim();
      final published = _text(entry, 'published') ?? _text(entry, 'updated');
      final id = _text(entry, 'id');
      final categories = entry
          .findAllElements('category')
          .map((e) => e.getAttribute('term') ?? e.innerText.trim())
          .where((s) => s.isNotEmpty)
          .toList();

      return FeedItem(
        title: title,
        url: link,
        description: _stripHtml(summary),
        author: author,
        datePublished: _tryParseDate(published),
        identifier: id ?? link,
        categories: categories,
      );
    }).toList();
  }

  @override
  Future<bool> validate(String url) async {
    try {
      final response = await _mesh.get(
        Uri.parse(url),
        headers: {
          'Accept': 'application/rss+xml, application/xml, text/xml, */*',
          'User-Agent': 'Kabuk/0.1',
        },
      );
      if (response.statusCode != 200) return false;
      final document = XmlDocument.parse(response.body);
      final root = document.rootElement;
      return root.name.local == 'rss' ||
          root.name.local == 'feed' ||
          root.name.local == 'RDF';
    } on Object {
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  static String? _text(XmlElement parent, String name) {
    final el = parent.findAllElements(name).firstOrNull;
    if (el == null) return null;
    final text = el.innerText.trim();
    return text.isEmpty ? null : text;
  }

  static String? _extractImageUrl(XmlElement item) {
    // media:thumbnail
    for (final el in item.findAllElements('media:thumbnail')) {
      final url = el.getAttribute('url');
      if (url != null && url.isNotEmpty) return url;
    }
    // media:content
    for (final el in item.findAllElements('media:content')) {
      final medium = el.getAttribute('medium');
      if (medium == 'image' || medium == null) {
        final url = el.getAttribute('url');
        if (url != null && url.isNotEmpty) return url;
      }
    }
    // enclosure with image type
    for (final el in item.findAllElements('enclosure')) {
      final mimeType = el.getAttribute('type') ?? '';
      if (mimeType.startsWith('image/')) {
        final url = el.getAttribute('url');
        if (url != null && url.isNotEmpty) return url;
      }
    }
    return null;
  }

  static String? _stripHtml(String? html) {
    if (html == null) return null;
    // Simple HTML tag stripping.
    final stripped = html
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&nbsp;', ' ')
        .trim();
    return stripped.isEmpty ? null : stripped;
  }

  static DateTime? _tryParseDate(String? value) {
    if (value == null) return null;
    // Try ISO 8601 first.
    final iso = DateTime.tryParse(value);
    if (iso != null) return iso;
    // Try RFC 2822 (common in RSS).
    return _tryParseRfc2822(value);
  }

  static DateTime? _tryParseRfc2822(String value) {
    // RFC 2822: "Mon, 25 Feb 2026 12:00:00 GMT"
    try {
      final months = {
        'jan': 1,
        'feb': 2,
        'mar': 3,
        'apr': 4,
        'may': 5,
        'jun': 6,
        'jul': 7,
        'aug': 8,
        'sep': 9,
        'oct': 10,
        'nov': 11,
        'dec': 12,
      };

      final cleaned = value.replaceAll(RegExp(r'\s+'), ' ').trim();
      final parts = cleaned.split(' ');

      // Skip day-of-week if present.
      final offset = parts[0].endsWith(',') ? 1 : 0;
      if (parts.length < offset + 4) return null;

      final day = int.parse(parts[offset]);
      final month = months[parts[offset + 1].substring(0, 3).toLowerCase()];
      if (month == null) return null;
      final year = int.parse(parts[offset + 2]);

      var hour = 0;
      var minute = 0;
      var second = 0;
      if (parts.length > offset + 3) {
        final timeParts = parts[offset + 3].split(':');
        hour = int.parse(timeParts[0]);
        if (timeParts.length > 1) minute = int.parse(timeParts[1]);
        if (timeParts.length > 2) second = int.parse(timeParts[2]);
      }

      return DateTime.utc(year, month, day, hour, minute, second);
    } on Object {
      return null;
    }
  }
}

/// Exception thrown when a feed cannot be fetched from the network.
class FeedFetchException implements Exception {
  /// Creates a [FeedFetchException] with a [message].
  const FeedFetchException(this.message);

  /// The error message.
  final String message;

  @override
  String toString() => 'FeedFetchException: $message';
}

/// Exception thrown when feed content cannot be parsed.
class FeedParseException implements Exception {
  /// Creates a [FeedParseException] with a [message].
  const FeedParseException(this.message);

  /// The error message.
  final String message;

  @override
  String toString() => 'FeedParseException: $message';
}
