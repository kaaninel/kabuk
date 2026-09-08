/// Shared Reddit JSON API helpers.
///
/// Since Reddit deprecated unauthenticated `.json` access (May 2026) and now
/// blocks most anonymous requests, this module centralises the workarounds:
/// - a **descriptive User-Agent** (Reddit blocks browser-like UAs from scripts),
/// - a **host fallback chain** (`api.reddit.com` → `old.reddit.com` →
///   `www.reddit.com`) so a 403 on one host doesn't kill the feed,
/// - a **back-off** on 429 rate limits before trying the next host.
///
/// Both `RedditFeedSource` and the Reddit content plugin use this so the
/// behaviour is consistent.
library;

/// User-Agent in Reddit's recommended `platform:app_id:version (by /u/…)`
/// format. Reddit explicitly discourages browser-like UAs from non-browsers.
const String kRedditUserAgent = 'kabuk:1.0 (by /u/kabukapp)';

/// Headers sent with every Reddit JSON request.
const Map<String, String> kRedditHeaders = {
  'Accept': 'application/json, text/plain, */*',
  'Accept-Language': 'en-US,en;q=0.9',
  'User-Agent': kRedditUserAgent,
  'Cookie': 'over18=1',
};

/// Reddit JSON hosts tried in order (most permissive first).
const List<String> kRedditHosts = [
  'https://api.reddit.com',
  'https://old.reddit.com',
  'https://www.reddit.com',
];

/// Normalises a Reddit URL / shorthand into a path with a `.json` suffix.
///
/// Examples:
/// - `r/flutter`           → `/r/flutter.json`
/// - `flutter`             → `/r/flutter.json`
/// - `https://www.reddit.com/r/flutter/new.json?limit=50` → `/r/flutter/new.json?limit=50`
/// - `https://www.reddit.com/search.json?q=x` → `/search.json?q=x`
String redditJsonPath(String input) {
  var url = input.trim();
  url = url.replaceFirst(RegExp(r'^https?://[^/]+'), '');
  if (!url.startsWith('/')) {
    url = url.startsWith('r/') ? '/$url' : '/r/$url';
  }
  if (!RegExp(r'\.json(\?|$)').hasMatch(url)) {
    url = '$url.json';
  }
  return url;
}

/// Thrown when a Reddit JSON fetch fails on every host.
class RedditApiException implements Exception {
  /// Creates a [RedditApiException] with a [message].
  const RedditApiException(this.message);

  /// The error message.
  final String message;

  @override
  String toString() => 'RedditApiException: $message';
}

/// Fetches a Reddit JSON endpoint, trying each host in [kRedditHosts] until
/// one returns a 200 (or a non-transient error).
///
/// [get] abstracts the HTTP client so both the mesh-based feed source and the
/// plugin's own http client can share this logic.
///
/// Returns the first successful response as `(statusCode, body)`.
Future<({int statusCode, String body})> fetchRedditJson({
  required Future<({int statusCode, String body})> Function(Uri url) get,
  required String pathOrUrl,
  String? after,
}) async {
  final path = redditJsonPath(pathOrUrl);
  final preferredHost = Uri.tryParse(pathOrUrl)?.host;
  final hosts = <String>[
    if (preferredHost != null && preferredHost.isNotEmpty)
      'https://$preferredHost',
    ...kRedditHosts,
  ];

  Object? lastError;
  for (final host in hosts) {
    var uri = Uri.parse('$host$path');
    if (after != null && after.isNotEmpty) {
      uri = uri.replace(
        queryParameters: {...uri.queryParameters, 'after': after},
      );
    }

    try {
      final response = await get(uri);
      final status = response.statusCode;
      if (status == 200) return response;

      final transient = status == 403 || status == 429 || status >= 500;
      if (!transient) {
        // Real client error — no point trying other hosts.
        throw RedditApiException('HTTP $status fetching $uri');
      }
      lastError = RedditApiException('HTTP $status fetching $uri');
      if (status == 429) {
        // Back off before hitting the next host.
        await Future<void>.delayed(const Duration(seconds: 2));
      }
    } on RedditApiException {
      // Non-transient error — stop the fallback chain.
      rethrow;
    } on Object catch (e) {
      // Network-level failure — remember it and try the next host.
      lastError = e;
    }
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }

  throw lastError ?? const RedditApiException('All Reddit hosts failed');
}