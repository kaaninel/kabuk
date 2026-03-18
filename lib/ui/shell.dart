/// Main app shell with bottom navigation for the Kabuk OS.
library;

import 'dart:convert';
import 'dart:developer' as dev;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kabuk/agents/cost_tracker.dart';
import 'package:kabuk/config/providers.dart';
import 'package:kabuk/knowledge/database.dart';
import 'package:kabuk/ui/apps/apps_view.dart';
import 'package:kabuk/ui/chat/chat_input.dart';
import 'package:kabuk/ui/chat/chat_service.dart';
import 'package:kabuk/ui/chat/chat_view.dart';
import 'package:kabuk/ui/chat/conversation_detail.dart';
import 'package:kabuk/ui/chat/message_bubble.dart';
import 'package:kabuk/ui/chat/nostr_chat_detail.dart';
import 'package:kabuk/ui/vault/vault_view.dart';
import 'package:kabuk/ui/explore/explore_view.dart';
import 'package:kabuk/ui/explore/profile_view.dart';
import 'package:kabuk/ui/settings/dev_mode_page.dart';
import 'package:kabuk/ui/theme.dart';

/// Provider for the currently selected tab index.
final selectedTabProvider = StateProvider<int>((ref) => 0);

/// Whether the pull-up chat sheet overlay is visible.
final chatSheetVisibleProvider = StateProvider<bool>((ref) => false);

/// When set, the shell should switch to the Explore tab and push a
/// [ProfileView] for the given pubkey. Cleared after navigation.
final pendingProfilePubkeyProvider = StateProvider<String?>((ref) => null);

/// The main app shell with swipeable page navigation.
///
/// Displays four primary views — Explore, Chat, Vault, and Apps —
/// using a [PageView] body with a thin multicolor indicator bar at the
/// bottom. Horizontal drag on the bar switches views; tapping the bar
/// opens the AI chat sheet overlay.
///
/// Also handles app lifecycle changes: when the app returns to the
/// foreground after being backgrounded it reconnects all Nostr relays
/// so that DMs are not missed.
class KabukShell extends ConsumerStatefulWidget {
  /// Creates a [KabukShell].
  const KabukShell({super.key});

  @override
  ConsumerState<KabukShell> createState() => _KabukShellState();
}

class _KabukShellState extends ConsumerState<KabukShell>
    with WidgetsBindingObserver {
  static const _views = <Widget>[
    ExploreView(),
    ChatView(),
    VaultView(),
    AppsView(),
  ];

  late final PageController _pageController;

  /// Whether we are currently animating the [PageController] programmatically
  /// to avoid re-entrant updates from the page-change callback.
  bool _animating = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pageController = PageController();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pageController.dispose();
    super.dispose();
  }

  /// Reconnect all Nostr relays when the app comes back to the foreground.
  ///
  /// Mobile OSes suspend Dart isolates when the app is backgrounded,
  /// dropping WebSocket connections. Reconnecting on resume ensures
  /// incoming DMs are received after the user returns to the app.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(nostrServiceProvider).connectAll();
    }
  }

  /// Animate the [PageView] to [page] and keep [selectedTabProvider] in sync.
  void _goToPage(int page) {
    if (page < 0 || page >= _views.length) return;
    HapticFeedback.selectionClick();
    _animating = true;
    ref.read(selectedTabProvider.notifier).state = page;
    _pageController
        .animateToPage(
          page,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        )
        .then((_) => _animating = false);
  }

  @override
  Widget build(BuildContext context) {
    final selectedTab = ref.watch(selectedTabProvider);
    final showChatSheet = ref.watch(chatSheetVisibleProvider);
    final modelState = ref.watch(modelReadinessProvider);
    final devMode = ref.watch(devModeProvider);

    // Eagerly ensure an identity exists (auto-generates on first launch).
    ref.watch(ensureIdentityProvider);

    // Resume the last conversation on first build so the chat
    // overlay and detail view start with the most recent thread.
    ref.watch(resumeLastConversationProvider);

    // Activate background DM listener to store incoming Nostr messages.
    ref.watch(nostrDmBackgroundListenerProvider);

    // Navigate to the DM conversation when a notification is tapped.
    ref.listen<AsyncValue<Map<String, dynamic>>>(
      notificationTapStreamProvider,
      (_, tap) {
        tap.whenData((event) {
          final payloadStr = event['payload'] as String?;
          if (payloadStr == null) return;
          try {
            final payload = jsonDecode(payloadStr) as Map<String, dynamic>;
            if (payload['type'] == 'nostr_dm') {
              final convId = payload['conversationId'] as String?;
              if (convId == null) return;
              final peerPubkey = convId.replaceFirst('nostr_dm_', '');
              ref.read(activeConversationProvider.notifier).state = convId;
              ref.read(selectedTabProvider.notifier).state = 1;
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => NostrChatDetail(
                    conversationId: convId,
                    recipientPubkey: peerPubkey,
                    displayName: '${peerPubkey.substring(0, 8)}...',
                  ),
                ),
              );
            }
          } on Object catch (e) {
            dev.log(
              'Malformed notification payload: $e',
              name: 'Shell',
              error: e,
            );
          }
        });
      },
    );

    // Auto-dismiss the sheet when the user switches to the Chat tab.
    ref.listen<int>(selectedTabProvider, (_, next) {
      if (next == 1 && ref.read(chatSheetVisibleProvider)) {
        ref.read(chatSheetVisibleProvider.notifier).state = false;
      }
      // Keep PageView in sync when selectedTabProvider changes externally.
      if (!_animating &&
          _pageController.hasClients &&
          _pageController.page?.round() != next) {
        _animating = true;
        _pageController
            .animateToPage(
              next,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
            )
            .then((_) => _animating = false);
      }
    });

    // Navigate to a profile in the Explore tab when requested from chat.
    ref.listen<String?>(pendingProfilePubkeyProvider, (_, pubkey) {
      if (pubkey == null) return;
      ref.read(pendingProfilePubkeyProvider.notifier).state = null;
      ref.read(selectedTabProvider.notifier).state = 0;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => ProfileView(pubkey: pubkey)),
        );
      });
    });

    return Scaffold(
      body: Stack(
        children: [
          Column(
            children: [
              // Developer mode info bar.
              if (devMode) const _DevInfoBar(),
              // Model download banner.
              if (modelState.status == ModelReadyStatus.downloading)
                _ModelDownloadBanner(state: modelState),
              if (modelState.status == ModelReadyStatus.unavailable)
                _ModelUnavailableBanner(
                  error: modelState.error,
                  onRetry: () =>
                      ref.read(modelReadinessProvider.notifier).retry(),
                ),
              Expanded(
                child: PageView(
                  controller: _pageController,
                  physics: const NeverScrollableScrollPhysics(),
                  children: _views,
                ),
              ),
              // Thin multicolor indicator bar at the bottom.
              _NavIndicatorBar(
                selectedTab: selectedTab,
                onSwitchTab: _goToPage,
                onTap: () {
                  ref.read(chatSheetVisibleProvider.notifier).state = true;
                },
              ),
            ],
          ),
          if (showChatSheet) const _ChatSheetOverlay(),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Bottom navigation indicator bar
// ---------------------------------------------------------------------------

/// Per-tab accent colors matching the four primary views.
const _tabColors = [
  KabukTheme.warmAccent, // Explore
  KabukTheme.accentGreen, // Chat
  KabukTheme.purpleAccent, // Vault
  KabukTheme.blueAccent, // Apps
];

/// A thin multicolor indicator bar that replaces the Material NavigationBar.
///
/// The bar sits at the very bottom of the screen, similar to Android's
/// gesture navigation pill. Horizontal drag switches views; tap opens
/// the AI chat sheet.
class _NavIndicatorBar extends StatelessWidget {
  const _NavIndicatorBar({
    required this.selectedTab,
    required this.onSwitchTab,
    required this.onTap,
  });

  /// Currently active tab index (0-3).
  final int selectedTab;

  /// Callback to switch to a different tab by index.
  final ValueChanged<int> onSwitchTab;

  /// Callback when the bar is tapped (opens chat sheet).
  final VoidCallback onTap;

  /// Height of the visible indicator bar.
  static const double _barHeight = 5.0;

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final bottomPadding = MediaQuery.of(context).viewPadding.bottom;
    final quarterWidth = screenWidth / 4;
    final color = _tabColors[selectedTab];

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onHorizontalDragEnd: (details) {
        final velocity = details.primaryVelocity ?? 0;
        // Follow finger direction: swipe right → next, swipe left → prev.
        if (velocity > 100) {
          onSwitchTab(selectedTab + 1);
        } else if (velocity < -100) {
          onSwitchTab(selectedTab - 1);
        }
      },
      child: Container(
        // Full-width gesture target pinned to the absolute bottom.
        padding: EdgeInsets.only(
          top: 8,
          bottom: bottomPadding > 0 ? bottomPadding : 4,
        ),
        color: Colors.transparent,
        alignment: Alignment.center,
        child: SizedBox(
          height: _barHeight,
          width: screenWidth,
          child: Stack(
            children: [
              // Full-width gray track.
              Container(
                width: screenWidth,
                height: _barHeight,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(_barHeight / 2),
                ),
              ),
              // Colored quarter segment that slides to the active tab.
              AnimatedPositioned(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                left: quarterWidth * selectedTab,
                top: 0,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                  width: quarterWidth,
                  height: _barHeight,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(_barHeight / 2),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Pull-up chat sheet overlay
// ---------------------------------------------------------------------------

/// A draggable sheet overlay providing quick chat access from any view.
///
/// Shares state with the main [ChatView] through the same Riverpod
/// providers ([activeConversationProvider], [messagesProvider], etc.).
class _ChatSheetOverlay extends ConsumerStatefulWidget {
  const _ChatSheetOverlay();

  @override
  ConsumerState<_ChatSheetOverlay> createState() => _ChatSheetOverlayState();
}

class _ChatSheetOverlayState extends ConsumerState<_ChatSheetOverlay> {
  final _sheetController = DraggableScrollableController();
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _sheetController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _sendMessage(String text) async {
    if (text.trim().isEmpty) return;
    _scrollToBottom();
    await ref.read(chatServiceProvider).sendMessage(text);
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final messagesAsync = ref.watch(messagesProvider);
    final isProcessing = ref.watch(isProcessingProvider);
    final streamingText = ref.watch(streamingTextProvider);
    final conversationId = ref.watch(activeConversationProvider);
    final processingStatus = ref.watch(processingStatusProvider);

    return DraggableScrollableSheet(
      controller: _sheetController,
      initialChildSize: 0.4,
      minChildSize: 0.15,
      maxChildSize: 0.85,
      snap: true,
      snapSizes: const [0.15, 0.4, 0.85],
      builder: (context, sheetScrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: KabukTheme.surface,
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(KabukTheme.radiusXl),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black54,
                blurRadius: 20,
                offset: Offset(0, -4),
              ),
            ],
          ),
          child: Column(
            children: [
              // Drag handle.
              _buildDragHandle(),
              // Header.
              _buildHeader(),
              const Divider(height: 1, color: KabukTheme.divider),
              // Messages list.
              Expanded(
                child: conversationId == null
                    ? _buildEmptyState()
                    : messagesAsync.when(
                        data: (messages) =>
                            _buildMessageList(messages, sheetScrollController),
                        loading: () =>
                            const Center(child: CircularProgressIndicator()),
                        error: (e, _) => Center(child: Text('Error: $e')),
                      ),
              ),
              // Streaming response.
              if (streamingText != null) _buildStreamingBubble(streamingText),
              // Thinking / status indicator.
              if (isProcessing && streamingText == null)
                _ThinkingBubble(status: processingStatus),
              // Input bar — pad for keyboard inset since this lives in a
              // Stack and does not benefit from Scaffold resize.
              Padding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).viewInsets.bottom,
                ),
                child: ChatInput(onSend: _sendMessage, enabled: !isProcessing),
              ),
            ],
          ),
        );
      },
    );
  }

  /// The small drag handle pill at the top of the sheet.
  Widget _buildDragHandle() {
    return ExcludeSemantics(
      child: Padding(
        padding: const EdgeInsets.only(top: KabukTheme.spacingSm),
        child: Center(
          child: Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: KabukTheme.textSecondary.withAlpha(100),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      ),
    );
  }

  /// Header row with title and action buttons.
  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: KabukTheme.spacingMd,
        vertical: KabukTheme.spacingXs,
      ),
      child: Row(
        children: [
          const Icon(
            Icons.smart_toy_rounded,
            size: 18,
            color: KabukTheme.accentGreen,
          ),
          const SizedBox(width: KabukTheme.spacingSm),
          const Expanded(
            child: Text(
              'Kabuk AI',
              style: TextStyle(
                color: KabukTheme.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.open_in_full, size: 18),
            color: KabukTheme.textSecondary,
            tooltip: 'Open full chat',
            onPressed: () {
              // Dismiss sheet and navigate to conversation detail.
              ref.read(chatSheetVisibleProvider.notifier).state = false;
              ref.read(selectedTabProvider.notifier).state = 1;
              // Push the conversation detail if we have an active conversation.
              final nav = Navigator.of(context);
              WidgetsBinding.instance.addPostFrameCallback((_) {
                nav.push(
                  MaterialPageRoute<void>(
                    builder: (_) => const ConversationDetail(title: 'Kabuk AI'),
                  ),
                );
              });
            },
            visualDensity: VisualDensity.compact,
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            color: KabukTheme.textSecondary,
            tooltip: 'Close',
            onPressed: () {
              ref.read(chatSheetVisibleProvider.notifier).state = false;
            },
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  /// Placeholder when no conversation is active.
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.smart_toy_rounded,
            size: 48,
            color: KabukTheme.accentGreen.withAlpha(100),
          ),
          const SizedBox(height: KabukTheme.spacingSm),
          const Text(
            'Ask me anything',
            style: TextStyle(color: KabukTheme.textSecondary, fontSize: 14),
          ),
        ],
      ),
    );
  }

  /// Message list that scrolls with the sheet.
  Widget _buildMessageList(
    List<Message> messages,
    ScrollController sheetScrollController,
  ) {
    if (messages.isEmpty) return _buildEmptyState();

    // Combine both scroll controllers so the list scrolls
    // within the draggable sheet.
    return ListView.builder(
      controller: sheetScrollController,
      padding: const EdgeInsets.symmetric(
        horizontal: KabukTheme.spacingMd,
        vertical: KabukTheme.spacingSm,
      ),
      itemCount: messages.length,
      itemBuilder: (context, index) => MessageBubble(message: messages[index]),
    );
  }

  /// A temporary bubble showing streaming agent text.
  Widget _buildStreamingBubble(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: KabukTheme.spacingMd,
        vertical: KabukTheme.spacingXs,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: KabukTheme.primaryGreen.withAlpha(40),
            child: const Icon(
              Icons.smart_toy_outlined,
              size: 18,
              color: KabukTheme.accentGreen,
            ),
          ),
          const SizedBox(width: KabukTheme.spacingSm),
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: KabukTheme.spacingMd,
                vertical: KabukTheme.spacingSm + 2,
              ),
              decoration: BoxDecoration(
                color: KabukTheme.cardColor,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(KabukTheme.radiusMd),
                  topRight: Radius.circular(KabukTheme.radiusMd),
                  bottomLeft: Radius.circular(4),
                  bottomRight: Radius.circular(KabukTheme.radiusMd),
                ),
                border: Border.all(color: KabukTheme.divider, width: 0.5),
              ),
              child: Text(
                '$text▍',
                style: const TextStyle(
                  color: KabukTheme.textPrimary,
                  fontSize: 14,
                  height: 1.4,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Model readiness banners
// ---------------------------------------------------------------------------

/// Banner shown when a model is being auto-downloaded.
class _ModelDownloadBanner extends StatelessWidget {
  const _ModelDownloadBanner({required this.state});

  final ModelReadyState state;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: KabukTheme.primaryGreen.withAlpha(20),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: KabukTheme.spacingMd,
            vertical: KabukTheme.spacingSm,
          ),
          child: Row(
            children: [
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: KabukTheme.accentGreen,
                ),
              ),
              const SizedBox(width: KabukTheme.spacingSm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Downloading AI model${state.modelName != null ? ' (${state.modelName})' : ''}...',
                      style: const TextStyle(
                        color: KabukTheme.textPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: state.progress,
                        backgroundColor: KabukTheme.divider,
                        color: KabukTheme.accentGreen,
                        minHeight: 4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: KabukTheme.spacingSm),
              Text(
                '${(state.progress * 100).toStringAsFixed(0)}%',
                style: const TextStyle(
                  color: KabukTheme.textSecondary,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Banner shown when model download failed.
class _ModelUnavailableBanner extends StatelessWidget {
  const _ModelUnavailableBanner({this.error, required this.onRetry});

  final String? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: KabukTheme.error.withAlpha(20),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: KabukTheme.spacingMd,
            vertical: KabukTheme.spacingSm,
          ),
          child: Row(
            children: [
              const Icon(
                Icons.warning_amber_rounded,
                color: KabukTheme.error,
                size: 18,
              ),
              const SizedBox(width: KabukTheme.spacingSm),
              Expanded(
                child: Text(
                  error ?? 'AI model unavailable.',
                  style: const TextStyle(
                    color: KabukTheme.textPrimary,
                    fontSize: 12,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              TextButton(
                onPressed: onRetry,
                style: TextButton.styleFrom(
                  foregroundColor: KabukTheme.accentGreen,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  visualDensity: VisualDensity.compact,
                ),
                child: const Text('Retry', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Animated thinking indicator shown while the AI is processing.
///
/// Displays a pulsing dot and a status label (e.g. \"Thinking…\",
/// \"Using Create note…\") so the user knows the AI is working.
class _ThinkingBubble extends StatefulWidget {
  const _ThinkingBubble({this.status});

  /// Current processing status text. Falls back to \"Thinking…\".
  final String? status;

  @override
  State<_ThinkingBubble> createState() => _ThinkingBubbleState();
}

class _ThinkingBubbleState extends State<_ThinkingBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final label = widget.status ?? 'Thinking\u2026';
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: KabukTheme.spacingMd,
        vertical: KabukTheme.spacingSm,
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: KabukTheme.primaryGreen.withAlpha(40),
            child: const Icon(
              Icons.smart_toy_outlined,
              size: 16,
              color: KabukTheme.accentGreen,
            ),
          ),
          const SizedBox(width: KabukTheme.spacingSm),
          FadeTransition(
            opacity: _controller.drive(Tween(begin: 0.4, end: 1.0)),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: KabukTheme.surfaceVariant,
                borderRadius: BorderRadius.circular(KabukTheme.radiusMd),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: KabukTheme.accentGreen.withAlpha(180),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: const TextStyle(
                      color: KabukTheme.textSecondary,
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Developer mode info bar
// ---------------------------------------------------------------------------

/// A compact info bar shown at the top of the shell when developer mode is on.
///
/// Displays live runtime stats and tapping it opens [DevModePage].
class _DevInfoBar extends ConsumerWidget {
  const _DevInfoBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final modelReady = ref.watch(modelReadinessProvider);
    final costState = ref.watch(llmCostTrackerProvider);
    final nostr = ref.watch(nostrServiceProvider);
    final tab = ref.watch(selectedTabProvider);
    const tabNames = ['Explore', 'Chat', 'Vault', 'Apps'];
    final tabName = tab < tabNames.length ? tabNames[tab] : '?';

    return Material(
      color: KabukTheme.warmAccent.withAlpha(20),
      child: SafeArea(
        bottom: false,
        child: InkWell(
          onTap: () => Navigator.of(
            context,
          ).push(MaterialPageRoute<void>(builder: (_) => const DevModePage())),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            child: Row(
              children: [
                const Icon(
                  Icons.bug_report_rounded,
                  size: 12,
                  color: KabukTheme.warmAccent,
                ),
                const SizedBox(width: 6),
                const Text(
                  'DEV',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: KabukTheme.warmAccent,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(width: 8),
                _DevChip(label: tabName, color: KabukTheme.blueAccent),
                const SizedBox(width: 4),
                _DevChip(
                  label: modelReady.status.name,
                  color: switch (modelReady.status) {
                    ModelReadyStatus.ready => KabukTheme.success,
                    ModelReadyStatus.downloading => KabukTheme.accentGreen,
                    ModelReadyStatus.unavailable => KabukTheme.error,
                    _ => KabukTheme.textSecondary,
                  },
                ),
                const SizedBox(width: 4),
                _DevChip(
                  label:
                      '${costState.totalTokens}tok '
                      '\$${costState.totalEstimatedCostUsd.toStringAsFixed(3)}',
                  color: KabukTheme.accentGreen,
                ),
                const SizedBox(width: 4),
                _DevChip(
                  label:
                      '${nostr.connectedRelays.length}/${nostr.relays.length} relay',
                  color: KabukTheme.purpleAccent,
                ),
                const Spacer(),
                const Icon(
                  Icons.chevron_right,
                  size: 12,
                  color: KabukTheme.textTertiary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A small pill badge used in the [_DevInfoBar].
class _DevChip extends StatelessWidget {
  const _DevChip({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: color.withAlpha(25),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withAlpha(60), width: 0.5),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9,
          color: color,
          fontFamily: 'monospace',
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
