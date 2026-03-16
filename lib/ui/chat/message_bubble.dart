/// Message bubble widget — renders a single chat message.
///
/// Displays user messages right-aligned and agent/system messages
/// left-aligned, with appropriate styling for each role.
/// Agent messages whose [Message.metadata] contains RFW widget data
/// are rendered as live Remote Flutter Widgets inline in the chat.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kabuk/config/providers.dart';
import 'package:kabuk/knowledge/database.dart';
import 'package:kabuk/ui/chat/chat_service.dart';
import 'package:kabuk/ui/shared/kabuk_markdown.dart';
import 'package:kabuk/ui/theme.dart';

/// A chat message bubble.
///
/// Renders a [Message] from the Drift database as a styled bubble.
/// User messages are right-aligned with a primary color tint.
/// Agent and system messages are left-aligned on a surface background.
///
/// When [Message.metadata] contains RFW widget data (JSON with
/// `type` equal to `"widget"` or `"raw_widget"`), the bubble renders
/// the corresponding Remote Flutter Widget inline via `KabukRfwRuntime`.
///
/// Uses [ConsumerStatefulWidget] to cache RFW render futures, avoiding
/// re-creation on every rebuild (which causes flicker and memory leaks).
class MessageBubble extends ConsumerStatefulWidget {
  /// Creates a [MessageBubble] for the given [message].
  const MessageBubble({required this.message, this.onTapInfo, super.key});

  /// The database message to render.
  final Message message;

  /// Called when the user selects "Info" from the context menu.
  final VoidCallback? onTapInfo;

  @override
  ConsumerState<MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends ConsumerState<MessageBubble> {
  /// Cached RFW widget render future. Computed once in [initState]
  /// and only recomputed if the message changes.
  Future<Widget>? _rfwWidgetFuture;

  /// The metadata string last used to create [_rfwWidgetFuture].
  String? _lastMetadata;

  Message get message => widget.message;
  bool get _isUser => message.role == 'user';
  bool get _isToolMessage =>
      message.role == 'tool_call' || message.role == 'tool_result';

  @override
  void initState() {
    super.initState();
    _maybeCreateRfwFuture();
  }

  @override
  void didUpdateWidget(covariant MessageBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only rebuild the RFW future if the metadata actually changed.
    if (oldWidget.message.metadata != widget.message.metadata) {
      _maybeCreateRfwFuture();
    }
  }

  void _maybeCreateRfwFuture() {
    final meta = _parseWidgetMetadata();
    if (meta == null) {
      _rfwWidgetFuture = null;
      _lastMetadata = null;
      return;
    }
    // Avoid recreating the future if metadata hasn't changed.
    if (message.metadata == _lastMetadata && _rfwWidgetFuture != null) return;
    _lastMetadata = message.metadata;
    _rfwWidgetFuture = _createRfwFuture(meta);
  }

  @override
  Widget build(BuildContext context) {
    // Tool messages get compact inline rendering without a full bubble.
    if (_isToolMessage) {
      return _buildToolIndicator(context);
    }

    return GestureDetector(
      excludeFromSemantics: true,
      onLongPressStart: (details) =>
          _showMessageActions(context, details.globalPosition),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: KabukTheme.spacingXs),
        child: Row(
          mainAxisAlignment: _isUser
              ? MainAxisAlignment.end
              : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!_isUser) ...[
              _buildAvatar(context),
              const SizedBox(width: KabukTheme.spacingSm),
            ],
            Flexible(child: _buildBubble(context)),
            if (_isUser) ...[const SizedBox(width: KabukTheme.spacingSm)],
          ],
        ),
      ),
    );
  }

  /// Shows context menu with message actions on long press.
  void _showMessageActions(BuildContext context, Offset position) {
    final items = <PopupMenuEntry<String>>[
      const PopupMenuItem(
        value: 'copy',
        child: ListTile(
          leading: Icon(Icons.copy, size: 20),
          title: Text('Copy text'),
          dense: true,
          contentPadding: EdgeInsets.zero,
        ),
      ),
      const PopupMenuItem(
        value: 'info',
        child: ListTile(
          leading: Icon(Icons.info_outline, size: 20),
          title: Text('Message info'),
          dense: true,
          contentPadding: EdgeInsets.zero,
        ),
      ),
      const PopupMenuItem(
        value: 'delete',
        child: ListTile(
          leading: Icon(
            Icons.delete_outline,
            size: 20,
            color: KabukTheme.error,
          ),
          title: Text(
            'Delete message',
            style: TextStyle(color: KabukTheme.error),
          ),
          dense: true,
          contentPadding: EdgeInsets.zero,
        ),
      ),
    ];

    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      items: items,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(KabukTheme.radiusMd),
      ),
      color: KabukTheme.surfaceVariant,
    ).then((value) {
      if (value == null || !context.mounted) return;
      switch (value) {
        case 'copy':
          Clipboard.setData(ClipboardData(text: message.content));
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Copied to clipboard'),
              duration: Duration(seconds: 1),
              behavior: SnackBarBehavior.floating,
            ),
          );
        case 'info':
          widget.onTapInfo?.call();
        case 'delete':
          ref.read(chatServiceProvider).deleteMessage(message.id);
      }
    }).ignore();
  }

  Widget _buildAvatar(BuildContext context) {
    final icon = switch (message.role) {
      'agent' => Icons.smart_toy_outlined,
      'system' => Icons.info_outline,
      'tool_call' => Icons.build_outlined,
      'tool_result' => Icons.check_circle_outline,
      _ => Icons.help_outline,
    };

    return CircleAvatar(
      radius: 16,
      backgroundColor: KabukTheme.primaryGreen.withAlpha(40),
      child: Icon(icon, size: 18, color: KabukTheme.accentGreen),
    );
  }

  Widget _buildBubble(BuildContext context) {
    final maxWidth = MediaQuery.of(context).size.width * 0.75;

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: KabukTheme.spacingMd,
          vertical: KabukTheme.spacingSm + 2,
        ),
        decoration: BoxDecoration(
          color: _isUser
              ? KabukTheme.primaryGreen.withAlpha(30)
              : KabukTheme.cardColor,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(KabukTheme.radiusMd),
            topRight: const Radius.circular(KabukTheme.radiusMd),
            bottomLeft: Radius.circular(_isUser ? KabukTheme.radiusMd : 4),
            bottomRight: Radius.circular(_isUser ? 4 : KabukTheme.radiusMd),
          ),
          border: Border.all(
            color: _isUser
                ? KabukTheme.primaryGreen.withAlpha(60)
                : KabukTheme.divider,
            width: 0.5,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Agent name label for non-user messages — always show
            // a friendly name instead of internal identifiers.
            if (!_isUser && message.agentName != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  _friendlyAgentName(message.agentName!),
                  style: const TextStyle(
                    color: KabukTheme.accentGreen,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            // Message content — rendered as an RFW widget when metadata
            // is present, otherwise as plain text / markdown.
            _buildContent(context),
            // Timestamp + delivery status.
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _formatTime(message.timestamp),
                  style: TextStyle(
                    color: KabukTheme.textSecondary.withAlpha(128),
                    fontSize: 11,
                  ),
                ),
                if (_isUser && message.status == 'sending') ...[
                  const SizedBox(width: 4),
                  SizedBox(
                    width: 10,
                    height: 10,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: KabukTheme.textSecondary.withAlpha(128),
                    ),
                  ),
                ] else if (_isUser && message.status == 'sent') ...[
                  const SizedBox(width: 4),
                  Icon(
                    Icons.check,
                    size: 12,
                    color: KabukTheme.textSecondary.withAlpha(128),
                  ),
                ] else if (_isUser &&
                    message.status.startsWith('delivered')) ...[
                  const SizedBox(width: 4),
                  const Icon(
                    Icons.done_all,
                    size: 12,
                    color: KabukTheme.accentGreen,
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Build a compact inline indicator for tool_call / tool_result messages.
  ///
  /// These are visually distinct from regular bubbles — smaller, with a
  /// colored left border and an icon denoting the tool operation.
  Widget _buildToolIndicator(BuildContext context) {
    final isCall = message.role == 'tool_call';
    final meta = _parseToolMetadata();
    final toolName = meta?['tool'] as String? ?? 'unknown';
    final isSuccess = meta?['success'] as bool? ?? true;

    final icon = isCall
        ? Icons.build_outlined
        : isSuccess
        ? Icons.check_circle_outline
        : Icons.error_outline;
    final accentColor = isCall
        ? KabukTheme.accentGreen
        : isSuccess
        ? KabukTheme.accentGreen
        : KabukTheme.error;

    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: 2,
        horizontal: KabukTheme.spacingMd,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(width: 36), // align with agent bubble content
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: KabukTheme.spacingSm + 2,
                vertical: KabukTheme.spacingXs + 2,
              ),
              decoration: BoxDecoration(
                color: KabukTheme.surfaceVariant,
                borderRadius: BorderRadius.circular(KabukTheme.radiusSm),
                border: Border(left: BorderSide(color: accentColor, width: 2)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 14, color: accentColor),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: toolName,
                            style: TextStyle(
                              color: accentColor,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (!isCall && message.content.isNotEmpty) ...[
                            const TextSpan(text: '  '),
                            TextSpan(
                              text: _sanitizeToolResult(message.content),
                              style: const TextStyle(
                                color: KabukTheme.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                          ],
                          if (isCall) ...[
                            const TextSpan(text: '  '),
                            TextSpan(
                              text: _formatToolArgs(meta?['args']),
                              style: const TextStyle(
                                color: KabukTheme.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ],
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
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

  /// Parse tool-specific metadata from [Message.metadata].
  ///
  /// Returns a map with `tool`, and either `args` (for tool_call) or
  /// `success` (for tool_result), or `null` if not parseable.
  Map<String, dynamic>? _parseToolMetadata() {
    if (message.metadata == null) return null;
    try {
      return json.decode(message.metadata!) as Map<String, dynamic>;
    } on FormatException catch (_) {
      return null;
    }
  }

  /// Sanitize tool result content for display.
  ///
  /// Strips raw URIs (e.g. `kabuk:…`, `schema:…`, `urn:…`) and
  /// long JSON blobs that users don't need to see.
  String _sanitizeToolResult(String content) {
    // Strip known internal URI patterns.
    final sanitized = content
        .replaceAll(RegExp(r'(?:kabuk|schema|urn|rdf):\S+'), '')
        .replaceAll(RegExp(r'https?://schema\.org/\S*'), '')
        .replaceAll(RegExp(r'\s{2,}'), ' ')
        .trim();
    // If it looks like raw JSON, show a simple summary.
    if (sanitized.startsWith('{') || sanitized.startsWith('[')) {
      return 'Done';
    }
    return sanitized.isEmpty ? 'Done' : sanitized;
  }

  /// Format tool arguments for display as a compact summary.
  String _formatToolArgs(dynamic args) {
    if (args == null) return '';
    if (args is Map) {
      final pairs = args.entries
          .take(3)
          .map((e) {
            final v = e.value is String
                ? (e.value as String).length > 30
                      ? '${(e.value as String).substring(0, 30)}…'
                      : e.value
                : e.value;
            return '${e.key}: $v';
          })
          .join(', ');
      return args.length > 3 ? '$pairs, …' : pairs;
    }
    return args.toString();
  }

  /// Build the main content area of the bubble.
  ///
  /// All messages are rendered as markdown. Agent messages are additionally
  /// checked for RFW widget metadata — if present the dynamic widget
  /// is rendered inline alongside the markdown content.
  Widget _buildContent(BuildContext context) {
    // Use cached RFW future when available (non-user messages with widget metadata).
    if (!_isUser && _rfwWidgetFuture != null) {
      return _buildRfwWidget(context);
    }

    // Sanitize agent/system messages to remove internal URI noise.
    final content =
        _isUser ? message.content : _sanitizeMessageContent(message.content);
    return KabukMarkdown(data: content);
  }

  /// Maps internal agent names to user-friendly display names.
  static String _friendlyAgentName(String internalName) {
    return switch (internalName) {
      'router' => 'Kabuk AI',
      'notes' => 'Notes Assistant',
      'contacts' => 'Contacts Assistant',
      'calendar' => 'Calendar Assistant',
      'file' => 'Files Assistant',
      'search' => 'Search',
      'feed' => 'Feed Assistant',
      'discovery' => 'Discovery',
      'identity' => 'Identity',
      'messaging' => 'Messaging',
      'system' => 'Kabuk',
      _ => 'Kabuk AI',
    };
  }

  /// Removes internal kabuk/schema URIs from agent message content.
  ///
  /// Strips patterns like `kabuk:FeedSubscription/uuid` and standalone
  /// `schema:TypeName` tokens so they are not visible to the user.
  static String _sanitizeMessageContent(String content) {
    return content
        .replaceAll(RegExp(r'kabuk:[A-Za-z]+/[a-f0-9\-]+'), '')
        .replaceAll(RegExp(r'\bschema:[A-Za-z]+\b'), '')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .replaceAll(RegExp(r'  +'), ' ')
        .trim();
  }

  /// Attempt to parse RFW widget metadata from [Message.metadata].
  ///
  /// Returns the decoded JSON map when the metadata encodes a widget
  /// (`type` is `"widget"` or `"raw_widget"`), or `null` otherwise.
  Map<String, dynamic>? _parseWidgetMetadata() {
    if (message.metadata == null) return null;
    try {
      final meta = json.decode(message.metadata!) as Map<String, dynamic>;
      final type = meta['type'];
      if (type == 'widget' || type == 'raw_widget') {
        return meta;
      }
    } on FormatException catch (_) {
      // metadata is not valid JSON — ignore.
    }
    return null;
  }

  /// Creates the RFW render future from decoded widget metadata.
  ///
  /// Called once in [initState] or [didUpdateWidget] and cached in
  /// [_rfwWidgetFuture] to avoid re-creation on every rebuild.
  Future<Widget> _createRfwFuture(Map<String, dynamic> meta) async {
    try {
      final runtime = ref.read(rfwRuntimeProvider);

      if (meta['type'] == 'widget') {
        return await runtime.renderWidget(
          libraryName: meta['library'] as String,
          widgetName: meta['widget'] as String,
          bindings: (meta['bindings'] as Map<String, dynamic>?) ?? const {},
        );
      }

      // Validate raw RFW templates before rendering.
      final source = meta['source'] as String;
      final validationError = runtime.validate(source);
      if (validationError != null) {
        return Container(
          padding: const EdgeInsets.all(KabukTheme.spacingSm),
          decoration: BoxDecoration(
            color: KabukTheme.error.withAlpha(20),
            borderRadius: BorderRadius.circular(KabukTheme.radiusSm),
          ),
          child: Text(
            'Invalid RFW template: $validationError',
            style: const TextStyle(color: KabukTheme.error, fontSize: 12),
          ),
        );
      }

      return await runtime.renderRaw(
        source: source,
        data: (meta['data'] as Map<String, dynamic>?) ?? const {},
      );
    } on Object {
      // Fallback to plain text rendering if RFW fails unexpectedly.
      return KabukMarkdown(data: message.content);
    }
  }

  /// Build an RFW widget using the cached [_rfwWidgetFuture].
  ///
  /// If `message.content` is non-empty, the text is shown above the
  /// dynamic widget as markdown so both contextual text and the rich
  /// widget are visible.
  Widget _buildRfwWidget(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Show markdown content alongside the widget when present.
        if (message.content.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: KabukTheme.spacingSm),
            child: _buildMarkdown(context),
          ),
        // Render the RFW widget using the cached future.
        FutureBuilder<Widget>(
          future: _rfwWidgetFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const SizedBox(
                height: 48,
                child: Center(
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: KabukTheme.accentGreen,
                  ),
                ),
              );
            }
            if (snapshot.hasError) {
              return Container(
                padding: const EdgeInsets.all(KabukTheme.spacingSm),
                decoration: BoxDecoration(
                  color: KabukTheme.error.withAlpha(20),
                  borderRadius: BorderRadius.circular(KabukTheme.radiusSm),
                  border: Border.all(color: KabukTheme.error.withAlpha(80)),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.error_outline,
                      color: KabukTheme.error,
                      size: 18,
                    ),
                    const SizedBox(width: KabukTheme.spacingSm),
                    Expanded(
                      child: Text(
                        'Widget error: ${snapshot.error}',
                        style: const TextStyle(
                          color: KabukTheme.error,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }
            return snapshot.data ?? const SizedBox.shrink();
          },
        ),
      ],
    );
  }

  /// Build the default markdown content widget.
  Widget _buildMarkdown(BuildContext context) {
    final content =
        _isUser ? message.content : _sanitizeMessageContent(message.content);
    return KabukMarkdown(data: content);
  }

  /// Format a [DateTime] to `HH:mm`.
  String _formatTime(DateTime time) {
    final h = time.hour.toString().padLeft(2, '0');
    final m = time.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}
