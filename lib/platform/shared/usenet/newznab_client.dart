/// Newznab API client for searching Usenet indexers.
///
/// Implements the Newznab standardised API used by indexers such as NZBGeek,
/// DrunkenSlug, and NZBPlanet. Responses are RSS 2.0 feeds with custom
/// `newznab:attr` extensions for binary metadata.
///
/// See: https://newznab.readthedocs.io/en/latest/misc/api/
library;

import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';
import 'package:xml/xml.dart';

// ---------------------------------------------------------------------------
// Constants – standard Newznab category IDs
// ---------------------------------------------------------------------------

/// Well-known top-level Newznab category IDs.
abstract final class NewznabCategoryId {
  /// Console / gaming releases.
  static const int console = 1000;

  /// Movie releases.
  static const int movies = 2000;

  /// Audio / music releases.
  static const int audio = 3000;

  /// PC / software releases.
  static const int pc = 4000;

  /// TV releases.
  static const int tv = 5000;

  /// Adult content.
  static const int xxx = 6000;

  /// Books / e-books.
  static const int books = 7000;

  /// Other / uncategorised.
  static const int other = 8000;

  // ---- Movie subcategories ------------------------------------------------

  /// Movies – Foreign.
  static const int moviesForeign = 2010;

  /// Movies – Other.
  static const int moviesOther = 2020;

  /// Movies – SD.
  static const int moviesSd = 2030;

  /// Movies – HD.
  static const int moviesHd = 2040;

  /// Movies – UHD.
  static const int moviesUhd = 2045;

  /// Movies – Blu-Ray.
  static const int moviesBluRay = 2050;

  /// Movies – 3-D.
  static const int movies3d = 2060;

  // ---- TV subcategories ---------------------------------------------------

  /// TV – Foreign.
  static const int tvForeign = 5020;

  /// TV – SD.
  static const int tvSd = 5030;

  /// TV – HD.
  static const int tvHd = 5040;

  /// TV – UHD.
  static const int tvUhd = 5045;
}

// ---------------------------------------------------------------------------
// Data classes
// ---------------------------------------------------------------------------

/// A Newznab indexer category with optional [subcategories].
@immutable
class NewznabCategory {
  /// Creates a [NewznabCategory].
  const NewznabCategory({
    required this.id,
    required this.name,
    this.subcategories = const [],
  });

  /// The numeric Newznab category identifier.
  final int id;

  /// Human-readable display name.
  final String name;

  /// Child categories belonging to this parent.
  final List<NewznabCategory> subcategories;

  @override
  String toString() => 'NewznabCategory($id, $name)';
}

/// Server capabilities returned by the `?t=caps` endpoint.
@immutable
class NewznabCaps {
  /// Creates a [NewznabCaps].
  const NewznabCaps({
    required this.serverTitle,
    this.serverEmail,
    this.categories = const [],
    this.supportsSearch = false,
    this.supportsTvSearch = false,
    this.supportsMovieSearch = false,
    this.supportsMusicSearch = false,
    this.supportsBookSearch = false,
    this.defaultResultLimit,
    this.maxResultLimit,
  });

  /// The indexer's display name.
  final String serverTitle;

  /// Optional contact email advertised by the server.
  final String? serverEmail;

  /// Available search categories.
  final List<NewznabCategory> categories;

  /// Whether the server supports free-text search (`?t=search`).
  final bool supportsSearch;

  /// Whether the server supports TV search (`?t=tvsearch`).
  final bool supportsTvSearch;

  /// Whether the server supports movie search (`?t=movie`).
  final bool supportsMovieSearch;

  /// Whether the server supports music search (`?t=music`).
  final bool supportsMusicSearch;

  /// Whether the server supports book search (`?t=book`).
  final bool supportsBookSearch;

  /// Default number of items per response, if advertised.
  final int? defaultResultLimit;

  /// Maximum number of items per response, if advertised.
  final int? maxResultLimit;

  @override
  String toString() => 'NewznabCaps($serverTitle)';
}

/// A single item (release) from a Newznab search response.
@immutable
class NewznabItem {
  /// Creates a [NewznabItem].
  const NewznabItem({
    required this.title,
    required this.nzbUrl,
    required this.guid,
    required this.sizeBytes,
    required this.publishedAt,
    this.category,
    this.categoryId,
    this.group,
    this.poster,
    this.description,
    this.imdbId,
    this.tvdbId,
    this.season,
    this.episode,
    this.attributes = const {},
  });

  /// Release title.
  final String title;

  /// Direct URL to the NZB file.
  final String nzbUrl;

  /// Unique identifier for this release.
  final String guid;

  /// Total file size in bytes.
  final int sizeBytes;

  /// Publication timestamp.
  final DateTime publishedAt;

  /// Human-readable category name.
  final String? category;

  /// Numeric Newznab category ID.
  final int? categoryId;

  /// Usenet newsgroup.
  final String? group;

  /// Poster / uploader name.
  final String? poster;

  /// Short description or subject line.
  final String? description;

  /// IMDB identifier (e.g. `0133093`), parsed from `newznab:attr`.
  final String? imdbId;

  /// TVDB identifier, parsed from `newznab:attr`.
  final String? tvdbId;

  /// Season number string (e.g. `1`), parsed from `newznab:attr`.
  final String? season;

  /// Episode number string (e.g. `5`), parsed from `newznab:attr`.
  final String? episode;

  /// All `newznab:attr` key-value pairs present on this item.
  final Map<String, String> attributes;

  @override
  String toString() => 'NewznabItem($title)';
}

/// A page of search results from a Newznab query.
@immutable
class NewznabSearchResult {
  /// Creates a [NewznabSearchResult].
  const NewznabSearchResult({
    required this.items,
    required this.total,
    required this.offset,
  });

  /// An empty result with zero items.
  static const empty = NewznabSearchResult(items: [], total: 0, offset: 0);

  /// The items returned in this page.
  final List<NewznabItem> items;

  /// Total number of results available on the server.
  final int total;

  /// The zero-based offset of this page.
  final int offset;

  /// Whether additional pages of results are available.
  bool get hasMore => offset + items.length < total;

  @override
  String toString() => 'NewznabSearchResult(${items.length}/$total @ $offset)';
}

// ---------------------------------------------------------------------------
// Exception
// ---------------------------------------------------------------------------

/// Error thrown for Newznab API failures.
///
/// [code] contains the Newznab error code when the server returns a
/// structured `<error>` element.  Common codes:
///
/// * `100` – incorrect credentials
/// * `101` – account suspended
/// * `102` – insufficient privileges
/// * `200` – missing parameter
/// * `201` – incorrect parameter
/// * `300` – no items found
/// * `500` – request limit reached
/// * `910` – API disabled
@immutable
class NewznabException {
  /// Creates a [NewznabException].
  const NewznabException({this.code, required this.message});

  /// The Newznab error code, if one was returned by the server.
  final int? code;

  /// A human-readable description of the error.
  final String message;

  @override
  String toString() =>
      code != null ? 'NewznabException($code: $message)' : 'NewznabException($message)';
}

// ---------------------------------------------------------------------------
// Client
// ---------------------------------------------------------------------------

/// HTTP client for the Newznab API.
///
/// Provides methods for every standard Newznab endpoint including free-text
/// search, TV, movie, music, and book search as well as capabilities and
/// NZB retrieval.
///
/// ```dart
/// final client = NewznabClient(
///   baseUrl: 'https://api.nzbgeek.info',
///   apiKey: 'your-api-key',
/// );
/// final caps = await client.capabilities();
/// final results = await client.search('ubuntu 24.04');
/// ```
class NewznabClient {
  /// Creates a [NewznabClient] targeting [baseUrl] with the given [apiKey].
  ///
  /// An optional [httpClient] may be provided for testing; when omitted a
  /// default [http.Client] is created internally.
  NewznabClient({
    required String baseUrl,
    required String apiKey,
    http.Client? httpClient,
  })  : _baseUrl = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl,
        _apiKey = apiKey,
        _http = httpClient ?? http.Client();

  final String _baseUrl;
  final String _apiKey;
  final http.Client _http;

  // ---- Public API ---------------------------------------------------------

  /// Queries the server's capabilities (`?t=caps`).
  ///
  /// Returns a [NewznabCaps] describing supported searches, categories, and
  /// server limits.
  Future<NewznabCaps> capabilities() async {
    final xml = await _get({'t': 'caps'});
    return _parseCaps(xml);
  }

  /// Performs a free-text search (`?t=search`).
  ///
  /// [query] is the search string. Optionally filter by [categories],
  /// control page size with [limit], and paginate with [offset].
  Future<NewznabSearchResult> search(
    String query, {
    List<int>? categories,
    int limit = 100,
    int offset = 0,
  }) async {
    final params = <String, String>{
      't': 'search',
      'q': query,
      ...  _paginationParams(limit, offset),
      if (categories != null && categories.isNotEmpty)
        'cat': categories.join(','),
    };
    final xml = await _get(params);
    return _parseSearchResult(xml);
  }

  /// Searches for TV releases (`?t=tvsearch`).
  ///
  /// At least one of [query], [tvdbId], [season], or [episode] should be
  /// provided.
  Future<NewznabSearchResult> tvSearch({
    String? query,
    int? tvdbId,
    int? season,
    int? episode,
    List<int>? categories,
    int limit = 100,
    int offset = 0,
  }) async {
    final params = <String, String>{
      't': 'tvsearch',
      ..._paginationParams(limit, offset),
      'q': ?query,
      'tvdbid': ?tvdbId?.toString(),
      'season': ?season?.toString(),
      'ep': ?episode?.toString(),
      if (categories != null && categories.isNotEmpty)
        'cat': categories.join(','),
    };
    final xml = await _get(params);
    return _parseSearchResult(xml);
  }

  /// Searches for movie releases (`?t=movie`).
  ///
  /// [imdbId] may be a bare numeric ID or prefixed with `tt`.
  Future<NewznabSearchResult> movieSearch({
    String? query,
    String? imdbId,
    List<int>? categories,
    int limit = 100,
    int offset = 0,
  }) async {
    final params = <String, String>{
      't': 'movie',
      ..._paginationParams(limit, offset),
      'q': ?query,
      'imdbid': ?imdbId,
      if (categories != null && categories.isNotEmpty)
        'cat': categories.join(','),
    };
    final xml = await _get(params);
    return _parseSearchResult(xml);
  }

  /// Searches for music releases (`?t=music`).
  Future<NewznabSearchResult> musicSearch({
    String? query,
    String? artist,
    String? album,
    List<int>? categories,
    int limit = 100,
    int offset = 0,
  }) async {
    final params = <String, String>{
      't': 'music',
      ..._paginationParams(limit, offset),
      'q': ?query,
      'artist': ?artist,
      'album': ?album,
      if (categories != null && categories.isNotEmpty)
        'cat': categories.join(','),
    };
    final xml = await _get(params);
    return _parseSearchResult(xml);
  }

  /// Searches for book releases (`?t=book`).
  Future<NewznabSearchResult> bookSearch({
    String? query,
    String? author,
    String? title,
    List<int>? categories,
    int limit = 100,
    int offset = 0,
  }) async {
    final params = <String, String>{
      't': 'book',
      ..._paginationParams(limit, offset),
      'q': ?query,
      'author': ?author,
      'title': ?title,
      if (categories != null && categories.isNotEmpty)
        'cat': categories.join(','),
    };
    final xml = await _get(params);
    return _parseSearchResult(xml);
  }

  /// Downloads the NZB XML content for the release identified by [nzbId].
  ///
  /// Returns the raw NZB XML as a string.
  Future<String> fetchNzbXml(String nzbId) async {
    final uri = getNzbUrl(nzbId);
    final response = await _http.get(uri, headers: _headers);
    if (response.statusCode != 200) {
      throw NewznabException(
        code: response.statusCode,
        message: 'Failed to download NZB: HTTP ${response.statusCode}',
      );
    }
    // The response might still be an XML error envelope.
    _checkForXmlError(response.body);
    return response.body;
  }

  /// Builds the download [Uri] for the NZB identified by [nzbId].
  Uri getNzbUrl(String nzbId) => _buildUri({
        't': 'get',
        'id': nzbId,
      });

  // ---- Internals ----------------------------------------------------------

  Map<String, String> get _headers => const {
        'Accept': 'application/rss+xml, application/xml, text/xml, */*',
        'User-Agent': 'Kabuk/0.1',
      };

  Map<String, String> _paginationParams(int limit, int offset) => {
        'limit': limit.toString(),
        'offset': offset.toString(),
      };

  Uri _buildUri(Map<String, String> params) {
    final base = Uri.parse('$_baseUrl/api');
    return base.replace(
      queryParameters: {
        'apikey': _apiKey,
        ...params,
      },
    );
  }

  Future<XmlDocument> _get(Map<String, String> params) async {
    final uri = _buildUri(params);
    final response = await _http
        .get(uri, headers: _headers)
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw NewznabException(
        code: response.statusCode,
        message: 'HTTP ${response.statusCode}: ${response.reasonPhrase}',
      );
    }
    final XmlDocument doc;
    try {
      doc = XmlDocument.parse(response.body);
    } on XmlException catch (e) {
      throw NewznabException(message: 'Malformed XML response: $e');
    }
    _checkForError(doc);
    return doc;
  }

  /// Inspects the root element for a Newznab `<error>` response.
  void _checkForError(XmlDocument doc) {
    final root = doc.rootElement;
    if (root.name.local == 'error') {
      final code = int.tryParse(root.getAttribute('code') ?? '');
      final description = root.getAttribute('description') ?? 'Unknown error';
      throw NewznabException(code: code, message: description);
    }
  }

  /// Best-effort check for an `<error>` envelope in a raw response body.
  void _checkForXmlError(String body) {
    try {
      final doc = XmlDocument.parse(body);
      _checkForError(doc);
    } on XmlException {
      // Not XML – treat the body as the raw NZB content.
    }
  }

  // ---- Parsing – capabilities ---------------------------------------------

  NewznabCaps _parseCaps(XmlDocument doc) {
    final root = doc.rootElement;

    // <server title="..." email="..." />
    final server = root.findAllElements('server').firstOrNull;
    final serverTitle = server?.getAttribute('title') ?? '';
    final serverEmail = server?.getAttribute('email');

    // <limits max="..." default="..." />
    final limits = root.findAllElements('limits').firstOrNull;
    final maxLimit = int.tryParse(limits?.getAttribute('max') ?? '');
    final defaultLimit = int.tryParse(limits?.getAttribute('default') ?? '');

    // <searching> — supported search types
    final searching = root.findAllElements('searching').firstOrNull;
    bool searchAvailable(String tag) {
      final el = searching?.findAllElements(tag).firstOrNull;
      return el?.getAttribute('available') == 'yes';
    }

    // <categories><category id="..." name="..."> ... </category></categories>
    final categoriesEl = root.findAllElements('categories').firstOrNull;
    final categories = <NewznabCategory>[];
    if (categoriesEl != null) {
      for (final catEl in categoriesEl.findElements('category')) {
        categories.add(_parseCapsCategory(catEl));
      }
    }

    return NewznabCaps(
      serverTitle: serverTitle,
      serverEmail: serverEmail,
      categories: categories,
      supportsSearch: searchAvailable('search'),
      supportsTvSearch: searchAvailable('tv-search'),
      supportsMovieSearch: searchAvailable('movie-search'),
      supportsMusicSearch: searchAvailable('audio-search'),
      supportsBookSearch: searchAvailable('book-search'),
      defaultResultLimit: defaultLimit,
      maxResultLimit: maxLimit,
    );
  }

  NewznabCategory _parseCapsCategory(XmlElement el) {
    final id = int.tryParse(el.getAttribute('id') ?? '') ?? 0;
    final name = el.getAttribute('name') ?? '';
    final subs = <NewznabCategory>[];
    for (final subEl in el.findElements('subcat')) {
      subs.add(_parseCapsCategory(subEl));
    }
    return NewznabCategory(id: id, name: name, subcategories: subs);
  }

  // ---- Parsing – search results -------------------------------------------

  NewznabSearchResult _parseSearchResult(XmlDocument doc) {
    final channel = doc.rootElement.findAllElements('channel').firstOrNull;
    if (channel == null) {
      return NewznabSearchResult.empty;
    }

    // <newznab:response offset="0" total="1234" />
    var total = 0;
    var offset = 0;
    final responseEl = channel.findAllElements('response').firstOrNull ??
        _findNewznabElement(channel, 'response');
    if (responseEl != null) {
      total = int.tryParse(responseEl.getAttribute('total') ?? '') ?? 0;
      offset = int.tryParse(responseEl.getAttribute('offset') ?? '') ?? 0;
    }

    final items = <NewznabItem>[];
    for (final itemEl in channel.findAllElements('item')) {
      final item = _parseItem(itemEl);
      if (item != null) items.add(item);
    }

    // Some indexers omit the total attribute – fall back to list length.
    if (total == 0 && items.isNotEmpty) total = items.length;

    return NewznabSearchResult(items: items, total: total, offset: offset);
  }

  NewznabItem? _parseItem(XmlElement el) {
    final title = _text(el, 'title');
    if (title == null) return null;

    // Collect all newznab:attr pairs.
    final attrs = <String, String>{};
    for (final attrEl in el.findAllElements('attr')) {
      final name = attrEl.getAttribute('name');
      final value = attrEl.getAttribute('value');
      if (name != null && value != null) attrs[name] = value;
    }
    // Also pick up explicitly namespaced elements.
    for (final attrEl in _findAllNewznabElements(el, 'attr')) {
      final name = attrEl.getAttribute('name');
      final value = attrEl.getAttribute('value');
      if (name != null && value != null) attrs[name] = value;
    }

    // NZB URL from <enclosure> or <link>.
    var nzbUrl = '';
    final enclosure = el.findAllElements('enclosure').firstOrNull;
    if (enclosure != null) {
      nzbUrl = enclosure.getAttribute('url') ?? '';
    }
    if (nzbUrl.isEmpty) {
      nzbUrl = _text(el, 'link') ?? '';
    }

    final guid = _text(el, 'guid') ?? attrs['guid'] ?? '';

    // Size: prefer newznab:attr, then <enclosure length>, then 0.
    final sizeBytes = int.tryParse(attrs['size'] ?? '') ??
        int.tryParse(enclosure?.getAttribute('length') ?? '') ??
        0;

    // Published date.
    final pubDateStr = _text(el, 'pubDate');
    final publishedAt = pubDateStr != null ? _parseDate(pubDateStr) : DateTime.now();

    final category = _text(el, 'category');
    final categoryId = int.tryParse(attrs['category'] ?? '');

    return NewznabItem(
      title: title,
      nzbUrl: nzbUrl,
      guid: guid,
      sizeBytes: sizeBytes,
      publishedAt: publishedAt,
      category: category,
      categoryId: categoryId,
      group: attrs['group'],
      poster: attrs['poster'] ?? _text(el, 'author'),
      description: _text(el, 'description'),
      imdbId: attrs['imdbid'],
      tvdbId: attrs['tvdbid'],
      season: attrs['season'],
      episode: attrs['episode'],
      attributes: attrs,
    );
  }

  // ---- XML helpers --------------------------------------------------------

  /// Returns the text content of the first child element named [tag].
  static String? _text(XmlElement parent, String tag) {
    final el = parent.findAllElements(tag).firstOrNull;
    final text = el?.innerText.trim();
    return (text != null && text.isNotEmpty) ? text : null;
  }

  /// Finds an element by local name within the `newznab` namespace.
  static XmlElement? _findNewznabElement(XmlElement parent, String localName) {
    for (final child in parent.children.whereType<XmlElement>()) {
      if (child.name.local == localName &&
          (child.name.prefix == 'newznab' ||
              child.name.namespaceUri?.contains('newznab') == true)) {
        return child;
      }
    }
    return null;
  }

  /// Finds all elements by local name within the `newznab` namespace.
  static Iterable<XmlElement> _findAllNewznabElements(
    XmlElement parent,
    String localName,
  ) sync* {
    for (final child in parent.children.whereType<XmlElement>()) {
      if (child.name.local == localName &&
          (child.name.prefix == 'newznab' ||
              child.name.namespaceUri?.contains('newznab') == true)) {
        yield child;
      }
    }
  }

  /// Parses an RFC 2822 / ISO 8601 date string to [DateTime].
  static DateTime _parseDate(String value) {
    // Try ISO 8601 first.
    final iso = DateTime.tryParse(value);
    if (iso != null) return iso;

    // Try RFC 2822 (e.g. "Sun, 01 Jan 2024 12:00:00 +0000").
    return _parseRfc2822(value);
  }

  static final _months = <String, int>{
    'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4,
    'may': 5, 'jun': 6, 'jul': 7, 'aug': 8,
    'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
  };

  static final _rfc2822 = RegExp(
    r'(?:\w{3},?\s+)?'        // optional day name
    r'(\d{1,2})\s+'           // day
    r'(\w{3})\s+'             // month abbreviation
    r'(\d{4})\s+'             // year
    r'(\d{2}):(\d{2})'        // hour:minute
    r'(?::(\d{2}))?'          // optional seconds
    r'\s*([+-]\d{4})?',       // optional timezone offset
  );

  static DateTime _parseRfc2822(String value) {
    final m = _rfc2822.firstMatch(value);
    if (m == null) return DateTime.now();

    final day = int.parse(m.group(1)!);
    final month = _months[m.group(2)!.toLowerCase()] ?? 1;
    final year = int.parse(m.group(3)!);
    final hour = int.parse(m.group(4)!);
    final minute = int.parse(m.group(5)!);
    final second = int.tryParse(m.group(6) ?? '') ?? 0;

    final tz = m.group(7);
    if (tz != null && tz.length == 5) {
      final sign = tz[0] == '+' ? 1 : -1;
      final tzHours = int.parse(tz.substring(1, 3));
      final tzMinutes = int.parse(tz.substring(3, 5));
      return DateTime.utc(year, month, day, hour, minute, second)
          .subtract(Duration(hours: sign * tzHours, minutes: sign * tzMinutes));
    }
    return DateTime.utc(year, month, day, hour, minute, second);
  }
}
