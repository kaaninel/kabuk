/// Central Riverpod providers wiring all services and layers together.
///
/// This file is the dependency injection root for the Kabuk app.
/// Every service, the knowledge store, agent runtime, and LLM service
/// are provided here, with platform-specific implementations selected
/// at runtime.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, debugPrint, defaultTargetPlatform;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kabuk/agents/context.dart';
import 'package:kabuk/agents/cost_tracker.dart';
import 'package:kabuk/agents/http_llm.dart';
import 'package:kabuk/agents/isolate_runtime.dart';
import 'package:kabuk/agents/llm.dart';
import 'package:kabuk/agents/local_llm.dart';
import 'package:kabuk/agents/privacy_filter.dart';
import 'package:kabuk/agents/runtime.dart';
import 'package:kabuk/agents/tiered_llm.dart';
import 'package:kabuk/knowledge/database.dart';
import 'package:kabuk/knowledge/drift_store.dart';
import 'package:kabuk/knowledge/store.dart';
import 'package:kabuk/knowledge/types/person.dart';
import 'package:kabuk/platform/android/auth_service_impl.dart' as android_auth;
import 'package:kabuk/platform/android/mesh_service_impl.dart' as android_mesh;
import 'package:kabuk/platform/android/notification_service_impl.dart'
    as android_notification;
import 'package:kabuk/platform/desktop/auth_service_impl.dart' as desktop_auth;
import 'package:kabuk/platform/desktop/mesh_service_impl.dart' as desktop_mesh;
import 'package:kabuk/platform/desktop/notification_service_impl.dart'
    as desktop_notification;
import 'package:kabuk/platform/ios/auth_service_impl.dart' as ios_auth;
import 'package:kabuk/platform/ios/mesh_service_impl.dart' as ios_mesh;
import 'package:kabuk/platform/ios/notification_service_impl.dart'
    as ios_notification;
import 'package:kabuk/platform/shared/auth_service_impl.dart';
import 'package:kabuk/platform/shared/device_capabilities.dart';
import 'package:kabuk/platform/shared/feed_service_impl.dart';
import 'package:kabuk/platform/shared/media_service_impl.dart';
import 'package:kabuk/platform/shared/model_manager_impl.dart';
import 'package:kabuk/platform/shared/nostr_service_impl.dart';
import 'package:kabuk/platform/shared/presentation_service_impl.dart';
import 'package:kabuk/platform/shared/vault_service_impl.dart';
import 'package:kabuk/rfw/built_in_libraries.dart';
import 'package:kabuk/rfw/registry.dart';
import 'package:kabuk/rfw/runtime.dart';
import 'package:kabuk/services/auth.dart';
import 'package:kabuk/services/feed.dart';
import 'package:kabuk/services/media.dart';
import 'package:kabuk/services/mesh.dart';
import 'package:kabuk/services/model_manager.dart';
import 'package:kabuk/services/nostr.dart';
import 'package:kabuk/services/nostr_utils.dart';
import 'package:kabuk/services/notification.dart';
import 'package:kabuk/services/presentation.dart';
import 'package:kabuk/services/vault.dart';

// =============================================================================
// Active Profile
// =============================================================================

/// The active profile ID (first 16 hex chars of the active identity's pubkey).
///
/// This is the reactive trigger for per-identity database and vault scoping.
/// When the active identity changes, this provider is invalidated, causing
/// [databaseProvider], [knowledgeStoreProvider], [vaultServiceProvider], and
/// all downstream providers to rebuild with the new profile's data.
final activeProfileIdProvider = FutureProvider<String?>((ref) async {
  final auth = ref.watch(authServiceProvider);
  return auth.getActiveProfileId();
});

// =============================================================================
// Database
// =============================================================================

/// Global settings database — identity-independent.
///
/// Stores app-wide configuration (LLM API keys, privacy settings,
/// model paths, etc.) that should be shared across all identity
/// profiles. This is a separate SQLite file from the per-profile DBs.
final globalSettingsDbProvider = Provider<KabukDatabase>((ref) {
  final db = KabukDatabase(driftDatabase(name: 'kabuk_global'));
  ref.onDispose(db.close);
  return db;
});

/// The Drift database instance, scoped to the active identity profile.
///
/// Each identity gets its own SQLite database file named
/// `kabuk_<profileId>` where profileId is the first 16 hex chars
/// of the identity's public key. This provides complete data isolation
/// between identities — conversations, messages, triples, and blobs
/// are fully sandboxed per profile.
///
/// Falls back to `kabuk_default` when no identity exists yet (e.g.
/// during first-launch onboarding).
final databaseProvider = Provider<KabukDatabase>((ref) {
  final profileAsync = ref.watch(activeProfileIdProvider);
  final profileId = profileAsync.valueOrNull ?? 'default';
  final db = KabukDatabase(driftDatabase(name: 'kabuk_$profileId'));
  ref.onDispose(() {
    // Delay close slightly to let in-flight queries settle when
    // switching identity profiles. Without this, async operations
    // (e.g. contactsProvider, conversationsProvider) that started
    // before the switch may hit "channel closed" errors.
    Future<void>.delayed(const Duration(milliseconds: 200), () async {
      try {
        await db.close();
      } on Object {
        // Already closed or GC'd — ignore.
      }
    });
  });
  return db;
});

// =============================================================================
// Knowledge Store
// =============================================================================

/// The [KnowledgeStore] backed by Drift/SQLite.
final knowledgeStoreProvider = Provider<KnowledgeStore>((ref) {
  final db = ref.watch(databaseProvider);
  final store = DriftKnowledgeStore(db);
  ref.onDispose(() {
    // Delay close to let in-flight knowledge store queries settle
    // during identity profile switches.
    Future<void>.delayed(const Duration(milliseconds: 150), () async {
      try {
        unawaited(store.close());
      } on Object {
        // Ignore — already closed.
      }
    });
  });
  return store;
});

// =============================================================================
// Agent Runtime
// =============================================================================

/// The [AgentRuntime] for invoking agents by name.
///
/// Uses [IsolateAgentRuntime] to run each agent invocation in a
/// separate Dart isolate, improving sandboxing and parallelism.
/// Falls back to in-process execution if isolate spawning fails.
final agentRuntimeProvider = Provider<AgentRuntime>((ref) {
  final runtime = IsolateAgentRuntime();
  ref.onDispose(runtime.dispose);
  return runtime;
});

/// The [VaultService] for secrets and encryption, scoped per identity.
///
/// Each identity profile gets its own vault directory and master key,
/// ensuring complete file-level isolation between profiles.
final vaultServiceProvider = Provider<VaultService>((ref) {
  final profileAsync = ref.watch(activeProfileIdProvider);
  final profileId = profileAsync.valueOrNull ?? 'default';
  return SharedVaultService(profileId: profileId);
});

/// The [MeshService] for networking and sync.
final meshServiceProvider = Provider<MeshService>((ref) {
  return _createMeshService();
});

/// The [NotificationService] for local and push notifications.
final notificationServiceProvider = Provider<NotificationService>((ref) {
  final service = _createNotificationService();
  ref.onDispose(service.dispose);
  return service;
});

/// Stream of notification tap payloads.
///
/// Emits a new value whenever the user taps a system notification.
/// Widgets can use [ref.listen] on this provider to react to taps —
/// for example, navigating to the conversation that was tapped.
final notificationTapStreamProvider = StreamProvider<Map<String, dynamic>>((
  ref,
) {
  final notification = ref.watch(notificationServiceProvider);
  return notification.onTap;
});

/// The [PresentationService] for display, haptics, and system UI.
final presentationServiceProvider = Provider<PresentationService>((ref) {
  return const SharedPresentationService();
});

/// The [AgentContext] providing agents access to all services.
///
/// Uses late-binding: services that don't yet have platform
/// implementations use stub no-op implementations.
final agentContextProvider = Provider<AgentContext>((ref) {
  final knowledge = ref.watch(knowledgeStoreProvider);
  final runtime = ref.watch(agentRuntimeProvider);
  final llm = ref.watch(llmServiceProvider);
  final auth = ref.watch(authServiceProvider);
  final nostr = ref.watch(nostrServiceProvider);
  final feed = ref.watch(feedServiceProvider);

  return AgentContext(
    knowledge: knowledge,
    vault: ref.watch(vaultServiceProvider),
    mesh: ref.watch(meshServiceProvider),
    media: ref.watch(mediaServiceProvider),
    auth: auth,
    notification: ref.watch(notificationServiceProvider),
    presentation: ref.watch(presentationServiceProvider),
    llm: llm,
    runtime: runtime,
    nostr: nostr,
    feed: feed,
  );
});

// =============================================================================
// Media
// =============================================================================

/// The [MediaService] instance for camera, audio, and file operations.
final mediaServiceProvider = Provider<MediaService>((ref) {
  return SharedMediaService();
});

// =============================================================================
// Feed Service
// =============================================================================

/// The [FeedService] for fetching RSS, Reddit, Nostr, and other content sources.
///
/// Uses the shared [MeshService] for HTTP requests and [NostrService]
/// for Nostr hashtag/topic feeds.
final feedServiceProvider = Provider<FeedService>((ref) {
  final mesh = ref.watch(meshServiceProvider);
  final nostr = ref.watch(nostrServiceProvider);
  return SharedFeedService(mesh: mesh, nostr: nostr);
});

// =============================================================================
// Identity / Auth
// =============================================================================

/// The [AuthService] instance backed by secp256k1 keypair identity.
///
/// Identity state is persisted in a standalone registry file
/// (`identity_registry.json`), independent of any per-profile database.
/// This solves the bootstrap problem: identities can be listed before
/// a profile database is opened.
///
/// Uses platform-specific implementations for biometric authentication.
final authServiceProvider = Provider<SharedAuthService>((ref) {
  // Legacy DB-backed loader for one-time migration. Reads from the
  // old global `kabuk` database (or `kabuk_default`) independently
  // of the per-profile databaseProvider to avoid circular deps.
  Future<String?> legacyLoader() async {
    try {
      final legacyDb = KabukDatabase(driftDatabase(name: 'kabuk'));
      try {
        const subject = 'kabuk:identity/keypair';
        const predicate = 'kabuk:keypairJson';
        final rows = await legacyDb.findTriples(
          subject: subject,
          predicate: predicate,
        );
        return rows.isNotEmpty ? rows.first.objectString : null;
      } finally {
        await legacyDb.close();
      }
    } on Object {
      return null;
    }
  }
  return _createAuthService(legacyLoader: legacyLoader);
});

/// Ensures a valid identity is loaded at app startup.
///
/// Eagerly initialises the auth service, loads persisted identities
/// (restoring the last-used `activeIndex`), and auto-generates a
/// keypair when none exist yet (first launch). The returned identity
/// is guaranteed to be non-null.
///
/// Watch this provider early (e.g. in [KabukShell]) so that an
/// identity is always available before any chat or Nostr code runs.
final ensureIdentityProvider = FutureProvider<UserIdentity>((ref) async {
  final auth = ref.watch(authServiceProvider);
  final existing = await auth.currentUser;
  if (existing != null) return existing;

  // First launch — generate a default identity automatically.
  final created = await auth.generateKeyPair();
  // Invalidate the profile ID so database/vault scope the new identity.
  ref.invalidate(activeProfileIdProvider);
  ref.invalidate(currentIdentityProvider);
  ref.invalidate(allIdentitiesProvider);
  return created;
});

/// Stream of the current user's identity (reactive).
final currentIdentityProvider = FutureProvider<UserIdentity?>((ref) async {
  final auth = ref.watch(authServiceProvider);
  return auth.currentUser;
});

/// Lists all identities managed by the auth service.
///
/// Returns a list of [UserIdentity] objects representing all stored
/// Nostr identities. The active identity is indicated by
/// [currentIdentityProvider].
final allIdentitiesProvider = FutureProvider<List<UserIdentity>>((ref) async {
  final auth = ref.watch(authServiceProvider);
  return auth.listIdentities();
});

/// Notifier for switching the active identity (profile).
///
/// Call `ref.read(switchIdentityProvider)(hexPubkey)` to switch to a
/// different identity profile. This triggers a full provider cascade:
/// the active profile ID changes, causing the database, vault, Nostr
/// relay config, conversations, messages, and all downstream providers
/// to rebuild with the new profile's data.
final switchIdentityProvider = Provider<Future<void> Function(String)>((ref) {
  return (String publicKeyHex) async {
    final auth = ref.read(authServiceProvider);
    await auth.switchIdentity(publicKeyHex);

    // IMPORTANT: Invalidate downstream providers BEFORE the profile ID.
    // If we invalidate activeProfileIdProvider first, it cascades to
    // databaseProvider which closes the old DB — but providers still
    // holding a reference to that DB (nostr, conversations, etc.) will
    // get "channel closed" errors when they try to dispose/save state.

    // 1. Invalidate Nostr service first — it holds DB lambdas.
    ref.invalidate(nostrDmStreamProvider);
    ref.invalidate(nostrServiceProvider);

    // 2. Invalidate conversation/message state.
    ref.invalidate(activeConversationProvider);
    ref.invalidate(conversationsProvider);
    ref.invalidate(messagesProvider);
    ref.invalidate(contactsProvider);
    ref.invalidate(resumeLastConversationProvider);

    // 3. Invalidate RFW runtime (depends on knowledge store).
    ref.invalidate(rfwRuntimeProvider);

    // 4. Invalidate identity providers.
    ref.invalidate(currentIdentityProvider);
    ref.invalidate(allIdentitiesProvider);

    // 5. NOW invalidate the profile ID — this cascades to database,
    //    vault, and knowledge store, safely since consumers are gone.
    ref.invalidate(activeProfileIdProvider);
  };
});

// =============================================================================
// Nostr Service
// =============================================================================

/// The [NostrService] for Nostr protocol communication.
///
/// Relay configuration is persisted in the knowledge store as a JSON triple.
final nostrServiceProvider = Provider<SharedNostrService>((ref) {
  final auth = ref.watch(authServiceProvider);
  final db = ref.watch(databaseProvider);
  const subject = 'kabuk:nostr/relays';
  const predicate = 'kabuk:relayConfigJson';

  final service = SharedNostrService(
    auth: auth,
    onRelayLoad: () async {
      final rows = await db.findTriples(subject: subject, predicate: predicate);
      return rows.isNotEmpty ? rows.first.objectString : null;
    },
    onRelaySave: (json) async {
      await db.deleteTriple(subject: subject, predicate: predicate);
      await db.insertTriple(
        TriplesCompanion(
          subject: const Value(subject),
          predicate: const Value(predicate),
          objectType: const Value('string'),
          objectString: Value(json),
        ),
      );
    },
  );

  // Auto-connect to all configured relays on startup.
  Future.microtask(service.connectAll);

  ref.onDispose(service.dispose);
  return service;
});

// =============================================================================
// LLM Service
// =============================================================================

/// The LLM configuration. Set this to enable real LLM calls.
///
/// Configuration is persisted in the knowledge store as a JSON triple
/// so that it survives app restarts.
///
/// Example:
/// ```dart
/// ref.read(llmConfigProvider.notifier).setConfig(
///   LlmConfig.anthropic(apiKey: 'sk-...'),
/// );
/// ```
final llmConfigProvider = NotifierProvider<LlmConfigNotifier, LlmConfig?>(
  LlmConfigNotifier.new,
);

/// Notifier that persists [LlmConfig] in the global settings DB.
///
/// LLM API keys are shared across all identity profiles since they
/// are system-level configuration, not per-profile data.
///
/// On first build, schedules an async load from the database.
/// When [setConfig] is called, the new value is written to the
/// database and the in-memory state is updated synchronously.
class LlmConfigNotifier extends Notifier<LlmConfig?> {
  static const _subject = 'kabuk:settings/llm';
  static const _predicate = 'kabuk:configJson';

  bool _disposed = false;

  @override
  LlmConfig? build() {
    _disposed = false;
    ref.onDispose(() => _disposed = true);
    // Schedule async load — state starts as null until DB read completes.
    _loadFromDb();
    return null;
  }

  Future<void> _loadFromDb() async {
    final db = ref.read(globalSettingsDbProvider);
    final rows = await db.findTriples(subject: _subject, predicate: _predicate);
    if (_disposed) return;
    if (rows.isNotEmpty) {
      final jsonStr = rows.first.objectString;
      if (jsonStr != null) {
        try {
          final map = jsonDecode(jsonStr) as Map<String, dynamic>;
          state = LlmConfig.fromJson(map);
        } on Object {
          // Corrupted data — leave config as null.
        }
      }
    }
  }

  /// Updates the in-memory config and persists it to the global DB.
  ///
  /// Pass `null` to clear the saved configuration.
  Future<void> setConfig(LlmConfig? config) async {
    state = config;
    final db = ref.read(globalSettingsDbProvider);

    // Remove existing config triple.
    await db.deleteTriple(subject: _subject, predicate: _predicate);

    if (config != null) {
      await db.insertTriple(
        TriplesCompanion(
          subject: const Value(_subject),
          predicate: const Value(_predicate),
          objectType: const Value('string'),
          objectString: Value(jsonEncode(config.toJson())),
        ),
      );
    }
  }
}

/// The active [LlmService] provider.
///
/// Returns a [TieredLlmService] that uses the local model as the base
/// (Tier 0), and routes to configured remote providers for higher tiers.
/// Privacy filtering is applied automatically to all remote requests.
///
/// Fall-through behavior:
/// - If a local model is configured, it becomes the base tier.
/// - If a remote API is configured, it becomes the advanced tier.
/// - If only a remote API is configured (no local model), it handles
///   all tiers but privacy filtering uses regex fallback.
/// - If nothing is configured, a stub service is used.
///
/// The returned service is always wrapped with [CostTrackingLlmService].
final llmServiceProvider = Provider<LlmService>((ref) {
  final config = ref.watch(llmConfigProvider);
  final localConfig = ref.watch(localModelConfigProvider);
  final tracker = ref.watch(llmCostTrackerProvider.notifier);
  final privacyLevel = ref.watch(privacyLevelProvider);
  final privacyEnabled = ref.watch(privacyFilterEnabledProvider);

  // Build the base (local) LLM service.
  LlmService? baseLlm;
  if (localConfig != null) {
    baseLlm = LocalLlmService(config: localConfig);
  }

  // Build the advanced (remote) LLM service.
  LlmService? advancedLlm;
  if (config != null && config.provider != LlmProvider.local) {
    advancedLlm = HttpLlmService(config: config);
  }

  LlmService inner;
  if (baseLlm != null) {
    // Best case: local model as base, remote as advanced.
    inner = TieredLlmService(
      config: TieredLlmConfig(
        baseLlm: baseLlm,
        advancedLlm: advancedLlm,
        defaultPrivacyLevel: privacyLevel,
        enablePrivacyFilter: privacyEnabled,
      ),
    );
  } else if (advancedLlm != null) {
    // No local model — remote service handles everything.
    // Privacy filter uses regex fallback (no local LLM to anonymize).
    inner = TieredLlmService(
      config: TieredLlmConfig(
        baseLlm: advancedLlm, // Remote is the only option.
        defaultPrivacyLevel: privacyLevel,
        enablePrivacyFilter: false, // Can't filter without a local model.
      ),
    );
  } else {
    inner = _StubLlmService();
  }

  ref.onDispose(() {
    if (advancedLlm is HttpLlmService) {
      advancedLlm.dispose();
    }
    if (baseLlm is LocalLlmService) {
      baseLlm.dispose();
    }
  });

  return CostTrackingLlmService(inner: inner, tracker: tracker);
});

// =============================================================================
// Local Model Configuration
// =============================================================================

/// The local model configuration, persisted in the knowledge store.
///
/// Used when [LlmProvider.local] is selected. Stores the model path,
/// GPU layers, context size, and other inference parameters.
final localModelConfigProvider =
    NotifierProvider<LocalModelConfigNotifier, LocalModelConfig?>(
      LocalModelConfigNotifier.new,
    );

/// Notifier that persists [LocalModelConfig] in the global settings DB.
///
/// Model configuration is shared across all identity profiles.
class LocalModelConfigNotifier extends Notifier<LocalModelConfig?> {
  static const _subject = 'kabuk:settings/local-model';
  static const _predicate = 'kabuk:configJson';

  bool _disposed = false;

  @override
  LocalModelConfig? build() {
    _disposed = false;
    ref.onDispose(() => _disposed = true);
    _loadFromDb();
    return null;
  }

  Future<void> _loadFromDb() async {
    final db = ref.read(globalSettingsDbProvider);
    final rows = await db.findTriples(subject: _subject, predicate: _predicate);
    if (_disposed) return;
    if (rows.isNotEmpty) {
      final jsonStr = rows.first.objectString;
      if (jsonStr != null) {
        try {
          final map = jsonDecode(jsonStr) as Map<String, dynamic>;
          final config = LocalModelConfig.fromJson(map);

          // Validate the model file still exists on disk.
          // If the app was reinstalled or the simulator was reset,
          // the persisted path may point to a deleted file.
          if (File(config.modelPath).existsSync()) {
            state = config;
          } else {
            // Clear the stale config so the user is prompted to
            // re-download the model.
            await _clearFromDb();
          }
        } on Object {
          // Corrupted data — leave config as null.
        }
      }
    }
  }

  /// Updates the in-memory config and persists it to the global DB.
  Future<void> setConfig(LocalModelConfig? config) async {
    state = config;
    final db = ref.read(globalSettingsDbProvider);

    await db.deleteTriple(subject: _subject, predicate: _predicate);

    if (config != null) {
      await db.insertTriple(
        TriplesCompanion(
          subject: const Value(_subject),
          predicate: const Value(_predicate),
          objectType: const Value('string'),
          objectString: Value(jsonEncode(config.toJson())),
        ),
      );
    }
  }

  /// Removes the persisted config from the global DB.
  Future<void> _clearFromDb() async {
    final db = ref.read(globalSettingsDbProvider);
    await db.deleteTriple(subject: _subject, predicate: _predicate);
  }
}

// =============================================================================
// Privacy Settings
// =============================================================================

/// The user's preferred privacy level for remote LLM requests.
///
/// Persisted in the knowledge store. Defaults to [PrivacyLevel.standard]
/// which strips PII before sending prompts to cloud APIs.
///
/// Privacy levels:
/// - [PrivacyLevel.none] — No filtering (only used for local-only setups).
/// - [PrivacyLevel.light] — Strips obvious PII (emails, phones, names).
/// - [PrivacyLevel.standard] — Replaces PII with placeholders (default).
/// - [PrivacyLevel.maximum] — Aggressively strips all identifying info.
final privacyLevelProvider =
    NotifierProvider<PrivacyLevelNotifier, PrivacyLevel>(
      PrivacyLevelNotifier.new,
    );

/// Notifier that persists the user's [PrivacyLevel] preference.
class PrivacyLevelNotifier extends Notifier<PrivacyLevel> {
  static const _subject = 'kabuk:settings/privacy';
  static const _predicate = 'kabuk:privacyLevel';

  bool _disposed = false;

  @override
  PrivacyLevel build() {
    _disposed = false;
    ref.onDispose(() => _disposed = true);
    _loadFromDb();
    return PrivacyLevel.standard; // Safe default.
  }

  Future<void> _loadFromDb() async {
    final db = ref.read(globalSettingsDbProvider);
    final rows = await db.findTriples(subject: _subject, predicate: _predicate);
    if (_disposed) return;
    if (rows.isNotEmpty) {
      final value = rows.first.objectString;
      if (value != null) {
        final level = PrivacyLevel.values
            .where((l) => l.name == value)
            .firstOrNull;
        if (level != null) state = level;
      }
    }
  }

  /// Updates the privacy level and persists it in the global settings DB.
  Future<void> setLevel(PrivacyLevel level) async {
    state = level;
    final db = ref.read(globalSettingsDbProvider);
    await db.deleteTriple(subject: _subject, predicate: _predicate);
    await db.insertTriple(
      TriplesCompanion(
        subject: const Value(_subject),
        predicate: const Value(_predicate),
        objectType: const Value('string'),
        objectString: Value(level.name),
      ),
    );
  }
}

/// Whether the privacy filter is enabled globally.
///
/// Defaults to `true`. When disabled, prompts are sent to remote
/// APIs without anonymization. Users can toggle this in settings.
/// Even when disabled, *no data is ever sent without a configured
/// remote provider* — this only controls the anonymization step.
final privacyFilterEnabledProvider =
    NotifierProvider<PrivacyFilterEnabledNotifier, bool>(
      PrivacyFilterEnabledNotifier.new,
    );

/// Notifier that persists the privacy filter enabled/disabled state.
class PrivacyFilterEnabledNotifier extends Notifier<bool> {
  static const _subject = 'kabuk:settings/privacy';
  static const _predicate = 'kabuk:filterEnabled';

  bool _disposed = false;

  @override
  bool build() {
    _disposed = false;
    ref.onDispose(() => _disposed = true);
    _loadFromDb();
    return true; // Privacy on by default — safe for non-technical users.
  }

  Future<void> _loadFromDb() async {
    final db = ref.read(globalSettingsDbProvider);
    final rows = await db.findTriples(subject: _subject, predicate: _predicate);
    if (_disposed) return;
    if (rows.isNotEmpty) {
      final value = rows.first.objectString;
      if (value != null) state = value == 'true';
    }
  }

  /// Enables or disables the privacy filter (persisted in global settings DB).
  Future<void> setEnabled(bool enabled) async {
    state = enabled;
    final db = ref.read(globalSettingsDbProvider);
    await db.deleteTriple(subject: _subject, predicate: _predicate);
    await db.insertTriple(
      TriplesCompanion(
        subject: const Value(_subject),
        predicate: const Value(_predicate),
        objectType: const Value('string'),
        objectString: Value(enabled.toString()),
      ),
    );
  }
}

// =============================================================================
// Model Manager
// =============================================================================

/// The [ModelManager] for discovering, downloading, and deleting GGUF models.
final modelManagerProvider = Provider<ModelManager>((ref) {
  final manager = SharedModelManager();
  ref.onDispose(manager.dispose);
  return manager;
});

// =============================================================================
// Model Readiness
// =============================================================================

/// Status of local model readiness.
enum ModelReadyStatus {
  /// Checking if a model is available.
  checking,

  /// A model is available and configured.
  ready,

  /// A model is being downloaded.
  downloading,

  /// No model available and download failed or not started.
  unavailable,
}

/// Current state of model readiness, including download progress.
class ModelReadyState {
  /// Creates a [ModelReadyState].
  const ModelReadyState({
    required this.status,
    this.progress = 0.0,
    this.modelName,
    this.error,
  });

  /// The readiness status.
  final ModelReadyStatus status;

  /// Download progress (0.0 to 1.0) when [status] is [ModelReadyStatus.downloading].
  final double progress;

  /// Name of the model being downloaded or ready.
  final String? modelName;

  /// Error message if download failed.
  final String? error;
}

/// Ensures a local model is always available after onboarding.
///
/// Watches [localModelConfigProvider]:
/// - If a valid config exists, status is [ModelReadyStatus.ready].
/// - If no config exists (model missing or never downloaded),
///   auto-detects device capabilities and downloads the best model.
///
/// This provider is watched by the app shell so users always see
/// download progress and never encounter a broken LLM state.
final modelReadinessProvider =
    NotifierProvider<ModelReadinessNotifier, ModelReadyState>(
      ModelReadinessNotifier.new,
    );

/// Notifier backing [modelReadinessProvider].
class ModelReadinessNotifier extends Notifier<ModelReadyState> {
  bool _disposed = false;
  bool _recovering = false;

  @override
  ModelReadyState build() {
    _disposed = false;
    ref.onDispose(() => _disposed = true);

    final localConfig = ref.watch(localModelConfigProvider);
    if (localConfig != null) {
      return const ModelReadyState(status: ModelReadyStatus.ready);
    }

    // No local model configured — try to recover.
    _ensureModelAvailable();
    return const ModelReadyState(status: ModelReadyStatus.checking);
  }

  /// Checks for existing models and downloads one if needed.
  Future<void> _ensureModelAvailable() async {
    if (_recovering) return;
    _recovering = true;

    try {
      final manager = ref.read(modelManagerProvider);

      // Check if there's already a downloaded model on disk.
      final existing = await manager.listLocalModels();
      if (_disposed) return;

      if (existing.isNotEmpty) {
        // A model exists on disk but wasn't configured — set it up.
        final model = existing.first;
        final config = LocalModelConfig(modelPath: model.path);
        unawaited(ref.read(localModelConfigProvider.notifier).setConfig(config));
        return;
      }

      // No model on disk — download the best one for this device.
      final device = await DeviceCapabilities.detect();
      if (_disposed) return;

      final recommended = pickModelForDevice(device, manager.recommendedModels);

      state = ModelReadyState(
        status: ModelReadyStatus.downloading,
        modelName: recommended.name,
      );

      await for (final progress in manager.downloadModel(recommended)) {
        if (_disposed) return;
        state = ModelReadyState(
          status: ModelReadyStatus.downloading,
          progress: progress.progress,
          modelName: recommended.name,
        );
      }

      // Download complete — find the model and configure it.
      final downloaded = await manager.listLocalModels();
      if (_disposed) return;

      if (downloaded.isNotEmpty) {
        final model = downloaded.first;
        final config = LocalModelConfig(modelPath: model.path);
        unawaited(ref.read(localModelConfigProvider.notifier).setConfig(config));
        // State will be updated by the build() re-run via ref.watch.
      } else {
        state = const ModelReadyState(
          status: ModelReadyStatus.unavailable,
          error: 'Download completed but model file not found.',
        );
      }
    } catch (e) {
      if (_disposed) return;
      state = ModelReadyState(
        status: ModelReadyStatus.unavailable,
        error: 'Failed to download model: $e',
      );
    } finally {
      _recovering = false;
    }
  }

  /// Manually triggers a model download retry.
  void retry() {
    state = const ModelReadyState(status: ModelReadyStatus.checking);
    _ensureModelAvailable();
  }
}

// =============================================================================
// Conversation state
// =============================================================================

/// Currently active conversation ID.
///
/// Initialized to `null` and set when the user opens a conversation.
/// To auto-resume the last conversation on startup, call
/// `resumeLastConversation()` from the chat view's init logic.
final activeConversationProvider = StateProvider<String?>((ref) => null);

/// Resumes the most recently updated conversation, if one exists.
///
/// Called during chat view initialization to restore the user's
/// last chat session after an app restart.
final resumeLastConversationProvider = FutureProvider<void>((ref) async {
  final db = ref.read(databaseProvider);
  try {
    final conversations = await db.listConversations(limit: 1);
    if (conversations.isNotEmpty) {
      ref.read(activeConversationProvider.notifier).state =
          conversations.first.id;
    }
  } catch (_) {
    // Database channel may have been closed during identity switch or app
    // lifecycle transition. Safe to ignore — the provider will be
    // re-created with the new DB instance.
  }
});

/// List of conversations, watched reactively.
///
/// Returns non-archived conversations sorted by pinned status then
/// last message time, so active Nostr DMs and AI chats interleave
/// naturally.
final conversationsProvider = StreamProvider<List<Conversation>>((ref) {
  final db = ref.watch(databaseProvider);
  return db.watchActiveConversations();
});

/// Messages for the active conversation.
final messagesProvider = StreamProvider<List<Message>>((ref) {
  final conversationId = ref.watch(activeConversationProvider);
  if (conversationId == null) return const Stream.empty();
  final db = ref.watch(databaseProvider);
  return db.watchMessages(conversationId);
});

/// All Person entities from the knowledge store — used as contacts.
final contactsProvider = FutureProvider<List<PersonData>>((ref) {
  final store = ref.watch(knowledgeStoreProvider);
  return store.listPersons(limit: 100);
});

/// Fetches (and caches) the Nostr kind-0 profile for a given pubkey.
///
/// Results are served from [NostrService]'s in-memory profile cache, so
/// repeated calls within an hour are free. Pass an empty string to get null.
final nostrProfileProvider = FutureProvider.family<NostrProfile?, String>((
  ref,
  pubkeyHex,
) async {
  if (pubkeyHex.isEmpty) return null;
  final nostr = ref.watch(nostrServiceProvider);
  return nostr.fetchProfileCached(pubkeyHex);
});

/// Fetches recent public text notes (kind 1) authored by [pubkeyHex].
///
/// Returns up to 30 notes sorted newest-first. Used for the contact
/// profile sheet's public-notes feed. Uses the same subscription pattern
/// as the explore profile view so events are fetched directly from the
/// author's relay set rather than through the following-feed endpoint.
final contactPublicNotesProvider =
    FutureProvider.family<List<NostrEvent>, String>((ref, pubkeyHex) async {
      if (pubkeyHex.isEmpty) return const [];
      final nostr = ref.watch(nostrServiceProvider);
      final notes = await collectNostrEvents(
        nostr.subscribe([
          NostrFilter(
            authors: [pubkeyHex],
            kinds: [NostrKind.textNote],
            limit: 30,
          ),
        ]),
        timeout: const Duration(seconds: 8),
      );
      notes.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return notes;
    });

// =============================================================================
// Nostr DMs
// =============================================================================

/// Stream of incoming Nostr direct messages.
///
/// Watches for gift-wrapped (NIP-17) DMs addressed to the current
/// user. Each [NostrDm] is an unwrapped, decrypted message.
final nostrDmStreamProvider = StreamProvider<NostrDm>((ref) async* {
  final nostr = ref.watch(nostrServiceProvider);
  final db = ref.read(databaseProvider);
  final since = await db.getNewestNostrDmTimestamp();
  yield* nostr.watchDirectMessages(since: since);
});

/// Background listener that stores incoming Nostr DMs into the database and
/// fires a local notification for every new message received while the
/// conversation is not already open.
///
/// This provider should be watched from the app shell so that DMs
/// are persisted even when the user is not viewing a specific chat.
/// It creates or updates conversations and inserts messages.
final nostrDmBackgroundListenerProvider = Provider<void>((ref) {
  final nostr = ref.watch(nostrServiceProvider);
  final db = ref.read(databaseProvider);
  final notification = ref.read(notificationServiceProvider);

  // Repair any conversations whose type/nostrPubkey were wiped by the
  // old INSERT OR REPLACE preview-update bug.
  Future.microtask(db.repairCorruptedNostrDmConversations);

  // M2: start the DM subscription from the newest known message timestamp so
  // we catch up on messages received while the app was offline.
  StreamSubscription<NostrDm>? dmSub;
  Future.microtask(() async {
    final since = await db.getNewestNostrDmTimestamp();
    dmSub = nostr.watchDirectMessages(since: since).listen((dm) async {
      // N1: skip ephemeral typing indicator events — they are not real messages.
      if (dm.isTypingIndicator) return;

      // Determine the other party's pubkey.
      final peerPubkey = dm.conversationPubkey;
      final convId = 'nostr_dm_$peerPubkey';

      // Ensure conversation exists; capture display name before any upsert.
      final conversation = await db.findNostrDmConversation(peerPubkey);
      String senderName;
      if (conversation == null) {
        senderName = '${peerPubkey.substring(0, 8)}...';
        await db.upsertConversation(
          ConversationsCompanion(
            id: Value(convId),
            title: Value(senderName),
            type: const Value('nostr_dm'),
            nostrPubkey: Value(peerPubkey),
            createdAt: Value(DateTime.now()),
            updatedAt: Value(DateTime.now()),
          ),
        );
      } else {
        senderName = conversation.title;
      }

      // Insert message (ignore duplicates via unique ID).
      try {
        await db.insertMessage(
          MessagesCompanion(
            id: Value(dm.id),
            conversationId: Value(convId),
            role: Value(dm.isOwnMessage ? 'user' : 'contact'),
            content: Value(dm.content),
            timestamp: Value(dm.timestamp),
            nostrEventId: Value(dm.id),
            status: const Value('received'),
          ),
        );
        debugPrint(
          '[DM-BG] inserted msg ${dm.id.substring(0, 8)} into $convId: ${dm.content.substring(0, dm.content.length.clamp(0, 40))}',
        );

        // Update conversation preview.
        await db.updateConversationPreview(
          convId,
          lastMessage: dm.content,
          lastMessageAt: dm.timestamp,
        );

        // Increment unread count and fire a local notification for incoming
        // messages, but only when the user is NOT currently viewing this chat
        // and the conversation is not muted.
        if (!dm.isOwnMessage) {
          await db.incrementUnreadCount(convId);

          final isMuted = conversation?.isMuted ?? false;
          final activeConv = ref.read(activeConversationProvider);
          if (!isMuted && activeConv != convId) {
            final preview = dm.content.length > 80
                ? '${dm.content.substring(0, 80)}…'
                : dm.content;
            await notification.show(
              title: senderName,
              body: preview,
              channelId: 'kabuk_dm',
              payload: {'conversationId': convId, 'type': 'nostr_dm'},
            );
          }
        }
      } on Object catch (e) {
        // Duplicate message or other DB error — log and ignore.
        debugPrint('[DM-BG] insert failed for ${dm.id.substring(0, 8)}: $e');
      }
    });
  });

  ref.onDispose(() => dmSub?.cancel());
});

// =============================================================================
// RFW Runtime
// =============================================================================

/// The RFW widget registry with all built-in libraries installed.
final rfwRegistryProvider = Provider<RfwRegistry>((ref) {
  final registry = RfwRegistry();
  for (final lib in builtInLibraries()) {
    registry.install(lib);
  }
  return registry;
});

/// The RFW runtime for rendering dynamic widgets.
final rfwRuntimeProvider = Provider<KabukRfwRuntime>((ref) {
  final registry = ref.watch(rfwRegistryProvider);
  final store = ref.watch(knowledgeStoreProvider);
  final runtime = KabukRfwRuntime(registry: registry, store: store);
  ref.onDispose(runtime.dispose);
  return runtime;
});

// =============================================================================
// Developer Mode
// =============================================================================

/// Whether developer mode is enabled.
///
/// When `true`, the app shows additional debug information:
/// - A debug info bar in the shell displaying live runtime stats
/// - A "Developer Tools" entry in Settings with knowledge store inspector,
///   provider state viewer, and LLM cost log
///
/// Toggle is persisted in the global settings DB and defaults to `false`.
final devModeProvider = NotifierProvider<DevModeNotifier, bool>(
  DevModeNotifier.new,
);

/// Notifier that persists the developer-mode toggle in the global settings DB.
class DevModeNotifier extends Notifier<bool> {
  static const _subject = 'kabuk:settings/dev';
  static const _predicate = 'kabuk:devModeEnabled';

  bool _disposed = false;

  @override
  bool build() {
    _disposed = false;
    ref.onDispose(() => _disposed = true);
    _loadFromDb();
    return false;
  }

  Future<void> _loadFromDb() async {
    final db = ref.read(globalSettingsDbProvider);
    final rows = await db.findTriples(subject: _subject, predicate: _predicate);
    if (_disposed) return;
    if (rows.isNotEmpty) {
      // Booleans are stored as 0/1 in objectInt.
      state = (rows.first.objectInt ?? 0) != 0;
    }
  }

  /// Toggle developer mode and persist the new value.
  Future<void> toggle() => setEnabled(!state);

  /// Set developer mode to [enabled] and persist.
  Future<void> setEnabled(bool enabled) async {
    state = enabled;
    final db = ref.read(globalSettingsDbProvider);
    await db.deleteTriple(subject: _subject, predicate: _predicate);
    await db.insertTriple(
      TriplesCompanion(
        subject: const Value(_subject),
        predicate: const Value(_predicate),
        objectType: const Value('boolean'),
        objectInt: Value(enabled ? 1 : 0),
      ),
    );
  }
}

// =============================================================================
// Simple agent runtime (runs in main isolate for now)
// =============================================================================

// =============================================================================
// Platform service factories
// =============================================================================

/// Creates the platform-appropriate [NotificationService].
NotificationService _createNotificationService() {
  if (defaultTargetPlatform == TargetPlatform.android) {
    return android_notification.AndroidNotificationService();
  }
  if (defaultTargetPlatform == TargetPlatform.iOS) {
    return ios_notification.IosNotificationService();
  }
  // macOS, Linux, Windows.
  return desktop_notification.DesktopNotificationService();
}

/// Creates the platform-appropriate [MeshService].
MeshService _createMeshService() {
  if (defaultTargetPlatform == TargetPlatform.android) {
    return android_mesh.AndroidMeshService();
  }
  if (defaultTargetPlatform == TargetPlatform.iOS) {
    return ios_mesh.IosMeshService();
  }
  return desktop_mesh.DesktopMeshService();
}

/// Creates the platform-appropriate [SharedAuthService].
///
/// The [legacyLoader] is used for one-time migration from the old
/// DB-backed identity storage to the standalone registry file.
SharedAuthService _createAuthService({
  Future<String?> Function()? legacyLoader,
}) {
  if (defaultTargetPlatform == TargetPlatform.android) {
    return android_auth.AndroidAuthService(knowledgeLoader: legacyLoader);
  }
  if (defaultTargetPlatform == TargetPlatform.iOS) {
    return ios_auth.IosAuthService(knowledgeLoader: legacyLoader);
  }
  // macOS, Linux, Windows.
  return desktop_auth.DesktopAuthService(knowledgeLoader: legacyLoader);
}

// =============================================================================
// Stub LLM service
// =============================================================================

class _StubLlmService implements LlmService {
  @override
  Future<LlmResponse> complete(LlmRequest request) async {
    return const LlmResponse.text(
      'AI model is being prepared. Please wait a moment while the '
      'model downloads, then try again.',
    );
  }

  @override
  Stream<LlmStreamEvent> stream(LlmRequest request) {
    return Stream.fromIterable([
      const LlmStreamEvent.textDelta(
        'AI model is being prepared. Please wait a moment while the '
        'model downloads, then try again.',
      ),
      const LlmStreamEvent.done(),
    ]);
  }

  @override
  int countTokens(String text) => text.split(' ').length;
}

/// [LlmService] decorator that records token usage in [LlmCostTracker]
/// after every [complete] and [stream] call.
///
/// Wraps any inner [LlmService] implementation transparently; agents and
/// other callers never need to know cost tracking is happening.
class CostTrackingLlmService implements LlmService {
  /// Creates a [CostTrackingLlmService].
  const CostTrackingLlmService({required this.inner, required this.tracker});

  /// The underlying LLM service that performs actual inference.
  final LlmService inner;

  /// The cost tracker notifier to record usage into.
  final LlmCostTracker tracker;

  @override
  Future<LlmResponse> complete(LlmRequest request) async {
    final response = await inner.complete(request);
    switch (response) {
      case TextLlmResponse(:final usage):
        tracker.record(usage);
      case ToolCallsLlmResponse(:final usage):
        tracker.record(usage);
      case ErrorLlmResponse():
        break;
    }
    return response;
  }

  @override
  Stream<LlmStreamEvent> stream(LlmRequest request) async* {
    await for (final event in inner.stream(request)) {
      if (event case UsageEvent(:final usage)) {
        tracker.record(usage);
      }
      yield event;
    }
  }

  @override
  int countTokens(String text) => inner.countTokens(text);
}
