/// Agent trace export & replay — review conversations and export them as
/// finetuning data.
///
/// Replays stored agent conversations read-only (user, agent, tool calls,
/// tool results) and exports them to ShareGPT/OpenAI-format JSONL in the
/// app's `traces/` directory. These traces are the training data for
/// improving the on-device MiniCPM5 1B model over time.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kabuk/config/providers.dart';
import 'package:kabuk/knowledge/database.dart';
import 'package:kabuk/services/trace_exporter.dart';
import 'package:kabuk/ui/theme.dart';

/// Lists agent conversations and offers export/replay.
class TraceExportPage extends ConsumerStatefulWidget {
  /// Creates a [TraceExportPage].
  const TraceExportPage({super.key});

  @override
  ConsumerState<TraceExportPage> createState() => _TraceExportPageState();
}

class _TraceExportPageState extends ConsumerState<TraceExportPage> {
  List<Conversation> _conversations = [];
  bool _loading = true;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = ref.read(databaseProvider);
    final all = await db.listConversations();
    if (!mounted) return;
    setState(() {
      _conversations = all
          .where((c) => c.type == 'agent')
          .toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      _loading = false;
    });
  }

  Future<void> _exportAll() async {
    setState(() => _exporting = true);
    try {
      final exporter = TraceExporter(db: ref.read(databaseProvider));
      final content = await exporter.exportAll();
      if (content.trim().isEmpty) {
        _showMessage('No agent conversations to export yet.');
        return;
      }
      final file = await exporter.writeTrace(
        content,
        'traces-${DateTime.now().toIso8601String().replaceAll(':', '-')}.jsonl',
      );
      if (!mounted) return;
      await _showExportResult(file, content);
    } on Object catch (e) {
      if (!mounted) return;
      _showMessage('Export failed: $e');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _showExportResult(File file, String content) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Trace exported'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Saved to:\n${file.path}',
              style: TextStyle(
                color: context.kabukTextSecondary,
                fontSize: 12,
                height: 1.4,
              ),
            ),
            const SizedBox(height: KabukTheme.spacingSm),
            Text(
              '${content.trim().split('\n').length} conversation sample(s). '
              'Format: ShareGPT JSONL (one {"messages": [...]} per line) — '
              'ready for axolotl/OpenAI finetuning.',
              style: TextStyle(
                color: context.kabukTextSecondary,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
          FilledButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: content));
              if (ctx.mounted) Navigator.pop(ctx);
              _showMessage('Copied JSONL to clipboard.');
            },
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('Copy'),
            style: FilledButton.styleFrom(
              backgroundColor: KabukTheme.primaryGreen,
            ),
          ),
        ],
      ),
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Agent Traces'),
        actions: [
          IconButton(
            tooltip: 'Export all to JSONL',
            onPressed: _exporting ? null : _exportAll,
            icon: _exporting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(KabukTheme.spacingMd),
              children: [
                Container(
                  padding: const EdgeInsets.all(KabukTheme.spacingMd),
                  decoration: BoxDecoration(
                    color: KabukTheme.primaryGreen.withAlpha(15),
                    borderRadius: BorderRadius.circular(KabukTheme.radiusMd),
                    border: Border.all(
                      color: KabukTheme.accentGreen.withAlpha(40),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.science_outlined,
                        size: 16,
                        color: KabukTheme.accentGreen,
                      ),
                      const SizedBox(width: KabukTheme.spacingSm),
                      Expanded(
                        child: Text(
                          'Replay conversations and export them as '
                          'ShareGPT JSONL traces. Feed the traces into a '
                          'larger model to distill answers, then finetune '
                          'the on-device MiniCPM5 1B from the results.',
                          style: TextStyle(
                            fontSize: 12,
                            color: context.kabukTextSecondary,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: KabukTheme.spacingLg),
                if (_conversations.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(KabukTheme.spacingLg),
                    child: Center(
                      child: Text(
                        'No agent conversations yet. Chat with Kabuk AI '
                        'to start generating traces.',
                        style: TextStyle(
                          color: context.kabukTextSecondary,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  )
                else
                  ..._conversations.map(
                    (conv) => Padding(
                      padding: const EdgeInsets.only(bottom: KabukTheme.spacingSm),
                      child: Material(
                        color: context.kabukSurfaceVariant,
                        borderRadius: BorderRadius.circular(KabukTheme.radiusMd),
                        child: ListTile(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              KabukTheme.radiusMd,
                            ),
                          ),
                          leading: const Icon(
                            Icons.forum_outlined,
                            color: KabukTheme.accentGreen,
                          ),
                          title: Text(
                            conv.title.isEmpty ? 'Untitled' : conv.title,
                            style: TextStyle(
                              color: context.kabukTextPrimary,
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            'Agent · ${_formatDate(conv.updatedAt)}',
                            style: TextStyle(
                              color: context.kabukTextSecondary,
                              fontSize: 12,
                            ),
                          ),
                          trailing: Icon(
                            Icons.play_circle_outline_rounded,
                            color: context.kabukTextSecondary,
                            size: 24,
                          ),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => TraceConversationPage(
                                conversation: conv,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 60),
              ],
            ),
    );
  }

  static String _formatDate(DateTime dt) {
    final local = dt.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')} '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }
}

/// Read-only replay of a single conversation, with per-conversation export.
class TraceConversationPage extends ConsumerStatefulWidget {
  /// Creates a [TraceConversationPage].
  const TraceConversationPage({required this.conversation, super.key});

  /// The conversation to replay.
  final Conversation conversation;

  @override
  ConsumerState<TraceConversationPage> createState() =>
      _TraceConversationPageState();
}

class _TraceConversationPageState extends ConsumerState<TraceConversationPage> {
  List<Message> _messages = [];
  bool _loading = true;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = ref.read(databaseProvider);
    final messages = await db.getMessages(widget.conversation.id);
    if (!mounted) return;
    setState(() {
      _messages = messages;
      _loading = false;
    });
  }

  Future<void> _export() async {
    setState(() => _exporting = true);
    try {
      final exporter = TraceExporter(db: ref.read(databaseProvider));
      final line = await exporter.exportConversation(widget.conversation.id);
      if (line == null) {
        _showMessage('Nothing to export in this conversation.');
        return;
      }
      final file = await exporter.writeTrace(
        '$line\n',
        'trace-${widget.conversation.id.substring(0, 8)}.jsonl',
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Trace exported'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Saved to:\n${file.path}',
                style: TextStyle(
                  color: context.kabukTextSecondary,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: KabukTheme.spacingSm),
              Container(
                padding: const EdgeInsets.all(KabukTheme.spacingSm),
                decoration: BoxDecoration(
                  color: context.kabukSurfaceVariant,
                  borderRadius: BorderRadius.circular(KabukTheme.radiusSm),
                ),
                child: Text(
                  line.length > 1200 ? '${line.substring(0, 1200)}…' : line,
                  style: const TextStyle(
                    fontSize: 10,
                    fontFamily: 'monospace',
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'),
            ),
            FilledButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: '$line\n'));
                if (ctx.mounted) Navigator.pop(ctx);
                _showMessage('Copied trace to clipboard.');
              },
              icon: const Icon(Icons.copy, size: 16),
              label: const Text('Copy'),
              style: FilledButton.styleFrom(
                backgroundColor: KabukTheme.primaryGreen,
              ),
            ),
          ],
        ),
      );
    } on Object catch (e) {
      if (!mounted) return;
      _showMessage('Export failed: $e');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.conversation.title.isEmpty
              ? 'Replay'
              : widget.conversation.title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        actions: [
          IconButton(
            tooltip: 'Export trace',
            onPressed: _exporting ? null : _export,
            icon: _exporting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              padding: const EdgeInsets.all(KabukTheme.spacingMd),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final m = _messages[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: KabukTheme.spacingSm),
                  child: _TraceMessageTile(message: m),
                );
              },
            ),
    );
  }
}

/// A single replayable trace message.
class _TraceMessageTile extends StatelessWidget {
  const _TraceMessageTile({required this.message});

  final Message message;

  @override
  Widget build(BuildContext context) {
    final (label, color, icon) = switch (message.role) {
      'user' => ('user', KabukTheme.blueAccent, Icons.person_outline),
      'agent' => (
        message.agentName ?? 'agent',
        KabukTheme.accentGreen,
        Icons.smart_toy_outlined,
      ),
      'system' => ('system', context.kabukTextTertiary, Icons.info_outline),
      'tool_call' => (
        'tool call${message.agentName != null ? ' · ${message.agentName}' : ''}',
        KabukTheme.warmAccent,
        Icons.build_outlined,
      ),
      'tool_result' => (
        'tool result',
        context.kabukTextTertiary,
        Icons.output_rounded,
      ),
      _ => (message.role, context.kabukTextTertiary, Icons.circle_outlined),
    };

    return Container(
      padding: const EdgeInsets.all(KabukTheme.spacingSm),
      decoration: BoxDecoration(
        color: context.kabukSurfaceVariant,
        borderRadius: BorderRadius.circular(KabukTheme.radiusMd),
        border: Border.all(color: context.kabukDivider.withAlpha(60)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3,
                ),
              ),
              const Spacer(),
              Text(
                _time(message.timestamp),
                style: TextStyle(
                  color: context.kabukTextTertiary,
                  fontSize: 10,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            message.content.isEmpty ? '(empty)' : message.content,
            style: TextStyle(
              color: context.kabukTextPrimary,
              fontSize: 13,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  static String _time(DateTime dt) {
    final local = dt.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}:'
        '${local.second.toString().padLeft(2, '0')}';
  }
}