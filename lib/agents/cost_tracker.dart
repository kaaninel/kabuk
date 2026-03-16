/// LLM cost tracking — accumulates token usage and estimates costs.
///
/// [LlmCostTracker] is a Riverpod [StateNotifier] that receives [LlmUsage]
/// records from [LlmService] calls and maintains running totals per model.
/// Cost estimates are based on publicly documented per-token pricing; they
/// should be treated as approximations, not billing-grade figures.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kabuk/agents/llm.dart';

// ---------------------------------------------------------------------------
// Per-model pricing table
// ---------------------------------------------------------------------------

/// Published per-token pricing for known models (USD per 1 000 tokens).
///
/// Prices are best-effort from public documentation and may lag behind
/// provider pricing changes. Unknown models fall back to zero cost.
const _kInputPricePer1k = <String, double>{
  // OpenAI
  'gpt-4o': 0.005,
  'gpt-4o-mini': 0.00015,
  'gpt-4-turbo': 0.01,
  'gpt-4': 0.03,
  'gpt-3.5-turbo': 0.0005,
  // Anthropic
  'claude-3-5-sonnet-20241022': 0.003,
  'claude-3-5-haiku-20241022': 0.00025,
  'claude-3-opus-20240229': 0.015,
  'claude-sonnet-4-20250514': 0.003,
  'claude-haiku-4-20250514': 0.00025,
};

const _kOutputPricePer1k = <String, double>{
  // OpenAI
  'gpt-4o': 0.015,
  'gpt-4o-mini': 0.0006,
  'gpt-4-turbo': 0.03,
  'gpt-4': 0.06,
  'gpt-3.5-turbo': 0.0015,
  // Anthropic
  'claude-3-5-sonnet-20241022': 0.015,
  'claude-3-5-haiku-20241022': 0.00125,
  'claude-3-opus-20240229': 0.075,
  'claude-sonnet-4-20250514': 0.015,
  'claude-haiku-4-20250514': 0.00125,
};

/// Estimate USD cost for [usage] based on the pricing table.
///
/// Returns 0.0 if the model is not in the pricing table (e.g. local/Ollama).
double estimateCost(LlmUsage usage) {
  final inputRate = _kInputPricePer1k[usage.model] ?? 0.0;
  final outputRate = _kOutputPricePer1k[usage.model] ?? 0.0;
  return (usage.promptTokens * inputRate + usage.completionTokens * outputRate) /
      1000.0;
}

// ---------------------------------------------------------------------------
// Data classes
// ---------------------------------------------------------------------------

/// Aggregated stats for a single model.
class ModelUsageSummary {
  /// Creates a [ModelUsageSummary].
  const ModelUsageSummary({
    required this.model,
    required this.provider,
    required this.calls,
    required this.promptTokens,
    required this.completionTokens,
    required this.estimatedCostUsd,
  });

  /// The model identifier.
  final String model;

  /// The provider this model belongs to.
  final LlmProvider provider;

  /// Number of completions recorded for this model.
  final int calls;

  /// Total prompt (input) tokens consumed.
  final int promptTokens;

  /// Total completion (output) tokens consumed.
  final int completionTokens;

  /// Total tokens consumed.
  int get totalTokens => promptTokens + completionTokens;

  /// Estimated cost in USD (best-effort approximation).
  final double estimatedCostUsd;

  /// Returns a new [ModelUsageSummary] with [usage] accumulated.
  ModelUsageSummary accumulate(LlmUsage usage) {
    return ModelUsageSummary(
      model: model,
      provider: provider,
      calls: calls + 1,
      promptTokens: promptTokens + usage.promptTokens,
      completionTokens: completionTokens + usage.completionTokens,
      estimatedCostUsd: estimatedCostUsd + estimateCost(usage),
    );
  }
}

/// Snapshot of all accumulated LLM cost data.
class LlmCostState {
  /// Creates an [LlmCostState].
  const LlmCostState({
    required this.byModel,
    required this.sessionStartedAt,
    required this.lastUpdatedAt,
  });

  /// Empty initial state.
  factory LlmCostState.initial() => LlmCostState(
    byModel: const {},
    sessionStartedAt: DateTime.now(),
    lastUpdatedAt: DateTime.now(),
  );

  /// Per-model usage summaries keyed by model identifier.
  final Map<String, ModelUsageSummary> byModel;

  /// When this tracking session started.
  final DateTime sessionStartedAt;

  /// Timestamp of the most recent usage record.
  final DateTime lastUpdatedAt;

  /// Total calls across all models.
  int get totalCalls =>
      byModel.values.fold(0, (sum, s) => sum + s.calls);

  /// Total tokens across all models.
  int get totalTokens =>
      byModel.values.fold(0, (sum, s) => sum + s.totalTokens);

  /// Total estimated cost in USD across all models.
  double get totalEstimatedCostUsd =>
      byModel.values.fold(0.0, (sum, s) => sum + s.estimatedCostUsd);

  /// Returns an updated copy with [usage] accumulated.
  LlmCostState withUsage(LlmUsage usage) {
    final existing = byModel[usage.model];
    final updated = existing == null
        ? ModelUsageSummary(
            model: usage.model,
            provider: usage.provider,
            calls: 1,
            promptTokens: usage.promptTokens,
            completionTokens: usage.completionTokens,
            estimatedCostUsd: estimateCost(usage),
          )
        : existing.accumulate(usage);

    return LlmCostState(
      byModel: {...byModel, usage.model: updated},
      sessionStartedAt: sessionStartedAt,
      lastUpdatedAt: DateTime.now(),
    );
  }
}

// ---------------------------------------------------------------------------
// Notifier
// ---------------------------------------------------------------------------

/// Riverpod [StateNotifier] that accumulates LLM token usage records.
///
/// Agents and LLM service wrappers call [record] after each LLM call.
/// UI components read [LlmCostState] to display usage dashboards.
///
/// Usage:
/// ```dart
/// // In an agent or service wrapper:
/// ref.read(llmCostTrackerProvider.notifier).record(response.usage!);
///
/// // In a widget:
/// final cost = ref.watch(llmCostTrackerProvider);
/// Text('Tokens: \${cost.totalTokens}');
/// ```
class LlmCostTracker extends StateNotifier<LlmCostState> {
  /// Creates an [LlmCostTracker] with an empty initial state.
  LlmCostTracker() : super(LlmCostState.initial());

  /// Record a [LlmUsage] instance from a completed LLM call.
  ///
  /// Safe to call with `null` — this method is a no-op when usage is null,
  /// which happens for error responses or providers that don't report usage.
  void record(LlmUsage? usage) {
    if (usage == null) return;
    state = state.withUsage(usage);
  }

  /// Reset all accumulated data and restart the session counter.
  void reset() {
    state = LlmCostState.initial();
  }
}

/// Riverpod provider for [LlmCostTracker].
///
/// Survives widget rebuild — destroyed only when the [ProviderScope] is torn
/// down (i.e. app exit). Use `.keepAlive()` if you need true session
/// persistence across hot-restarts during development.
final llmCostTrackerProvider =
    StateNotifierProvider<LlmCostTracker, LlmCostState>(
  (ref) => LlmCostTracker(),
);
