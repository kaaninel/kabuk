/// Generic result type for operations that can succeed or fail.
///
/// Uses sealed classes for exhaustive pattern matching. Prefer [Result]
/// over throwing exceptions for expected failure modes in services and agents.
///
/// ```dart
/// final result = await knowledgeStore.query(...);
/// switch (result) {
///   case Success(:final value):
///     print('Got ${value.length} triples');
///   case Failure(:final error):
///     print('Query failed: $error');
/// }
/// ```
library;

import 'package:kabuk/config/errors.dart';

/// Generic result type for operations that can succeed or fail.
///
/// Every service and agent method that can fail should return a [Result]
/// rather than throwing exceptions. This makes error handling explicit
/// and enables exhaustive pattern matching at call sites.
sealed class Result<T> {
  /// Base constructor for [Result].
  const Result();

  /// Creates a successful result containing [value].
  const factory Result.success(T value) = Success<T>;

  /// Creates a failed result containing [error].
  const factory Result.failure(ServiceError error) = Failure<T>;

  /// Maps the success value using [transform], leaving failures unchanged.
  ///
  /// ```dart
  /// final result = Result.success(42);
  /// final mapped = result.map((v) => v.toString()); // Success('42')
  /// ```
  Result<U> map<U>(U Function(T value) transform);

  /// Maps the success value using an async [transform], leaving failures
  /// unchanged.
  ///
  /// ```dart
  /// final result = Result.success(uri);
  /// final mapped = await result.mapAsync((u) => fetchData(u));
  /// ```
  Future<Result<U>> mapAsync<U>(Future<U> Function(T value) transform);

  /// Returns the success value or throws the contained [ServiceError].
  ///
  /// Only use this when a failure is truly unexpected and should crash.
  /// Prefer pattern matching in normal control flow.
  T getOrThrow();

  /// Returns the success value or the result of calling [orElse].
  ///
  /// ```dart
  /// final name = result.getOrElse(() => 'Unknown');
  /// ```
  T getOrElse(T Function() orElse);

  /// Whether this result represents a successful operation.
  bool get isSuccess;

  /// Whether this result represents a failed operation.
  bool get isFailure;
}

/// A successful [Result] containing a [value].
final class Success<T> extends Result<T> {
  /// Creates a [Success] result with the given [value].
  const Success(this.value);

  /// The successful result value.
  final T value;

  @override
  Result<U> map<U>(U Function(T value) transform) =>
      Result<U>.success(transform(value));

  @override
  Future<Result<U>> mapAsync<U>(Future<U> Function(T value) transform) async =>
      Result<U>.success(await transform(value));

  @override
  T getOrThrow() => value;

  @override
  T getOrElse(T Function() orElse) => value;

  @override
  bool get isSuccess => true;

  @override
  bool get isFailure => false;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is Success<T> && other.value == value);

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'Success($value)';
}

/// A failed [Result] containing a [ServiceError].
final class Failure<T> extends Result<T> {
  /// Creates a [Failure] result with the given [error].
  const Failure(this.error);

  /// The error that caused the operation to fail.
  final ServiceError error;

  @override
  Result<U> map<U>(U Function(T value) transform) => Result<U>.failure(error);

  @override
  Future<Result<U>> mapAsync<U>(Future<U> Function(T value) transform) async =>
      Result<U>.failure(error);

  @override
  T getOrThrow() => throw error;

  @override
  T getOrElse(T Function() orElse) => orElse();

  @override
  bool get isSuccess => false;

  @override
  bool get isFailure => true;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is Failure<T> && other.error == error);

  @override
  int get hashCode => error.hashCode;

  @override
  String toString() => 'Failure($error)';
}
