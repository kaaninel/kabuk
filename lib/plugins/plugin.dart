/// Plugin interface for content adapters.
///
/// A [ContentPlugin] adapts an external content source (YouTube, RSS,
/// Reddit, etc.) into a stream of [ContentItem] objects that the
/// knowledge store can ingest. Plugins declare their capabilities,
/// provide a settings schema via config fields, and receive a
/// sandboxed [PluginContext] at initialisation time.
library;

import 'package:flutter/widgets.dart' show IconData;
import 'package:kabuk/plugins/channel.dart' show ChannelEntityType;
import 'package:kabuk/plugins/content_item.dart';
import 'package:kabuk/plugins/context.dart';
import 'package:meta/meta.dart';

/// A capability that a [ContentPlugin] may support.
enum ContentCapability {
  /// Can search for content by query string.
  search,

  /// Can fetch content for a channel or entity feed.
  channel,

  /// Can resolve arbitrary URLs to structured content.
  urlResolve,

  /// Can provide trending or popular content without a query.
  trending,
}

/// The high-level category a plugin belongs to.
enum PluginCategory {
  /// Social media platforms (Twitter, Reddit, Mastodon, etc.).
  social,

  /// Video or streaming platforms (YouTube, Vimeo, etc.).
  media,

  /// News feeds and aggregators.
  news,

  /// Music and podcast services.
  music,

  /// Reference and knowledge sources (Wikipedia, etc.).
  reference,

  /// Anything that doesn't fit the above categories.
  other,
}

// ---------------------------------------------------------------------------
// Plugin configuration schema
// ---------------------------------------------------------------------------

/// The data type of a [PluginConfigField].
enum PluginConfigFieldType {
  /// Free-form text input.
  text,

  /// Masked password input.
  password,

  /// Boolean on/off toggle.
  toggle,

  /// Numeric input.
  number,

  /// Single selection from a list of choices.
  choice,
}

/// Describes a single configuration field in a plugin's settings schema.
///
/// The settings UI renders a form from the list of [PluginConfigField]
/// objects returned by [ContentPlugin.configFields]. Values marked
/// [secret] are stored in the vault rather than plain preferences.
@immutable
class PluginConfigField {
  /// Creates a [PluginConfigField].
  const PluginConfigField({
    required this.key,
    required this.label,
    this.description,
    this.type = PluginConfigFieldType.text,
    this.required = false,
    this.secret = false,
    this.defaultValue,
    this.choices = const [],
  });

  /// Unique key for this configuration value.
  final String key;

  /// Human-readable label shown in the settings UI.
  final String label;

  /// Optional help text displayed below the field.
  final String? description;

  /// The input type for this field.
  final PluginConfigFieldType type;

  /// Whether the field must be filled before the plugin can initialise.
  final bool required;

  /// Whether the value should be encrypted in the vault.
  final bool secret;

  /// Default value if the user hasn't set one.
  final String? defaultValue;

  /// Available options when [type] is [PluginConfigFieldType.choice].
  final List<String> choices;

  @override
  String toString() => 'PluginConfigField($key, type: $type)';
}

// ---------------------------------------------------------------------------
// URL resolution result
// ---------------------------------------------------------------------------

/// The result of resolving a URL through a plugin.
///
/// Use exhaustive pattern matching:
/// ```dart
/// switch (resolved) {
///   case ResolvedContentItem(:final item) => showItem(item),
///   case ResolvedChannel(:final title) => openChannel(title),
///   case ResolvedNotHandled() => tryNextPlugin(),
/// }
/// ```
sealed class ResolvedContent {
  /// Base constructor.
  const ResolvedContent();
}

/// The URL resolved to a single content item.
@immutable
class ResolvedContentItem extends ResolvedContent {
  /// Creates a [ResolvedContentItem].
  const ResolvedContentItem(this.item);

  /// The resolved content item.
  final ContentItem item;
}

/// The URL resolved to a channel or entity feed.
@immutable
class ResolvedChannel extends ResolvedContent {
  /// Creates a [ResolvedChannel].
  const ResolvedChannel({
    required this.entityUri,
    required this.title,
    this.imageUrl,
    this.sourcePluginId,
    this.externalEntityId,
    this.entityType = ChannelEntityType.custom,
  });

  /// Knowledge store URI for the resolved channel entity.
  final String entityUri;

  /// Human-readable channel title.
  final String title;

  /// Optional channel avatar or banner image URL.
  final String? imageUrl;

  /// Which plugin provides this channel's content (null = knowledge-store query).
  final String? sourcePluginId;

  /// Plugin-specific entity ID for fetching channel content.
  final String? externalEntityId;

  /// The kind of entity this channel represents.
  final ChannelEntityType entityType;
}

/// The plugin does not handle this URL.
@immutable
class ResolvedNotHandled extends ResolvedContent {
  /// Creates a [ResolvedNotHandled].
  const ResolvedNotHandled();
}

// ---------------------------------------------------------------------------
// ContentPlugin interface
// ---------------------------------------------------------------------------

/// Abstract interface for content-source plugins.
///
/// Each plugin adapts one external platform into the Kabuk content
/// model. Plugins are registered with the plugin registry at startup
/// and receive a [PluginContext] via [initialize] before any other
/// method is called.
///
/// Methods corresponding to capabilities the plugin does not support
/// should throw [UnsupportedError]. Use [hasCapability] to check
/// before calling.
///
/// ```dart
/// if (plugin.hasCapability(ContentCapability.search)) {
///   final results = await plugin.search('flutter');
/// }
/// ```
abstract interface class ContentPlugin {
  /// Unique identifier for this plugin (e.g. `"youtube"`, `"rss"`).
  String get id;

  /// Human-readable display name.
  String get name;

  /// Short description of what this plugin provides.
  String get description;

  /// Semantic version string (e.g. `"1.0.0"`).
  String get version;

  /// Icon for display in the plugin list and settings UI.
  IconData get iconData;

  /// High-level category this plugin belongs to.
  PluginCategory get category;

  /// The set of capabilities this plugin supports.
  Set<ContentCapability> get capabilities;

  /// Configuration fields the user must or may fill in.
  List<PluginConfigField> get configFields;

  /// Returns `true` if this plugin supports the given [capability].
  bool hasCapability(ContentCapability capability) =>
      capabilities.contains(capability);

  /// Initialise the plugin with its sandboxed [context].
  ///
  /// Called once before any content methods. Plugins should validate
  /// configuration and set up internal state here.
  Future<void> initialize(PluginContext context);

  /// Release resources held by the plugin.
  ///
  /// Called when the plugin is being unloaded or the app is shutting
  /// down. After this call no other methods will be invoked.
  Future<void> dispose();

  /// Returns `true` if this plugin can resolve the given [url].
  ///
  /// This is a cheap, synchronous check (e.g. regex on the host name).
  /// Returning `true` does not guarantee [resolveUrl] will succeed.
  bool canHandleUrl(String url);

  /// Resolve [url] into structured content.
  ///
  /// Returns one of [ResolvedContentItem], [ResolvedChannel], or
  /// [ResolvedNotHandled]. Requires [ContentCapability.urlResolve].
  Future<ResolvedContent> resolveUrl(String url);

  /// Search for content matching [query].
  ///
  /// Requires [ContentCapability.search].
  Future<List<ContentItem>> search(
    String query, {
    int page = 0,
    int perPage = 20,
  });

  /// Fetch content from a channel or entity feed.
  ///
  /// [entityId] is the platform-specific channel identifier.
  /// Requires [ContentCapability.channel].
  Future<List<ContentItem>> fetchChannel(
    String entityId, {
    int page = 0,
    int perPage = 20,
  });

  /// Fetch trending or popular content.
  ///
  /// Requires [ContentCapability.trending].
  Future<List<ContentItem>> fetchTrending({
    int page = 0,
    int perPage = 20,
  });
}
