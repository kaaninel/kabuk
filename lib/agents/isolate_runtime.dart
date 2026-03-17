/// Isolate-based agent runtime — runs each agent invocation in a
/// separate Dart isolate for sandboxing and parallelism.
///
/// This replaces the main-isolate execution path in `_SimpleAgentRuntime`.
/// Because Flutter services (network, DB, etc.) can't be transferred
/// across isolate boundaries, the isolate does only the CPU-bound parts
/// (LLM response parsing, prompt construction, tool-call loop logic)
/// while service calls are proxied back to the main isolate via a
/// bidirectional port protocol.
///
/// **All service calls** (LLM, knowledge store, auth, vault, etc.) are
/// proxied via message passing to ensure isolate safety.
///
/// **Tool execution** is also proxied: the isolate sends a tool-call
/// request to the host, which looks up the real agent, executes the
/// tool with the real [AgentContext], and sends the result back.
/// This avoids the closure-serialization problem entirely — closures
/// never cross the isolate boundary.
library;

import 'dart:async';
import 'dart:developer' as dev;
import 'dart:isolate';
import 'dart:typed_data';

import 'package:kabuk/agents/base.dart';
import 'package:kabuk/agents/context.dart';
import 'package:kabuk/agents/llm.dart';
import 'package:kabuk/agents/messages.dart';
import 'package:kabuk/agents/runtime.dart';
import 'package:kabuk/config/errors.dart';
import 'package:kabuk/config/result.dart';
import 'package:kabuk/knowledge/changes.dart';
import 'package:kabuk/knowledge/mutation.dart';
import 'package:kabuk/knowledge/query.dart';
import 'package:kabuk/knowledge/store.dart';
import 'package:kabuk/knowledge/triple.dart';
import 'package:kabuk/services/auth.dart';
import 'package:kabuk/services/media.dart';
import 'package:kabuk/services/mesh.dart';
import 'package:kabuk/services/notification.dart';
import 'package:kabuk/services/presentation.dart';
import 'package:kabuk/services/vault.dart';

// ---------------------------------------------------------------------------
// Isolate message protocol
// ---------------------------------------------------------------------------

/// A request sent from the isolate to the host for service calls.
sealed class _IsolateRequest {
  const _IsolateRequest();
}

/// Request to complete an LLM prompt.
final class _LlmCompleteRequest extends _IsolateRequest {
  const _LlmCompleteRequest(this.id, this.request);
  final int id;
  final LlmRequest request;
}

/// Request to execute a knowledge store query.
final class _KnowledgeQueryRequest extends _IsolateRequest {
  const _KnowledgeQueryRequest(this.id, this.filters);
  final int id;
  final _QueryFilters filters;
}

/// Request to execute a knowledge store mutation.
final class _KnowledgeMutateRequest extends _IsolateRequest {
  const _KnowledgeMutateRequest(this.id, this.operations);
  final int id;
  final List<_MutationOp> operations;
}

/// Request to get an entity by subject URI.
final class _KnowledgeGetEntityRequest extends _IsolateRequest {
  const _KnowledgeGetEntityRequest(this.id, this.subjectUri);
  final int id;
  final String subjectUri;
}

/// Request to get multiple entities by subject URIs.
final class _KnowledgeGetEntitiesRequest extends _IsolateRequest {
  const _KnowledgeGetEntitiesRequest(this.id, this.subjects);
  final int id;
  final List<String> subjects;
}

/// Request to search the knowledge store.
final class _KnowledgeSearchRequest extends _IsolateRequest {
  const _KnowledgeSearchRequest(this.id, this.query, this.limit);
  final int id;
  final String query;
  final int limit;
}

/// Request to execute an agent tool on the main isolate.
final class _ToolExecuteRequest extends _IsolateRequest {
  const _ToolExecuteRequest(this.id, this.toolName, this.args);
  final int id;
  final String toolName;
  final Map<String, dynamic> args;
}

/// Request to stream an LLM response (multiple events).
final class _LlmStreamRequest extends _IsolateRequest {
  const _LlmStreamRequest(this.id, this.request);
  final int id;
  final LlmRequest request;
}

/// Response from the host to the isolate for a service call.
sealed class _IsolateResponse {
  const _IsolateResponse();
  int get id;
}

/// LLM completion result.
final class _LlmCompleteResponse extends _IsolateResponse {
  const _LlmCompleteResponse(this.id, this.response);
  @override
  final int id;
  final LlmResponse response;
}

/// Knowledge query result.
final class _KnowledgeQueryResponse extends _IsolateResponse {
  const _KnowledgeQueryResponse(this.id, this.triples);
  @override
  final int id;
  final List<Triple> triples;
}

/// Knowledge mutation result.
final class _KnowledgeMutateResponse extends _IsolateResponse {
  const _KnowledgeMutateResponse(this.id, this.result);
  @override
  final int id;
  final dynamic result;
}

/// Knowledge entity result.
final class _KnowledgeEntityResponse extends _IsolateResponse {
  const _KnowledgeEntityResponse(this.id, this.triples);
  @override
  final int id;
  final List<Triple> triples;
}

/// Knowledge entities result (multiple).
final class _KnowledgeEntitiesResponse extends _IsolateResponse {
  const _KnowledgeEntitiesResponse(this.id, this.entities);
  @override
  final int id;
  final Map<String, List<Triple>> entities;
}

/// Knowledge search result.
final class _KnowledgeSearchResponse extends _IsolateResponse {
  const _KnowledgeSearchResponse(this.id, this.triples);
  @override
  final int id;
  final List<Triple> triples;
}

/// Error from a service call.
final class _IsolateErrorResponse extends _IsolateResponse {
  const _IsolateErrorResponse(this.id, this.error);
  @override
  final int id;
  final ServiceError error;
}

/// Tool execution result from the main isolate.
final class _ToolExecuteResponse extends _IsolateResponse {
  const _ToolExecuteResponse(this.id, this.resultJson);
  @override
  final int id;
  final Map<String, dynamic> resultJson;
}

/// A single LLM stream event forwarded from host to isolate.
final class _LlmStreamEventResponse extends _IsolateResponse {
  const _LlmStreamEventResponse(this.id, this.event);
  @override
  final int id;
  final LlmStreamEvent event;
}

/// Signals that the LLM stream has completed.
final class _LlmStreamEndResponse extends _IsolateResponse {
  const _LlmStreamEndResponse(this.id);
  @override
  final int id;
}

// ---------------------------------------------------------------------------
// Serializable query/mutation descriptors
// ---------------------------------------------------------------------------

/// Serializable query filter descriptor for isolate boundary crossing.
class _QueryFilters {
  const _QueryFilters({
    this.subject,
    this.predicate,
    this.object,
    this.type,
    this.limit,
    this.offset,
  });
  final String? subject;
  final String? predicate;
  final String? object;
  final String? type;
  final int? limit;
  final int? offset;
}

/// A single mutation operation — set, add, or remove.
sealed class _MutationOp {
  const _MutationOp();
}

final class _SetOp extends _MutationOp {
  const _SetOp(this.subject, this.predicate, this.object);
  final String subject;
  final String predicate;
  final String object;
}

final class _AddOp extends _MutationOp {
  const _AddOp(this.subject, this.predicate, this.object);
  final String subject;
  final String predicate;
  final String object;
}

final class _RemoveOp extends _MutationOp {
  const _RemoveOp({this.subject, this.predicate, this.object});
  final String? subject;
  final String? predicate;
  final String? object;
}

final class _CreateOp extends _MutationOp {
  const _CreateOp(this.type, this.resultIndex);
  final String type;

  /// Index into a list so the isolate can reference the created URI.
  final int resultIndex;
}

// ---------------------------------------------------------------------------
// Serializable agent descriptor (crosses isolate boundary instead of agent)
// ---------------------------------------------------------------------------

/// Serializable description of an agent — carries everything the isolate
/// needs to reconstruct a shim agent without transferring closures.
class _AgentDescriptor {
  const _AgentDescriptor({
    required this.name,
    required this.description,
    required this.systemPrompt,
    required this.toolSchemas,
    required this.toolNames,
  });

  final String name;
  final String description;
  final String systemPrompt;

  /// JSON Schema definitions for each tool (for LLM function calling).
  final List<Map<String, dynamic>> toolSchemas;

  /// Ordered tool names, parallel to [toolSchemas].
  final List<String> toolNames;

  /// Creates a descriptor from a real [BaseAgent].
  factory _AgentDescriptor.fromAgent(BaseAgent agent) => _AgentDescriptor(
    name: agent.name,
    description: agent.description,
    systemPrompt: agent.buildSystemPrompt(),
    toolSchemas: agent.tools.map((t) => t.toFunctionSchema()).toList(),
    toolNames: agent.tools.map((t) => t.name).toList(),
  );
}

/// Wrapper sent from the isolate to forward an [LlmStreamEvent].
class _AgentStreamEventMessage {
  const _AgentStreamEventMessage(this.event);
  final LlmStreamEvent event;
}

/// Signals the agent's streaming response is complete.
class _AgentStreamDone {
  const _AgentStreamDone();
}

/// Handshake: isolate sends its [SendPort] to the host.
class _HandshakeMessage {
  const _HandshakeMessage(this.isolateSendPort);
  final SendPort isolateSendPort;
}

// ---------------------------------------------------------------------------
// Isolate entry point
// ---------------------------------------------------------------------------

/// Entry-point function spawned in each agent isolate.
///
/// Receives an [_IsolateBootstrap] with a serializable agent descriptor,
/// the message, and ports for bidirectional communication. A shim agent
/// is created inside the isolate — its tool `execute` closures are created
/// locally (never cross the boundary) and proxy calls back to the host.
Future<void> _agentIsolateEntry(_IsolateBootstrap bootstrap) async {
  // Create a ReceivePort for responses from the host.
  final responsePort = ReceivePort();
  final responseBroadcast = responsePort.asBroadcastStream();

  // Send our SendPort back so the host can send us responses.
  bootstrap.requestPort.send(_HandshakeMessage(responsePort.sendPort));

  try {
    // Build proxy services that route calls back to the host.
    final proxyKnowledge = _ProxyKnowledgeStore(
      send: bootstrap.requestPort,
      receive: responseBroadcast,
    );
    final proxyLlm = _ProxyLlmService(
      send: bootstrap.requestPort,
      receive: responseBroadcast,
    );

    // Create the shim agent from the descriptor. Tool execute closures
    // are created HERE (inside the isolate) — they proxy via SendPort
    // and never need to be serialized.
    final shimAgent = _IsolateShimAgent(
      descriptor: bootstrap.descriptor,
      requestPort: bootstrap.requestPort,
      responseStream: responseBroadcast,
    );

    // Build a proxy AgentContext. Services that agents rarely call
    // (vault, mesh, etc.) are stubbed — the core services (knowledge,
    // LLM) are fully proxied.
    final proxyContext = AgentContext(
      knowledge: proxyKnowledge,
      vault: _StubVaultService(),
      mesh: _StubMeshService(),
      media: _StubMediaService(),
      auth: _StubAuthService(),
      notification: _StubNotificationService(),
      presentation: _StubPresentationService(),
      llm: proxyLlm,
      runtime: _StubAgentRuntime(),
    );

    final response = await shimAgent.process(bootstrap.message, proxyContext);

    // Handle the response: streams can't be sent across isolate
    // boundaries, so we consume them and forward events via port.
    switch (response) {
      case StreamingAgentResponse(:final events):
        await for (final event in events) {
          bootstrap.resultPort.send(_AgentStreamEventMessage(event));
        }
        bootstrap.resultPort.send(const _AgentStreamDone());
      case TextAgentResponse():
        bootstrap.resultPort.send(response);
      case WidgetAgentResponse():
        bootstrap.resultPort.send(response);
      case ErrorAgentResponse():
        bootstrap.resultPort.send(response);
    }
  } on Object catch (e, st) {
    bootstrap.resultPort.send(
      AgentResponse.error('Isolate agent error: $e\n$st'),
    );
  } finally {
    responsePort.close();
  }
}

/// Serializable bootstrap message passed to the agent isolate.
///
/// Contains only data that can be transferred across isolate boundaries:
/// the agent descriptor (strings/maps), the message, and SendPorts.
class _IsolateBootstrap {
  const _IsolateBootstrap({
    required this.descriptor,
    required this.message,
    required this.resultPort,
    required this.requestPort,
  });

  /// Serializable agent metadata (no closures).
  final _AgentDescriptor descriptor;

  /// The user's message to process.
  final AgentMessage message;

  /// Port to send the final result/stream events back to the host.
  final SendPort resultPort;

  /// Port to send service proxy requests to the host.
  final SendPort requestPort;
}

// ---------------------------------------------------------------------------
// Shim agent — reconstructed inside the isolate from a descriptor
// ---------------------------------------------------------------------------

/// A lightweight agent created inside the isolate that proxies tool
/// execution back to the main isolate.
///
/// Tool `execute` closures are created locally within the isolate —
/// they send [_ToolExecuteRequest] messages via [requestPort] and
/// await [_ToolExecuteResponse] from [responseStream]. This avoids
/// the core serialization problem: closures never cross isolate boundaries.
class _IsolateShimAgent extends BaseAgent {
  _IsolateShimAgent({
    required _AgentDescriptor descriptor,
    required SendPort requestPort,
    required Stream<dynamic> responseStream,
  }) : _descriptor = descriptor,
       _requestPort = requestPort,
       _responseStream = responseStream,
       _nextId = 0;

  final _AgentDescriptor _descriptor;
  final SendPort _requestPort;
  final Stream<dynamic> _responseStream;
  int _nextId;

  @override
  String get name => _descriptor.name;

  @override
  String get description => _descriptor.description;

  @override
  String get systemPrompt => _descriptor.systemPrompt;

  @override
  String buildSystemPrompt({bool includeIdentity = true}) =>
      _descriptor.systemPrompt;

  @override
  Set<AgentCapability> get requiredCapabilities => {};

  @override
  List<AgentTool> get tools => List.generate(_descriptor.toolNames.length, (i) {
    final toolName = _descriptor.toolNames[i];
    final schema = _descriptor.toolSchemas[i];
    final funcDef = schema['function'] as Map<String, dynamic>;
    return AgentTool(
      name: toolName,
      description: (funcDef['description'] as String?) ?? '',
      parameters: (funcDef['parameters'] as Map<String, dynamic>?) ?? const {},
      execute: (args, context) => _proxyToolExecute(toolName, args),
    );
  });

  /// Proxies a tool execution request to the main isolate and waits
  /// for the result.
  Future<ToolResult> _proxyToolExecute(
    String toolName,
    Map<String, dynamic> args,
  ) async {
    final id = _nextId++;
    _requestPort.send(_ToolExecuteRequest(id, toolName, args));

    // Wait for the matching response.
    final response = await _responseStream
        .where((msg) => msg is _IsolateResponse && msg.id == id)
        .first;

    return switch (response) {
      _ToolExecuteResponse(:final resultJson) => _deserializeToolResult(
        resultJson,
      ),
      _IsolateErrorResponse(:final error) => ToolResult.error(error.message),
      _ => const ToolResult.error('Unexpected proxy response'),
    };
  }

  /// Reconstruct a [ToolResult] from its JSON representation.
  ToolResult _deserializeToolResult(Map<String, dynamic> json) {
    return switch (json['type'] as String?) {
      'text' => ToolResult.text(json['content'] as String? ?? ''),
      'error' => ToolResult.error(json['message'] as String? ?? 'Unknown'),
      'widget' => ToolResult.widget(
        library: json['library'] as String? ?? '',
        widget: json['widget'] as String? ?? '',
        bindings: (json['bindings'] as Map<String, dynamic>?) ?? const {},
        data: json['data'] as Map<String, dynamic>?,
      ),
      'raw_widget' => ToolResult.rawWidget(
        source: json['source'] as String? ?? '',
        data: (json['data'] as Map<String, dynamic>?) ?? const {},
      ),
      'mutation' => ToolResult.mutation(
        added:
            (json['added'] as List?)?.cast<Map<String, dynamic>>() ?? const [],
        removed:
            (json['removed'] as List?)?.cast<Map<String, dynamic>>() ??
            const [],
      ),
      'compound' => ToolResult.compound(
        (json['results'] as List?)
                ?.map((r) => _deserializeToolResult(r as Map<String, dynamic>))
                .toList() ??
            const [],
      ),
      _ => ToolResult.text(json.toString()),
    };
  }

  @override
  Future<AgentResponse> process(
    AgentMessage message,
    AgentContext context,
  ) async {
    // Extract the user content from the message.
    final content = switch (message) {
      UserMessage(:final content) => content,
      SystemMessage(:final content) => content,
      _ => '',
    };

    // Build LLM messages from conversation history if available.
    final history = switch (message) {
      UserMessage(:final history) => history ?? <LlmMessage>[],
      _ => <LlmMessage>[],
    };

    final messages = [...history, LlmMessage.user(content)];

    return processLlmRequest(
      context: context,
      messages: messages,
      systemPrompt: _descriptor.systemPrompt,
    );
  }
}

// ---------------------------------------------------------------------------
// Proxy KnowledgeStore — forwards calls via isolate ports
// ---------------------------------------------------------------------------

/// Knowledge store proxy that serializes operations and sends them
/// across the isolate boundary as messages.
///
/// Uses a broadcast [Stream] shared across all proxies. Each request
/// gets a unique [_nextId] and the proxy filters responses by that id.
class _ProxyKnowledgeStore implements KnowledgeStore {
  _ProxyKnowledgeStore({required this.send, required this.receive});

  final SendPort send;
  final Stream<dynamic> receive;
  int _nextId = 0;

  /// Waits for the response matching [id] from the shared broadcast stream.
  Future<dynamic> _awaitResponse(int id) =>
      receive.where((msg) => msg is _IsolateResponse && msg.id == id).first;

  @override
  QueryBuilder query() => QueryBuilder(_ProxyQueryExecutor(this));

  @override
  Future<T> mutate<T>(Future<T> Function(MutationContext ctx) action) async {
    final recorder = _RecordingMutationContext();
    final result = await action(recorder);

    final id = _nextId++;
    send.send(_KnowledgeMutateRequest(id, recorder.operations));
    final response = await _awaitResponse(id);
    if (response is _IsolateErrorResponse) {
      throw StateError(response.error.message);
    }
    return result;
  }

  @override
  Stream<List<Triple>> watch({
    String? subject,
    String? predicate,
    String? object,
  }) {
    // Watching across isolate boundaries is complex — return an empty stream.
    // Agents should not typically watch from within a single invocation.
    return const Stream.empty();
  }

  @override
  Future<List<Triple>> search(String query, {int limit = 20}) async {
    final id = _nextId++;
    send.send(_KnowledgeSearchRequest(id, query, limit));
    final response = await _awaitResponse(id);
    return switch (response) {
      _KnowledgeSearchResponse(:final triples) => triples,
      _IsolateErrorResponse(:final error) => throw StateError(error.message),
      _ => <Triple>[],
    };
  }

  @override
  Future<List<Triple>> getEntity(String subjectUri) async {
    final id = _nextId++;
    send.send(_KnowledgeGetEntityRequest(id, subjectUri));
    final response = await _awaitResponse(id);
    return switch (response) {
      _KnowledgeEntityResponse(:final triples) => triples,
      _IsolateErrorResponse(:final error) => throw StateError(error.message),
      _ => <Triple>[],
    };
  }

  @override
  Future<Map<String, List<Triple>>> getEntities(List<String> subjects) async {
    final id = _nextId++;
    send.send(_KnowledgeGetEntitiesRequest(id, subjects));
    final response = await _awaitResponse(id);
    return switch (response) {
      _KnowledgeEntitiesResponse(:final entities) => entities,
      _IsolateErrorResponse(:final error) => throw StateError(error.message),
      _ => <String, List<Triple>>{},
    };
  }

  @override
  Stream<ChangeSet> get changes => const Stream.empty();

  @override
  Future<void> close() async {
    // No-op in proxy — the real store is owned by the main isolate.
  }

  /// Executes a query using the proxy.
  Future<List<Triple>> executeQuery(_QueryFilters filters) async {
    final id = _nextId++;
    send.send(_KnowledgeQueryRequest(id, filters));
    final response = await _awaitResponse(id);
    return switch (response) {
      _KnowledgeQueryResponse(:final triples) => triples,
      _IsolateErrorResponse(:final error) => throw StateError(error.message),
      _ => <Triple>[],
    };
  }
}

/// Records mutation operations without executing them.
class _RecordingMutationContext implements MutationContext {
  final List<_MutationOp> operations = [];
  int _createIndex = 0;
  final Map<int, String> _createdUris = {};

  @override
  String create(String type) {
    final idx = _createIndex++;
    operations.add(_CreateOp(type, idx));
    // Return a placeholder URI — the real URI is generated on the main isolate.
    final uri = 'kabuk:$type/_pending_$idx';
    _createdUris[idx] = uri;
    return uri;
  }

  @override
  Future<void> set(
    String subject,
    String predicate,
    dynamic object, {
    ObjectType? objectType,
    String? graph,
  }) async {
    operations.add(_SetOp(subject, predicate, object.toString()));
  }

  @override
  Future<void> add(
    String subject,
    String predicate,
    dynamic object, {
    ObjectType? objectType,
    String? graph,
  }) async {
    operations.add(_AddOp(subject, predicate, object.toString()));
  }

  @override
  Future<void> remove({
    String? subject,
    String? predicate,
    String? object,
  }) async {
    operations.add(
      _RemoveOp(subject: subject, predicate: predicate, object: object),
    );
  }

  @override
  Future<String> storeBlob(List<int> data, {String? mimeType}) async {
    // Blob operations are not proxied in the current implementation.
    // Agents requiring blob storage should use the main isolate path.
    throw StateError(
      'storeBlob is not supported in isolate proxy. '
      'Use the main isolate path for blob storage.',
    );
  }

  @override
  Future<Result<List<int>>> retrieveBlob(String hash) async {
    return const Result.failure(
      const NotFoundError('Blob retrieval not supported in isolate proxy'),
    );
  }
}

/// A [QueryExecutor] that serializes queries and sends them across the
/// isolate boundary for execution on the main isolate.
class _ProxyQueryExecutor implements QueryExecutor {
  _ProxyQueryExecutor(this._store);
  final _ProxyKnowledgeStore _store;

  @override
  Future<List<Triple>> execute(QueryBuilder builder) {
    return _store.executeQuery(
      _QueryFilters(
        subject: builder.subjectFilter,
        predicate: builder.predicateFilter,
        object: builder.objectFilter,
        type: null, // whereType is already handled by clauses
        limit: builder.limitValue,
        offset: builder.offsetValue,
      ),
    );
  }

  @override
  Future<Triple?> first(QueryBuilder builder) async {
    final results = await execute(builder.limit(1));
    return results.isEmpty ? null : results.first;
  }

  @override
  Future<int> count(QueryBuilder builder) async {
    final results = await execute(builder);
    return results.length;
  }

  @override
  Stream<List<Triple>> stream(QueryBuilder builder) {
    // Streaming not supported across isolate boundary.
    return const Stream.empty();
  }
}

/// LLM service proxy that forwards calls via isolate ports.
///
/// Uses the shared broadcast [receive] stream to correlate responses by id.
class _ProxyLlmService implements LlmService {
  _ProxyLlmService({required this.send, required this.receive});

  final SendPort send;
  final Stream<dynamic> receive;
  int _nextId = 0;

  @override
  Future<LlmResponse> complete(LlmRequest request) async {
    final id = _nextId++;
    send.send(_LlmCompleteRequest(id, request));
    final response = await receive
        .where((msg) => msg is _IsolateResponse && msg.id == id)
        .first;
    return switch (response) {
      _LlmCompleteResponse(:final response) => response,
      _IsolateErrorResponse(:final error) => LlmResponse.error(error.message),
      _ => const LlmResponse.error('Unexpected proxy response type'),
    };
  }

  @override
  Stream<LlmStreamEvent> stream(LlmRequest request) async* {
    final id = _nextId++;
    send.send(_LlmStreamRequest(id, request));

    // Listen for stream events from the host until we get an end signal.
    await for (final msg in receive) {
      if (msg is _LlmStreamEventResponse && msg.id == id) {
        yield msg.event;
      } else if (msg is _LlmStreamEndResponse && msg.id == id) {
        break;
      }
    }
  
  }

  @override
  int countTokens(String text) => (text.length / 4).ceil();
}

// ---------------------------------------------------------------------------
// Stub services — lightweight no-ops for rarely-used services in isolates
// ---------------------------------------------------------------------------

/// Stub [VaultService] — agents in isolates cannot access the vault.
class _StubVaultService implements VaultService {
  @override
  Future<VaultEntry> store(
    Uint8List data, {
    required String name,
    String? mimeType,
    Map<String, String>? metadata,
    List<String>? tags,
    bool encrypt = true,
  }) => throw StateError('VaultService not available in isolate');

  @override
  Future<Result<Uint8List>> retrieve(String hash) async => const Result.failure(
    const NotFoundError('VaultService not available in isolate'),
  );

  @override
  Future<Result<void>> delete(String hash) async => const Result.failure(
    const NotFoundError('VaultService not available in isolate'),
  );

  @override
  Future<List<VaultEntry>> list({
    List<String>? tags,
    String? mimeTypePrefix,
    int? limit,
    int? offset,
  }) async => const [];

  @override
  Future<List<VaultEntry>> search(String query) async => const [];

  @override
  Stream<VaultChange> watchChanges() => const Stream.empty();

  @override
  Future<Result<VaultEntry>> updateTags(String hash, List<String> tags) async =>
      const Result.failure(
        const NotFoundError('VaultService not available in isolate'),
      );

  @override
  Future<VaultStats> getStats() =>
      throw StateError('VaultService not available in isolate');

  @override
  Future<VaultEntry> importFromPath(String platformPath) =>
      throw StateError('VaultService not available in isolate');
}

/// Stub [MeshService] — agents in isolates cannot make network calls.
class _StubMeshService implements MeshService {
  @override
  Future<MeshResponse> get(Uri url, {Map<String, String>? headers}) =>
      throw StateError('MeshService not available in isolate');

  @override
  Future<MeshResponse> post(
    Uri url, {
    Object? body,
    Map<String, String>? headers,
  }) => throw StateError('MeshService not available in isolate');

  @override
  Stream<MeshPeer> discoverPeers() => const Stream.empty();

  @override
  Future<bool> get isConnected async => false;
}

/// Stub [MediaService] — agents in isolates cannot access media.
class _StubMediaService implements MediaService {
  @override
  Future<String?> capturePhoto() async => null;
  @override
  Future<String?> captureVideo() async => null;
  @override
  Future<String?> recordAudio() async => null;
  @override
  Future<String?> stopRecording() async => null;
  @override
  Future<bool> isRecording() async => false;
  @override
  Future<String?> pickFile({List<String>? allowedExtensions}) async => null;
  @override
  Future<String?> pickImage() async => null;
  @override
  Future<List<String>> pickMultipleImages() async => const [];
  @override
  Future<String?> pickVideo() async => null;
  @override
  Future<List<int>> readFile(String path) =>
      throw StateError('MediaService not available in isolate');
  @override
  Future<void> writeFile(String path, List<int> data) =>
      throw StateError('MediaService not available in isolate');
  @override
  Future<void> deleteFile(String path) =>
      throw StateError('MediaService not available in isolate');
  @override
  Future<bool> fileExists(String path) async => false;
  @override
  Future<String> getTemporaryDirectoryPath() =>
      throw StateError('MediaService not available in isolate');
}

/// Stub [AuthService] — agents in isolates cannot access auth.
class _StubAuthService implements AuthService {
  @override
  Future<UserIdentity?> get currentUser async => null;
  @override
  Future<bool> get hasIdentity async => false;
  @override
  Future<UserIdentity> generateKeyPair() =>
      throw StateError('AuthService not available in isolate');
  @override
  Future<Result<UserIdentity>> importFromNsec(String nsec) async =>
      const Result.failure(
        const NotFoundError('AuthService not available in isolate'),
      );
  @override
  Future<String?> exportNsec() async => null;
  @override
  Future<String?> getPublicKeyHex() async => null;
  @override
  Future<String?> getNpub() async => null;
  @override
  Future<void> setDisplayName(String name) async {}
  @override
  Future<bool> authenticateBiometric({String? reason}) async => false;
  @override
  Future<Uint8List?> getPrivateKeyBytes() async => null;
  @override
  Future<Result<Uint8List>> sign(List<int> data) async => const Result.failure(
    const NotFoundError('AuthService not available in isolate'),
  );
  @override
  Future<Result<Uint8List>> signHash(Uint8List hash) async => const Result.failure(
    const NotFoundError('AuthService not available in isolate'),
  );
  @override
  Future<bool> verify(
    List<int> data,
    List<int> signature, {
    List<int>? publicKey,
  }) async => false;
  @override
  Future<bool> verifyHash(
    Uint8List hash,
    Uint8List signature, {
    Uint8List? publicKey,
  }) async => false;
  @override
  Future<List<UserIdentity>> listIdentities() async => const [];
  @override
  Future<Result<UserIdentity>> switchIdentity(String publicKeyHex) async =>
      const Result.failure(
        const NotFoundError('AuthService not available in isolate'),
      );
  @override
  Future<Result<void>> removeIdentity(String publicKeyHex) async =>
      const Result.failure(
        const NotFoundError('AuthService not available in isolate'),
      );
  @override
  Future<String?> exportNsecFor(String publicKeyHex) async => null;
}

/// Stub [NotificationService] — agents in isolates cannot show notifications.
class _StubNotificationService implements NotificationService {
  @override
  Future<void> show({
    required String title,
    required String body,
    String? channelId,
    Map<String, dynamic>? payload,
  }) async {}
  @override
  Future<void> schedule({
    required String title,
    required String body,
    required DateTime dateTime,
    String? channelId,
    Map<String, dynamic>? payload,
  }) async {}
  @override
  Future<void> cancel(String id) async {}
  @override
  Future<void> cancelAll() async {}
  @override
  Stream<Map<String, dynamic>> get onTap => const Stream.empty();
  @override
  void dispose() {}
}

/// Stub [PresentationService] — agents in isolates cannot access display.
class _StubPresentationService implements PresentationService {
  @override
  Future<List<ExternalDisplay>> discoverDisplays() async => const [];
  @override
  Stream<List<ExternalDisplay>> watchDisplays() => const Stream.empty();
  @override
  Future<ScreenInfo> getScreenInfo() =>
      throw StateError('PresentationService not available in isolate');
  @override
  Future<double> getBrightness() async => 1.0;
  @override
  Future<void> setBrightness(double value) async {}
}

/// Stub [AgentRuntime] — nested agent invocations are not supported in isolates.
class _StubAgentRuntime implements AgentRuntime {
  @override
  void register(BaseAgent agent) {}
  @override
  BaseAgent? getAgent(String name) => null;
  @override
  List<BaseAgent> get agents => const [];
  @override
  List<AgentSummary> get registeredAgents => const [];
  @override
  Future<AgentResponse> invoke(
    String agentName,
    AgentMessage message,
    AgentContext context,
  ) async => const AgentResponse.error('Agent invocations not supported in isolate');
  @override
  void dispose() {}
}

// ---------------------------------------------------------------------------
// IsolateAgentRuntime
// ---------------------------------------------------------------------------

/// [AgentRuntime] that spawns a Dart isolate for each agent invocation.
///
/// **All** service calls from within the isolate are proxied back to the
/// main isolate via port channels. This includes LLM calls AND knowledge
/// store operations (which use Drift/SQLite and cannot safely cross
/// isolate boundaries).
///
/// Falls back to in-process execution if isolate spawning fails.
class IsolateAgentRuntime implements AgentRuntime {
  /// Creates an [IsolateAgentRuntime].
  IsolateAgentRuntime();

  final Map<String, BaseAgent> _agents = {};

  @override
  void register(BaseAgent agent) {
    _agents[agent.name] = agent;
  }

  @override
  BaseAgent? getAgent(String name) => _agents[name];

  @override
  List<BaseAgent> get agents => _agents.values.toList();

  @override
  List<AgentSummary> get registeredAgents =>
      _agents.values.map(AgentSummary.fromAgent).toList();

  @override
  void dispose() {
    _agents.clear();
  }

  @override
  Future<AgentResponse> invoke(
    String agentName,
    AgentMessage message,
    AgentContext context,
  ) async {
    final agent = _agents[agentName];
    if (agent == null) {
      return AgentResponse.error('Agent not found: $agentName');
    }

    try {
      return await _runInIsolate(agent, message, context);
    } on Object catch (e, st) {
      // Graceful fallback: run in main isolate if isolate spawn fails.
      dev.log(
        'Isolate spawn failed, running agent in-process: $e',
        error: e,
        stackTrace: st,
        name: 'IsolateAgentRuntime',
      );
      return agent.process(message, context);
    }
  }

  Future<AgentResponse> _runInIsolate(
    BaseAgent agent,
    AgentMessage message,
    AgentContext context,
  ) async {
    // This port receives the final result (or stream events) from the isolate.
    final resultPort = ReceivePort();
    final resultBroadcast = resultPort.asBroadcastStream();

    // This port receives service proxy requests from the isolate
    // (knowledge queries, LLM calls, tool execution requests, handshake).
    final hostPort = ReceivePort();

    // Once we get the handshake, we'll have a SendPort to send responses
    // back to the isolate.
    SendPort? isolateSendPort;

    StreamSubscription<dynamic>? hostSub;

    // Track whether cleanup is already handled (e.g. by streaming path).
    var cleanupHandled = false;
    void cleanup() {
      if (cleanupHandled) return;
      cleanupHandled = true;
      hostSub?.cancel();
      resultPort.close();
      hostPort.close();
    }

    try {
      // Build the serializable bootstrap — no closures cross the boundary.
      final descriptor = _AgentDescriptor.fromAgent(agent);
      final bootstrap = _IsolateBootstrap(
        descriptor: descriptor,
        message: message,
        resultPort: resultPort.sendPort,
        requestPort: hostPort.sendPort,
      );

      // Listen for requests from the isolate.
      hostSub = hostPort.listen((dynamic req) async {
        // Handshake: isolate sends us its SendPort.
        if (req is _HandshakeMessage) {
          isolateSendPort = req.isolateSendPort;
          return;
        }

        final sendPort = isolateSendPort;
        if (sendPort == null) {
          dev.log(
            'Received request before handshake',
            name: 'IsolateAgentRuntime',
          );
          return;
        }

        if (req is _ToolExecuteRequest) {
          // Execute the tool on the REAL agent in the main isolate.
          try {
            final tool = agent.tools.firstWhere(
              (t) => t.name == req.toolName,
              orElse: () => throw StateError('Tool not found: ${req.toolName}'),
            );
            final result = await agent.executeTool(tool, req.args, context);
            sendPort.send(_ToolExecuteResponse(req.id, result.toJson()));
          } on Object catch (e) {
            sendPort.send(
              _IsolateErrorResponse(
                req.id,
                ServiceError.agent('Tool execution error: $e'),
              ),
            );
          }
        } else if (req is _LlmStreamRequest) {
          // Forward LLM stream events to the isolate.
          try {
            await for (final event in context.llm.stream(req.request)) {
              sendPort.send(_LlmStreamEventResponse(req.id, event));
            }
            sendPort.send(_LlmStreamEndResponse(req.id));
          } on Object catch (e, st) {
            sendPort.send(
              _IsolateErrorResponse(
                req.id,
                ServiceError.llm('LLM stream error: $e'),
              ),
            );
            sendPort.send(_LlmStreamEndResponse(req.id));
          }
        } else if (req is _LlmCompleteRequest) {
          try {
            final response = await context.llm.complete(req.request);
            sendPort.send(_LlmCompleteResponse(req.id, response));
          } on Object catch (e) {
            sendPort.send(
              _IsolateErrorResponse(req.id, ServiceError.llm('LLM error: $e')),
            );
          }
        } else if (req is _KnowledgeQueryRequest) {
          try {
            var qb = context.knowledge.query();
            if (req.filters.subject != null) {
              qb = qb.subject(req.filters.subject!);
            }
            if (req.filters.predicate != null) {
              qb = qb.predicate(req.filters.predicate!);
            }
            if (req.filters.object != null) {
              qb = qb.object(req.filters.object!);
            }
            if (req.filters.type != null) {
              qb = qb.whereType(req.filters.type!);
            }
            if (req.filters.limit != null) {
              qb = qb.limit(req.filters.limit!);
            }
            if (req.filters.offset != null) {
              qb = qb.offset(req.filters.offset!);
            }
            final result = await qb.execute();
            sendPort.send(_KnowledgeQueryResponse(req.id, result));
          } on Object catch (e) {
            sendPort.send(
              _IsolateErrorResponse(
                req.id,
                ServiceError.storage('Query error: $e'),
              ),
            );
          }
        } else if (req is _KnowledgeMutateRequest) {
          try {
            await context.knowledge.mutate((ctx) async {
              for (final op in req.operations) {
                switch (op) {
                  case _CreateOp(:final type, resultIndex: _):
                    ctx.create(type);
                  case _SetOp(:final subject, :final predicate, :final object):
                    await ctx.set(subject, predicate, object);
                  case _AddOp(:final subject, :final predicate, :final object):
                    await ctx.add(subject, predicate, object);
                  case _RemoveOp(
                    :final subject,
                    :final predicate,
                    :final object,
                  ):
                    await ctx.remove(
                      subject: subject,
                      predicate: predicate,
                      object: object,
                    );
                }
              }
            });
            sendPort.send(_KnowledgeMutateResponse(req.id, null));
          } on Object catch (e) {
            sendPort.send(
              _IsolateErrorResponse(
                req.id,
                ServiceError.storage('Mutation error: $e'),
              ),
            );
          }
        } else if (req is _KnowledgeGetEntityRequest) {
          try {
            final triples = await context.knowledge.getEntity(req.subjectUri);
            sendPort.send(_KnowledgeEntityResponse(req.id, triples));
          } on Object catch (e) {
            sendPort.send(
              _IsolateErrorResponse(
                req.id,
                ServiceError.storage('GetEntity error: $e'),
              ),
            );
          }
        } else if (req is _KnowledgeGetEntitiesRequest) {
          try {
            final entities = await context.knowledge.getEntities(req.subjects);
            sendPort.send(_KnowledgeEntitiesResponse(req.id, entities));
          } on Object catch (e) {
            sendPort.send(
              _IsolateErrorResponse(
                req.id,
                ServiceError.storage('GetEntities error: $e'),
              ),
            );
          }
        } else if (req is _KnowledgeSearchRequest) {
          try {
            final triples = await context.knowledge.search(
              req.query,
              limit: req.limit,
            );
            sendPort.send(_KnowledgeSearchResponse(req.id, triples));
          } on Object catch (e) {
            sendPort.send(
              _IsolateErrorResponse(
                req.id,
                ServiceError.storage('Search error: $e'),
              ),
            );
          }
        }
      });

      // Spawn the isolate with the serializable bootstrap.
      await Isolate.spawn(
        _agentIsolateEntry,
        bootstrap,
        errorsAreFatal: true,
        onError: resultPort.sendPort,
      );

      // Wait for the first result message.
      final raw = await resultBroadcast.first;

      // Handle streaming responses: the isolate sends _AgentStreamEventMessage
      // events followed by _AgentStreamDone.
      if (raw is _AgentStreamEventMessage) {
        // Build a stream controller that yields events as they arrive.
        final controller = StreamController<LlmStreamEvent>();
        controller.add(raw.event);

        // Listen for remaining stream events.
        late final StreamSubscription<dynamic> streamSub;
        streamSub = resultBroadcast.listen(
          (msg) {
            if (msg is _AgentStreamEventMessage) {
              controller.add(msg.event);
            } else if (msg is _AgentStreamDone) {
              controller.close();
              streamSub.cancel();
              cleanup(); // Close ports now that the stream is done.
            }
          },
          onDone: () {
            // resultPort was closed (e.g., by an error path) before
            // _AgentStreamDone arrived — make sure the controller closes.
            if (!controller.isClosed) controller.close();
            cleanup();
          },
          onError: (_) {
            if (!controller.isClosed) controller.close();
            cleanup();
          },
        );

        // Prevent the finally block from closing ports — the streaming
        // path above handles cleanup when the stream is fully consumed.
        cleanupHandled = true;
        return AgentResponse.streaming(controller.stream);
      }

      if (raw is AgentResponse) return raw;

      if (raw is List) {
        // Uncaught error forwarded via onError port.
        final errMsg = raw.isNotEmpty
            ? raw[0].toString()
            : 'Unknown isolate error';
        return AgentResponse.error(errMsg);
      }

      return const AgentResponse.error('Unexpected isolate result type');
    } finally {
      cleanup();
    }
  }
}
