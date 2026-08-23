/// Channel sessions — the agent-populated containers the OS draws.
///
/// The channel is the core agent-OS contract. A [ChannelSession] holds a
/// [Channel] plus the typed [ContentItem]s an agent produced for it. The
/// OS renders the items with existing drawing primitives (`contentCardFor`
/// / `ViewerRouter`); the agent never authors UI.
///
/// The active session is exposed through [agentChannelProvider] so any
/// surface can reactively draw whatever the agent just populated.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kabuk/plugins/channel.dart';
import 'package:kabuk/plugins/content_item.dart';

/// An agent-populated channel: identity + content + provenance.
class ChannelSession {
  /// Creates a [ChannelSession].
  ChannelSession({
    required this.channel,
    required this.items,
    this.summary,
    this.agentName,
    this.source,
    DateTime? populatedAt,
  }) : populatedAt = populatedAt ?? DateTime.now();

  /// The channel identity (uri, type, title, artwork).
  final Channel channel;

  /// Typed content items the agent produced for this channel.
  final List<ContentItem> items;

  /// Optional one-line summary the agent wrote about the results.
  final String? summary;

  /// Which agent populated this channel.
  final String? agentName;

  /// The source URL/query that led to this channel, when known.
  final String? source;

  /// When the channel was last populated.
  final DateTime populatedAt;

  /// Returns a copy of this session with the given fields overridden.
  ChannelSession copyWith({
    Channel? channel,
    List<ContentItem>? items,
    String? summary,
    String? agentName,
    String? source,
    DateTime? populatedAt,
  }) => ChannelSession(
    channel: channel ?? this.channel,
    items: items ?? this.items,
    summary: summary ?? this.summary,
    agentName: agentName ?? this.agentName,
    source: source ?? this.source,
    populatedAt: populatedAt ?? this.populatedAt,
  );
}

/// Controls the active [ChannelSession].
///
/// Agents populate channels through this controller (a side-effect of
/// returning `ToolResult.channel`); surfaces watch [agentChannelProvider]
/// to redraw. The controller is profile-scoped through Riverpod.
abstract interface class ChannelController {
  /// The currently active session, or `null` if none.
  ChannelSession? get current;

  /// Replaces the active session with [session].
  void populate(ChannelSession session);

  /// Clears the active session.
  void clear();
}

/// Riverpod [StateNotifier] implementation of [ChannelController].
class AgentChannelController extends StateNotifier<ChannelSession?>
    implements ChannelController {
  /// Creates an [AgentChannelController] with no active session.
  AgentChannelController() : super(null);

  @override
  ChannelSession? get current => state;

  @override
  void populate(ChannelSession session) => state = session;

  @override
  void clear() => state = null;
}

/// The active agent-populated [ChannelSession].
///
/// Watch this in any surface to draw whatever the agent most recently
/// produced for a channel.
final agentChannelProvider =
    StateNotifierProvider<AgentChannelController, ChannelSession?>(
      (ref) => AgentChannelController(),
    );

/// Builds a stable channel URI from a source URL/query.
///
/// Reused by the resolver and agents so the same source maps to the same
/// channel (find-or-create semantics without a persisted store).
String channelUriFor(String source, {String prefix = 'agent'}) {
  final clean = source
      .replaceAll('https://', '')
      .replaceAll('http://', '')
      .replaceAll(RegExp(r'[^a-zA-Z0-9]+'), '-')
      .trim()
      .replaceAll(RegExp(r'^-+|-+$'), '');
  final slug = clean.isEmpty ? 'untitled' : clean.toLowerCase();
  return 'kabuk:$prefix/$slug';
}