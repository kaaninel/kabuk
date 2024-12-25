import 'package:flutter/material.dart';
import 'pages/create_page.dart';
import 'pages/chat_page.dart';
import 'pages/explore_page.dart';
import 'pages/apps_page.dart';

void main() {
  runApp(const KabukApp());
}

class KabukApp extends StatefulWidget {
  const KabukApp({super.key});

  @override
  KabukAppState createState() => KabukAppState();
}

class KabukAppState extends State<KabukApp> {
  int _selectedIndex = 0;

  static const List<Widget> _pages = <Widget>[
    CreatePage(),
    ChatPage(),
    ExplorePage(),
    AppsPage(),
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "Kabuk",
      debugShowCheckedModeBanner: false,
      darkTheme: ThemeData.dark(),
      home: Scaffold(
        body: _pages[_selectedIndex],
        bottomNavigationBar: BottomNavigationBar(
          type: BottomNavigationBarType.fixed,
          items: const <BottomNavigationBarItem>[
            BottomNavigationBarItem(
              icon: Icon(Icons.add),
              label: 'Create',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.chat_bubble_outline),
              label: 'Chat',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.language),
              label: 'Explore',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.apps),
              label: 'Apps',
            ),
          ],
          currentIndex: _selectedIndex,
          onTap: _onItemTapped,
        ),
      ),
    );
  }

  void onFilter() {}

  void onSearch() {}
}

class Layout extends StatelessWidget {
  final int selectedIndex;
  final Function(int) onItemTapped;
  final Widget page;

  const Layout({
    required this.selectedIndex,
    required this.onItemTapped,
    required this.page,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: const Drawer(),
      appBar: AppBar(
        title: const Text("Timeline"),
        actions: [
          IconButton(onPressed: () {}, icon: const Icon(Icons.filter_list)),
          IconButton(onPressed: () {}, icon: const Icon(Icons.search)),
          const Padding(
            padding: EdgeInsets.only(right: 8),
            child: CircleAvatar(
              backgroundImage: NetworkImage('https://i.pravatar.cc/300'),
            ),
          ),
        ],
      ),
      body: page,
    );
  }
}
