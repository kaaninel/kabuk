import 'package:flutter_test/flutter_test.dart';
import 'package:kabuk/platform/shared/duckduckgo_source.dart';

void main() {
  group('parseDuckDuckGoQuery', () {
    test('parses the canonical ddg://search?q= URL', () {
      expect(
        parseDuckDuckGoQuery('ddg://search?q=flutter'),
        'flutter',
      );
      expect(
        parseDuckDuckGoQuery('ddg://search?q=why%20is%20the%20sky%20blue'),
        'why is the sky blue',
      );
    });

    test('parses the duckduckgo:// alias', () {
      expect(
        parseDuckDuckGoQuery('duckduckgo://search?q=flutter'),
        'flutter',
      );
    });

    test('parses the ddg: shorthand', () {
      expect(parseDuckDuckGoQuery('ddg:flutter'), 'flutter');
      expect(parseDuckDuckGoQuery('ddg:search flutter'), 'flutter');
    });

    test('returns empty for unrecognised input', () {
      expect(parseDuckDuckGoQuery('flutter'), '');
      expect(parseDuckDuckGoQuery('https://example.com'), '');
    });
  });

  group('buildDuckDuckGoUrl', () {
    test('round-trips a query', () {
      final url = buildDuckDuckGoUrl('flutter framework');
      expect(url.startsWith('ddg://search?q='), isTrue);
      expect(parseDuckDuckGoQuery(url), 'flutter framework');
    });
  });
}