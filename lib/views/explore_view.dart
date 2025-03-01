import 'package:flutter/material.dart';

class ExploreView extends StatefulWidget {
  const ExploreView({super.key});

  @override
  State<ExploreView> createState() => _ExploreViewState();
}

class _ExploreViewState extends State<ExploreView> {
  bool _isSearchActive = false;
  bool _isMenuOpen = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          if (_isMenuOpen) _buildLeftPanel(),
          Expanded(
            child: Column(
              children: [
                _buildTopNavigationBar(),
                Expanded(
                  child: _buildContentGrid(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopNavigationBar() {
    return Material(
      elevation: 2,
      child: Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.menu),
              onPressed: () => setState(() => _isMenuOpen = !_isMenuOpen),
            ),
            Expanded(
              child: _isSearchActive
                  ? _buildSearchInput()
                  : SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: _buildLocationDisplay(),
                    ),
            ),
            // Wrap buttons in overflow menu on small screens
            LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth < 400) {
                  return PopupMenuButton(
                    icon: const Icon(Icons.more_vert),
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'Search',
                        child: Text('Search'),
                      ),
                      const PopupMenuItem(
                        value: 'Filter',
                        child: Text('Filter'),
                      ),
                      const PopupMenuItem(
                        value: 'View',
                        child: Text('View'),
                      ),
                      const PopupMenuItem(
                        value: 'Sort',
                        child: Text('Sort'),
                      ),
                    ],
                    onSelected: (value) {
                      // Handle menu item selection
                      switch (value) {
                        case 'Search':
                          // Handle search action
                          break;
                        case 'Filter':
                          // Handle filter action
                          break;
                        case 'View':
                          // Handle view action
                          break;
                        case 'Sort':
                          // Handle sort action
                          break;
                      }
                    },
                  );
                }
                return Row(
                  children: [
                    IconButton(
                        icon: const Icon(Icons.search),
                        onPressed: () {
                          setState(() {
                            _isSearchActive = true;
                          });
                        }),
                    IconButton(
                        icon: const Icon(Icons.filter_list), onPressed: () {}),
                    IconButton(
                        icon: const Icon(Icons.grid_view), onPressed: () {}),
                    IconButton(icon: const Icon(Icons.sort), onPressed: () {}),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchInput() {
    return TextField(
      decoration: const InputDecoration(
        hintText: 'Search...',
        border: InputBorder.none,
      ),
    );
  }

  Widget _buildLocationDisplay() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: const [
          Text('Home > Images > Nature > 2023',
              style: TextStyle(fontSize: 16), overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }

  Widget _buildLeftPanel() {
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.85,
        minWidth: 250,
      ),
      child: Container(
        width: 300,
        color: Theme.of(context).cardColor,
        child: Column(
          children: [
            Expanded(child: _buildTabList()),
            const Divider(),
            SafeArea(child: _buildQuickActions()),
          ],
        ),
      ),
    );
  }

  Widget _buildTabList() {
    return ListView(
      children: const [
        ListTile(
          leading: Icon(Icons.tab),
          title: Text('Tab 1'),
          selected: true,
        ),
        // Add more tabs here
      ],
    );
  }

  Widget _buildQuickActions() {
    return Column(
      children: [
        ListTile(
          leading: const Icon(Icons.push_pin),
          title: const Text('Pin Menu'),
          onTap: () {},
        ),
        // Add more quick actions
      ],
    );
  }

  Widget _buildContentGrid() {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 300,
        mainAxisExtent: 300,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemBuilder: (context, index) => _buildContentCard(index),
      itemCount: 20, // Example count
    );
  }

  Widget _buildContentCard(int index) {
    // Example card - implement different types based on content
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Container(
              color: Colors.grey[200],
              child: Center(
                child: Icon(Icons.image, size: 48, color: Colors.grey[400]),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text(
              'Item $index',
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
            ),
          ),
        ],
      ),
    );
  }
}
