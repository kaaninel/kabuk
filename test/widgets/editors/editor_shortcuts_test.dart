import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kabuk/widgets/editors/editor_shortcuts.dart';

void main() {
  group('EditorShortcuts', () {
    testWidgets('triggers save shortcut', (tester) async {
      bool saveTriggered = false;
      
      await tester.pumpWidget(
        MaterialApp(
          home: EditorShortcuts(
            onSave: () => saveTriggered = true,
            child: const SizedBox(),
          ),
        ),
      );

      await tester.sendKeyDownEvent(LogicalKeyboardKey.meta);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.meta);
      
      expect(saveTriggered, isTrue);
    });

    testWidgets('triggers undo/redo shortcuts', (tester) async {
      bool undoTriggered = false;
      bool redoTriggered = false;
      
      await tester.pumpWidget(
        MaterialApp(
          home: EditorShortcuts(
            onUndo: () => undoTriggered = true,
            onRedo: () => redoTriggered = true,
            child: const SizedBox(),
          ),
        ),
      );

      // Test undo
      await tester.sendKeyDownEvent(LogicalKeyboardKey.meta);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.meta);
      
      expect(undoTriggered, isTrue);

      // Test redo
      await tester.sendKeyDownEvent(LogicalKeyboardKey.meta);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.meta);
      
      expect(redoTriggered, isTrue);
    });

    testWidgets('triggers panel toggle shortcuts', (tester) async {
      bool leftPanelToggled = false;
      bool rightPanelToggled = false;
      
      await tester.pumpWidget(
        MaterialApp(
          home: EditorShortcuts(
            onToggleLeftPanel: () => leftPanelToggled = true,
            onToggleRightPanel: () => rightPanelToggled = true,
            child: const SizedBox(),
          ),
        ),
      );

      // Test left panel toggle
      await tester.sendKeyDownEvent(LogicalKeyboardKey.meta);
      await tester.sendKeyEvent(LogicalKeyboardKey.backslash);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.meta);
      
      expect(leftPanelToggled, isTrue);

      // Test right panel toggle
      await tester.sendKeyDownEvent(LogicalKeyboardKey.meta);
      await tester.sendKeyEvent(LogicalKeyboardKey.bracketRight);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.meta);
      
      expect(rightPanelToggled, isTrue);
    });
  });
}