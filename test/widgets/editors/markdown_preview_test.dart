import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kabuk/widgets/editors/markdown_preview.dart';

void main() {
  group('MarkdownPreview', () {
    testWidgets('renders markdown content correctly', (tester) async {
      const testContent = '# Hello\nThis is a test';
      
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: MarkdownPreview(
              content: testContent,
            ),
          ),
        ),
      );

      expect(find.text('Hello'), findsOneWidget);
      expect(find.text('This is a test'), findsOneWidget);
    });

    testWidgets('applies correct font sizes', (tester) async {
      const testContent = '# Heading\nParagraph';
      const fontSize = 16.0;
      
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: MarkdownPreview(
              content: testContent,
              fontSize: fontSize,
            ),
          ),
        ),
      );

      final headingStyle = tester.widget<Text>(find.text('Heading')).style;
      final paragraphStyle = tester.widget<Text>(find.text('Paragraph')).style;

      expect(headingStyle?.fontSize, fontSize * 2);
      expect(paragraphStyle?.fontSize, fontSize);
    });

    testWidgets('handles dark mode correctly', (tester) async {
      const testContent = 'Test content';
      
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: MarkdownPreview(
              content: testContent,
              darkMode: true,
            ),
          ),
        ),
      );

      final textStyle = tester.widget<Text>(find.text('Test content')).style;
      expect(textStyle?.color, Colors.white);
    });
  });
}