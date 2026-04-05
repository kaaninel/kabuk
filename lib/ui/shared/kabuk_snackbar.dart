/// Standardized SnackBar helpers for consistent feedback across the app.
library;

import 'package:flutter/material.dart';
import 'package:kabuk/ui/theme.dart';

/// Shows a standardized floating SnackBar with consistent styling.
///
/// All SnackBars in Kabuk should use this helper to ensure uniform
/// duration, behavior, and appearance.
void showKabukSnackBar(
  BuildContext context,
  String message, {
  Duration duration = const Duration(seconds: 2),
  SnackBarAction? action,
  bool isError = false,
}) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(color: Colors.white, fontSize: 14),
        ),
        duration: duration,
        behavior: SnackBarBehavior.floating,
        backgroundColor:
            isError ? KabukTheme.error : context.kabukSurfaceVariant,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.symmetric(
          horizontal: KabukTheme.spacingMd,
          vertical: KabukTheme.spacingSm,
        ),
        action: action,
      ),
    );
}

/// Shows a success SnackBar with a green accent.
void showKabukSuccess(BuildContext context, String message) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: KabukTheme.accentGreen, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
            ),
          ],
        ),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        backgroundColor: context.kabukSurfaceVariant,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.symmetric(
          horizontal: KabukTheme.spacingMd,
          vertical: KabukTheme.spacingSm,
        ),
      ),
    );
}

/// Shows an error SnackBar with a red accent.
void showKabukError(BuildContext context, String message) {
  showKabukSnackBar(context, message, isError: true);
}
