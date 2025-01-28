import 'dart:math';

import 'package:flutter/material.dart';
import "package:flutter/material.dart" as material;
import 'package:kabuk/ui/widgets.dart';

enum KabukWidgetSize {
  small(1, 1),
  vertical(1, 2),
  horizontal(2, 1),
  large(2, 2);

  final int x;
  final int y;
  const KabukWidgetSize(this.x, this.y);
}

abstract class KabukWidget extends StatefulWidget {
  const KabukWidget({super.key});
}

abstract class KabukWidgetState<T extends KabukWidget> extends State<T> {}

class Placeholder extends KabukWidget {
  const Placeholder({super.key});

  @override
  State<Placeholder> createState() => _PlaceholderState();
}

class _PlaceholderState extends KabukWidgetState<Placeholder> {
  @override
  Widget build(BuildContext context) {
    return const material.Placeholder();
  }
}

class KabukWidgetWrapper extends StatefulWidget {
  final KabukWidgetSize size;
  final KabukWidget child;
  const KabukWidgetWrapper({
    super.key,
    this.size = KabukWidgetSize.small,
    required this.child,
  });

  @override
  State<KabukWidgetWrapper> createState() => _KabukWidgetWrapperState();
}

class _KabukWidgetWrapperState extends State<KabukWidgetWrapper> {
  @override
  Widget build(BuildContext context) {
    return ClipRRect(
        borderRadius: BorderRadius.circular(8), child: widget.child);
  }
}

enum KabukWidgetRows {
  small(1, 1),
  right(1, 2),
  left(2, 1),
  large(2, 2),
  horizontal(1, 0);

  final int x;
  final int y;
  const KabukWidgetRows(this.x, this.y);
}

class KabukWidgetRow extends StatelessWidget {
  final List<KabukWidget> children;
  final KabukWidgetRows size;
  const KabukWidgetRow({super.key, required this.size, required this.children});

  factory KabukWidgetRow.small(
          {Key? key,
          List<KabukWidget> children = const [Placeholder(), Placeholder()]}) =>
      KabukWidgetRow(key: key, size: KabukWidgetRows.small, children: children);

  factory KabukWidgetRow.right(
          {Key? key,
          List<KabukWidget> children = const [
            Placeholder(),
            Placeholder(),
            Placeholder()
          ]}) =>
      KabukWidgetRow(key: key, size: KabukWidgetRows.right, children: children);

  factory KabukWidgetRow.left(
          {Key? key,
          List<KabukWidget> children = const [
            Placeholder(),
            Placeholder(),
            Placeholder()
          ]}) =>
      KabukWidgetRow(key: key, size: KabukWidgetRows.left, children: children);

  factory KabukWidgetRow.large(
          {Key? key, List<KabukWidget> children = const [Placeholder()]}) =>
      KabukWidgetRow(key: key, size: KabukWidgetRows.large, children: children);

  factory KabukWidgetRow.horizontal(
          {Key? key, List<KabukWidget> children = const [Placeholder()]}) =>
      KabukWidgetRow(
          key: key, size: KabukWidgetRows.horizontal, children: children);

  factory KabukWidgetRow.random() {
    final random = Random().nextInt(5);
    final article = ArticleWidget();
    switch (random) {
      case 0:
        return KabukWidgetRow.small(
          children: [article, article],
        );
      case 1:
        return KabukWidgetRow.right();
      case 2:
        return KabukWidgetRow.left();
      case 3:
        return KabukWidgetRow.large();
      case 4:
        return KabukWidgetRow.horizontal();
      default:
        throw Exception("Invalid random number");
    }
  }

  Widget small() {
    assert(children.length == 2);
    return AspectRatio(
      aspectRatio: 2,
      child: Row(spacing: 16, children: [
        Expanded(
            child: KabukWidgetWrapper(
                size: KabukWidgetSize.small, child: children[0])),
        Expanded(
            child: KabukWidgetWrapper(
                size: KabukWidgetSize.small, child: children[1])),
      ]),
    );
  }

  Widget right() {
    assert(children.length == 3);
    return AspectRatio(
      aspectRatio: 1,
      child: Row(spacing: 16, children: [
        Expanded(
          child: Column(
            spacing: 16,
            children: [
              Expanded(
                  child: KabukWidgetWrapper(
                      size: KabukWidgetSize.small, child: children[0])),
              Expanded(
                  child: KabukWidgetWrapper(
                      size: KabukWidgetSize.small, child: children[1])),
            ],
          ),
        ),
        Expanded(
            child: KabukWidgetWrapper(
                size: KabukWidgetSize.vertical, child: children[2])),
      ]),
    );
  }

  Widget left() {
    assert(children.length == 3);
    return AspectRatio(
      aspectRatio: 1,
      child: Row(
        spacing: 16,
        children: [
          Expanded(
              child: KabukWidgetWrapper(
                  size: KabukWidgetSize.vertical, child: children[0])),
          Expanded(
            child: Column(
              spacing: 16,
              children: [
                Expanded(
                    child: KabukWidgetWrapper(
                        size: KabukWidgetSize.small, child: children[1])),
                Expanded(
                    child: KabukWidgetWrapper(
                        size: KabukWidgetSize.small, child: children[2])),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget large() {
    assert(children.length == 1);
    return AspectRatio(
      aspectRatio: 1,
      child: Row(children: [
        Expanded(
            child: KabukWidgetWrapper(
                size: KabukWidgetSize.large, child: children[0])),
      ]),
    );
  }

  Widget horizontal() {
    assert(children.length == 1);
    return AspectRatio(
      aspectRatio: 2,
      child: Row(children: [
        Expanded(
            child: KabukWidgetWrapper(
                size: KabukWidgetSize.horizontal, child: children[0])),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: switch (size) {
        KabukWidgetRows.small => small(),
        KabukWidgetRows.right => right(),
        KabukWidgetRows.left => left(),
        KabukWidgetRows.large => large(),
        KabukWidgetRows.horizontal => horizontal(),
      },
    );
  }
}
