import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kabuk/widgets/editors/metadata_editor.dart';

void main() {
  group('MetadataEditor', () {
    testWidgets('shows schema type selector with options', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MetadataEditor(
              initialMetadata: {'@type': 'Article'},
            ),
          ),
        ),
      );

      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();

      expect(find.text('Article'), findsOneWidget);
      expect(find.text('ImageObject'), findsOneWidget);
      expect(find.text('VideoObject'), findsOneWidget);
    });

    testWidgets('updates metadata when fields change', (tester) async {
      Map<String, dynamic>? changedMetadata;
      
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MetadataEditor(
              initialMetadata: const {'author': ''},
              onChanged: (metadata) => changedMetadata = metadata,
            ),
          ),
        ),
      );

      await tester.enterText(find.widgetWithText(TextField, 'Author'), 'John Doe');
      expect(changedMetadata?['author'], equals('John Doe'));
    });

    testWidgets('handles tag input correctly', (tester) async {
      Map<String, dynamic>? changedMetadata;
      
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MetadataEditor(
              onChanged: (metadata) => changedMetadata = metadata,
            ),
          ),
        ),
      );

      await tester.enterText(
        find.widgetWithText(TextField, 'Tags (comma separated)'), 
        'tag1, tag2, tag3'
      );
      
      expect(
        changedMetadata?['keywords'], 
        equals(['tag1', 'tag2', 'tag3'])
      );
    });
  });
}