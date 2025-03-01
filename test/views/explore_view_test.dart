import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kabuk/views/explore_view.dart';

void main() {
  group('ExploreView', () {
    testWidgets('shows navigation bar with expected controls', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: ExploreView()));

      expect(find.byIcon(Icons.menu), findsOneWidget);
      expect(find.byIcon(Icons.search), findsOneWidget);
      expect(find.byIcon(Icons.filter_list), findsOneWidget);
      expect(find.byIcon(Icons.grid_view), findsOneWidget);
      expect(find.byIcon(Icons.sort), findsOneWidget);
    });

    testWidgets('toggles left panel on menu click', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: ExploreView()));
      await tester.pump();

      expect(find.byIcon(Icons.push_pin), findsNothing);

      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.push_pin), findsOneWidget);
    });
  });
}
