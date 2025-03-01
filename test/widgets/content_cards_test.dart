import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kabuk/views/explore_view.dart';

void main() {
  group('ContentCards', () {
    testWidgets('renders grid with correct spacing', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ExploreView(),
          ),
        ),
      );

      final gridFinder = find.byType(GridView);
      expect(gridFinder, findsOneWidget);

      final GridView grid = tester.widget(gridFinder);
      final SliverGridDelegateWithMaxCrossAxisExtent delegate =
          grid.gridDelegate as SliverGridDelegateWithMaxCrossAxisExtent;

      expect(delegate.maxCrossAxisExtent, 300);
      expect(delegate.mainAxisExtent, 300);
      expect(delegate.crossAxisSpacing, 16);
      expect(delegate.mainAxisSpacing, 16);
    });
  });
}
