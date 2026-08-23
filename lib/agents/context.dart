/// Agent execution context — the only way agents interact with the system.
///
/// [AgentContext] bundles all services and the knowledge store into a
/// single object that is passed to every agent invocation. Agents must
/// never access globals, singletons, or import service files directly.
library;

import 'package:kabuk/agents/base.dart';
import 'package:kabuk/agents/channels.dart';
import 'package:kabuk/agents/llm.dart';
import 'package:kabuk/agents/observation.dart';
import 'package:kabuk/agents/privacy_filter.dart';
import 'package:kabuk/agents/runtime.dart';
import 'package:kabuk/agents/tiered_llm.dart';
import 'package:kabuk/knowledge/store.dart';
import 'package:kabuk/services/auth.dart';
import 'package:kabuk/services/feed.dart';
import 'package:kabuk/services/media.dart';
import 'package:kabuk/services/mesh.dart';
import 'package:kabuk/services/nostr.dart';
import 'package:kabuk/services/notification.dart';
import 'package:kabuk/services/presentation.dart';
import 'package:kabuk/services/usenet.dart';
import 'package:kabuk/services/vault.dart';

/// Callback invoked when a tool is about to be called.
typedef ToolCallCallback =
    void Function(String toolName, Map<String, dynamic> args);

/// Callback invoked when a tool call completes.
typedef ToolResultCallback = void Function(String toolName, ToolResult result);

/// The execution context provided to agents.
///
/// `AgentContext` is the **only** way agents can interact with the system.
/// It provides access to the knowledge store, all virtual OS services,
/// the LLM service, and the agent runtime for invoking other agents.
///
/// Agents receive this as a parameter — they must never construct it
/// themselves or access services through any other mechanism.
class AgentContext {
  /// Creates an [AgentContext] with all required services.
  const AgentContext({
    required this.knowledge,
    required this.vault,
    required this.mesh,
    required this.media,
    required this.auth,
    required this.notification,
    required this.presentation,
    required this.llm,
    required this.runtime,
    this.nostr,
    this.feed,
    this.usenet,
    this.onToolCall,
    this.onToolResult,
    this.channels,
    this.observation,
    this.privacyLevel = PrivacyLevel.standard,
  });

  /// The RDF triple knowledge store for reading and writing data.
  final KnowledgeStore knowledge;

  /// Secure storage and encryption service.
  final VaultService vault;

  /// Networking, sync, and peer discovery service.
  final MeshService mesh;

  /// Camera, files, audio, and gallery service.
  final MediaService media;

  /// Identity, biometrics, and account service.
  final AuthService auth;

  /// Local and push notification service.
  final NotificationService notification;

  /// Display, brightness, and external screen service.
  final PresentationService presentation;

  /// LLM provider abstraction for language model calls.
  ///
  /// When the system uses [TieredLlmService], this is the tiered
  /// service. Agents calling `llm.complete(request)` with no tier
  /// hint default to the base on-device model. Use [llmForTier]
  /// to explicitly request a higher tier.
  final LlmService llm;

  /// Agent runtime for invoking other agents.
  final AgentRuntime runtime;

  /// The current privacy level for remote LLM requests.
  ///
  /// Defaults to [PrivacyLevel.standard]. Can be overridden per
  /// context for testing or user preference.
  final PrivacyLevel privacyLevel;

  /// Returns the [LlmService] for a specific [tier].
  ///
  /// If [llm] is a [TieredLlmService], returns the resolved service
  /// for that tier (with appropriate privacy filtering). Otherwise,
  /// returns [llm] unchanged — the single configured service handles
  /// everything.
  ///
  /// Usage:
  /// ```dart
  /// // Use the advanced tier for complex reasoning.
  /// final response = await context.llmForTier(LlmTier.advanced).complete(request);
  /// ```
  LlmService llmForTier(LlmTier tier) {
    if (llm is TieredLlmService) {
      return (llm as TieredLlmService).serviceForTier(tier);
    }
    return llm;
  }

  /// Whether a specific [tier] has a dedicated model configured.
  ///
  /// Returns `true` for [LlmTier.base] always. For standard and
  /// advanced, returns `true` only if a dedicated service is configured.
  /// UI uses this to show upgrade prompts or tier availability.
  bool isTierAvailable(LlmTier tier) {
    if (llm is TieredLlmService) {
      return (llm as TieredLlmService).isTierAvailable(tier);
    }
    return true; // Single service — all tiers resolve to the same thing.
  }

  /// Nostr protocol service for decentralized social networking.
  final NostrService? nostr;

  /// Feed service for fetching RSS, Reddit, and other content sources.
  final FeedService? feed;

  /// Usenet service for indexer/provider management, search, and streaming.
  final UsenetService? usenet;

  /// The active channel controller. When an agent returns a
  /// [ChannelToolResult], the runtime populates the session here so the
  /// OS can draw it with existing primitives.
  final ChannelController? channels;

  /// The observation bus for publishing perception events (OS → agent).
  ///
  /// Agents and the runtime publish [ObservationEvent]s here so the
  /// Concierge and proactive agents can react to OS activity.
  final ObservationBus? observation;

  /// Optional callback invoked when a tool is about to be called.
  final ToolCallCallback? onToolCall;

  /// Optional callback invoked when a tool call completes.
  final ToolResultCallback? onToolResult;

  /// Creates a copy of this context with the given tool callbacks.
  AgentContext copyWithCallbacks({
    ToolCallCallback? onToolCall,
    ToolResultCallback? onToolResult,
  }) {
    return AgentContext(
      knowledge: knowledge,
      vault: vault,
      mesh: mesh,
      media: media,
      auth: auth,
      notification: notification,
      presentation: presentation,
      llm: llm,
      runtime: runtime,
      nostr: nostr,
      feed: feed,
      usenet: usenet,
      onToolCall: onToolCall ?? this.onToolCall,
      onToolResult: onToolResult ?? this.onToolResult,
      channels: channels,
      observation: observation,
      privacyLevel: privacyLevel,
    );
  }
}
