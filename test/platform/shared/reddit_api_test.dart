import 'package:flutter_test/flutter_test.dart';
import 'package:kabuk/platform/shared/reddit_api.dart';

void main() {
  group('redditJsonPath', () {
    test('bare subreddit name', () {
      expect(redditJsonPath('flutter'), '/r/flutter.json');
    });

    test('r/ shorthand', () {
      expect(redditJsonPath('r/flutter'), '/r/flutter.json');
      expect(redditJsonPath('/r/flutter'), '/r/flutter.json');
    });

    test('full www URL', () {
      expect(
        redditJsonPath('https://www.reddit.com/r/flutter'),
        '/r/flutter.json',
      );
    });

    test('preserves sort path + query', () {
      expect(
        redditJsonPath(
          'https://www.reddit.com/r/flutter/new.json?limit=50&raw_json=1',
        ),
        '/r/flutter/new.json?limit=50&raw_json=1',
      );
    });

    test('preserves search query', () {
      expect(
        redditJsonPath('https://www.reddit.com/search.json?q=flutter'),
        '/search.json?q=flutter',
      );
    });

    test('user profile path', () {
      expect(
        redditJsonPath('https://www.reddit.com/user/spez/submitted'),
        '/user/spez/submitted.json',
      );
    });
  });

  group('fetchRedditJson', () {
    test('returns the first successful host', () async {
      final calls = <String>[];
      final res = await fetchRedditJson(
        get: (uri) async {
          calls.add(uri.host);
          if (uri.host == 'api.reddit.com') {
            return (statusCode: 403, body: '{"message":"Blocked"}');
          }
          return (statusCode: 200, body: '{"data":{}}');
        },
        pathOrUrl: 'r/flutter',
      );
      expect(calls, ['api.reddit.com', 'old.reddit.com']);
      expect(res.statusCode, 200);
    });

    test('prefers the input host first', () async {
      final calls = <String>[];
      await fetchRedditJson(
        get: (uri) async {
          calls.add(uri.host);
          return (statusCode: 200, body: '{}');
        },
        pathOrUrl: 'https://www.reddit.com/r/flutter.json',
      );
      expect(calls.first, 'www.reddit.com');
    });

    test('throws when every host fails', () async {
      await expectLater(
        fetchRedditJson(
          get: (uri) async => (statusCode: 403, body: '{"message":"Blocked"}'),
          pathOrUrl: 'r/flutter',
        ),
        throwsA(isA<RedditApiException>()),
      );
    });

    test('does not try other hosts on a 404', () async {
      final calls = <String>[];
      await expectLater(
        fetchRedditJson(
          get: (uri) async {
            calls.add(uri.host);
            return (statusCode: 404, body: '{}');
          },
          pathOrUrl: 'r/flutter',
        ),
        throwsA(isA<RedditApiException>()),
      );
      expect(calls, hasLength(1)); // stopped after the first (non-transient) 404
    });

    test('appends the after cursor as a query param', () async {
      Uri? seen;
      await fetchRedditJson(
        get: (uri) async {
          seen = uri;
          return (statusCode: 200, body: '{}');
        },
        pathOrUrl: 'r/flutter',
        after: 't3_abc',
      );
      expect(seen!.queryParameters['after'], 't3_abc');
    });
  });
}