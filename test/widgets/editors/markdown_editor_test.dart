import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kabuk/widgets/editors/markdown_editor.dart';

void main() {
  group('MarkdownEditor', () {
    testWidgets('shows line numbers when enabled', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MarkdownEditor(
              initialContent: 'Line 1\nLine 2\nLine 3',
              showLineNumbers: true,
            ),
          ),
        ),
      );

      expect(find.text('1'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
    });

    testWidgets('updates content via controller', (tester) async {
      String? changedContent;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MarkdownEditor(
              onChanged: (content) => changedContent = content,
            ),
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), 'New content');
      expect(changedContent, equals('New content'));
    });

    testWidgets('hides line numbers when disabled', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MarkdownEditor(
              showLineNumbers: false,
            ),
          ),
        ),
      );

      expect(find.text('1'), findsNothing);
    });

    testWidgets('shows auto-completion suggestions when typing /',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MarkdownEditor(
              initialContent: '',
              showLineNumbers: true,
            ),
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), '/head');
      await tester.pump();

      expect(find.text('# Heading 1'), findsOneWidget);
      expect(find.text('## Heading 2'), findsOneWidget);
      expect(find.text('### Heading 3'), findsOneWidget);
    });

    testWidgets('inserts selected suggestion', (tester) async {
      String? changedContent;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MarkdownEditor(
              initialContent: '',
              onChanged: (content) => changedContent = content,
            ),
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), '/head');
      await tester.pump();

      await tester.tap(find.text('# Heading 1'));
      await tester.pump();

      expect(changedContent, equals('# Heading 1'));
    });

    testWidgets('supports code folding for headers', (tester) async {
      const testContent = '# Header\nLine 1\nLine 2\n## Subheader\nLine 3';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MarkdownEditor(
              initialContent: testContent,
              showLineNumbers: true,
            ),
          ),
        ),
      );

      // Verify fold indicators are shown for headers
      expect(find.byIcon(Icons.expand_more), findsNWidgets(2));

      // Toggle fold for first header
      await tester.tap(find.text('1')); // First line number
      await tester.pump();

      expect(find.byIcon(Icons.chevron_right), findsOneWidget);
      expect(find.byIcon(Icons.expand_more), findsOneWidget);
    });

    testWidgets('handles keyboard shortcuts', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MarkdownEditor(
              initialContent: 'Test',
              showLineNumbers: true,
            ),
          ),
        ),
      );

      // Test indent/outdent
      await tester.sendKeyDownEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(find.text('    Test'), findsOneWidget);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(find.text('Test'), findsOneWidget);
    });
  });
}
