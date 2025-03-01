import 'package:flutter/material.dart';

class AssetManager extends StatefulWidget {
  final List<AssetItem>? initialAssets;
  final ValueChanged<List<AssetItem>>? onAssetsChanged;
  final Function(AssetItem)? onAssetSelected;

  const AssetManager({
    super.key,
    this.initialAssets,
    this.onAssetsChanged,
    this.onAssetSelected,
  });

  @override
  State<AssetManager> createState() => _AssetManagerState();
}

class AssetItem {
  final String id;
  final String name;
  final String type;
  final String? thumbnailUrl;
  final Map<String, dynamic>? metadata;

  const AssetItem({
    required this.id,
    required this.name,
    required this.type,
    this.thumbnailUrl,
    this.metadata,
  });
}

class _AssetManagerState extends State<AssetManager> {
  late List<AssetItem> _assets;
  String _selectedFilter = 'all';
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _assets = widget.initialAssets ?? _getMockAssets();
  }

  List<AssetItem> _getMockAssets() {
    return [
      const AssetItem(
        id: '1',
        name: 'Sample Image 1',
        type: 'image',
        thumbnailUrl: 'https://picsum.photos/100',
      ),
      const AssetItem(
        id: '2',
        name: 'Sample Video 1',
        type: 'video',
        thumbnailUrl: 'https://picsum.photos/100',
      ),
      const AssetItem(
        id: '3',
        name: 'Sample Audio 1',
        type: 'audio',
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildToolbar(),
        _buildFilterBar(),
        Expanded(
          child: _buildAssetGrid(),
        ),
      ],
    );
  }

  Widget _buildToolbar() {
    return Container(
      padding: const EdgeInsets.all(8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Search assets...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(vertical: 0, horizontal: 16),
              ),
              onChanged: (value) {
                setState(() {
                  _searchQuery = value;
                });
              },
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.upload),
            onPressed: () {
              // Handle asset upload
            },
            tooltip: 'Upload Asset',
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _buildFilterChip('All', 'all'),
          _buildFilterChip('Images', 'image'),
          _buildFilterChip('Videos', 'video'),
          _buildFilterChip('Audio', 'audio'),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: _selectedFilter == value,
        onSelected: (selected) {
          setState(() {
            _selectedFilter = value;
          });
        },
      ),
    );
  }

  Widget _buildAssetGrid() {
    final filteredAssets = _assets.where((asset) {
      final matchesFilter = _selectedFilter == 'all' || asset.type == _selectedFilter;
      final matchesSearch = _searchQuery.isEmpty ||
          asset.name.toLowerCase().contains(_searchQuery.toLowerCase());
      return matchesFilter && matchesSearch;
    }).toList();

    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 120,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 1,
      ),
      itemCount: filteredAssets.length,
      itemBuilder: (context, index) {
        final asset = filteredAssets[index];
        return _buildAssetTile(asset);
      },
    );
  }

  Widget _buildAssetTile(AssetItem asset) {
    return InkWell(
      onTap: () {
        if (widget.onAssetSelected != null) {
          widget.onAssetSelected!(asset);
        }
      },
      child: Card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: asset.thumbnailUrl != null
                  ? Image.network(
                      asset.thumbnailUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) =>
                          _buildAssetTypeIcon(asset.type),
                    )
                  : _buildAssetTypeIcon(asset.type),
            ),
            Container(
              padding: const EdgeInsets.all(4),
              color: Colors.black54,
              child: Text(
                asset.name,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAssetTypeIcon(String type) {
    IconData iconData;
    switch (type) {
      case 'image':
        iconData = Icons.image;
        break;
      case 'video':
        iconData = Icons.videocam;
        break;
      case 'audio':
        iconData = Icons.audiotrack;
        break;
      default:
        iconData = Icons.insert_drive_file;
    }

    return Container(
      color: Colors.grey[200],
      child: Icon(iconData, color: Colors.grey[400], size: 32),
    );
  }
}