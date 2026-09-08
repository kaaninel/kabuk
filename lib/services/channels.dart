/// MCP-style channel tool layer.
///
/// Channels (web search, web fetch, Reddit, Nostr, RSS, Usenet, plugins) are
/// exposed as **tool servers** with a uniform, discoverable interface — the
/// same shape as the Model Context Protocol (`tools/list` / `tools/call`),
/// but in-process. This lets agents (via LLM tool calling), the omnibar, and
/// the feed engine all invoke any channel through one registry.
///
/// An external MCP server later plugs in as another [ChannelServer]
/// implementation over stdio/HTTP (see `docs/MCP.md`).
library;

import 'package:kabuk/plugins/content_item.dart';
import 'package:kabuk/services/feed.dart';

/// A callable tool exposed by a [ChannelServer].
///
/// Mirrors MCP's tool schema: a name, a description the LLM sees, and a JSON
/// Schema describing the arguments.
class ChannelTool {
  /// Creates a [ChannelTool].
  const ChannelTool({
    required this.name,
    required this.description,
    this.inputSchema = const {'type': 'object', 'properties': <String, dynamic>{}},
  });

  /// Machine-readable tool name (e.g. `web_search`).
  final String name;

  /// Human-readable description injected into the LLM context.
  final String description;

  /// JSON Schema for the tool's arguments.
  final Map<String, dynamic> inputSchema;
}

/// A readable resource exposed by a [ChannelServer] (e.g. an article body).
///
/// Mirrors MCP resources: a stable URI that can be read on demand.
class ChannelResource {
  /// Creates a [ChannelResource].
  const ChannelResource({required this.uri, this.mimeType, this.description});

  /// Stable URI identifying the resource.
  final String uri;

  /// MIME type (e.g. `text/markdown`, `application/json`).
  final String? mimeType;

  /// Short human-readable description.
  final String? description;
}

/// The result of invoking a channel tool.
sealed class ChannelCallResult {
  /// Creates a [ChannelCallResult].
  const ChannelCallResult();

  /// Plain text (bounded for LLM context).
  const factory ChannelCallResult.text(String content) = ChannelTextResult;

  /// Structured JSON data.
  const factory ChannelCallResult.json(Map<String, dynamic> data) =
      ChannelJsonResult;

  /// A list of typed content items (for the channel UI).
  const factory ChannelCallResult.content(List<ContentItem> items) =
      ChannelContentResult;

  /// An error message.
  const factory ChannelCallResult.error(String message) = ChannelErrorResult;
}

/// A plain-text channel tool result.
final class ChannelTextResult extends ChannelCallResult {
  /// Creates a [ChannelTextResult].
  const ChannelTextResult(this.content);

  /// The text content.
  final String content;
}

/// A JSON channel tool result.
final class ChannelJsonResult extends ChannelCallResult {
  /// Creates a [ChannelJsonResult].
  const ChannelJsonResult(this.data);

  /// The structured data.
  final Map<String, dynamic> data;
}

/// A content-items channel tool result.
final class ChannelContentResult extends ChannelCallResult {
  /// Creates a [ChannelContentResult].
  const ChannelContentResult(this.items);

  /// Typed content items for the channel UI.
  final List<ContentItem> items;
}

/// An error channel tool result.
final class ChannelErrorResult extends ChannelCallResult {
  /// Creates a [ChannelErrorResult].
  const ChannelErrorResult(this.message);

  /// The error message.
  final String message;
}

/// A channel exposed as a tool server.
///
/// Implementations map a single source (web, Reddit, Nostr, …) onto a small
/// set of tools. Callers use [ChannelRegistry.invoke] — never construct
/// servers directly.
abstract interface class ChannelServer {
  /// Stable identifier (e.g. `web`, `reddit`, `nostr`, `plugin:youtube`).
  String get id;

  /// Human-readable name.
  String get name;

  /// Short description of what this channel provides.
  String get description;

  /// The tools this server exposes.
  List<ChannelTool> listTools();

  /// Invoke [tool] with [args].
  ///
  /// Returns a [ChannelCallResult]; unknown tools should return an error
  /// result rather than throwing.
  Future<ChannelCallResult> callTool(String tool, Map<String, dynamic> args);

  /// Optional resources (article bodies, structured data) this server exposes.
  List<ChannelResource> listResources();

  /// Read a resource by [uri]. Throws [ArgumentError] for unknown URIs.
  Future<ChannelResource> readResource(String uri);
}

/// In-process registry of [ChannelServer]s.
///
/// This is the single entry point for invoking any channel — from agents,
/// the omnibar, or the feed engine.
class ChannelRegistry {
  final Map<String, ChannelServer> _servers = {};

  /// Register a [server].
  void register(ChannelServer server) => _servers[server.id] = server;

  /// Get a server by [id], or `null` if not registered.
  ChannelServer? server(String id) => _servers[id];

  /// All registered servers.
  List<ChannelServer> get servers => List.unmodifiable(_servers.values);

  /// The union of every server's tools.
  List<ChannelTool> listTools() => [
    for (final server in _servers.values) ...server.listTools(),
  ];

  /// Invoke [tool] on the server [serverId].
  ///
  /// Unknown servers and tools return an error result instead of throwing.
  Future<ChannelCallResult> invoke(
    String serverId,
    String tool,
    Map<String, dynamic> args,
  ) async {
    final server = _servers[serverId];
    if (server == null) {
      return ChannelCallResult.error('Unknown channel server "$serverId"');
    }
    if (!server.listTools().any((t) => t.name == tool)) {
      return ChannelCallResult.error(
        'Unknown tool "$tool" on channel server "$serverId"',
      );
    }
    try {
      return await server.callTool(tool, args);
    } on Object catch (e) {
      return ChannelCallResult.error(
        'Channel "$serverId" tool "$tool" failed: $e',
      );
    }
  }
}

/// Converts a [FeedItem] into a [ContentItem] for the channel UI.
///
/// The unified bridge between feed sources (RSS/Reddit/Nostr/Usenet/DDG) and
/// the channel surface.
ContentItem feedItemToContentItem(FeedItem item) => ContentItem(
  sourcePluginId: 'feed',
  externalId: item.identifier ?? item.url,
  contentType: ContentType.article,
  title: item.title,
  description: item.description,
  url: item.url,
  thumbnailUrl: item.imageUrl,
  author: item.author == null ? null : ContentAuthor(name: item.author),
  publishedAt: item.datePublished,
  tags: item.categories,
);