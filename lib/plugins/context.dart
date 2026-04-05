/// Sandboxed execution context provided to plugins.
///
/// [PluginContext] is the only gateway through which a content plugin
/// may access external resources — HTTP networking, encrypted storage,
/// the knowledge store, configuration values, and structured logging.
/// By funnelling all access through this context, the host can enforce
/// rate-limiting, auditing, and permission checks in the future.
library;

import 'package:http/http.dart' as http;
import 'package:kabuk/knowledge/store.dart';
import 'package:kabuk/services/vault.dart';
import 'package:meta/meta.dart';

/// Sandboxed context injected into every content plugin at init time.
///
/// Plugins must not hold references to services beyond what this context
/// provides. All fields are final and the context is immutable once
/// created — the host may however supply function-typed fields that
/// internally delegate to mutable state.
@immutable
class PluginContext {
  /// Creates a [PluginContext].
  const PluginContext({
    required this.httpClient,
    required this.vault,
    required this.store,
    required this.pluginId,
    required this.getConfig,
    required this.log,
  });

  /// HTTP client for making network requests.
  ///
  /// The host may wrap this client to inject headers, enforce
  /// rate-limits, or record metrics per plugin.
  final http.Client httpClient;

  /// Encrypted file storage service.
  ///
  /// Plugins can use the vault to cache downloaded media or store
  /// plugin-specific encrypted data.
  final VaultService vault;

  /// RDF triple store for reading and writing knowledge data.
  ///
  /// Plugins should use [KnowledgeStore.mutate] for writes so that change
  /// events propagate to the UI layer.
  final KnowledgeStore store;

  /// The identifier of the plugin this context belongs to.
  ///
  /// Useful for scoping log messages and vault entries.
  final String pluginId;

  /// Retrieve a configuration value by its key.
  ///
  /// Returns `null` if the key has not been set. Secret values are
  /// transparently decrypted by the host before being returned.
  final String? Function(String key) getConfig;

  /// Emit a structured log message.
  ///
  /// The host routes these to the app's logging infrastructure,
  /// prefixed with the plugin identifier. Pass an optional `error`
  /// string for error-level entries.
  final void Function(String message, {String? error}) log;
}
