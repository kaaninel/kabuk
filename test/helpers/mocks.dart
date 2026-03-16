/// Central mock definitions for all Kabuk tests.
///
/// Import this file in every test to get pre-built mocks for all
/// services, stores, and the agent runtime.
library;

import 'package:kabuk/agents/context.dart';
import 'package:kabuk/agents/llm.dart';
import 'package:kabuk/agents/messages.dart';
import 'package:kabuk/agents/runtime.dart';
import 'package:kabuk/config/errors.dart';
import 'package:kabuk/config/result.dart';
import 'package:kabuk/knowledge/mutation.dart';
import 'package:kabuk/knowledge/query.dart';
import 'package:kabuk/knowledge/store.dart';
import 'package:kabuk/knowledge/triple.dart';
import 'package:kabuk/services/auth.dart';
import 'package:kabuk/services/feed.dart';
import 'package:kabuk/services/media.dart';
import 'package:kabuk/services/mesh.dart';
import 'package:kabuk/services/nostr.dart';
import 'package:kabuk/services/notification.dart';
import 'package:kabuk/services/presentation.dart';
import 'package:kabuk/services/vault.dart';
import 'package:mocktail/mocktail.dart';

// ---------------------------------------------------------------------------
// Mock classes
// ---------------------------------------------------------------------------

/// Mock implementation of [KnowledgeStore].
///
/// Overrides [mutate] to properly handle the generic type parameter,
/// which mocktail's default stub resolution cannot match reliably.
/// Also overrides [query] to return a default empty-result builder
/// so agent memory loading doesn't fail when unstubbed.
class MockKnowledgeStore extends Mock implements KnowledgeStore {
  /// Optional handler for [mutate] calls. Set this in your test to
  /// intercept mutation transactions.
  Future<T> Function<T>(Future<T> Function(MutationContext ctx) action)?
  onMutate;

  /// Optional handler for [query] calls. Set this to return a custom
  /// [QueryBuilder] with specific stubs for your test.
  QueryBuilder Function()? onQuery;

  /// How many times [mutate] has been called.
  int mutateCallCount = 0;

  @override
  Future<T> mutate<T>(Future<T> Function(MutationContext ctx) action) async {
    mutateCallCount++;
    if (onMutate != null) return onMutate!<T>(action);
    // Default: execute with a FakeMutationContext (no-op stubs).
    return action(FakeMutationContext());
  }

  @override
  QueryBuilder query() {
    if (onQuery != null) return onQuery!();
    final qb = MockQueryBuilder();
    when(() => qb.where(any(), equals: any(named: 'equals'))).thenReturn(qb);
    when(() => qb.execute()).thenAnswer((_) async => []);
    return qb;
  }
}

/// Mock implementation of [LlmService].
class MockLlmService extends Mock implements LlmService {}

/// Mock implementation of [VaultService].
class MockVaultService extends Mock implements VaultService {}

/// Mock implementation of [MeshService].
class MockMeshService extends Mock implements MeshService {}

/// Mock implementation of [MediaService].
class MockMediaService extends Mock implements MediaService {}

/// Mock implementation of [AuthService].
class MockAuthService extends Mock implements AuthService {}

/// Mock implementation of [NotificationService].
class MockNotificationService extends Mock implements NotificationService {}

/// Mock implementation of [PresentationService].
class MockPresentationService extends Mock implements PresentationService {}

/// Mock implementation of [NostrService].
class MockNostrService extends Mock implements NostrService {}

/// Mock implementation of [FeedService].
class MockFeedService extends Mock implements FeedService {}

/// Mock implementation of [FeedSource].
class MockFeedSource extends Mock implements FeedSource {}

/// Mock implementation of [AgentRuntime].
class MockAgentRuntime extends Mock implements AgentRuntime {}

/// Mock implementation of [QueryBuilder].
class MockQueryBuilder extends Mock implements QueryBuilder {}

/// Mock implementation of [MutationContext].
class MockMutationContext extends Mock implements MutationContext {}

/// Fake implementation of [MutationContext] with no-op defaults.
///
/// Used as the default context in [MockKnowledgeStore.mutate] to avoid
/// polluting mocktail's matcher state with `when()`/`any()` inside
/// production code paths.
class FakeMutationContext extends Fake implements MutationContext {
  int _counter = 0;

  @override
  String create(String type) {
    _counter++;
    return 'kabuk:$type/$_counter';
  }

  @override
  Future<void> set(
    String subject,
    String predicate,
    dynamic object, {
    ObjectType? objectType,
    String? graph,
  }) async {}

  @override
  Future<void> add(
    String subject,
    String predicate,
    dynamic object, {
    ObjectType? objectType,
    String? graph,
  }) async {}

  @override
  Future<void> remove({
    String? subject,
    String? predicate,
    String? object,
  }) async {}

  @override
  Future<String> storeBlob(List<int> data, {String? mimeType}) async =>
      'fake-hash';

  @override
  Future<Result<List<int>>> retrieveBlob(String hash) async =>
      const Result.failure(ServiceError.notFound('Not found'));
}

// ---------------------------------------------------------------------------
// Fallback values
// ---------------------------------------------------------------------------

/// A fallback [LlmRequest] for use with `registerFallbackValue`.
class FakeLlmRequest extends Fake implements LlmRequest {}

/// A fallback mutation action function for use with `registerFallbackValue`.
Future<void> fakeMutationAction(MutationContext ctx) async {}

// ---------------------------------------------------------------------------
// Helper: build a fully-mocked AgentContext
// ---------------------------------------------------------------------------

/// All mocks needed to construct an [AgentContext].
///
/// Use [createMockAgentContext] to get an instance with all fields set.
class MockAgentContextBundle {
  MockAgentContextBundle()
    : knowledge = MockKnowledgeStore(),
      vault = MockVaultService(),
      mesh = MockMeshService(),
      media = MockMediaService(),
      auth = MockAuthService(),
      notification = MockNotificationService(),
      presentation = MockPresentationService(),
      nostr = MockNostrService(),
      feed = MockFeedService(),
      llm = MockLlmService(),
      runtime = MockAgentRuntime();

  final MockKnowledgeStore knowledge;
  final MockVaultService vault;
  final MockMeshService mesh;
  final MockMediaService media;
  final MockAuthService auth;
  final MockNotificationService notification;
  final MockPresentationService presentation;
  final MockNostrService nostr;
  final MockFeedService feed;
  final MockLlmService llm;
  final MockAgentRuntime runtime;

  /// Build the [AgentContext] wired to all mocks.
  AgentContext get context => AgentContext(
    knowledge: knowledge,
    vault: vault,
    mesh: mesh,
    media: media,
    auth: auth,
    notification: notification,
    presentation: presentation,
    nostr: nostr,
    feed: feed,
    llm: llm,
    runtime: runtime,
  );
}

/// Creates a [MockAgentContextBundle] containing all mocks and the
/// assembled [AgentContext].
///
/// ```dart
/// final bundle = createMockAgentContext();
/// when(() => bundle.llm.complete(any())).thenAnswer((_) async => ...);
/// final response = await agent.process(message, bundle.context);
/// ```
MockAgentContextBundle createMockAgentContext() => MockAgentContextBundle();

// ---------------------------------------------------------------------------
// Streaming test helpers
// ---------------------------------------------------------------------------

/// Stubs [llm.stream] to emit a single text delta followed by done.
///
/// Use this in place of the old `complete()` stub when testing agents
/// that now use streaming via `processLlmRequest()`.
void stubLlmStreamText(MockLlmService llm, String text) {
  when(() => llm.stream(any())).thenAnswer(
    (_) => Stream.fromIterable([
      LlmStreamEvent.textDelta(text),
      const LlmStreamEvent.done(),
    ]),
  );
}

/// Stubs [llm.stream] to throw an [LlmStreamException] synchronously.
///
/// This causes `processLlmRequest()` to catch the exception and return
/// an [ErrorAgentResponse] with the given [message].
void stubLlmStreamError(MockLlmService llm, String message) {
  when(() => llm.stream(any())).thenThrow(LlmStreamException(message));
}

/// Stubs [llm.stream] to emit tool call events.
void stubLlmStreamToolCalls(MockLlmService llm, List<LlmToolCall> calls) {
  when(() => llm.stream(any())).thenAnswer(
    (_) => Stream.fromIterable([
      for (final call in calls) LlmStreamEvent.toolCall(call),
      const LlmStreamEvent.done(),
    ]),
  );
}

/// Collects all text from a [StreamingAgentResponse].
///
/// Asserts that [response] is a [StreamingAgentResponse], listens to
/// the event stream, concatenates text deltas, and returns the result.
Future<String> collectStreamingText(AgentResponse response) async {
  if (response is! StreamingAgentResponse) {
    throw StateError(
      'Expected StreamingAgentResponse, got ${response.runtimeType}',
    );
  }
  final buffer = StringBuffer();
  await for (final event in response.events) {
    if (event case TextDeltaEvent(:final text)) {
      buffer.write(text);
    }
  }
  return buffer.toString();
}
