import 'package:flutter/material.dart';

class MediaEditor extends StatefulWidget {
  final String type; // 'image', 'video', or 'audio'
  final String? initialUrl;
  final Map<String, dynamic>? initialConfig;
  final Function(Map<String, dynamic>)? onConfigChanged;

  const MediaEditor({
    super.key,
    required this.type,
    this.initialUrl,
    this.initialConfig,
    this.onConfigChanged,
  });

  @override
  State<MediaEditor> createState() => _MediaEditorState();
}

class _MediaEditorState extends State<MediaEditor> {
  late Map<String, dynamic> _config;
  bool _isPlaying = false;
  double _playbackPosition = 0;

  @override
  void initState() {
    super.initState();
    _config = widget.initialConfig ?? {};
  }

  void _updateConfig(String key, dynamic value) {
    setState(() {
      _config[key] = value;
      widget.onConfigChanged?.call(_config);
    });
  }

  Widget _buildImageEditor() {
    return Column(
      children: [
        Expanded(
          child: Center(
            child: widget.initialUrl != null
                ? Image.network(
                    widget.initialUrl!,
                    fit: BoxFit.contain,
                  )
                : const Icon(Icons.image, size: 100),
          ),
        ),
        const Divider(),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildFilterButton('Original'),
              _buildFilterButton('Grayscale'),
              _buildFilterButton('Sepia'),
              _buildFilterButton('Blur'),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            const Text('Brightness'),
            Expanded(
              child: Slider(
                value: _config['brightness'] ?? 1.0,
                min: 0.0,
                max: 2.0,
                onChanged: (value) => _updateConfig('brightness', value),
              ),
            ),
          ],
        ),
        Row(
          children: [
            const Text('Contrast'),
            Expanded(
              child: Slider(
                value: _config['contrast'] ?? 1.0,
                min: 0.0,
                max: 2.0,
                onChanged: (value) => _updateConfig('contrast', value),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildVideoEditor() {
    return Column(
      children: [
        Expanded(
          child: Center(
            child: widget.initialUrl != null
                ? Stack(
                    alignment: Alignment.center,
                    children: [
                      AspectRatio(
                        aspectRatio: 16 / 9,
                        child: Container(
                          color: Colors.black,
                          // TODO: Add video player widget
                        ),
                      ),
                      IconButton(
                        icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow),
                        onPressed: () {
                          setState(() => _isPlaying = !_isPlaying);
                        },
                      ),
                    ],
                  )
                : const Icon(Icons.video_file, size: 100),
          ),
        ),
        const Divider(),
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.cut),
              onPressed: () {
                // TODO: Implement trim functionality
              },
              tooltip: 'Trim Video',
            ),
            Expanded(
              child: Slider(
                value: _playbackPosition,
                min: 0.0,
                max: 1.0,
                onChanged: (value) {
                  setState(() => _playbackPosition = value);
                  // TODO: Seek video to position
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildAudioEditor() {
    return Column(
      children: [
        Expanded(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.audiotrack, size: 100),
                if (widget.initialUrl != null)
                  const Text('Audio Waveform Visualization'),
              ],
            ),
          ),
        ),
        const Divider(),
        Row(
          children: [
            IconButton(
              icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow),
              onPressed: () {
                setState(() => _isPlaying = !_isPlaying);
              },
            ),
            Expanded(
              child: Slider(
                value: _playbackPosition,
                min: 0.0,
                max: 1.0,
                onChanged: (value) {
                  setState(() => _playbackPosition = value);
                  // TODO: Seek audio to position
                },
              ),
            ),
          ],
        ),
        Row(
          children: [
            const Text('Volume'),
            Expanded(
              child: Slider(
                value: _config['volume'] ?? 1.0,
                min: 0.0,
                max: 1.0,
                onChanged: (value) => _updateConfig('volume', value),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildFilterButton(String name) {
    final isSelected = _config['filter'] == name.toLowerCase();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: FilterChip(
        label: Text(name),
        selected: isSelected,
        onSelected: (selected) {
          _updateConfig('filter', selected ? name.toLowerCase() : null);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    switch (widget.type) {
      case 'image':
        return _buildImageEditor();
      case 'video':
        return _buildVideoEditor();
      case 'audio':
        return _buildAudioEditor();
      default:
        return const Center(child: Text('Unsupported media type'));
    }
  }
}