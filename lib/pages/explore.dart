import 'package:flutter/material.dart';
import 'package:kabuk/ui/scaffolding.dart';

class ExplorePage extends StatelessWidget {
  const ExplorePage({super.key});

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
      body: ListView.builder(
        padding: EdgeInsets.all(8),
        itemBuilder: (context, index) {
          return KabukWidgetRow.random();
        },
      ),
    );
  }
}
