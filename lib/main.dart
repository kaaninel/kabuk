import 'package:flutter/material.dart';
import 'package:kabuk/views/apps_view.dart';
import 'package:kabuk/views/chat_view.dart';
import 'package:kabuk/views/create_view.dart';
import 'package:kabuk/views/explore_view.dart';

void main() {
  runApp(const KabukApp());
}

class KabukApp extends StatelessWidget {
  const KabukApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Kabuk',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
      ),
      home: const MainLayout(),
    );
  }
}

class MainLayout extends StatefulWidget {
  const MainLayout({super.key});

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  int _selectedIndex = 2; // Explore view is default

  static const List<Widget> _views = <Widget>[
    CreateView(),
    ChatView(),
    ExploreView(),
    AppsView(),
  ];

  @override
  Widget build(BuildContext context) {
    final bool isDesktop = MediaQuery.of(context).size.width >= 1240;

    return Scaffold(
      body: Row(
        children: [
          if (isDesktop)
            NavigationRail(
              extended: false,
              destinations: const [
                NavigationRailDestination(
                  icon: Icon(Icons.create),
                  label: Text('Create'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.chat),
                  label: Text('Chat'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.explore),
                  label: Text('Explore'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.apps),
                  label: Text('Apps'),
                ),
              ],
              selectedIndex: _selectedIndex,
              onDestinationSelected: _onItemTapped,
            ),
          Expanded(
            child: _views[_selectedIndex],
          ),
        ],
      ),
      bottomNavigationBar: isDesktop
          ? null
          : NavigationBar(
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.create),
                  label: 'Create',
                ),
                NavigationDestination(
                  icon: Icon(Icons.chat),
                  label: 'Chat',
                ),
                NavigationDestination(
                  icon: Icon(Icons.explore),
                  label: 'Explore',
                ),
                NavigationDestination(
                  icon: Icon(Icons.apps),
                  label: 'Apps',
                ),
              ],
              selectedIndex: _selectedIndex,
              onDestinationSelected: _onItemTapped,
            ),
    );
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }
}
