/// Settings page for streaming quality preferences.
///
/// Lets users set default resolution, codec, source, language, HDR, and
/// file-size preferences used by the [UsenetResolver] for automatic
/// NZB source selection.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kabuk/config/providers.dart';
import 'package:kabuk/knowledge/types/streaming_prefs.dart';
import 'package:kabuk/ui/settings/settings_shared.dart';
import 'package:kabuk/ui/theme.dart';

/// Settings page for configuring streaming quality defaults.
class StreamingPrefsPage extends ConsumerStatefulWidget {
  const StreamingPrefsPage({super.key});

  @override
  ConsumerState<StreamingPrefsPage> createState() => _StreamingPrefsPageState();
}

class _StreamingPrefsPageState extends ConsumerState<StreamingPrefsPage> {
  StreamingPrefs _prefs = StreamingPrefs.defaults;
  bool _loaded = false;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final prefs = await ref.read(streamingPrefsProvider.future);
    if (mounted) {
      setState(() {
        _prefs = prefs;
        _loaded = true;
      });
    }
  }

  void _update(StreamingPrefs Function(StreamingPrefs) updater) {
    setState(() {
      _prefs = updater(_prefs);
      _dirty = true;
    });
  }

  Future<void> _save() async {
    final store = ref.read(knowledgeStoreProvider);
    await store.saveStreamingPrefs(_prefs);
    ref.invalidate(streamingPrefsProvider);
    if (mounted) {
      setState(() => _dirty = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Quality preferences saved'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Streaming Quality'),
        actions: [
          if (_dirty)
            TextButton(
              onPressed: _save,
              child: Text(
                'Save',
                style: TextStyle(
                  color: cs.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Description.
                Text(
                  'These defaults are used when you press Play on a movie or '
                  'episode. The system picks the best available Usenet source '
                  'matching your preferences.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurface.withValues(alpha: 0.6),
                  ),
                ),
                const SizedBox(height: 24),

                // Resolution.
                const SettingsSectionHeader(
                  icon: Icons.hd_rounded,
                  title: 'Resolution',
                  color: KabukTheme.blueAccent,
                ),
                const SizedBox(height: 8),
                _ChoiceChipRow<PreferredResolution>(
                  values: PreferredResolution.values,
                  selected: _prefs.resolution,
                  labelOf: (v) => switch (v) {
                    PreferredResolution.uhd4k => '4K',
                    PreferredResolution.fullHd => '1080p',
                    PreferredResolution.hd => '720p',
                    PreferredResolution.sd => '480p',
                    PreferredResolution.any => 'Best Available',
                  },
                  onSelected: (v) =>
                      _update((p) => p.copyWith(resolution: v)),
                ),

                const SizedBox(height: 24),

                // Source.
                const SettingsSectionHeader(
                  icon: Icons.disc_full_rounded,
                  title: 'Source',
                  color: KabukTheme.purpleAccent,
                ),
                const SizedBox(height: 8),
                _ChoiceChipRow<String>(
                  values: const [
                    'any', 'Remux', 'BluRay', 'WEB-DL', 'WEBRip', 'HDTV'
                  ],
                  selected: _prefs.source,
                  labelOf: (v) => v == 'any' ? 'Any' : v,
                  onSelected: (v) => _update((p) => p.copyWith(source: v)),
                ),

                const SizedBox(height: 24),

                // Codec.
                const SettingsSectionHeader(
                  icon: Icons.code_rounded,
                  title: 'Codec',
                  color: KabukTheme.accentGreen,
                ),
                const SizedBox(height: 8),
                _ChoiceChipRow<String>(
                  values: const ['any', 'x265', 'x264', 'AV1'],
                  selected: _prefs.codec,
                  labelOf: (v) => v == 'any' ? 'Any' : v.toUpperCase(),
                  onSelected: (v) => _update((p) => p.copyWith(codec: v)),
                ),

                const SizedBox(height: 24),

                // HDR.
                const SettingsSectionHeader(
                  icon: Icons.hdr_on_rounded,
                  title: 'HDR',
                  color: Color(0xFFFFD700),
                ),
                const SizedBox(height: 8),
                _ChoiceChipRow<HdrPreference>(
                  values: HdrPreference.values,
                  selected: _prefs.hdr,
                  labelOf: (v) => switch (v) {
                    HdrPreference.required => 'Required',
                    HdrPreference.preferred => 'Preferred',
                    HdrPreference.any => 'Any',
                    HdrPreference.none => 'SDR Only',
                  },
                  onSelected: (v) => _update((p) => p.copyWith(hdr: v)),
                ),

                const SizedBox(height: 24),

                // Language.
                const SettingsSectionHeader(
                  icon: Icons.language_rounded,
                  title: 'Language',
                  color: KabukTheme.blueAccent,
                ),
                const SizedBox(height: 8),
                _ChoiceChipRow<String>(
                  values: const [
                    'English', 'Multi', 'German', 'French', 'Spanish',
                    'Japanese', 'Korean', 'any',
                  ],
                  selected: _prefs.language,
                  labelOf: (v) => v == 'any' ? 'Any' : v,
                  onSelected: (v) =>
                      _update((p) => p.copyWith(language: v)),
                ),

                const SizedBox(height: 24),

                // Audio.
                const SettingsSectionHeader(
                  icon: Icons.surround_sound_rounded,
                  title: 'Audio',
                  color: KabukTheme.purpleAccent,
                ),
                const SizedBox(height: 8),
                _ChoiceChipRow<String>(
                  values: const [
                    'any', 'Atmos', 'DTS-HD MA', 'TrueHD', 'DTS',
                    'DD+', 'AAC',
                  ],
                  selected: _prefs.audio,
                  labelOf: (v) => v == 'any' ? 'Any' : v,
                  onSelected: (v) => _update((p) => p.copyWith(audio: v)),
                ),

                const SizedBox(height: 24),

                // Max file size.
                const SettingsSectionHeader(
                  icon: Icons.storage_rounded,
                  title: 'Max File Size',
                  color: KabukTheme.accentGreen,
                ),
                const SizedBox(height: 8),
                _buildMaxSizeSlider(theme, cs),

                const SizedBox(height: 24),

                // Max retries.
                const SettingsSectionHeader(
                  icon: Icons.replay_rounded,
                  title: 'Auto-retry',
                  color: KabukTheme.blueAccent,
                ),
                const SizedBox(height: 8),
                _buildRetriesSlider(theme, cs),

                const SizedBox(height: 32),
              ],
            ),
    );
  }

  Widget _buildMaxSizeSlider(ThemeData theme, ColorScheme cs) {
    final sizeMb = _prefs.maxFileSizeMb;
    final label = sizeMb == 0 ? 'No Limit' : '${(sizeMb / 1024).toStringAsFixed(1)} GB';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            )),
        Slider(
          value: sizeMb.toDouble(),
          min: 0,
          max: 50000,
          divisions: 50,
          label: label,
          onChanged: (v) =>
              _update((p) => p.copyWith(maxFileSizeMb: v.toInt())),
        ),
        Text(
          'Excludes NZBs larger than this. 0 = no limit.',
          style: theme.textTheme.labelSmall?.copyWith(
            color: cs.onSurface.withValues(alpha: 0.5),
          ),
        ),
      ],
    );
  }

  Widget _buildRetriesSlider(ThemeData theme, ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('${_prefs.maxRetries} sources',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            )),
        Slider(
          value: _prefs.maxRetries.toDouble(),
          min: 1,
          max: 15,
          divisions: 14,
          label: '${_prefs.maxRetries}',
          onChanged: (v) =>
              _update((p) => p.copyWith(maxRetries: v.toInt())),
        ),
        Text(
          'How many NZB sources to try before giving up.',
          style: theme.textTheme.labelSmall?.copyWith(
            color: cs.onSurface.withValues(alpha: 0.5),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Generic choice chip row
// ---------------------------------------------------------------------------

class _ChoiceChipRow<T> extends StatelessWidget {
  const _ChoiceChipRow({
    required this.values,
    required this.selected,
    required this.labelOf,
    required this.onSelected,
    super.key,
  });

  final List<T> values;
  final T selected;
  final String Function(T) labelOf;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: values.map((v) {
        final isSelected = v == selected;
        return ChoiceChip(
          label: Text(labelOf(v)),
          selected: isSelected,
          onSelected: (_) => onSelected(v),
          selectedColor: cs.primary.withValues(alpha: 0.15),
          labelStyle: TextStyle(
            color: isSelected ? cs.primary : cs.onSurface,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          ),
        );
      }).toList(),
    );
  }
}
