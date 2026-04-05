/// Safari-inspired tab sidebar drawer for explore tab management.
///
/// A Material Design 3 drawer that slides over content as a 280 px overlay
/// with a scrim backdrop. Features a clean header with tab count and "Done"
/// button, rounded tab tiles with favicon/URL, browser navigation controls
/// for Classic-mode tabs, and a full-width "New Tab" button at the bottom.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kabuk/ui/explore/explore_tab.dart';
import 'package:kabuk/ui/marketplace/marketplace_page.dart';
import 'package:kabuk/ui/theme.dart';

// =============================================================================
// Constants
// =============================================================================

const double _kDrawerWidth = 280.0;
const Duration _kAnimationDuration = Duration(milliseconds: 250);
const double _kActiveIndicatorWidth = 3.0;
const double _kSwipeThreshold = 20.0;
const double _kTabTileHeight = 52.0;
const double _kTabTileRadius = 10.0;
const double _kHeaderHeight = 52.0;
const double _kFooterHeight = 48.0;
const double _kBrowserControlsHeight = 40.0;
const int _kScrimAlpha = 60;

// =============================================================================
// Provider
// =============================================================================

/// Whether the explore tab drawer is open.
final exploreDrawerOpenProvider = StateProvider<bool>((ref) => false);

// =============================================================================
// TabSidebar
// =============================================================================

/// A drawer-style overlay that lists all [ExploreTab]s.
///
/// Completely hidden when closed (zero width). Slides over content when opened
/// with a translucent scrim. Includes browser navigation controls (back,
/// forward, reload, URL) when the active tab is in Classic mode.
class TabSidebar extends ConsumerStatefulWidget {
  /// Creates a [TabSidebar].
  const TabSidebar({
    super.key,
    this.onBack,
    this.onForward,
    this.onRefresh,
  });

  /// Called when the user taps the browser back button.
  final VoidCallback? onBack;

  /// Called when the user taps the browser forward button.
  final VoidCallback? onForward;

  /// Called when the user taps the browser refresh button.
  final VoidCallback? onRefresh;

  @override
  ConsumerState<TabSidebar> createState() => _TabSidebarState();
}

class _TabSidebarState extends ConsumerState<TabSidebar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  late final Animation<double> _slideAnimation;
  late final Animation<double> _scrimAnimation;

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: _kAnimationDuration,
    );
    _slideAnimation = Tween<double>(begin: -_kDrawerWidth, end: 0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic),
    );
    _scrimAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Close helper
  // ---------------------------------------------------------------------------

  void _close() {
    _animController.reverse().then((_) {
      if (mounted) {
        ref.read(exploreDrawerOpenProvider.notifier).state = false;
      }
    });
  }

  // ---------------------------------------------------------------------------
  // Tab helpers
  // ---------------------------------------------------------------------------

  void _switchTab(String id) {
    ref.read(exploreTabsProvider.notifier).switchTab(id);
  }

  void _addTab() {
    ref.read(exploreTabsProvider.notifier).addTab(title: 'New Tab');
  }

  void _removeTab(String id) {
    ref.read(exploreTabsProvider.notifier).removeTab(id);
  }

  void _reorder(int oldIndex, int newIndex) {
    ref.read(exploreTabsProvider.notifier).reorderTabs(oldIndex, newIndex);
  }

  IconData _iconForTab(ExploreTab tab) {
    if (tab.id == 'home') return Icons.home_rounded;
    return switch (tab.mode) {
      ExploreTabMode.semantic => Icons.explore_rounded,
      ExploreTabMode.classic => Icons.language_rounded,
    };
  }

  ExploreTabMode _toggledMode(ExploreTabMode mode) => switch (mode) {
        ExploreTabMode.semantic => ExploreTabMode.classic,
        ExploreTabMode.classic => ExploreTabMode.semantic,
      };

  // ---------------------------------------------------------------------------
  // Context menu
  // ---------------------------------------------------------------------------

  void _showContextMenu(BuildContext ctx, ExploreTab tab) {
    final notifier = ref.read(exploreTabsProvider.notifier);
    final oppositeLabel = tab.mode == ExploreTabMode.semantic
        ? 'Switch to Classic'
        : 'Switch to Semantic';

    showMenu<String>(
      context: ctx,
      position: _menuPosition(ctx),
      color: context.kabukSurfaceElevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
      items: [
        const PopupMenuItem(value: 'close', child: Text('Close Tab')),
        const PopupMenuItem(value: 'duplicate', child: Text('Duplicate Tab')),
        PopupMenuItem(value: 'toggle', child: Text(oppositeLabel)),
      ],
    ).then((value) {
      if (value == null) return;
      switch (value) {
        case 'close':
          _removeTab(tab.id);
        case 'duplicate':
          notifier.addTab(
            title: tab.title,
            url: tab.url,
            mode: tab.mode,
          );
        case 'toggle':
          notifier.updateTab(
            tab.id,
            (t) => t.copyWith(mode: _toggledMode(t.mode)),
          );
      }
    });
  }

  RelativeRect _menuPosition(BuildContext ctx) {
    final box = ctx.findRenderObject()! as RenderBox;
    final offset = box.localToGlobal(Offset.zero);
    return RelativeRect.fromLTRB(
      offset.dx + box.size.width,
      offset.dy,
      offset.dx + box.size.width,
      offset.dy + box.size.height,
    );
  }

  /// Extracts the domain from a URL for display in the browser bar.
  String? _domainFromUrl(String? url) {
    if (url == null || url.isEmpty) return null;
    try {
      return Uri.parse(url).host;
    } catch (_) {
      return url;
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final tabs = ref.watch(exploreTabsProvider);
    final activeTab = ref.watch(activeExploreTabProvider);
    final isOpen = ref.watch(exploreDrawerOpenProvider);
    final theme = Theme.of(context);

    // Sync animation controller with provider state (handles external opens).
    if (isOpen && !_animController.isAnimating && _animController.value == 0) {
      _animController.forward();
    } else if (!isOpen &&
        !_animController.isAnimating &&
        _animController.value == 1) {
      _animController.reverse();
    }

    return AnimatedBuilder(
      animation: _animController,
      builder: (context, _) {
        final isAnimatingOrOpen =
            _animController.value > 0 || _animController.isAnimating;

        return Stack(
          children: [
            // ── Scrim (tap to close) ────────────────────────────────────
            if (isAnimatingOrOpen)
              Positioned.fill(
                child: GestureDetector(
                  onTap: _close,
                  onHorizontalDragUpdate: (details) {
                    if (details.delta.dx < -_kSwipeThreshold) _close();
                  },
                  child: ColoredBox(
                    color: theme.colorScheme.scrim.withAlpha(
                      (_kScrimAlpha * _scrimAnimation.value).round(),
                    ),
                  ),
                ),
              ),

            // ── Drawer panel ────────────────────────────────────────────
            if (isAnimatingOrOpen)
              Positioned(
                left: _slideAnimation.value,
                top: 0,
                bottom: 0,
                width: _kDrawerWidth,
                child: GestureDetector(
                  onHorizontalDragUpdate: (details) {
                    if (details.delta.dx < -_kSwipeThreshold) _close();
                  },
                  child: Material(
                    color: context.kabukSurface,
                    elevation: 4,
                    surfaceTintColor: Colors.transparent,
                    shadowColor: theme.shadowColor,
                    child: Column(
                      children: [
                        // ── Header ──────────────────────────────────
                        _DrawerHeader(
                          tabCount: tabs.length,
                          onDone: _close,
                        ),
                        Divider(
                          height: 1,
                          color: context.kabukDivider,
                        ),

                        // ── Browser controls (classic only) ─────────
                        if (activeTab?.mode == ExploreTabMode.classic)
                          _BrowserControls(
                            domain: _domainFromUrl(activeTab?.url),
                            onBack: widget.onBack,
                            onForward: widget.onForward,
                            onRefresh: widget.onRefresh,
                          ),

                        // ── Tab list ────────────────────────────────
                        Expanded(
                          child: _DrawerTabList(
                            tabs: tabs,
                            iconForTab: _iconForTab,
                            onTap: (id) {
                              _switchTab(id);
                              _close();
                            },
                            onRemove: _removeTab,
                            onReorder: _reorder,
                            onLongPress: _showContextMenu,
                          ),
                        ),

                        // ── New tab button ──────────────────────────
                        Divider(
                          height: 1,
                          color: context.kabukDivider,
                        ),
                        ListTile(
                          dense: true,
                          leading: Icon(
                            Icons.store_outlined,
                            color: context.kabukTextSecondary,
                            size: 20,
                          ),
                          title: Text(
                            'Marketplace',
                            style: TextStyle(
                              color: context.kabukTextPrimary,
                              fontSize: 14,
                            ),
                          ),
                          onTap: () {
                            _close();
                            Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => const MarketplacePage(),
                              ),
                            );
                          },
                        ),
                        Divider(
                          height: 1,
                          color: context.kabukDivider,
                        ),
                        _AddTabButton(onTap: () {
                          _addTab();
                          _close();
                        }),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

// =============================================================================
// Drawer header — tab count + "Done" button
// =============================================================================

class _DrawerHeader extends StatelessWidget {
  const _DrawerHeader({required this.tabCount, required this.onDone});

  /// Number of open tabs to display in the header label.
  final int tabCount;

  /// Called when the user taps the "Done" button.
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: _kHeaderHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            Text(
              '$tabCount Tab${tabCount == 1 ? '' : 's'}',
              style: TextStyle(
                color: context.kabukTextPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
            const Spacer(),
            TextButton(
              onPressed: onDone,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                minimumSize: const Size(0, 36),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                'Done',
                style: TextStyle(
                  color: theme.colorScheme.primary,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Browser controls — back, forward, reload, domain
// =============================================================================

class _BrowserControls extends StatelessWidget {
  const _BrowserControls({
    this.domain,
    this.onBack,
    this.onForward,
    this.onRefresh,
  });

  /// Domain text displayed in the browser bar.
  final String? domain;

  /// Called when the user taps the browser back button.
  final VoidCallback? onBack;

  /// Called when the user taps the browser forward button.
  final VoidCallback? onForward;

  /// Called when the user taps the browser refresh button.
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: _kBrowserControlsHeight,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: context.kabukSurfaceVariant,
        border: Border(
          bottom: BorderSide(color: context.kabukDivider),
        ),
      ),
      child: Row(
        children: [
          _NavIconButton(icon: Icons.arrow_back_rounded, onTap: onBack),
          _NavIconButton(icon: Icons.arrow_forward_rounded, onTap: onForward),
          _NavIconButton(icon: Icons.refresh_rounded, onTap: onRefresh),
          const SizedBox(width: 6),
          Icon(Icons.lock_rounded, size: 12, color: context.kabukTextTertiary),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              domain ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: context.kabukTextSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact icon button used in the browser navigation bar.
class _NavIconButton extends StatelessWidget {
  const _NavIconButton({required this.icon, this.onTap});

  /// The icon to display.
  final IconData icon;

  /// Called when the button is tapped. `null` disables the button.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return SizedBox(
      width: 32,
      height: 32,
      child: IconButton(
        padding: EdgeInsets.zero,
        iconSize: 20,
        onPressed: onTap,
        icon: Icon(
          icon,
          color: enabled
              ? context.kabukTextSecondary
              : context.kabukTextTertiary,
        ),
      ),
    );
  }
}

// =============================================================================
// Drawer tab list (reorderable)
// =============================================================================

class _DrawerTabList extends StatelessWidget {
  const _DrawerTabList({
    required this.tabs,
    required this.iconForTab,
    required this.onTap,
    required this.onRemove,
    required this.onReorder,
    required this.onLongPress,
  });

  /// All open tabs.
  final List<ExploreTab> tabs;

  /// Returns the leading icon for a given tab.
  final IconData Function(ExploreTab) iconForTab;

  /// Called when the user taps a tab to switch to it.
  final void Function(String) onTap;

  /// Called when the user removes a tab via the close button.
  final void Function(String) onRemove;

  /// Called when the user reorders tabs via drag.
  final void Function(int, int) onReorder;

  /// Called on long-press to show the tab context menu.
  final void Function(BuildContext, ExploreTab) onLongPress;

  @override
  Widget build(BuildContext context) {
    return ReorderableListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      buildDefaultDragHandles: false,
      proxyDecorator: (child, index, animation) {
        return AnimatedBuilder(
          animation: animation,
          builder: (context, child) => Material(
            color: context.kabukSurfaceElevated,
            elevation: 6,
            surfaceTintColor: Colors.transparent,
            borderRadius: BorderRadius.circular(_kTabTileRadius),
            child: child,
          ),
          child: child,
        );
      },
      itemCount: tabs.length,
      onReorder: onReorder,
      itemBuilder: (context, index) {
        final tab = tabs[index];
        return _DrawerTabTile(
          key: ValueKey(tab.id),
          tab: tab,
          index: index,
          icon: iconForTab(tab),
          showClose: tabs.length > 1,
          onTap: () => onTap(tab.id),
          onRemove: () => onRemove(tab.id),
          onLongPress: (ctx) => onLongPress(ctx, tab),
        );
      },
    );
  }
}

// =============================================================================
// Individual tab tile — rounded card with favicon, title, URL, close button
// =============================================================================

class _DrawerTabTile extends StatefulWidget {
  const _DrawerTabTile({
    super.key,
    required this.tab,
    required this.index,
    required this.icon,
    required this.showClose,
    required this.onTap,
    required this.onRemove,
    required this.onLongPress,
  });

  /// The tab data to render.
  final ExploreTab tab;

  /// Index in the list (used for [ReorderableDragStartListener]).
  final int index;

  /// Leading icon for the tab.
  final IconData icon;

  /// Whether to show the close button (hidden when only one tab remains).
  final bool showClose;

  /// Called when the tile is tapped.
  final VoidCallback onTap;

  /// Called when the close button is pressed.
  final VoidCallback onRemove;

  /// Called on long-press (provides the local [BuildContext] for menu positioning).
  final void Function(BuildContext) onLongPress;

  @override
  State<_DrawerTabTile> createState() => _DrawerTabTileState();
}

class _DrawerTabTileState extends State<_DrawerTabTile> {
  bool _hovered = false;

  /// Extracts a displayable domain from the tab URL.
  String? get _domain {
    final url = widget.tab.url;
    if (url == null || url.isEmpty) return null;
    try {
      return Uri.parse(url).host;
    } catch (_) {
      return url;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isActive = widget.tab.isActive;
    final domain = _domain;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onLongPress: () => widget.onLongPress(context),
          child: Material(
            color: isActive
                ? cs.primary.withAlpha(20)
                : _hovered
                    ? context.kabukSurfaceVariant
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(_kTabTileRadius),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              borderRadius: BorderRadius.circular(_kTabTileRadius),
              onTap: widget.onTap,
              child: SizedBox(
                height: _kTabTileHeight,
                child: Row(
                  children: [
                    // ── Active accent border ────────────────────────
                    if (isActive)
                      Container(
                        width: _kActiveIndicatorWidth,
                        decoration: BoxDecoration(
                          color: cs.primary,
                          borderRadius: const BorderRadius.horizontal(
                            left: Radius.circular(_kTabTileRadius),
                          ),
                        ),
                      ),
                    SizedBox(width: isActive ? 9 : 12),

                    // ── Favicon / icon ──────────────────────────────
                    ReorderableDragStartListener(
                      index: widget.index,
                      child: Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          color: isActive
                              ? cs.primary.withAlpha(30)
                              : context.kabukSurfaceVariant,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Icon(
                          widget.icon,
                          size: 14,
                          color:
                              isActive ? cs.primary : context.kabukTextSecondary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),

                    // ── Title + URL ─────────────────────────────────
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.tab.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              color: isActive
                                  ? context.kabukTextPrimary
                                  : context.kabukTextSecondary,
                              fontWeight: isActive
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                            ),
                          ),
                          if (domain != null && domain.isNotEmpty)
                            Text(
                              domain,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: context.kabukTextTertiary,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 4),

                    // ── Close button ────────────────────────────────
                    if (widget.showClose)
                      SizedBox(
                        width: 28,
                        height: 28,
                        child: IconButton(
                          padding: EdgeInsets.zero,
                          iconSize: 16,
                          onPressed: widget.onRemove,
                          icon: Icon(
                            Icons.close_rounded,
                            color: context.kabukTextTertiary,
                          ),
                        ),
                      ),
                    const SizedBox(width: 4),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Add-tab button — full-width footer
// =============================================================================

class _AddTabButton extends StatelessWidget {
  const _AddTabButton({required this.onTap});

  /// Called when the user taps to create a new tab.
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: _kFooterHeight,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Icon(
                  Icons.add_rounded,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 10),
                Text(
                  'New Tab',
                  style: TextStyle(
                    color: theme.colorScheme.primary,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
