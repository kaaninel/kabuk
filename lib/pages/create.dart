import 'package:flutter/material.dart';
import "package:kabuk/util/context.dart";

class CreatePage extends StatefulWidget {
  const CreatePage({super.key});

  static final types = {
    (0, Icons.article, "Article"): CreateArticle(),
    (1, Icons.photo, "Photo"): Placeholder(),
  };

  @override
  State<CreatePage> createState() => _CreatePageState();
}

class _CreatePageState extends State<CreatePage> {
  int page = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: Drawer(
          child: ListView(children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text("Create", style: context.text.headlineMedium),
        ),
        for (final key in CreatePage.types.keys)
          ListTile(
            leading: Icon(key.$2),
            title: Text(key.$3),
            onTap: () {
              setState(() => page = key.$1);
              Navigator.pop(context);
            },
          )
      ])),
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
      body: IndexedStack(
        index: page,
        children: CreatePage.types.values.toList(),
      ),
    );
  }
}

class CreateArticle extends StatefulWidget {
  const CreateArticle({super.key});

  @override
  State<CreateArticle> createState() => _CreateArticleState();
}

class _CreateArticleState extends State<CreateArticle> {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              children: [
                TextField(
                  decoration: const InputDecoration(
                    hintText: 'Title',
                    border: InputBorder.none,
                  ),
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                TextField(
                  decoration: const InputDecoration(
                    hintText: 'Content',
                    border: InputBorder.none,
                  ),
                  maxLines: null,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ),
        Row(mainAxisAlignment: MainAxisAlignment.end, spacing: 8, children: [
          ElevatedButton.icon(
              onPressed: () {}, icon: Icon(Icons.save), label: Text("Save")),
          ElevatedButton.icon(
              onPressed: () {}, icon: Icon(Icons.share), label: Text("Share")),
        ]),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              spacing: 8,
              children: [
                FilledButton.tonal(onPressed: () {}, child: Icon(Icons.photo)),
                FilledButton.tonal(
                    onPressed: () {}, child: Icon(Icons.article)),
                FilledButton.tonal(
                    onPressed: () {}, child: Icon(Icons.location_on)),
                FilledButton.tonal(onPressed: () {}, child: Icon(Icons.person)),
                FilledButton.tonal(
                    onPressed: () {}, child: Icon(Icons.list_alt)),
                FilledButton.tonal(
                    onPressed: () {}, child: Icon(Icons.headphones)),
              ]),
        )
      ]),
    );
  }
}
