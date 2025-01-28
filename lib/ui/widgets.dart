import 'package:flutter/material.dart';
import 'package:kabuk/ui/scaffolding.dart';

class UserInfo extends StatelessWidget {
  final String id;
  final String name;
  const UserInfo({super.key, required this.id, required this.name});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Image.network("https://i.pravatar.cc/32?u=$id"),
        Column(
          children: [
            Text(id),
            Text(name),
          ],
        ),
      ],
    );
  }
}

class ArticleWidget extends KabukWidget {
  const ArticleWidget({super.key});

  @override
  State<ArticleWidget> createState() => _ArticleWidgetState();
}

class _ArticleWidgetState extends KabukWidgetState<ArticleWidget> {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text("Lorem ipsum dolor sit amet, consectetur adipiscing elit."),
        UserInfo(id: "@kaan:kabuk.dev", name: "Kaan Inel")
      ],
    );
  }
}
