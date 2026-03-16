/// Tiered LLM service — routes requests to the appropriate model tier.
///
/// Implements a three-tier LLM architecture:
///
/// | Tier     | Role                                  | Runs           |
/// |----------|---------------------------------------|----------------|
/// | **base** | Always-on default. Routing, simple     | On-device      |
/// |          | tool calls, short Q&A.                |                |
/// | **standard** | Domain agent work, multi-step tool | On-device or   |
/// |          | loops, summarization.                 | Ollama         |
/// | **advanced** | Complex reasoning, creative        | Remote API     |
/// |          | writing, long-context tasks.          |                |
///
/// Privacy filtering is applied automatically to any request that
/// leaves the device (standard with remote backend, advanced). The
/// on-device base model handles anonymization so PII never touches
/// a remote server.
///
/// Non-technical users don't need to configure anything — the system
/// works fully offline with just the base tier, upgrading transparently
/// when better models are available.
library;

import 'dart:async';

import 'package:kabuk/agents/llm.dart';
import 'package:kabuk/agents/privacy_filter.dart';

/// The tier of LLM to use for a request.
///
/// Agents can request a specific tier via [LlmRequest.model] using
/// the tier name prefixed with `tier:` (e.g., `'tier:advanced'`).
/// If no tier is specified, [LlmTier.base] is used.
enum LlmTier {
  /// Small on-device model. Always available, zero cost, zero latency.
  /// Good for: intent classification, simple tool calls, short Q&A,
  /// privacy filtering, prompt anonymization.
  base,

  /// Medium model. On-device (larger GGUF) or local server (Ollama).
  /// Good for: domain agent work, multi-step tool loops, summarization.
  standard,

  /// Large remote model. Requires API key and network.
  /// Good for: complex reasoning, creative writing, long-context tasks.
  /// Privacy filter is applied automatically before sending.
  advanced,
}

/// Configuration for the tiered LLM system.
///
/// Specifies which [LlmService] backs each tier and the default
/// privacy level for remote requests.
class TieredLlmConfig {
  /// Creates a [TieredLlmConfig].
  const TieredLlmConfig({
    required this.baseLlm,
    this.standardLlm,
    this.advancedLlm,
    this.defaultPrivacyLevel = PrivacyLevel.standard,
    this.enablePrivacyFilter = true,
  });

  /// The always-available on-device model (Tier 0).
  ///
  /// This model is also used by the [PrivacyFilter] to anonymize
  /// prompts before they're sent to remote tiers.
  final LlmService baseLlm;

  /// Optional medium-tier model (Tier 1).
  ///
  /// When `null`, standard-tier requests fall through to [baseLlm].
  final LlmService? standardLlm;

  /// Optional large remote model (Tier 2).
  ///
  /// When `null`, advanced-tier requests fall through to
  /// [standardLlm] ?? [baseLlm].
  final LlmService? advancedLlm;

  /// Default privacy level for requests that leave the device.
  ///
  /// Applied to [LlmTier.advanced] and any [LlmTier.standard]
  /// backed by a remote service.
  final PrivacyLevel defaultPrivacyLevel;

  /// Whether to run the privacy filter on outgoing remote requests.
  ///
  /// Defaults to `true`. When disabled, prompts are sent as-is.
  /// Users can toggle this in settings for full transparency.
  final bool enablePrivacyFilter;
}

/// A composite [LlmService] that routes requests to the appropriate
/// tier and applies privacy filtering to remote requests.
///
/// This is the primary LLM service used throughout Kabuk. Agents
/// interact with it like any other [LlmService] — tier selection
/// happens transparently based on the request's `model` field.
///
/// ### Tier selection
///
/// - If `request.model` starts with `'tier:'`, the suffix determines
///   the tier (e.g., `'tier:advanced'`).
/// - If `request.model` is `null` or doesn't match a tier name,
///   the [base] tier is used.
/// - If the selected tier isn't available (no model configured),
///   the request falls through to the next lower tier.
///
/// ### Privacy filtering
///
/// Requests routed to remote models (advanced, or standard if backed
/// by a remote service) are automatically anonymized by the
/// [PrivacyFilter] using the base on-device LLM. The response is
/// de-anonymized before being returned to the caller. This happens
/// transparently — agents and users don't need to know about it.
class TieredLlmService implements LlmService {
  /// Creates a [TieredLlmService] from the given [config].
  TieredLlmService({required this.config})
    : _privacyFilter = PrivacyFilter(
        localLlm: config.enablePrivacyFilter ? config.baseLlm : null,
      );

  /// The tiered configuration.
  final TieredLlmConfig config;

  /// The privacy filter for anonymizing remote requests.
  final PrivacyFilter _privacyFilter;

  /// Parse the requested tier from the model field.
  ///
  /// Returns [LlmTier.base] if no tier hint is present.
  LlmTier _parseTier(String? model) {
    if (model == null) return LlmTier.base;
    if (!model.startsWith('tier:')) return LlmTier.base;
    final tierName = model.substring(5);
    return LlmTier.values.where((t) => t.name == tierName).firstOrNull ??
        LlmTier.base;
  }

  /// Resolve the actual [LlmService] for the requested tier,
  /// falling through to lower tiers if the requested one isn't
  /// available.
  LlmService _resolveService(LlmTier tier) {
    return switch (tier) {
      LlmTier.advanced =>
        config.advancedLlm ?? config.standardLlm ?? config.baseLlm,
      LlmTier.standard => config.standardLlm ?? config.baseLlm,
      LlmTier.base => config.baseLlm,
    };
  }

  /// Whether the resolved service for [tier] is a remote API.
  ///
  /// Remote services need privacy filtering. The base tier is always
  /// local. Standard and advanced are remote if they differ from base.
  bool _isRemote(LlmTier tier) {
    final service = _resolveService(tier);
    // If it resolved to the base LLM, it's local.
    if (identical(service, config.baseLlm)) return false;
    // Standard might be local (Ollama) or remote — we treat anything
    // that isn't the base model as potentially remote for safety.
    return true;
  }

  /// Strip the `tier:` prefix from the model field so the underlying
  /// service gets a clean model name (or `null`).
  LlmRequest _cleanRequest(LlmRequest request) {
    if (request.model != null && request.model!.startsWith('tier:')) {
      return LlmRequest(
        messages: request.messages,
        tools: request.tools,
        model: null, // Let the underlying service use its default.
        temperature: request.temperature,
        maxTokens: request.maxTokens,
        systemPrompt: request.systemPrompt,
      );
    }
    return request;
  }

  @override
  Future<LlmResponse> complete(LlmRequest request) async {
    final tier = _parseTier(request.model);
    final service = _resolveService(tier);
    final cleanRequest = _cleanRequest(request);

    // Apply privacy filter for remote requests.
    if (_isRemote(tier) && config.enablePrivacyFilter) {
      final anonymized = await _privacyFilter.anonymizeRequest(
        cleanRequest,
        config.defaultPrivacyLevel,
      );
      final response = await service.complete(anonymized.request);
      return _privacyFilter.deAnonymizeResponse(response, anonymized.map);
    }

    return service.complete(cleanRequest);
  }

  @override
  Stream<LlmStreamEvent> stream(LlmRequest request) async* {
    final tier = _parseTier(request.model);
    final service = _resolveService(tier);
    final cleanRequest = _cleanRequest(request);

    // Apply privacy filter for remote requests.
    if (_isRemote(tier) && config.enablePrivacyFilter) {
      final anonymized = await _privacyFilter.anonymizeRequest(
        cleanRequest,
        config.defaultPrivacyLevel,
      );
      await for (final event in service.stream(anonymized.request)) {
        yield _privacyFilter.deAnonymizeEvent(event, anonymized.map);
      }
      return;
    }

    yield* service.stream(cleanRequest);
  }

  @override
  int countTokens(String text) => config.baseLlm.countTokens(text);

  /// Returns the resolved service for a specific [tier].
  ///
  /// Useful for agents that need to explicitly call a specific tier
  /// (e.g., the router always wants base, a creative writing agent
  /// always wants advanced).
  LlmService serviceForTier(LlmTier tier) => _resolveService(tier);

  /// Whether the given [tier] has a dedicated service configured.
  ///
  /// If `false`, requests for this tier will fall through to a lower
  /// tier. UI can use this to show users which tiers are available.
  bool isTierAvailable(LlmTier tier) {
    return switch (tier) {
      LlmTier.base => true, // Base is always available.
      LlmTier.standard => config.standardLlm != null,
      LlmTier.advanced => config.advancedLlm != null,
    };
  }

  /// Returns a summary of available tiers for display in the UI.
  Map<LlmTier, bool> get tierAvailability => {
    for (final tier in LlmTier.values) tier: isTierAvailable(tier),
  };
}

/// Extension on [LlmRequest] to make tier selection ergonomic.
extension LlmRequestTierExtension on LlmRequest {
  /// Creates a copy of this request targeting a specific [tier].
  LlmRequest withTier(LlmTier tier) => LlmRequest(
    messages: messages,
    tools: tools,
    model: 'tier:${tier.name}',
    temperature: temperature,
    maxTokens: maxTokens,
    systemPrompt: systemPrompt,
  );
}
