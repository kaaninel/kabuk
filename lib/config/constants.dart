/// App-wide constants for the Kabuk OS shell.
///
/// All values are compile-time constants. This class cannot be instantiated.
library;

/// App-wide constants that govern limits, timeouts, and identity values.
///
/// ```dart
/// if (depth > AppConstants.maxAgentDepth) {
///   return Result.failure(ServiceError.agent('Max recursion depth exceeded'));
/// }
/// ```
abstract final class AppConstants {
  /// The user-visible application name.
  static const String appName = 'Kabuk';

  /// The current application version following semantic versioning.
  static const String appVersion = '0.1.0';

  /// Maximum number of messages retained in a single conversation context
  /// window when sending to the LLM.
  static const int maxConversationContext = 50;

  /// Maximum depth of recursive agent-to-agent calls before the runtime
  /// terminates the chain to prevent runaway loops.
  static const int maxAgentDepth = 3;

  /// Default timeout for a single agent tool execution.
  static const Duration agentTimeout = Duration(seconds: 30);

  /// Maximum nesting depth allowed in a Remote Flutter Widget tree.
  static const int maxRfwWidgetDepth = 30;

  /// Maximum total number of widgets allowed in a single RFW template.
  static const int maxRfwWidgetCount = 500;
}
