import 'package:flutter_test/flutter_test.dart';
import 'package:kabuk/config/errors.dart';
import 'package:kabuk/config/result.dart';

void main() {
  group('Result', () {
    // -----------------------------------------------------------------------
    // Construction
    // -----------------------------------------------------------------------

    group('Success', () {
      test('wraps a value', () {
        const result = Result<int>.success(42);
        expect(result, isA<Success<int>>());
        expect((result as Success<int>).value, 42);
      });

      test('isSuccess is true', () {
        const result = Result<String>.success('hello');
        expect(result.isSuccess, isTrue);
      });

      test('isFailure is false', () {
        const result = Result<String>.success('hello');
        expect(result.isFailure, isFalse);
      });
    });

    group('Failure', () {
      test('wraps a ServiceError', () {
        const error = ServiceError.notFound('item/1');
        const result = Result<int>.failure(error);
        expect(result, isA<Failure<int>>());
        expect((result as Failure<int>).error, error);
      });

      test('isSuccess is false', () {
        const result = Result<int>.failure(NotFoundError('x'));
        expect(result.isSuccess, isFalse);
      });

      test('isFailure is true', () {
        const result = Result<int>.failure(NotFoundError('x'));
        expect(result.isFailure, isTrue);
      });
    });

    // -----------------------------------------------------------------------
    // map
    // -----------------------------------------------------------------------

    group('map', () {
      test('transforms Success value', () {
        const result = Result<int>.success(10);
        final mapped = result.map((v) => v * 2);
        expect(mapped.isSuccess, isTrue);
        expect((mapped as Success<int>).value, 20);
      });

      test('maps Success to a different type', () {
        const result = Result<int>.success(42);
        final mapped = result.map((v) => v.toString());
        expect(mapped.isSuccess, isTrue);
        expect((mapped as Success<String>).value, '42');
      });

      test('propagates Failure unchanged', () {
        const error = StorageError('disk full');
        const result = Result<int>.failure(error);
        final mapped = result.map((v) => v * 2);
        expect(mapped.isFailure, isTrue);
        expect((mapped as Failure<int>).error, error);
      });
    });

    // -----------------------------------------------------------------------
    // mapAsync
    // -----------------------------------------------------------------------

    group('mapAsync', () {
      test('transforms Success value asynchronously', () async {
        const result = Result<int>.success(5);
        final mapped = await result.mapAsync((v) async => v + 1);
        expect(mapped.isSuccess, isTrue);
        expect((mapped as Success<int>).value, 6);
      });

      test('propagates Failure unchanged', () async {
        const error = NetworkError('timeout');
        const result = Result<int>.failure(error);
        final mapped = await result.mapAsync((v) async => v + 1);
        expect(mapped.isFailure, isTrue);
        expect((mapped as Failure<int>).error, error);
      });
    });

    // -----------------------------------------------------------------------
    // getOrThrow
    // -----------------------------------------------------------------------

    group('getOrThrow', () {
      test('returns value on Success', () {
        const result = Result<String>.success('ok');
        expect(result.getOrThrow(), 'ok');
      });

      test('throws ServiceError on Failure', () {
        const error = ValidationError('bad input');
        const result = Result<String>.failure(error);
        expect(() => result.getOrThrow(), throwsA(isA<ValidationError>()));
      });
    });

    // -----------------------------------------------------------------------
    // getOrElse
    // -----------------------------------------------------------------------

    group('getOrElse', () {
      test('returns value on Success', () {
        const result = Result<int>.success(99);
        expect(result.getOrElse(() => 0), 99);
      });

      test('returns fallback on Failure', () {
        const result = Result<int>.failure(NotFoundError('x'));
        expect(result.getOrElse(() => -1), -1);
      });
    });

    // -----------------------------------------------------------------------
    // Equality
    // -----------------------------------------------------------------------

    group('equality', () {
      test('two Success with same value are equal', () {
        const a = Result<int>.success(1);
        const b = Result<int>.success(1);
        expect(a, equals(b));
        expect(a.hashCode, b.hashCode);
      });

      test('two Success with different values are not equal', () {
        const a = Result<int>.success(1);
        const b = Result<int>.success(2);
        expect(a, isNot(equals(b)));
      });

      test('two Failure with same error are equal', () {
        const a = Result<int>.failure(NotFoundError('x'));
        const b = Result<int>.failure(NotFoundError('x'));
        expect(a, equals(b));
        expect(a.hashCode, b.hashCode);
      });

      test('Success and Failure are never equal', () {
        const a = Result<int>.success(0);
        const b = Result<int>.failure(StorageError('oops'));
        expect(a, isNot(equals(b)));
      });
    });

    // -----------------------------------------------------------------------
    // toString
    // -----------------------------------------------------------------------

    group('toString', () {
      test('Success toString', () {
        const result = Result<int>.success(42);
        expect(result.toString(), 'Success(42)');
      });

      test('Failure toString', () {
        const result = Result<int>.failure(NotFoundError('item'));
        expect(result.toString(), contains('Failure'));
        expect(result.toString(), contains('NotFoundError'));
      });
    });

    // -----------------------------------------------------------------------
    // Pattern matching
    // -----------------------------------------------------------------------

    group('pattern matching', () {
      test('switch expression on Success', () {
        const result = Result<int>.success(7);
        final output = switch (result) {
          Success(:final value) => 'got $value',
          Failure(:final error) => 'err: $error',
        };
        expect(output, 'got 7');
      });

      test('switch expression on Failure', () {
        const result = Result<int>.failure(AgentError('boom'));
        final output = switch (result) {
          Success(:final value) => 'got $value',
          Failure(:final error) => 'err: ${error.message}',
        };
        expect(output, 'err: boom');
      });
    });
  });

  // -------------------------------------------------------------------------
  // ServiceError variants
  // -------------------------------------------------------------------------

  group('ServiceError', () {
    test('NotSupportedError', () {
      const e = ServiceError.notSupported('bluetooth');
      expect(e, isA<NotSupportedError>());
      expect((e as NotSupportedError).feature, 'bluetooth');
      expect(e.message, contains('bluetooth'));
    });

    test('PermissionDeniedError', () {
      const e = ServiceError.permissionDenied('camera');
      expect(e, isA<PermissionDeniedError>());
      expect((e as PermissionDeniedError).permission, 'camera');
    });

    test('NotFoundError', () {
      const e = ServiceError.notFound('user/123');
      expect(e, isA<NotFoundError>());
      expect((e as NotFoundError).resource, 'user/123');
    });

    test('NetworkError', () {
      const e = ServiceError.network('timeout');
      expect(e, isA<NetworkError>());
    });

    test('EncryptionError', () {
      const e = ServiceError.encryption('bad key');
      expect(e, isA<EncryptionError>());
    });

    test('StorageError', () {
      const e = ServiceError.storage('disk full');
      expect(e, isA<StorageError>());
    });

    test('AgentError', () {
      const e = ServiceError.agent('agent crashed');
      expect(e, isA<AgentError>());
    });

    test('LlmError', () {
      const e = ServiceError.llm('rate limited');
      expect(e, isA<LlmError>());
    });

    test('ValidationError', () {
      const e = ServiceError.validation('missing field');
      expect(e, isA<ValidationError>());
    });

    test('UnknownError with cause', () {
      final cause = Exception('underlying');
      final e = ServiceError.unknown('oops', cause);
      expect(e, isA<UnknownError>());
      expect((e as UnknownError).cause, cause);
      expect(e.toString(), contains('oops'));
      expect(e.toString(), contains('underlying'));
    });
  });
}
