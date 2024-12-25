import 'package:flutter/material.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  ChatPageState createState() => ChatPageState();
}

class ChatPageState extends State<ChatPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: const Drawer(),
      appBar: AppBar(
        title: const Text("Timeline"),
        actions: [
          IconButton(
            onPressed: () {},
            icon: const Icon(Icons.filter_list),
          ),
          IconButton(
            onPressed: () {},
            icon: const Icon(Icons.search),
          ),
          const Padding(
            padding: EdgeInsets.only(right: 8),
            child: CircleAvatar(
              backgroundImage: NetworkImage('https://i.pravatar.cc/300'),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(8.0),
        children: const [],
      ),
      bottomNavigationBar: const Padding(
        padding: EdgeInsets.all(8.0),
        child: InputRow(),
      ),
    );
  }
}

class InputRow extends StatefulWidget {
  const InputRow({super.key});

  @override
  InputRowState createState() => InputRowState();
}

class InputRowState extends State<InputRow>
    with SingleTickerProviderStateMixin {
  final TextEditingController _controller = TextEditingController();
  bool _hasText = false;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      setState(() {
        _hasText = _controller.text.isNotEmpty;
      });
    });
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _animationController.dispose();
    super.dispose();
  }

  void _onAddPressed() {
    // Add button pressed logic
  }

  void _onChannelPressed() {
    // Channel button pressed logic
  }

  void _onMicPressed() {
    // Mic button pressed logic
  }

  void _onImagePressed() {
    // Image button pressed logic
  }

  @override
  Widget build(BuildContext context) {
    if (_hasText) {
      _animationController.reverse();
    } else {
      _animationController.forward();
    }

    return Row(
      children: [
        IconButton(
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.add_circle_outline),
          onPressed: _onAddPressed,
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.cable),
          onPressed: _onChannelPressed,
        ),
        Expanded(
          child: TextField(
            controller: _controller,
            maxLines: null,
            decoration: InputDecoration(
              hintText: "Message",
              filled: true,
              fillColor: Theme.of(context).colorScheme.surfaceContainer,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(20),
                borderSide: BorderSide.none,
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              suffixIcon: FadeTransition(
                opacity: _fadeAnimation,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.graphic_eq),
                      visualDensity: VisualDensity.compact,
                      onPressed: _onMicPressed,
                    ),
                    IconButton(
                      icon: const Icon(Icons.camera_alt),
                      onPressed: _onImagePressed,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class MessageGroup extends StatelessWidget {
  const MessageGroup({super.key});

  @override
  Widget build(BuildContext context) {
    return const Placeholder();
  }
}
