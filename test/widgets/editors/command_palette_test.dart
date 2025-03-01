import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kabuk/widgets/editors/command_palette.dart';

void main() {
  group('CommandPalette', () {
    final testCommands = [
      Command(
        id: 'save',
        label: 'Save',
        category: 'File',
        shortcut: '⌘S',
        icon: Icons.save,
        onExecute: () {},
      ),
      Command(
        id: 'copy',
        label: 'Copy',
        category: 'Edit',
        shortcut: '⌘C',
        icon: Icons.copy,
        onExecute: () {},
      ),
      Command(
        id: 'paste',
        label: 'Paste',
        category: 'Edit',
        shortcut: '⌘V',
        icon: Icons.paste,
        onExecute: () {},
      ),
    ];

    testWidgets('shows commands when visible', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CommandPalette(
              commands: testCommands,
            ),
          ),
        ),
      );

      // Initially hidden
      expect(find.text('Save'), findsNothing);

      // Simulate Cmd+P
      await tester.sendKeyDownEvent(LogicalKeyboardKey.meta);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.meta);
      await tester.pumpAndSettle();

      // Should show all commands
      expect(find.text('Save'), findsOneWidget);
      expect(find.text('Copy'), findsOneWidget);
      expect(find.text('Paste'), findsOneWidget);
    });

    testWidgets('filters commands when searching', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CommandPalette(
              commands: testCommands,
            ),
          ),
        ),
      );

      // Show palette
      await tester.sendKeyDownEvent(LogicalKeyboardKey.meta);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.meta);
      await tester.pumpAndSettle();

      // Search for 'copy'
      await tester.enterText(find.widgetWithText(TextField, 'Search commands...'), 'copy');
      await tester.pump();

      expect(find.text('Copy'), findsOneWidget);
      expect(find.text('Save'), findsNothing);
      expect(find.text('Paste'), findsNothing);
    });

    testWidgets('executes selected command', (tester) async {
      bool commandExecuted = false;
      final commands = [
        Command(
          id: 'test',
          label: 'Test Command',
          onExecute: () => commandExecuted = true,
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CommandPalette(
              commands: commands,
            ),
          ),
        ),
      );

      // Show palette
      await tester.sendKeyDownEvent(LogicalKeyboardKey.meta);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.meta);
      await tester.pumpAndSettle();

      // Execute command with Enter
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(commandExecuted, isTrue);
    });
  });
}