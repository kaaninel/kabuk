/// Service error hierarchy for all Kabuk operations.
///
/// Uses sealed classes to enable exhaustive pattern matching on error types.
/// Every service method that can fail should return a `Result` containing
/// a [ServiceError] variant on failure.
library;

/// Base error type for all service errors.
///
/// Each variant represents a distinct category of failure that can occur
/// across the Virtual OS service layer, agent layer, and knowledge layer.
///
/// ```dart
/// final error = ServiceError.notFound('user/123');
/// switch (error) {
///   case NotFoundError(:final resource):
///     print('Missing: $resource');
///   case NetworkError(:final message):
///     print('Network issue: $message');
///   // ... exhaustive
/// }
/// ```
sealed class ServiceError {
  /// Creates a [ServiceError] with the given [message].
  const ServiceError(this.message);

  /// Human-readable description of the error.
  final String message;

  /// The requested feature or capability is not supported on this platform.
  const factory ServiceError.notSupported(String feature) = NotSupportedError;

  /// The required permission was not granted.
  const factory ServiceError.permissionDenied(String permission) =
      PermissionDeniedError;

  /// The requested resource could not be found.
  const factory ServiceError.notFound(String resource) = NotFoundError;

  /// A network-related error occurred.
  const factory ServiceError.network(String message) = NetworkError;

  /// An encryption or decryption operation failed.
  const factory ServiceError.encryption(String message) = EncryptionError;

  /// A storage (database, file system) operation failed.
  const factory ServiceError.storage(String message) = StorageError;

  /// An agent execution error occurred.
  const factory ServiceError.agent(String message) = AgentError;

  /// An LLM service call failed.
  const factory ServiceError.llm(String message) = LlmError;

  /// Input validation failed.
  const factory ServiceError.validation(String message) = ValidationError;

  /// An unexpected or uncategorized error occurred.
  const factory ServiceError.unknown(
    String message, [
    Object? cause,
    StackTrace? stackTrace,
  ]) = UnknownError;

  @override
  String toString() => '$runtimeType: $message';
}

/// The requested feature or capability is not supported on this platform.
///
/// Thrown when a Virtual OS service method is called on a platform that
/// does not provide the underlying capability.
final class NotSupportedError extends ServiceError {
  /// Creates a [NotSupportedError] for the given [feature].
  const NotSupportedError(this.feature) : super('Not supported: $feature');

  /// The feature or capability that is not supported.
  final String feature;
}

/// The required permission was not granted by the user or system.
///
/// Services should request permissions lazily and return this error
/// when the user declines or the system restricts access.
final class PermissionDeniedError extends ServiceError {
  /// Creates a [PermissionDeniedError] for the given [permission].
  const PermissionDeniedError(this.permission)
    : super('Permission denied: $permission');

  /// The permission that was denied (e.g. `'camera'`, `'location'`).
  final String permission;
}

/// The requested resource could not be found.
///
/// Used by the knowledge store when a triple/entity lookup yields no results,
/// or by services when a referenced asset is missing.
final class NotFoundError extends ServiceError {
  /// Creates a [NotFoundError] for the given [resource].
  const NotFoundError(this.resource) : super('Not found: $resource');

  /// Identifier or description of the missing resource.
  final String resource;
}

/// A network-related error occurred.
///
/// Covers connectivity loss, DNS failures, HTTP errors, timeouts, and
/// any other transport-level issue encountered by the mesh service.
final class NetworkError extends ServiceError {
  /// Creates a [NetworkError] with the given [message].
  const NetworkError(super.message);
}

/// An encryption or decryption operation failed.
///
/// Raised by the vault service when key derivation, cipher operations,
/// or integrity checks fail.
final class EncryptionError extends ServiceError {
  /// Creates an [EncryptionError] with the given [message].
  const EncryptionError(super.message);
}

/// A storage (database, file system) operation failed.
///
/// Covers SQLite/Drift errors, file I/O failures, and quota exhaustion.
final class StorageError extends ServiceError {
  /// Creates a [StorageError] with the given [message].
  const StorageError(super.message);
}

/// An agent execution error occurred.
///
/// Raised when an agent's tool execution fails, an agent times out,
/// or the router cannot dispatch a request.
final class AgentError extends ServiceError {
  /// Creates an [AgentError] with the given [message].
  const AgentError(super.message);
}

/// An LLM service call failed.
///
/// Covers rate limiting, context-length exceeded, provider outages,
/// and malformed completions.
final class LlmError extends ServiceError {
  /// Creates an [LlmError] with the given [message].
  const LlmError(super.message);
}

/// Input validation failed.
///
/// Raised when parameters supplied to a service or agent tool
/// do not meet the expected schema or constraints.
final class ValidationError extends ServiceError {
  /// Creates a [ValidationError] with the given [message].
  const ValidationError(super.message);
}

/// An unexpected or uncategorized error occurred.
///
/// Wraps an optional [cause] and [stackTrace] for debugging.
/// Prefer a more specific variant whenever possible.
final class UnknownError extends ServiceError {
  /// Creates an [UnknownError] with the given [message] and optional [cause]
  /// and [stackTrace].
  const UnknownError(super.message, [this.cause, this.stackTrace]);

  /// The underlying exception or error object, if available.
  final Object? cause;

  /// The stack trace captured at the point of failure, if available.
  final StackTrace? stackTrace;

  @override
  String toString() {
    final buffer = StringBuffer('UnknownError: $message');
    if (cause != null) buffer.write(' (cause: $cause)');
    return buffer.toString();
  }
}
