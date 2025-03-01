import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' as flutter_services;

class MarkdownEditor extends StatefulWidget {
  final String initialContent;
  final ValueChanged<String>? onChanged;
  final bool showLineNumbers;

  const MarkdownEditor({
    super.key,
    this.initialContent = '',
    this.onChanged,
    this.showLineNumbers = true,
  });

  @override
  State<MarkdownEditor> createState() => _MarkdownEditorState();
}

class _MarkdownEditorState extends State<MarkdownEditor> {
  late TextEditingController _controller;
  late ScrollController _scrollController;
  late FocusNode _focusNode;
  int _currentLine = 1;
  int _totalLines = 1;
  final Map<int, bool> _foldedLines = {};
  String? _suggestionsQuery;
  final List<String> _markdownSuggestions = [
    '# Heading 1',
    '## Heading 2',
    '### Heading 3',
    '- Bullet point',
    '1. Numbered list',
    '[link](url)',
    '![image](url)',
    '**bold**',
    '*italic*',
    '`code`',
    '```\ncode block\n```',
    '> blockquote',
    '---',
    '| Table | Header |',
    '|--------|---------|',
  ];
  List<flutter_services.SuggestionSpan>? _spellCheckResults;
  Timer? _spellCheckDebouncer;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialContent);
    _scrollController = ScrollController();
    _focusNode = FocusNode();
    _updateLineCount();
    
    _controller.addListener(_handleTextChanged);
    _initializeSpellCheck();
  }

  void _handleTextChanged() {
    if (widget.onChanged != null) {
      widget.onChanged!(_controller.text);
    }
    _updateLineCount();
    _checkForAutoComplete();
    _initializeSpellCheck();
  }

  void _initializeSpellCheck() {
    _spellCheckDebouncer?.cancel();
    _spellCheckDebouncer = Timer(const Duration(milliseconds: 500), () {
      _checkSpelling();
    });
  }

  Future<void> _checkSpelling() async {
    final results = await flutter_services.DefaultSpellCheckService().fetchSpellCheckSuggestions(Locale.fromSubtags(), _controller.text);

    setState(() {
      _spellCheckResults = results;
    });
  }

  void _showSpellCheckSuggestions(BuildContext context, flutter_services.SuggestionSpan span) {
    final RenderBox button = context.findRenderObject() as RenderBox;
    final Offset position = button.localToGlobal(Offset.zero);

    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy + button.size.height,
        position.dx + button.size.width,
        position.dy + button.size.height + 200,
      ),
      items: [
        ...span.suggestions.map((suggestion) => PopupMenuItem<String>(
          value: suggestion,
          child: Text(suggestion),
        )),
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: 'add_to_dictionary',
          child: Row(
            children: const [
              Icon(Icons.add),
              SizedBox(width: 8),
              Text('Add to Dictionary'),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value == null) return;
      
      if (value == 'add_to_dictionary') {
        final word = _controller.text.substring(span.range.start, span.range.end);
    
        _checkSpelling();
      } else {
        // Replace the misspelled word with the suggestion
        final newText = _controller.text.replaceRange(
          span.range.start,
          span.range.end,
          value,
        );
        _controller.value = TextEditingValue(
          text: newText,
          selection: TextSelection.collapsed(
            offset: span.range.start + value.length,
          ),
        );
      }
    });
  }

  void _checkForAutoComplete() {
    final selection = _controller.selection;
    if (!selection.isValid || selection.isCollapsed) return;

    final text = _controller.text;
    final cursorPosition = selection.baseOffset;
    if (cursorPosition <= 0) return;

    // Find the start of the current line
    int lineStart = text.lastIndexOf('\n', cursorPosition - 1) + 1;
    final currentLineText = text.substring(lineStart, cursorPosition);

    setState(() {
      if (currentLineText.startsWith('/')) {
        _suggestionsQuery = currentLineText.substring(1);
      } else {
        _suggestionsQuery = null;
      }
    });
  }

  List<String> _getFilteredSuggestions() {
    if (_suggestionsQuery == null || _suggestionsQuery!.isEmpty) {
      return _markdownSuggestions;
    }
    return _markdownSuggestions
        .where((s) => s.toLowerCase().contains(_suggestionsQuery!.toLowerCase()))
        .toList();
  }

  void _insertSuggestion(String suggestion) {
    final selection = _controller.selection;
    if (!selection.isValid) return;

    final text = _controller.text;
    final cursorPosition = selection.baseOffset;
    final lineStart = text.lastIndexOf('\n', cursorPosition - 1) + 1;

    final newText = text.replaceRange(lineStart, cursorPosition, suggestion);
    _controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(
        offset: lineStart + suggestion.length,
      ),
    );
    setState(() => _suggestionsQuery = null);
  }

  void _updateLineCount() {
    setState(() {
      _totalLines = '\n'.allMatches(_controller.text).length + 1;
      final cursorPos = _controller.selection.baseOffset;
      if (cursorPos >= 0) {
        _currentLine = '\n'
            .allMatches(_controller.text.substring(0, cursorPos))
            .length +
            1;
      }
    });
  }

  bool _isLineStart(int index) {
    final text = _controller.text;
    return index == 0 || text[index - 1] == '\n';
  }

  bool _isHeader(String line) {
    return line.trimLeft().startsWith('#');
  }

  void _toggleFold(int lineNumber) {
    final lines = _controller.text.split('\n');
    if (lineNumber >= lines.length) return;

    if (_isHeader(lines[lineNumber])) {
      setState(() {
        _foldedLines[lineNumber] = !(_foldedLines[lineNumber] ?? false);
      });
    }
  }

  String _getVisibleText() {
    final lines = _controller.text.split('\n');
    final visibleLines = <String>[];
    bool isHidden = false;

    for (var i = 0; i < lines.length; i++) {
      if (_isHeader(lines[i])) {
        isHidden = false;
        visibleLines.add(lines[i]);
      } else if (!isHidden) {
        visibleLines.add(lines[i]);
      }

      if (_foldedLines[i] ?? false) {
        isHidden = true;
      }
    }

    return visibleLines.join('\n');
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    _spellCheckDebouncer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.showLineNumbers)
                Container(
                  width: 48,
                  color: Theme.of(context).colorScheme.surfaceVariant,
                  padding: const EdgeInsets.only(right: 8),
                  child: ListView.builder(
                    controller: ScrollController()
                      ..addListener(() {
                        _scrollController.jumpTo(_scrollController.position.pixels);
                      }),
                    itemCount: _totalLines,
                    itemBuilder: (context, index) => GestureDetector(
                      onTap: () => _toggleFold(index),
                      child: Container(
                        height: 20,
                        alignment: Alignment.centerRight,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            if (_isHeader(_controller.text.split('\n')[index]))
                              Icon(
                                _foldedLines[index] ?? false
                                    ? Icons.chevron_right
                                    : Icons.expand_more,
                                size: 14,
                              ),
                            Text(
                              '${index + 1}',
                              style: TextStyle(
                                color: _currentLine == index + 1
                                    ? Theme.of(context).colorScheme.primary
                                    : Theme.of(context).colorScheme.onSurfaceVariant,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              Expanded(
                child: Stack(
                  children: [
                    _buildTextField(),
                    if (_suggestionsQuery != null)
                      _buildSuggestionsPanel(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTextField() {
    return Stack(
      children: [
        TextField(
          controller: _controller,
          focusNode: _focusNode,
          scrollController: _scrollController,
          maxLines: null,
          style: const TextStyle(
            fontFamily: 'monospace',
            fontSize: 14,
          ),
          decoration: InputDecoration(
            border: InputBorder.none,
            contentPadding: const EdgeInsets.all(8),
            // Add spell check underlines
            errorStyle: const TextStyle(
              decoration: TextDecoration.underline,
              decorationColor: Colors.red,
              decorationStyle: TextDecorationStyle.wavy,
            ),
          ),
          onChanged: (value) {
            _updateLineCount();
            _initializeSpellCheck();
          },
        ),
        // Overlay for spell check suggestions
        if (_spellCheckResults != null)
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: SpellCheckPainter(
                  text: _controller.text,
                  suggestions: _spellCheckResults!,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildSuggestionsPanel() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Card(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: _getFilteredSuggestions()
            .map((suggestion) => ListTile(
              dense: true,
              title: Text(suggestion),
              onTap: () => _insertSuggestion(suggestion),
            ))
            .toList(),
        ),
      ),
    );
  }
}

class SpellCheckPainter extends CustomPainter {
  final String text;
  final List<flutter_services.SuggestionSpan> suggestions;
  final TextStyle style;

  SpellCheckPainter({
    required this.text,
    required this.suggestions,
    required this.style,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.red
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    final textPainter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();

    for (final suggestion in suggestions) {
      final textSpan = TextSpan(
        text: text.substring(0, suggestion.range.start),
        style: style,
      );
      final beforePainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      )..layout();

      final misspelledWord = text.substring(
        suggestion.range.start,
        suggestion.range.end,
      );
      final wordSpan = TextSpan(
        text: misspelledWord,
        style: style,
      );
      final wordPainter = TextPainter(
        text: wordSpan,
        textDirection: TextDirection.ltr,
      )..layout();

      final startX = beforePainter.width;
      final startY = beforePainter.height;
      
      // Draw wavy underline
      var x = startX;
      final y = startY;
      final width = wordPainter.width;
      const waveHeight = 2.0;
      const waveWidth = 4.0;

      final path = Path();
      path.moveTo(x, y);
      
      var up = true;
      while (x < startX + width) {
        x += waveWidth;
        path.lineTo(
          x,
          y + (up ? waveHeight : -waveHeight),
        );
        up = !up;
      }

      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant SpellCheckPainter oldDelegate) {
    return text != oldDelegate.text ||
        suggestions != oldDelegate.suggestions ||
        style != oldDelegate.style;
  }
}