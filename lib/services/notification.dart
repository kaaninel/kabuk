/// Notification service — local and push notifications.
///
/// Platform implementations provide the concrete behavior.
/// Agents access this only through `AgentContext`.
library;

/// Abstract interface for sending notifications.
///
/// Handles both local (on-device) and push notifications through
/// a unified API.
abstract interface class NotificationService {
  /// Show a local notification with the given [title] and [body].
  Future<void> show({
    required String title,
    required String body,
    String? channelId,
    Map<String, dynamic>? payload,
  });

  /// Schedule a notification for a future [dateTime].
  Future<void> schedule({
    required String title,
    required String body,
    required DateTime dateTime,
    String? channelId,
    Map<String, dynamic>? payload,
  });

  /// Cancel a previously scheduled notification by [id].
  Future<void> cancel(String id);

  /// Cancel all pending notifications.
  Future<void> cancelAll();

  /// A stream of notification tap events (when the user taps a notification).
  Stream<Map<String, dynamic>> get onTap;

  /// Release resources held by this service.
  ///
  /// Implementations should close any stream controllers and cancel
  /// pending futures.
  void dispose() {}
}
