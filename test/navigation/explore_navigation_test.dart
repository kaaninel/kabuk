import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kabuk/views/explore_view.dart';

void main() {
  group('ExploreNavigation', () {
    testWidgets('location display shows correct path', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: ExploreView()));

      expect(find.text('Home > Images > Nature > 2023'), findsOneWidget);
    });

    testWidgets('search input appears when search is active', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: ExploreView()));

      await tester.tap(find.byIcon(Icons.search));
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Search...'), findsOneWidget);
    });
  });
}
