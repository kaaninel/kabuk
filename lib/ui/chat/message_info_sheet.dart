/// Message info bottom sheet — shows detailed metadata for a message.
///
/// Displays timestamps, delivery status, message role, metadata
/// (tool calls, widget data), and message ID.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kabuk/knowledge/database.dart';
import 'package:kabuk/ui/theme.dart';

/// A bottom sheet showing detailed information about a [Message].
class MessageInfoSheet extends StatelessWidget {
  /// Creates a [MessageInfoSheet] for the given [message].
  const MessageInfoSheet({required this.message, super.key});

  /// The message whose details are shown.
  final Message message;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          KabukTheme.spacingLg,
          KabukTheme.spacingSm,
          KabukTheme.spacingLg,
          KabukTheme.spacingLg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: KabukTheme.spacingMd),
                decoration: BoxDecoration(
                  color: context.kabukTextSecondary.withAlpha(100),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Title
            Text(
              'Message Info',
              style: TextStyle(
                color: context.kabukTextPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: KabukTheme.spacingMd),
            // Info rows
            _InfoRow(label: 'Role', value: _roleLabel(message.role)),
            if (message.agentName != null)
              _InfoRow(label: 'Agent', value: message.agentName!),
            _InfoRow(label: 'Sent', value: _formatDateTime(message.timestamp)),
            _InfoRow(label: 'Status', value: _statusLabel(message.status)),
            if (message.nostrEventId != null)
              _InfoRow(label: 'Nostr Event ID', value: message.nostrEventId!),
            if (message.replyToId != null)
              _InfoRow(label: 'Reply to', value: message.replyToId!),
            if (message.isPinned) const _InfoRow(label: 'Pinned', value: 'Yes'),
            if (message.expiresAt != null)
              _InfoRow(
                label: 'Expires',
                value: _formatDateTime(message.expiresAt!),
              ),
            if (message.metadata != null) ...[
              const SizedBox(height: KabukTheme.spacingSm),
              _MetadataSection(metadata: message.metadata!),
            ],
            Divider(color: context.kabukDivider, height: 24),
            // Message ID (compact, copyable)
            InkWell(
              borderRadius: BorderRadius.circular(KabukTheme.radiusSm),
              onTap: () {
                Clipboard.setData(ClipboardData(text: message.id));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Message ID copied'),
                    duration: Duration(seconds: 1),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: KabukTheme.spacingXs,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.fingerprint,
                      size: 14,
                      color: context.kabukTextTertiary,
                    ),
                    const SizedBox(width: KabukTheme.spacingSm),
                    Expanded(
                      child: Text(
                        message.id,
                        style: TextStyle(
                          color: context.kabukTextTertiary,
                          fontSize: 11,
                          fontFamily: 'monospace',
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Icon(
                      Icons.copy,
                      size: 12,
                      color: context.kabukTextTertiary,
                    ),
                  ],
                ),
              ),
            ),
            // Content preview
            const SizedBox(height: KabukTheme.spacingSm),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(KabukTheme.spacingSm),
              decoration: BoxDecoration(
                color: context.kabukSurfaceVariant,
                borderRadius: BorderRadius.circular(KabukTheme.radiusSm),
              ),
              child: Text(
                message.content.length > 300
                    ? '${message.content.substring(0, 300)}…'
                    : message.content,
                style: TextStyle(
                  color: context.kabukTextSecondary,
                  fontSize: 12,
                  height: 1.4,
                ),
                maxLines: 8,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _roleLabel(String role) => switch (role) {
    'user' => 'You',
    'agent' => 'AI Agent',
    'system' => 'System',
    'tool_call' => 'Tool Call',
    'tool_result' => 'Tool Result',
    _ => role,
  };

  static String _statusLabel(String status) {
    if (status.startsWith('delivered')) {
      final parts = status.split(':');
      if (parts.length > 1) return 'Delivered to ${parts[1]} relays';
      return 'Delivered';
    }
    return switch (status) {
      'sending' => 'Sending…',
      'sent' => 'Sent',
      'failed' => 'Failed',
      _ => status,
    };
  }

  static String _formatDateTime(DateTime dt) {
    final d = dt.toLocal();
    return '${d.year}-${_pad(d.month)}-${_pad(d.day)} '
        '${_pad(d.hour)}:${_pad(d.minute)}:${_pad(d.second)}';
  }

  static String _pad(int n) => n.toString().padLeft(2, '0');
}

/// A single label–value row.
class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(
                color: context.kabukTextSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: context.kabukTextPrimary,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Collapsible metadata section showing parsed JSON.
class _MetadataSection extends StatefulWidget {
  const _MetadataSection({required this.metadata});

  final String metadata;

  @override
  State<_MetadataSection> createState() => _MetadataSectionState();
}

class _MetadataSectionState extends State<_MetadataSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    Map<String, dynamic>? parsed;
    try {
      parsed = json.decode(widget.metadata) as Map<String, dynamic>;
    } on FormatException catch (_) {
      // Not valid JSON — skip.
    }

    if (parsed == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          borderRadius: BorderRadius.circular(KabukTheme.radiusSm),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Icon(
                  _expanded
                      ? Icons.keyboard_arrow_down
                      : Icons.keyboard_arrow_right,
                  size: 18,
                  color: context.kabukTextSecondary,
                ),
                const SizedBox(width: 4),
                Text(
                  'Metadata',
                  style: TextStyle(
                    color: context.kabukTextSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_expanded)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(top: 4),
            padding: const EdgeInsets.all(KabukTheme.spacingSm),
            decoration: BoxDecoration(
              color: context.kabukSurfaceVariant,
              borderRadius: BorderRadius.circular(KabukTheme.radiusSm),
            ),
            child: SelectableText(
              const JsonEncoder.withIndent('  ').convert(parsed),
              style: TextStyle(
                color: context.kabukTextSecondary,
                fontSize: 11,
                fontFamily: 'monospace',
                height: 1.4,
              ),
            ),
          ),
      ],
    );
  }
}
