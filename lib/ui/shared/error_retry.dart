/// Reusable error state with retry button.
library;

import 'package:flutter/material.dart';
import 'package:kabuk/ui/theme.dart';

/// A centered error message with an optional retry action.
///
/// Use this wherever async operations can fail to give the user
/// a clear error message and a way to recover.
class ErrorRetryWidget extends StatelessWidget {
  /// Creates an [ErrorRetryWidget].
  const ErrorRetryWidget({
    required this.message,
    super.key,
    this.onRetry,
    this.icon,
  });

  /// Constructs an [ErrorRetryWidget] from a raw error object.
  ///
  /// Extracts a user-friendly message from the error.
  factory ErrorRetryWidget.fromError(Object error, {VoidCallback? onRetry}) {
    final message = _friendlyMessage(error);
    return ErrorRetryWidget(message: message, onRetry: onRetry);
  }

  /// The error message to display.
  final String message;

  /// Called when the user taps the retry button. If null, no retry button shown.
  final VoidCallback? onRetry;

  /// Optional icon to display above the message.
  final IconData? icon;

  static String _friendlyMessage(Object error) {
    final str = error.toString();
    // Strip "Exception: " or "Error: " prefixes.
    if (str.startsWith('Exception: ')) return str.substring(11);
    if (str.startsWith('Error: ')) return str.substring(7);
    // Truncate very long messages.
    if (str.length > 200) return '${str.substring(0, 197)}...';
    return str;
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(KabukTheme.spacingLg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon ?? Icons.error_outline_rounded,
              color: KabukTheme.error,
              size: 40,
            ),
            const SizedBox(height: KabukTheme.spacingMd),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: context.kabukTextSecondary,
                fontSize: 14,
              ),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: KabukTheme.spacingMd),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Retry'),
                style: FilledButton.styleFrom(
                  backgroundColor: KabukTheme.primaryGreen,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
