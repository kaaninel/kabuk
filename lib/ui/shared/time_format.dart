/// Time formatting utilities for the Kabuk UI.
///
/// Provides consistent human-readable time formatting across all views.
library;

/// Formats a Unix timestamp (seconds) as a human-readable "time ago" string.
///
/// Returns compact relative strings: `now`, `5m`, `2h`, `3d`,
/// `2mo`, `1y`.
String timeAgo(int unixSeconds) {
  final dt = DateTime.fromMillisecondsSinceEpoch(unixSeconds * 1000);
  final diff = DateTime.now().difference(dt);
  if (diff.inDays > 365) return '${diff.inDays ~/ 365}y';
  if (diff.inDays > 30) return '${diff.inDays ~/ 30}mo';
  if (diff.inDays > 0) return '${diff.inDays}d';
  if (diff.inHours > 0) return '${diff.inHours}h';
  if (diff.inMinutes > 0) return '${diff.inMinutes}m';
  return 'now';
}

/// Formats a Unix timestamp (seconds) as a human-readable date string.
///
/// Returns contextual formats: `Today HH:MM`, `Yesterday`,
/// `N days ago`, or `Mon DD, YYYY`.
String formatDate(int unixSeconds) {
  final dt = DateTime.fromMillisecondsSinceEpoch(unixSeconds * 1000);
  final diff = DateTime.now().difference(dt);

  if (diff.inDays == 0) {
    return 'Today ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
  if (diff.inDays == 1) return 'Yesterday';
  if (diff.inDays < 7) return '${diff.inDays} days ago';

  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
}

/// Formats a [DateTime] as a human-readable "time ago" string.
///
/// Convenience wrapper around [timeAgo] for callers that already
/// have a [DateTime] instead of a Unix timestamp.
String timeAgoFromDateTime(DateTime dateTime) {
  return timeAgo(dateTime.millisecondsSinceEpoch ~/ 1000);
}
