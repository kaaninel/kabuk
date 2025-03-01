import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kabuk/widgets/editors/media_editor.dart';

void main() {
  group('MediaEditor', () {
    testWidgets('shows image editing controls for image type', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: MediaEditor(
              type: 'image',
            ),
          ),
        ),
      );

      expect(find.text('Brightness'), findsOneWidget);
      expect(find.text('Contrast'), findsOneWidget);
      expect(find.text('Original'), findsOneWidget);
      expect(find.text('Grayscale'), findsOneWidget);
    });

    testWidgets('shows video editing controls for video type', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: MediaEditor(
              type: 'video',
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.play_arrow), findsOneWidget);
      expect(find.byIcon(Icons.cut), findsOneWidget);
      expect(find.byType(Slider), findsOneWidget);
    });

    testWidgets('shows audio editing controls for audio type', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: MediaEditor(
              type: 'audio',
            ),
          ),
        ),
      );

      expect(find.text('Volume'), findsOneWidget);
      expect(find.byIcon(Icons.audiotrack), findsOneWidget);
      expect(find.byType(Slider), findsNWidgets(2)); // Playback and volume sliders
    });

    testWidgets('updates config when controls are changed', (tester) async {
      Map<String, dynamic>? changedConfig;
      
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MediaEditor(
              type: 'image',
              onConfigChanged: (config) => changedConfig = config,
            ),
          ),
        ),
      );

      // Test filter selection
      await tester.tap(find.text('Grayscale'));
      await tester.pump();
      expect(changedConfig?['filter'], equals('grayscale'));

      // Test brightness adjustment
      final slider = find.byType(Slider).first;
      await tester.drag(slider, const Offset(20.0, 0.0));
      await tester.pump();
      expect(changedConfig?['brightness'], isNotNull);
    });
  });
}