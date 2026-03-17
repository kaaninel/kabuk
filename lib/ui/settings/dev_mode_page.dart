/// Developer mode tools page.
///
/// Provides internal inspection views only visible when developer mode
/// is enabled. Three tabs: Knowledge Store inspector, Provider snapshot,
/// and LLM cost log.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kabuk/agents/cost_tracker.dart';
import 'package:kabuk/config/providers.dart';
import 'package:kabuk/knowledge/triple.dart';
import 'package:kabuk/ui/theme.dart';

/// The developer tools page — shows knowledge store, provider state, and LLM costs.
class DevModePage extends ConsumerStatefulWidget {
  /// Creates a [DevModePage].
  const DevModePage({super.key});

  @override
  ConsumerState<DevModePage> createState() => _DevModePageState();
}

class _DevModePageState extends ConsumerState<DevModePage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              margin: const EdgeInsets.only(right: 8),
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: KabukTheme.warmAccent,
              ),
            ),
            const Text('Developer Tools'),
          ],
        ),
        bottom: TabBar(
          controller: _tabs,
          labelColor: KabukTheme.accentGreen,
          unselectedLabelColor: KabukTheme.textSecondary,
          indicatorColor: KabukTheme.accentGreen,
          tabs: const [
            Tab(icon: Icon(Icons.dns_rounded), text: 'Store'),
            Tab(icon: Icon(Icons.memory_rounded), text: 'Providers'),
            Tab(icon: Icon(Icons.attach_money_rounded), text: 'LLM'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: const [_KnowledgeStoreTab(), _ProvidersTab(), _LlmCostTab()],
      ),
    );
  }
}

// =============================================================================
// Knowledge Store Inspector
// =============================================================================

class _KnowledgeStoreTab extends ConsumerStatefulWidget {
  const _KnowledgeStoreTab();

  @override
  ConsumerState<_KnowledgeStoreTab> createState() => _KnowledgeStoreTabState();
}

class _KnowledgeStoreTabState extends ConsumerState<_KnowledgeStoreTab> {
  final _subjectController = TextEditingController();
  final _predicateController = TextEditingController();
  final _objectController = TextEditingController();
  List<Triple>? _results;
  bool _loading = false;
  String? _error;
  int _totalCount = 0;
  static const _pageSize = 50;

  @override
  void dispose() {
    _subjectController.dispose();
    _predicateController.dispose();
    _objectController.dispose();
    super.dispose();
  }

  Future<void> _query() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final store = ref.read(knowledgeStoreProvider);
      final sub = _subjectController.text.trim().isEmpty
          ? null
          : _subjectController.text.trim();
      final pred = _predicateController.text.trim().isEmpty
          ? null
          : _predicateController.text.trim();
      final obj = _objectController.text.trim().isEmpty
          ? null
          : _objectController.text.trim();

      // Use raw watch/query to count then paginate.
      final results = await store
          .query()
          .also((b) {
            if (sub != null) b.subject(sub);
            if (pred != null) b.predicate(pred);
            if (obj != null) b.object(obj);
          })
          .limit(_pageSize)
          .execute();

      // Count total without limit.
      final all = await store.query().also((b) {
        if (sub != null) b.subject(sub);
        if (pred != null) b.predicate(pred);
        if (obj != null) b.object(obj);
      }).execute();

      setState(() {
        _results = results;
        _totalCount = all.length;
        _loading = false;
      });
    } on Object catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _FilterPanel(
          subjectCtl: _subjectController,
          predicateCtl: _predicateController,
          objectCtl: _objectController,
          onSearch: _query,
          loading: _loading,
        ),
        if (_error != null)
          _ErrorBanner(message: _error!)
        else if (_results != null)
          _ResultHeader(shown: _results!.length, total: _totalCount),
        if (_results != null)
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _TripleList(triples: _results!),
          )
        else
          const Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.dns_outlined,
                    size: 48,
                    color: KabukTheme.textTertiary,
                  ),
                  SizedBox(height: KabukTheme.spacingSm),
                  Text(
                    'Enter filters and tap Search\nto inspect triples.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: KabukTheme.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _FilterPanel extends StatelessWidget {
  const _FilterPanel({
    required this.subjectCtl,
    required this.predicateCtl,
    required this.objectCtl,
    required this.onSearch,
    required this.loading,
  });

  final TextEditingController subjectCtl;
  final TextEditingController predicateCtl;
  final TextEditingController objectCtl;
  final VoidCallback onSearch;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: KabukTheme.surfaceElevated,
      padding: const EdgeInsets.all(KabukTheme.spacingSm),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _MonoField(controller: subjectCtl, label: 'Subject'),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _MonoField(controller: predicateCtl, label: 'Predicate'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: _MonoField(controller: objectCtl, label: 'Object'),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: loading ? null : onSearch,
                icon: loading
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.search, size: 16),
                label: const Text('Search'),
                style: FilledButton.styleFrom(
                  backgroundColor: KabukTheme.accentGreen,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 14,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MonoField extends StatelessWidget {
  const _MonoField({required this.controller, required this.label});
  final TextEditingController controller;
  final String label;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      style: const TextStyle(
        fontFamily: 'monospace',
        fontSize: 11,
        color: KabukTheme.textPrimary,
      ),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(
          fontSize: 11,
          color: KabukTheme.textSecondary,
        ),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        filled: true,
        fillColor: KabukTheme.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(KabukTheme.radiusSm),
          borderSide: const BorderSide(color: KabukTheme.divider),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(KabukTheme.radiusSm),
          borderSide: const BorderSide(color: KabukTheme.divider),
        ),
      ),
    );
  }
}

class _ResultHeader extends StatelessWidget {
  const _ResultHeader({required this.shown, required this.total});
  final int shown;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: KabukTheme.surface,
      padding: const EdgeInsets.symmetric(
        horizontal: KabukTheme.spacingMd,
        vertical: 6,
      ),
      child: Text(
        'Showing $shown of $total triples',
        style: const TextStyle(
          fontSize: 11,
          color: KabukTheme.textSecondary,
          fontFamily: 'monospace',
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: KabukTheme.error.withAlpha(30),
      padding: const EdgeInsets.all(KabukTheme.spacingSm),
      child: Text(
        message,
        style: const TextStyle(
          fontSize: 11,
          color: KabukTheme.error,
          fontFamily: 'monospace',
        ),
      ),
    );
  }
}

class _TripleList extends StatelessWidget {
  const _TripleList({required this.triples});
  final List<Triple> triples;

  @override
  Widget build(BuildContext context) {
    if (triples.isEmpty) {
      return const Center(
        child: Text(
          'No triples match the filter.',
          style: TextStyle(color: KabukTheme.textSecondary, fontSize: 13),
        ),
      );
    }
    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: triples.length,
      separatorBuilder: (_, _) =>
          const Divider(height: 0, color: KabukTheme.divider),
      itemBuilder: (context, i) => _TripleTile(triple: triples[i]),
    );
  }
}

class _TripleTile extends StatelessWidget {
  const _TripleTile({required this.triple});
  final Triple triple;

  String get _objectDisplay {
    return switch (triple.objectType) {
      ObjectType.uri => triple.objectValue,
      ObjectType.blobRef => '[blob] ${triple.objectValue}',
      _ => triple.objectValue,
    };
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onLongPress: () {
        final text =
            '${triple.subject}\n${triple.predicate}\n${triple.objectValue}';
        Clipboard.setData(ClipboardData(text: text));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Triple copied to clipboard'),
            duration: Duration(seconds: 1),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: KabukTheme.spacingMd,
          vertical: 10,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _TripleRow(
              color: KabukTheme.blueAccent,
              prefix: 'S',
              value: triple.subject,
            ),
            const SizedBox(height: 2),
            _TripleRow(
              color: KabukTheme.accentGreen,
              prefix: 'P',
              value: triple.predicate,
            ),
            const SizedBox(height: 2),
            _TripleRow(
              color: KabukTheme.warmAccent,
              prefix: triple.objectType.name[0].toUpperCase(),
              value: _objectDisplay,
            ),
            if (triple.createdAt != null)
              Padding(
                padding: const EdgeInsets.only(top: 4, left: 22),
                child: Text(
                  _formatDate(triple.createdAt!),
                  style: const TextStyle(
                    fontSize: 10,
                    color: KabukTheme.textTertiary,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  static String _formatDate(DateTime dt) {
    final local = dt.toLocal();
    return '${local.year}-'
        '${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')} '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}:'
        '${local.second.toString().padLeft(2, '0')}';
  }
}

class _TripleRow extends StatelessWidget {
  const _TripleRow({
    required this.color,
    required this.prefix,
    required this.value,
  });
  final Color color;
  final String prefix;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 16,
          height: 16,
          margin: const EdgeInsets.only(right: 6),
          decoration: BoxDecoration(
            color: color.withAlpha(40),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Center(
            child: Text(
              prefix,
              style: TextStyle(
                fontSize: 9,
                color: color,
                fontWeight: FontWeight.w700,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 11,
              color: KabukTheme.textPrimary,
              fontFamily: 'monospace',
            ),
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// Provider State Snapshot
// =============================================================================

class _ProvidersTab extends ConsumerWidget {
  const _ProvidersTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final devMode = ref.watch(devModeProvider);
    final llmConfig = ref.watch(llmConfigProvider);
    final localModel = ref.watch(localModelConfigProvider);
    final modelReady = ref.watch(modelReadinessProvider);
    final privacyLevel = ref.watch(privacyLevelProvider);
    final privacyFilter = ref.watch(privacyFilterEnabledProvider);
    final activeId = ref.watch(activeProfileIdProvider);
    final allIds = ref.watch(allIdentitiesProvider);
    final nostr = ref.watch(nostrServiceProvider);
    final costState = ref.watch(llmCostTrackerProvider);

    final sections = <_ProviderSection>[
      _ProviderSection(
        title: 'Developer',
        icon: Icons.bug_report_rounded,
        color: KabukTheme.warmAccent,
        entries: [_ProviderEntry('devMode', devMode.toString())],
      ),
      _ProviderSection(
        title: 'Identity',
        icon: Icons.key_rounded,
        color: KabukTheme.accentGreen,
        entries: [
          _ProviderEntry(
            'activeProfileId',
            activeId.when(
              data: (v) => v ?? '(none)',
              loading: () => 'loading…',
              error: (e, _) => 'error: $e',
            ),
          ),
          _ProviderEntry(
            'identityCount',
            (allIds.valueOrNull?.length ?? 0).toString(),
          ),
        ],
      ),
      _ProviderSection(
        title: 'LLM',
        icon: Icons.psychology_rounded,
        color: KabukTheme.blueAccent,
        entries: [
          _ProviderEntry(
            'llmProvider',
            llmConfig != null ? llmConfig.provider.name : 'not configured',
          ),
          _ProviderEntry('llmModel', llmConfig?.defaultModel ?? 'default'),
          _ProviderEntry('localModelPath', localModel?.modelPath ?? '(none)'),
          _ProviderEntry('modelReadyStatus', modelReady.status.name),
          _ProviderEntry(
            'downloadProgress',
            modelReady.status == ModelReadyStatus.downloading
                ? '${(modelReady.progress * 100).toStringAsFixed(1)}%'
                : 'n/a',
          ),
        ],
      ),
      _ProviderSection(
        title: 'Privacy',
        icon: Icons.shield_rounded,
        color: KabukTheme.purpleAccent,
        entries: [
          _ProviderEntry('privacyLevel', privacyLevel.name),
          _ProviderEntry('privacyFilterEnabled', privacyFilter.toString()),
        ],
      ),
      _ProviderSection(
        title: 'Nostr',
        icon: Icons.cell_tower_rounded,
        color: KabukTheme.warmAccent,
        entries: [
          _ProviderEntry(
            'relays',
            '${nostr.connectedRelays.length}/${nostr.relays.length} connected',
          ),
          _ProviderEntry(
            'connectedRelays',
            nostr.connectedRelays.isEmpty
                ? '(none)'
                : nostr.connectedRelays.join(', '),
          ),
        ],
      ),
      _ProviderSection(
        title: 'LLM Cost (session)',
        icon: Icons.attach_money_rounded,
        color: KabukTheme.success,
        entries: [
          _ProviderEntry('totalCalls', costState.totalCalls.toString()),
          _ProviderEntry('totalTokens', costState.totalTokens.toString()),
          _ProviderEntry(
            'estimatedCostUsd',
            '\$${costState.totalEstimatedCostUsd.toStringAsFixed(4)}',
          ),
        ],
      ),
    ];

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: KabukTheme.spacingSm),
      itemCount: sections.length,
      itemBuilder: (context, i) => _ProviderSectionWidget(section: sections[i]),
    );
  }
}

class _ProviderSection {
  const _ProviderSection({
    required this.title,
    required this.icon,
    required this.color,
    required this.entries,
  });
  final String title;
  final IconData icon;
  final Color color;
  final List<_ProviderEntry> entries;
}

class _ProviderEntry {
  const _ProviderEntry(this.key, this.value);
  final String key;
  final String value;
}

class _ProviderSectionWidget extends StatelessWidget {
  const _ProviderSectionWidget({required this.section});
  final _ProviderSection section;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: KabukTheme.spacingMd,
        vertical: KabukTheme.spacingSm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(section.icon, size: 14, color: section.color),
              const SizedBox(width: 6),
              Text(
                section.title.toUpperCase(),
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: section.color,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Container(
            decoration: BoxDecoration(
              color: KabukTheme.cardColor,
              borderRadius: BorderRadius.circular(KabukTheme.radiusMd),
              border: Border.all(color: KabukTheme.divider, width: 0.5),
            ),
            child: Column(
              children: [
                for (var i = 0; i < section.entries.length; i++) ...[
                  if (i > 0)
                    const Divider(
                      height: 0,
                      indent: 12,
                      endIndent: 12,
                      color: KabukTheme.divider,
                    ),
                  _ProviderRow(entry: section.entries[i]),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProviderRow extends StatelessWidget {
  const _ProviderRow({required this.entry});
  final _ProviderEntry entry;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onLongPress: () {
        Clipboard.setData(ClipboardData(text: '${entry.key}: ${entry.value}'));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Copied to clipboard'),
            duration: Duration(seconds: 1),
          ),
        );
      },
      borderRadius: BorderRadius.circular(KabukTheme.radiusMd),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Expanded(
              flex: 2,
              child: Text(
                entry.key,
                style: const TextStyle(
                  fontSize: 11,
                  color: KabukTheme.textSecondary,
                  fontFamily: 'monospace',
                ),
              ),
            ),
            Expanded(
              flex: 3,
              child: Text(
                entry.value,
                textAlign: TextAlign.end,
                style: const TextStyle(
                  fontSize: 11,
                  color: KabukTheme.textPrimary,
                  fontFamily: 'monospace',
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// LLM Cost Log
// =============================================================================

class _LlmCostTab extends ConsumerWidget {
  const _LlmCostTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final costState = ref.watch(llmCostTrackerProvider);

    if (costState.byModel.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.attach_money_rounded,
              size: 48,
              color: KabukTheme.textTertiary,
            ),
            SizedBox(height: KabukTheme.spacingSm),
            Text(
              'No LLM calls recorded yet.\nStart a conversation to track usage.',
              textAlign: TextAlign.center,
              style: TextStyle(color: KabukTheme.textSecondary, fontSize: 13),
            ),
          ],
        ),
      );
    }

    final sessionDuration = DateTime.now().difference(
      costState.sessionStartedAt,
    );

    return ListView(
      padding: const EdgeInsets.all(KabukTheme.spacingMd),
      children: [
        // Session summary card.
        _SummaryCard(
          totalCalls: costState.totalCalls,
          totalTokens: costState.totalTokens,
          totalCost: costState.totalEstimatedCostUsd,
          sessionDuration: sessionDuration,
          onReset: () => ref.read(llmCostTrackerProvider.notifier).reset(),
        ),
        const SizedBox(height: KabukTheme.spacingMd),
        const Text(
          'BY MODEL',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: KabukTheme.textSecondary,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: KabukTheme.spacingSm),
        for (final entry in costState.byModel.entries)
          _ModelUsageCard(model: entry.key, summary: entry.value),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.totalCalls,
    required this.totalTokens,
    required this.totalCost,
    required this.sessionDuration,
    required this.onReset,
  });

  final int totalCalls;
  final int totalTokens;
  final double totalCost;
  final Duration sessionDuration;
  final VoidCallback onReset;

  String _formatDuration(Duration d) {
    if (d.inHours >= 1) {
      return '${d.inHours}h ${d.inMinutes.remainder(60)}m';
    }
    if (d.inMinutes >= 1) {
      return '${d.inMinutes}m ${d.inSeconds.remainder(60)}s';
    }
    return '${d.inSeconds}s';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(KabukTheme.spacingMd),
      decoration: BoxDecoration(
        color: KabukTheme.cardColor,
        borderRadius: BorderRadius.circular(KabukTheme.radiusMd),
        border: Border.all(color: KabukTheme.accentGreen.withAlpha(60)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Session Summary',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: KabukTheme.textPrimary,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: onReset,
                style: TextButton.styleFrom(
                  foregroundColor: KabukTheme.error,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('Reset', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: KabukTheme.spacingSm),
          Wrap(
            spacing: KabukTheme.spacingMd,
            runSpacing: 8,
            children: [
              _StatChip(
                label: 'Calls',
                value: '$totalCalls',
                color: KabukTheme.blueAccent,
              ),
              _StatChip(
                label: 'Tokens',
                value: totalTokens.toString(),
                color: KabukTheme.accentGreen,
              ),
              _StatChip(
                label: 'Est. cost',
                value: '\$${totalCost.toStringAsFixed(4)}',
                color: KabukTheme.warmAccent,
              ),
              _StatChip(
                label: 'Session',
                value: _formatDuration(sessionDuration),
                color: KabukTheme.textSecondary,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.label,
    required this.value,
    required this.color,
  });
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(KabukTheme.radiusSm),
        border: Border.all(color: color.withAlpha(60)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: color,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: KabukTheme.textPrimary,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}

class _ModelUsageCard extends StatelessWidget {
  const _ModelUsageCard({required this.model, required this.summary});
  final String model;
  final ModelUsageSummary summary;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: KabukTheme.spacingSm),
      padding: const EdgeInsets.all(KabukTheme.spacingMd),
      decoration: BoxDecoration(
        color: KabukTheme.cardColor,
        borderRadius: BorderRadius.circular(KabukTheme.radiusMd),
        border: Border.all(color: KabukTheme.divider, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  model,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: KabukTheme.textPrimary,
                    fontFamily: 'monospace',
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                summary.provider.name,
                style: const TextStyle(
                  fontSize: 11,
                  color: KabukTheme.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _ModelStat(label: 'calls', value: '${summary.calls}'),
              const SizedBox(width: KabukTheme.spacingMd),
              _ModelStat(label: 'prompt', value: '${summary.promptTokens} tok'),
              const SizedBox(width: KabukTheme.spacingMd),
              _ModelStat(
                label: 'completion',
                value: '${summary.completionTokens} tok',
              ),
              const Spacer(),
              Text(
                '\$${summary.estimatedCostUsd.toStringAsFixed(4)}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: KabukTheme.success,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ModelStat extends StatelessWidget {
  const _ModelStat({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 9,
            color: KabukTheme.textTertiary,
            letterSpacing: 0.5,
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 11,
            color: KabukTheme.textPrimary,
            fontFamily: 'monospace',
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// Extension helper — lets us chain .also() calls on QueryBuilder fluently.
// =============================================================================

extension _QueryBuilderAlso<T> on T {
  T also(void Function(T it) block) {
    block(this);
    return this;
  }
}
