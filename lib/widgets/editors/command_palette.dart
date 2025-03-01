import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class Command {
  final String id;
  final String label;
  final String? category;
  final String? shortcut;
  final VoidCallback onExecute;
  final IconData? icon;

  const Command({
    required this.id,
    required this.label,
    required this.onExecute,
    this.category,
    this.shortcut,
    this.icon,
  });
}

class CommandPalette extends StatefulWidget {
  final List<Command> commands;
  final ValueChanged<bool>? onVisibilityChanged;

  const CommandPalette({
    super.key,
    required this.commands,
    this.onVisibilityChanged,
  });

  @override
  State<CommandPalette> createState() => _CommandPaletteState();
}

class _CommandPaletteState extends State<CommandPalette> {
  bool _isVisible = false;
  String _searchQuery = '';
  int _selectedIndex = 0;
  final FocusNode _focusNode = FocusNode();
  final TextEditingController _searchController = TextEditingController();

  List<Command> get _filteredCommands {
    if (_searchQuery.isEmpty) return widget.commands;
    return widget.commands.where((command) {
      return command.label.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          (command.category?.toLowerCase().contains(_searchQuery.toLowerCase()) ?? false);
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    _registerKeyboardShortcuts();
  }

  void _registerKeyboardShortcuts() {
    RawKeyboard.instance.addListener(_handleKeyEvent);
  }

  void _handleKeyEvent(RawKeyEvent event) {
    if (event is RawKeyDownEvent) {
      // Toggle palette visibility with Cmd/Ctrl + P
      if (event.isMetaPressed && event.logicalKey == LogicalKeyboardKey.keyP) {
        _toggleVisibility();
      }
      
      if (_isVisible) {
        if (event.logicalKey == LogicalKeyboardKey.escape) {
          _hideCommandPalette();
        } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
          _selectPreviousCommand();
        } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
          _selectNextCommand();
        } else if (event.logicalKey == LogicalKeyboardKey.enter) {
          _executeSelectedCommand();
        }
      }
    }
  }

  void _toggleVisibility() {
    setState(() {
      _isVisible = !_isVisible;
      if (_isVisible) {
        _searchQuery = '';
        _searchController.clear();
        _selectedIndex = 0;
        _focusNode.requestFocus();
      }
    });
    widget.onVisibilityChanged?.call(_isVisible);
  }

  void _hideCommandPalette() {
    setState(() {
      _isVisible = false;
      _searchQuery = '';
      _searchController.clear();
      _selectedIndex = 0;
    });
    widget.onVisibilityChanged?.call(false);
  }

  void _selectPreviousCommand() {
    setState(() {
      _selectedIndex = (_selectedIndex - 1).clamp(0, _filteredCommands.length - 1);
    });
  }

  void _selectNextCommand() {
    setState(() {
      _selectedIndex = (_selectedIndex + 1).clamp(0, _filteredCommands.length - 1);
    });
  }

  void _executeSelectedCommand() {
    if (_filteredCommands.isNotEmpty) {
      _filteredCommands[_selectedIndex].onExecute();
      _hideCommandPalette();
    }
  }

  @override
  void dispose() {
    RawKeyboard.instance.removeListener(_handleKeyEvent);
    _focusNode.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isVisible) return const SizedBox.shrink();

    return Material(
      color: Colors.black54,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Card(
            margin: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: TextField(
                    controller: _searchController,
                    focusNode: _focusNode,
                    decoration: const InputDecoration(
                      hintText: 'Search commands...',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (value) {
                      setState(() {
                        _searchQuery = value;
                        _selectedIndex = 0;
                      });
                    },
                  ),
                ),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 400),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _filteredCommands.length,
                    itemBuilder: (context, index) {
                      final command = _filteredCommands[index];
                      return ListTile(
                        leading: command.icon != null ? Icon(command.icon) : null,
                        title: Text(command.label),
                        subtitle: command.category != null
                            ? Text(command.category!)
                            : null,
                        trailing: command.shortcut != null
                            ? Text(
                                command.shortcut!,
                                style: Theme.of(context).textTheme.bodySmall,
                              )
                            : null,
                        selected: index == _selectedIndex,
                        onTap: () {
                          command.onExecute();
                          _hideCommandPalette();
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}