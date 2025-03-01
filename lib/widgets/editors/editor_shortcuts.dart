import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class EditorShortcuts extends StatelessWidget {
  final Widget child;
  final VoidCallback? onSave;
  final VoidCallback? onUndo;
  final VoidCallback? onRedo;
  final VoidCallback? onFind;
  final VoidCallback? onTogglePreview;
  final VoidCallback? onToggleLeftPanel;
  final VoidCallback? onToggleRightPanel;

  const EditorShortcuts({
    super.key,
    required this.child,
    this.onSave,
    this.onUndo,
    this.onRedo,
    this.onFind,
    this.onTogglePreview,
    this.onToggleLeftPanel,
    this.onToggleRightPanel,
  });

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        SingleActivator(
          LogicalKeyboardKey.keyS,
          meta: true,
        ): VoidCallbackIntent(onSave ?? () {}),
        SingleActivator(
          LogicalKeyboardKey.keyZ,
          meta: true,
        ): VoidCallbackIntent(onUndo ?? () {}),
        SingleActivator(
          LogicalKeyboardKey.keyZ,
          meta: true,
          shift: true,
        ): VoidCallbackIntent(onRedo ?? () {}),
        SingleActivator(
          LogicalKeyboardKey.keyF,
          meta: true,
        ): VoidCallbackIntent(onFind ?? () {}),
        SingleActivator(
          LogicalKeyboardKey.keyP,
          meta: true,
        ): VoidCallbackIntent(onTogglePreview ?? () {}),
        SingleActivator(
          LogicalKeyboardKey.backslash,
          meta: true,
        ): VoidCallbackIntent(onToggleLeftPanel ?? () {}),
        SingleActivator(
          LogicalKeyboardKey.bracketRight,
          meta: true,
        ): VoidCallbackIntent(onToggleRightPanel ?? () {}),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          VoidCallbackIntent: VoidCallbackAction(),
        },
        child: child,
      ),
    );
  }
}