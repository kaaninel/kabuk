/// Agent channel surface — draws whatever the agent populated.
///
/// This is the render half of the agent-OS channel: it watches
/// [agentChannelProvider] and draws the session's typed content with
/// existing primitives (`contentCardFor` / `ViewerRouter`). The agent
/// produces data; this surface draws it. It also publishes perception
/// events ([ChannelViewedEvent], [ItemOpenedEvent]) so the agent can
/// react to what the user does with its output.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kabuk/agents/channels.dart';
import 'package:kabuk/agents/observation.dart';
import 'package:kabuk/plugins/content_item.dart';
import 'package:kabuk/ui/theme.dart';
import 'package:kabuk/ui/viewers/content_cards.dart';
import 'package:kabuk/ui/viewers/viewer_router.dart';

/// Full-screen page rendering the active agent-populated channel.
class AgentChannelPage extends ConsumerStatefulWidget {
  /// Creates an [AgentChannelPage].
  const AgentChannelPage({super.key});

  @override
  ConsumerState<AgentChannelPage> createState() => _AgentChannelPageState();
}

class _AgentChannelPageState extends ConsumerState<AgentChannelPage> {
  bool _viewed = false;

  @override
  void initState() {
    super.initState();
    // Publish a viewed observation as soon as the surface opens so the
    // agent can perceive the user is looking at its output.
    final session = ref.read(agentChannelProvider);
    if (session != null) _publishViewed(session);
  }

  void _publishViewed(ChannelSession session) {
    if (_viewed) return;
    _viewed = true;
    ref.read(observationBusProvider).publish(
      ChannelViewedEvent(
        channelUri: session.channel.entityUri,
        title: session.channel.title,
      ),
    );
  }

  void _openItem(ChannelSession session, ContentItem item) {
    ref.read(observationBusProvider).publish(
      ItemOpenedEvent(
        channelUri: session.channel.entityUri,
        itemTitle: item.title,
        itemUrl: item.url,
        contentType: item.contentType,
      ),
    );
    ViewerRouter.open(context, item);
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(agentChannelProvider);
    if (session != null) _publishViewed(session);

    return Scaffold(
      backgroundColor: context.kabukBackground,
      appBar: AppBar(
        backgroundColor: context.kabukSurface,
        title: Text(
          session?.channel.title ?? 'Agent channel',
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
      ),
      body: session == null
          ? _EmptyChannelState()
          : ChannelItemsGrid(
              session: session,
              onOpenItem: (item) => _openItem(session, item),
            ),
    );
  }
}

/// A grid/list of the items in a [ChannelSession], drawn with the
/// standard content card primitives.
class ChannelItemsGrid extends StatelessWidget {
  /// Creates a [ChannelItemsGrid].
  const ChannelItemsGrid({required this.session, this.onOpenItem, super.key});

  /// The session to draw.
  final ChannelSession session;

  /// Called when the user taps an item. Defaults to [ViewerRouter.open].
  final void Function(ContentItem item)? onOpenItem;

  @override
  Widget build(BuildContext context) {
    final items = session.items;
    if (items.isEmpty) {
      return const _EmptyChannelState();
    }

    final useGrid = items.length > 2 && items.every((i) => _gridLike(i.contentType));

    void openItem(ContentItem item) {
      final cb = onOpenItem;
      if (cb != null) {
        cb(item);
      } else {
        ViewerRouter.open(context, item);
      }
    }

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: _ChannelHeader(session: session)),
        if (useGrid)
          SliverPadding(
            padding: const EdgeInsets.symmetric(
              horizontal: KabukTheme.spacingSm,
              vertical: KabukTheme.spacingSm,
            ),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: KabukTheme.spacingSm,
                crossAxisSpacing: KabukTheme.spacingSm,
                childAspectRatio: 0.75,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) => contentCardFor(
                  items[index],
                  onTap: () => openItem(items[index]),
                ),
                childCount: items.length,
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.symmetric(
              horizontal: KabukTheme.spacingSm,
              vertical: KabukTheme.spacingSm,
            ),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) => Padding(
                  padding: const EdgeInsets.only(bottom: KabukTheme.spacingSm),
                  child: contentCardFor(
                    items[index],
                    onTap: () => openItem(items[index]),
                  ),
                ),
                childCount: items.length,
              ),
            ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 48)),
      ],
    );
  }

  static bool _gridLike(ContentType type) =>
      type == ContentType.video ||
      type == ContentType.image ||
      type == ContentType.mixed;
}

/// Channel identity row: avatar, title, producer badge, item count.
class _ChannelHeader extends StatelessWidget {
  const _ChannelHeader({required this.session});

  final ChannelSession session;

  @override
  Widget build(BuildContext context) {
    final channel = session.channel;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        KabukTheme.spacingMd,
        KabukTheme.spacingSm,
        KabukTheme.spacingMd,
        KabukTheme.spacingSm,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: KabukTheme.accentGreen.withAlpha(40),
            child: Icon(
              Icons.auto_awesome_rounded,
              color: KabukTheme.accentGreen,
              size: 22,
            ),
          ),
          const SizedBox(width: KabukTheme.spacingSm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  channel.title,
                  style: TextStyle(
                    color: context.kabukTextPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (channel.description != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    channel.description!,
                    style: TextStyle(
                      color: context.kabukTextSecondary,
                      fontSize: 12,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 6),
                Wrap(
                  spacing: KabukTheme.spacingXs,
                  children: [
                    _Badge(
                      icon: Icons.smart_toy_outlined,
                      label: session.agentName ?? 'agent',
                    ),
                    _Badge(
                      icon: Icons.grid_view_rounded,
                      label: '${session.items.length} items',
                    ),
                    if (session.source != null)
                      _Badge(
                        icon: Icons.link_rounded,
                        label: _shorten(session.source!, 28),
                      ),
                  ],
                ),
                if (session.summary != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    session.summary!,
                    style: TextStyle(
                      color: context.kabukTextSecondary,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _shorten(String s, int max) =>
      s.length <= max ? s : '${s.substring(0, max)}…';
}

/// A small pill badge in the channel header.
class _Badge extends StatelessWidget {
  const _Badge({required this.label, this.icon});

  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: context.kabukSurfaceVariant,
        borderRadius: BorderRadius.circular(KabukTheme.radiusSm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: context.kabukTextSecondary),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              color: context.kabukTextSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

/// Empty state shown when no agent has populated a channel yet.
class _EmptyChannelState extends StatelessWidget {
  const _EmptyChannelState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.auto_awesome_rounded,
            size: 48,
            color: KabukTheme.accentGreen.withAlpha(120),
          ),
          const SizedBox(height: KabukTheme.spacingMd),
          Text(
            'Nothing here yet',
            style: TextStyle(
              color: context.kabukTextSecondary,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: KabukTheme.spacingSm),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              'Ask an agent to find something — search a topic, a Usenet '
              'query, or a hashtag — and the results will be drawn here.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: context.kabukTextTertiary,
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}