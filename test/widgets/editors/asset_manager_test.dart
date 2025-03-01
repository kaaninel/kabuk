import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kabuk/widgets/editors/asset_manager.dart';

void main() {
  group('AssetManager', () {
    testWidgets('shows filter chips for asset types', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AssetManager(),
          ),
        ),
      );

      expect(find.text('All'), findsOneWidget);
      expect(find.text('Images'), findsOneWidget);
      expect(find.text('Videos'), findsOneWidget);
      expect(find.text('Audio'), findsOneWidget);
    });

    testWidgets('filters assets when chip is selected', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AssetManager(),
          ),
        ),
      );

      // Initially shows all assets
      expect(find.byType(Card), findsNWidgets(3));

      // Tap the Images filter
      await tester.tap(find.text('Images'));
      await tester.pumpAndSettle();

      // Should only show image assets
      expect(find.byIcon(Icons.image), findsOneWidget);
      expect(find.byIcon(Icons.videocam), findsNothing);
      expect(find.byIcon(Icons.audiotrack), findsNothing);
    });

    testWidgets('search filters assets by name', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AssetManager(),
          ),
        ),
      );

      await tester.enterText(find.widgetWithText(TextField, 'Search assets...'), 'Video');
      await tester.pump();

      expect(find.text('Sample Video 1'), findsOneWidget);
      expect(find.text('Sample Image 1'), findsNothing);
    });
  });
}