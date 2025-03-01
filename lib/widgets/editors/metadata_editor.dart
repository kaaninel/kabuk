import 'package:flutter/material.dart';

class MetadataEditor extends StatefulWidget {
  final Map<String, dynamic>? initialMetadata;
  final ValueChanged<Map<String, dynamic>>? onChanged;

  const MetadataEditor({
    super.key,
    this.initialMetadata,
    this.onChanged,
  });

  @override
  State<MetadataEditor> createState() => _MetadataEditorState();
}

class _MetadataEditorState extends State<MetadataEditor> {
  late Map<String, dynamic> _metadata;
  final List<String> _suggestedSchemas = [
    'Article',
    'ImageObject',
    'VideoObject',
    'AudioObject',
    'BlogPosting',
    'CreativeWork',
  ];

  @override
  void initState() {
    super.initState();
    _metadata = widget.initialMetadata ?? {};
  }

  void _updateMetadata(String key, dynamic value) {
    setState(() {
      _metadata[key] = value;
      if (widget.onChanged != null) {
        widget.onChanged!(_metadata);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Schema type selector
        DropdownButtonFormField<String>(
          value: _metadata['@type'] as String?,
          decoration: const InputDecoration(
            labelText: 'Schema Type',
            border: OutlineInputBorder(),
          ),
          items: _suggestedSchemas.map((type) {
            return DropdownMenuItem(
              value: type,
              child: Text(type),
            );
          }).toList(),
          onChanged: (value) => _updateMetadata('@type', value),
        ),
        const SizedBox(height: 16),

        // Common metadata fields
        TextField(
          decoration: const InputDecoration(
            labelText: 'Author',
            border: OutlineInputBorder(),
          ),
          onChanged: (value) => _updateMetadata('author', value),
          controller: TextEditingController(text: _metadata['author'] as String?),
        ),
        const SizedBox(height: 16),

        TextField(
          decoration: const InputDecoration(
            labelText: 'Description',
            border: OutlineInputBorder(),
          ),
          maxLines: 3,
          onChanged: (value) => _updateMetadata('description', value),
          controller: TextEditingController(text: _metadata['description'] as String?),
        ),
        const SizedBox(height: 16),

        // Tags
        TextField(
          decoration: const InputDecoration(
            labelText: 'Tags (comma separated)',
            border: OutlineInputBorder(),
          ),
          onChanged: (value) {
            final tags = value.split(',').map((e) => e.trim()).toList();
            _updateMetadata('keywords', tags);
          },
          controller: TextEditingController(
            text: (_metadata['keywords'] as List<String>?)?.join(', '),
          ),
        ),
        const SizedBox(height: 16),

        // Date fields
        Row(
          children: [
            Expanded(
              child: TextField(
                decoration: const InputDecoration(
                  labelText: 'Date Created',
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) => _updateMetadata('dateCreated', value),
                controller: TextEditingController(
                  text: _metadata['dateCreated'] as String?,
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: TextField(
                decoration: const InputDecoration(
                  labelText: 'Date Modified',
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) => _updateMetadata('dateModified', value),
                controller: TextEditingController(
                  text: _metadata['dateModified'] as String?,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // License
        TextField(
          decoration: const InputDecoration(
            labelText: 'License',
            border: OutlineInputBorder(),
          ),
          onChanged: (value) => _updateMetadata('license', value),
          controller: TextEditingController(text: _metadata['license'] as String?),
        ),
      ],
    );
  }
}