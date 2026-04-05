/// Explore tab model and state management.
///
/// Each explore tab holds its own rendering mode (semantic vs. classic
/// WebView), optional [BrowseSession], scroll position, and URL. The
/// [ExploreTabNotifier] manages the ordered list of tabs and exposes
/// convenience methods for adding, removing, reordering, and switching tabs.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kabuk/ui/explore/browse_session.dart';
import 'package:meta/meta.dart';

// =============================================================================
// Enums
// =============================================================================

/// Whether a tab renders in semantic (agent-consumed) or classic (WebView) mode.
enum ExploreTabMode {
  /// Semantic mode — feeds, articles, agent-driven content.
  semantic,

  /// Classic mode — raw WebView browser with full JS/cookies.
  classic,
}

// =============================================================================
// Data class
// =============================================================================

/// Sentinel value to distinguish "not passed" from "passed as null" in
/// [ExploreTab.copyWith].
const Object _sentinel = Object();

/// A single tab in the Explore view.
///
/// Tabs are identified by [id] and carry all per-tab state required to restore
/// scroll position, rendering mode, and browse session when the user switches
/// between them.
@immutable
class ExploreTab {
  /// Creates an [ExploreTab].
  const ExploreTab({
    required this.id,
    required this.title,
    this.url,
    this.mode = ExploreTabMode.semantic,
    this.favicon,
    this.isActive = false,
    this.browseSession,
    this.scrollOffset = 0.0,
    this.selectedFeed,
  });

  /// Unique tab identifier.
  final String id;

  /// Display title for the tab sidebar.
  final String title;

  /// Current URL (for classic mode) or feed URL (for semantic browse).
  final String? url;

  /// Rendering mode.
  final ExploreTabMode mode;

  /// Favicon URL or icon data for the sidebar.
  final String? favicon;

  /// Whether this is the currently displayed tab.
  final bool isActive;

  /// Associated browse session for semantic mode.
  final BrowseSession? browseSession;

  /// Scroll position to restore when switching back to this tab.
  final double scrollOffset;

  /// Currently selected feed filter for this tab (null = all feeds).
  final String? selectedFeed;

  /// Returns a copy of this tab with the given fields overridden.
  ExploreTab copyWith({
    String? id,
    String? title,
    String? url,
    ExploreTabMode? mode,
    String? favicon,
    bool? isActive,
    BrowseSession? browseSession,
    double? scrollOffset,
    Object? selectedFeed = _sentinel,
  }) =>
      ExploreTab(
        id: id ?? this.id,
        title: title ?? this.title,
        url: url ?? this.url,
        mode: mode ?? this.mode,
        favicon: favicon ?? this.favicon,
        isActive: isActive ?? this.isActive,
        browseSession: browseSession ?? this.browseSession,
        scrollOffset: scrollOffset ?? this.scrollOffset,
        selectedFeed: selectedFeed == _sentinel
            ? this.selectedFeed
            : selectedFeed as String?,
      );
}

// =============================================================================
// Notifier
// =============================================================================

/// Manages the ordered list of [ExploreTab]s.
///
/// Always guarantees at least one tab exists. When the last tab is removed a
/// new "Home" tab is created automatically.
class ExploreTabNotifier extends StateNotifier<List<ExploreTab>> {
  /// Creates an [ExploreTabNotifier] with a single default Home tab.
  ExploreTabNotifier()
      : super([const ExploreTab(id: 'home', title: 'Home', isActive: true)]);

  /// The currently active tab, or `null` if the list is somehow empty.
  ExploreTab? get activeTab => state.where((t) => t.isActive).firstOrNull;

  /// Adds a new tab and makes it active.
  ///
  /// All existing tabs are deactivated first.
  void addTab({
    String? title,
    String? url,
    ExploreTabMode mode = ExploreTabMode.semantic,
  }) {
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final deactivated = [
      for (final t in state)
        if (t.isActive) t.copyWith(isActive: false) else t,
    ];
    state = [
      ...deactivated,
      ExploreTab(
        id: id,
        title: title ?? 'New Tab',
        url: url,
        mode: mode,
        isActive: true,
      ),
    ];
  }

  /// Removes the tab identified by [tabId].
  ///
  /// If the removed tab was active, the nearest sibling becomes active.
  /// If the last tab is removed, a new Home tab is added automatically.
  void removeTab(String tabId) {
    final index = state.indexWhere((t) => t.id == tabId);
    if (index == -1) return;

    final wasActive = state[index].isActive;
    final updated = [...state]..removeAt(index);

    if (updated.isEmpty) {
      state = [const ExploreTab(id: 'home', title: 'Home', isActive: true)];
      return;
    }

    if (wasActive) {
      final newActiveIndex = index.clamp(0, updated.length - 1);
      state = [
        for (var i = 0; i < updated.length; i++)
          updated[i].copyWith(isActive: i == newActiveIndex),
      ];
    } else {
      state = updated;
    }
  }

  /// Switches the active tab to the one identified by [tabId].
  void switchTab(String tabId) {
    state = [
      for (final t in state) t.copyWith(isActive: t.id == tabId),
    ];
  }

  /// Updates a tab's properties using the provided [updater] function.
  void updateTab(String tabId, ExploreTab Function(ExploreTab) updater) {
    state = [
      for (final t in state)
        if (t.id == tabId) updater(t) else t,
    ];
  }

  /// Reorders tabs by moving the item at [oldIndex] to [newIndex].
  void reorderTabs(int oldIndex, int newIndex) {
    if (oldIndex == newIndex) return;
    final updated = [...state];
    final tab = updated.removeAt(oldIndex);
    final insertAt = newIndex > oldIndex ? newIndex - 1 : newIndex;
    updated.insert(insertAt, tab);
    state = updated;
  }

  /// Sets the rendering [mode] of the currently active tab.
  void setActiveMode(ExploreTabMode mode) {
    state = [
      for (final t in state)
        if (t.isActive) t.copyWith(mode: mode) else t,
    ];
  }

  /// Updates the active tab's URL (typically used during classic-mode navigation).
  void updateActiveUrl(String url, {String? title}) {
    state = [
      for (final t in state)
        if (t.isActive)
          t.copyWith(url: url, title: title ?? t.title)
        else
          t,
    ];
  }

  /// Persists the current scroll [offset] on the active tab.
  void saveScrollOffset(double offset) {
    state = [
      for (final t in state)
        if (t.isActive) t.copyWith(scrollOffset: offset) else t,
    ];
  }
}

// =============================================================================
// Providers
// =============================================================================

/// Manages all explore tabs.
final exploreTabsProvider =
    StateNotifierProvider<ExploreTabNotifier, List<ExploreTab>>(
  (ref) => ExploreTabNotifier(),
);

/// Convenience provider for just the active tab.
final activeExploreTabProvider = Provider<ExploreTab?>((ref) {
  final tabs = ref.watch(exploreTabsProvider);
  return tabs.where((t) => t.isActive).firstOrNull;
});
