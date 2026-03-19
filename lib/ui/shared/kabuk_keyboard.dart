/// Custom virtual keyboard — a rich input panel with multiple modes.
///
/// Provides a keyboard replacement with support for:
/// - Standard QWERTY text input
/// - Emoji picker
/// - Gallery/media picker
/// - Voice recorder
/// - GIF search (placeholder)
///
/// This component overlays the OS keyboard by intercepting focus and
/// rendering its own input surface. It works with any [TextEditingController].
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kabuk/config/providers.dart';
import 'package:kabuk/ui/shared/markdown_toolbar.dart';
import 'package:kabuk/ui/theme.dart';

// =============================================================================
// Public API
// =============================================================================

/// The active mode of the virtual keyboard.
enum KeyboardMode {
  /// Hidden — OS or custom keyboard not visible.
  none,

  /// Standard QWERTY text input.
  text,

  /// Emoji picker grid.
  emoji,

  /// Gallery / media picker.
  gallery,

  /// Voice recorder.
  voice,
}

/// Provider tracking the active keyboard mode so other widgets can react.
final keyboardModeProvider = StateProvider<KeyboardMode>(
  (ref) => KeyboardMode.none,
);

// =============================================================================
// Language support
// =============================================================================

/// Supported keyboard languages with their layouts.
enum KeyboardLanguage {
  /// English — standard QWERTY layout.
  en('English', 'EN'),

  /// Turkish — QWERTY with additional characters.
  tr('Türkçe', 'TR'),

  /// French — AZERTY layout.
  fr('Français', 'FR'),

  /// German — QWERTZ layout with umlauts.
  de('Deutsch', 'DE'),

  /// Spanish — QWERTY with ñ.
  es('Español', 'ES'),

  /// Russian — standard Cyrillic layout.
  ru('Русский', 'RU'),

  /// Arabic — standard Arabic layout.
  ar('العربية', 'AR'),

  /// Portuguese — QWERTY with ç.
  pt('Português', 'PT');

  const KeyboardLanguage(this.displayName, this.code);

  /// Human-readable name in the language itself.
  final String displayName;

  /// Short ISO-style code for the mode bar indicator.
  final String code;
}

/// Provider tracking the selected keyboard language.
final keyboardLanguageProvider = StateProvider<KeyboardLanguage>(
  (ref) => KeyboardLanguage.en,
);

/// Keyboard layout definition: three rows of characters.
typedef _Layout = ({String row1, String row2, String row3});

/// Character layouts per language.
const Map<KeyboardLanguage, _Layout> _layouts = {
  KeyboardLanguage.en: (row1: 'qwertyuiop', row2: 'asdfghjkl', row3: 'zxcvbnm'),
  KeyboardLanguage.tr: (
    row1: 'qwertyuıopğü',
    row2: 'asdfghjklşi',
    row3: 'zxcvbnmöç',
  ),
  KeyboardLanguage.fr: (row1: 'azertyuiop', row2: 'qsdfghjklm', row3: 'wxcvbn'),
  KeyboardLanguage.de: (
    row1: 'qwertzuiopü',
    row2: 'asdfghjklöä',
    row3: 'yxcvbnmß',
  ),
  KeyboardLanguage.es: (
    row1: 'qwertyuiop',
    row2: 'asdfghjklñ',
    row3: 'zxcvbnm',
  ),
  KeyboardLanguage.ru: (
    row1: 'йцукенгшщзхъ',
    row2: 'фывапролджэ',
    row3: 'ячсмитьбю',
  ),
  KeyboardLanguage.ar: (
    row1: 'ضصثقفغعهخحجد',
    row2: 'شسيبلاتنمكط',
    row3: 'ئءؤرلاىةوز',
  ),
  KeyboardLanguage.pt: (
    row1: 'qwertyuiop',
    row2: 'asdfghjklç',
    row3: 'zxcvbnm',
  ),
};

/// A custom virtual keyboard panel with text, emoji, gallery, and voice modes.
///
/// Place this at the bottom of a layout, below the input bar. It takes a
/// `TextEditingController` to insert text/emoji at the cursor position.
///
/// When the mode is [KeyboardMode.none], the widget collapses to zero height.
///
/// Set [simple] to `true` for a lightweight variant that renders only a
/// themed text field using the system keyboard — no mode toolbar, send
/// button, emoji, gallery, or voice overlays.
class KabukKeyboard extends ConsumerStatefulWidget {
  /// Creates a [KabukKeyboard].
  const KabukKeyboard({
    required this.controller,
    this.focusNode,
    this.onMediaSelected,
    this.onVoiceRecorded,
    this.onSend,
    this.onAttachment,
    this.onChanged,
    this.onSubmitted,
    this.hintText = 'Ask anything\u2026',
    this.enabled = true,
    this.simple = false,
    this.maxLines,
    this.autofocus = false,
    super.key,
  });

  /// The text controller to insert characters into.
  final TextEditingController controller;

  /// The text field's focus node — used to prevent OS keyboard from showing.
  ///
  /// Optional in [simple] mode; the system [TextField] creates its own when
  /// this is `null`.
  final FocusNode? focusNode;

  /// Called when the user picks media from the gallery panel.
  final ValueChanged<List<String>>? onMediaSelected;

  /// Called when a voice recording is completed with the file path.
  final ValueChanged<String>? onVoiceRecorded;

  /// Called when the user taps the send button.
  final VoidCallback? onSend;

  /// Called when the user taps the attachment button in the mode bar.
  final VoidCallback? onAttachment;

  /// Called when the text changes.
  final ValueChanged<String>? onChanged;

  /// Called when the user submits (e.g. presses enter/done on the keyboard).
  final ValueChanged<String>? onSubmitted;

  /// Hint text shown in the embedded text field.
  final String hintText;

  /// Whether the input is interactive.
  final bool enabled;

  /// When `true`, renders a lightweight text field with no mode toolbar,
  /// send button, or overlay panels. Uses the system keyboard.
  final bool simple;

  /// Maximum lines for the text field.
  ///
  /// Defaults to `1` in [simple] mode, `5` in full mode.
  final int? maxLines;

  /// Whether the text field should be focused on build.
  final bool autofocus;

  @override
  ConsumerState<KabukKeyboard> createState() => _KabukKeyboardState();
}

class _KabukKeyboardState extends ConsumerState<KabukKeyboard> {
  static const _keyboardHeight = 235.0;
  static const _emojiHeight = 270.0;
  static const _galleryHeight = 300.0;
  static const _voiceHeight = 180.0;

  KeyboardMode _previousMode = KeyboardMode.none;
  bool _showToolbar = false;
  bool _hasText = false;

  double _targetHeight(KeyboardMode mode) => switch (mode) {
    KeyboardMode.none => 0,
    KeyboardMode.text => _keyboardHeight,
    KeyboardMode.emoji => _emojiHeight,
    KeyboardMode.gallery => _galleryHeight,
    KeyboardMode.voice => _voiceHeight,
  };

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    super.dispose();
  }

  void _onTextChanged() {
    final hasText = widget.controller.text.trim().isNotEmpty;
    if (hasText != _hasText) setState(() => _hasText = hasText);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.simple) return _buildSimpleInput();

    final mode = ref.watch(keyboardModeProvider);
    final panelHeight = _targetHeight(mode);
    final isOpening =
        _previousMode == KeyboardMode.none && mode != KeyboardMode.none;
    final isClosing = mode == KeyboardMode.none;
    final isCustomKeyboardActive = mode != KeyboardMode.none;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _previousMode = mode;
    });

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Embedded input field.
        _buildInputRow(isCustomKeyboardActive),
        // Collapsible markdown toolbar.
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          child: _showToolbar
              ? MarkdownToolbar(
                  controller: widget.controller,
                  focusNode: widget.focusNode,
                  compact: true,
                )
              : const SizedBox.shrink(),
        ),
        // Mode selector bar.
        KeyboardModeBar(onAttachment: widget.onAttachment),
        // Panel.
        AnimatedContainer(
          duration: Duration(milliseconds: isOpening || isClosing ? 300 : 200),
          curve: isClosing
              ? Curves.easeInCubic
              : isOpening
              ? Curves.easeOutBack
              : Curves.easeOutCubic,
          height: panelHeight,
          clipBehavior: Clip.hardEdge,
          decoration: const BoxDecoration(),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            transitionBuilder: (child, animation) =>
                FadeTransition(opacity: animation, child: child),
            child: panelHeight > 0
                ? KeyedSubtree(key: ValueKey(mode), child: _buildPanel(mode))
                : const SizedBox.shrink(),
          ),
        ),
      ],
    );
  }

  /// Lightweight text field — no toolbar, no send button, system keyboard.
  Widget _buildSimpleInput() {
    return TextField(
      controller: widget.controller,
      focusNode: widget.focusNode,
      enabled: widget.enabled,
      autofocus: widget.autofocus,
      maxLines: widget.maxLines ?? 1,
      minLines: 1,
      onChanged: widget.onChanged,
      onSubmitted: widget.onSubmitted,
      style: const TextStyle(color: KabukTheme.textPrimary, fontSize: 14),
      decoration: InputDecoration(
        hintText: widget.hintText,
        hintStyle: const TextStyle(
          color: KabukTheme.textSecondary,
          fontSize: 14,
        ),
        filled: true,
        fillColor: KabukTheme.surfaceVariant,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  Widget _buildInputRow(bool isCustomKeyboardActive) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: KabukTheme.spacingSm,
        vertical: KabukTheme.spacingXs,
      ),
      child: _EnterInterceptor(
        onEnter: () {
          if (_hasText) widget.onSend?.call();
        },
        child: TextField(
          controller: widget.controller,
          focusNode: widget.focusNode,
          enabled: widget.enabled,
          readOnly: isCustomKeyboardActive,
          showCursor: true,
          textInputAction: TextInputAction.newline,
          maxLines: widget.maxLines ?? 5,
          minLines: 1,
          autofocus: widget.autofocus,
          onTap: () {
            if (isCustomKeyboardActive) {
              ref.read(keyboardModeProvider.notifier).state = KeyboardMode.none;
            } else {
              // Auto-activate text keyboard when tapping the input.
              ref.read(keyboardModeProvider.notifier).state = KeyboardMode.text;
            }
          },
          style: const TextStyle(color: KabukTheme.textPrimary, fontSize: 14),
          decoration: InputDecoration(
            hintText: widget.hintText,
            hintStyle: const TextStyle(
              color: KabukTheme.textSecondary,
              fontSize: 14,
            ),
            filled: true,
            fillColor: KabukTheme.surfaceVariant,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
            prefixIcon: Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Tooltip(
                message: _showToolbar
                    ? 'Hide formatting toolbar'
                    : 'Show formatting toolbar',
                child: GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _showToolbar = !_showToolbar);
                  },
                  child: Icon(
                    _showToolbar
                        ? Icons.keyboard_arrow_down_rounded
                        : Icons.text_format_rounded,
                    size: 20,
                    color: _showToolbar
                        ? KabukTheme.accentGreen
                        : KabukTheme.textSecondary,
                  ),
                ),
              ),
            ),
            prefixIconConstraints: const BoxConstraints(
              minWidth: 32,
              minHeight: 0,
            ),
            suffixIcon: _hasText
                ? GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => widget.onSend?.call(),
                    child: Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: const BoxDecoration(
                          color: KabukTheme.primaryGreen,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.arrow_upward,
                          size: 18,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  )
                : null,
            suffixIconConstraints: const BoxConstraints(
              minWidth: 40,
              minHeight: 40,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(20),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPanel(KeyboardMode mode) => switch (mode) {
    KeyboardMode.none => const SizedBox.shrink(),
    KeyboardMode.text => TextKeyboardPanel(
      controller: widget.controller,
      onSend: widget.onSend,
      hasText: _hasText,
    ),
    KeyboardMode.emoji => _EmojiPanel(controller: widget.controller),
    KeyboardMode.gallery => _GalleryPanel(
      onMediaSelected: widget.onMediaSelected,
    ),
    KeyboardMode.voice => _VoicePanel(onVoiceRecorded: widget.onVoiceRecorded),
  };
}

// =============================================================================
// Mode selector bar
// =============================================================================

/// A row of mode buttons placed above or inside the input bar.
///
/// Toggles between keyboard modes. When the active mode is tapped again,
/// it collapses the keyboard (sets mode to [KeyboardMode.none]).
class KeyboardModeBar extends ConsumerWidget {
  /// Creates a [KeyboardModeBar].
  const KeyboardModeBar({this.onAttachment, super.key});

  /// Called when the user taps the attachment button.
  final VoidCallback? onAttachment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(keyboardModeProvider);

    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: KabukTheme.spacingSm),
      child: Row(
        children: [
          _ModeButton(
            icon: Icons.keyboard_rounded,
            label: 'Keyboard',
            isActive: mode == KeyboardMode.text,
            onTap: () => _toggle(ref, KeyboardMode.text),
          ),
          _ModeButton(
            icon: Icons.emoji_emotions_outlined,
            label: 'Emoji',
            isActive: mode == KeyboardMode.emoji,
            onTap: () => _toggle(ref, KeyboardMode.emoji),
          ),
          _ModeButton(
            icon: Icons.photo_library_outlined,
            label: 'Gallery',
            isActive: mode == KeyboardMode.gallery,
            onTap: () => _toggle(ref, KeyboardMode.gallery),
          ),
          _ModeButton(
            icon: Icons.mic_rounded,
            label: 'Voice',
            isActive: mode == KeyboardMode.voice,
            onTap: () => _toggle(ref, KeyboardMode.voice),
          ),
          if (onAttachment != null)
            _ModeButton(
              icon: Icons.attach_file_rounded,
              label: 'Attach',
              isActive: false,
              onTap: onAttachment!,
            ),
        ],
      ),
    );
  }

  void _toggle(WidgetRef ref, KeyboardMode target) {
    final current = ref.read(keyboardModeProvider);
    ref.read(keyboardModeProvider.notifier).state = current == target
        ? KeyboardMode.none
        : target;
  }
}

class _ModeButton extends StatelessWidget {
  const _ModeButton({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Tooltip(
        message: label,
        child: InkWell(
          borderRadius: BorderRadius.circular(KabukTheme.radiusSm),
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          child: Container(
            alignment: Alignment.center,
            child: Icon(
              icon,
              size: 22,
              color: isActive
                  ? KabukTheme.accentGreen
                  : KabukTheme.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Keyboard attachment — reusable keyboard for any text field
// =============================================================================

/// A keyboard panel that attaches to an external [TextEditingController].
///
/// Unlike [KabukKeyboard] which wraps its own [TextField], this widget
/// provides only the mode bar and keyboard panels. Use it when you have
/// your own text fields (e.g. a document editor with title + body fields)
/// and want to add the custom keyboard at the bottom.
///
/// The [controller] should point to whichever text field is currently active.
///
/// When [showMarkdownToolbar] is true, a markdown formatting toolbar is
/// shown above the mode bar for quick access to formatting shortcuts.
class KabukKeyboardAttachment extends ConsumerWidget {
  /// Creates a [KabukKeyboardAttachment].
  const KabukKeyboardAttachment({
    required this.controller,
    this.onSend,
    this.onMediaSelected,
    this.onVoiceRecorded,
    this.showMarkdownToolbar = false,
    this.markdownFocusNode,
    super.key,
  });

  /// The active [TextEditingController] to insert characters into.
  final TextEditingController controller;

  /// Called when the user taps send (return key in text mode).
  final VoidCallback? onSend;

  /// Called when the user picks media from the gallery panel.
  final ValueChanged<List<String>>? onMediaSelected;

  /// Called when a voice recording is completed.
  final ValueChanged<String>? onVoiceRecorded;

  /// Whether to show a markdown formatting toolbar above the mode bar.
  final bool showMarkdownToolbar;

  /// Focus node to refocus after formatting actions.
  final FocusNode? markdownFocusNode;

  static const _keyboardHeight = 235.0;
  static const _emojiHeight = 270.0;
  static const _galleryHeight = 300.0;
  static const _voiceHeight = 180.0;

  double _targetHeight(KeyboardMode mode) => switch (mode) {
    KeyboardMode.none => 0,
    KeyboardMode.text => _keyboardHeight,
    KeyboardMode.emoji => _emojiHeight,
    KeyboardMode.gallery => _galleryHeight,
    KeyboardMode.voice => _voiceHeight,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(keyboardModeProvider);
    final panelHeight = _targetHeight(mode);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Markdown formatting toolbar (when enabled and keyboard is active).
        if (showMarkdownToolbar && mode != KeyboardMode.none)
          MarkdownToolbar(
            controller: controller,
            focusNode: markdownFocusNode,
          ),
        const KeyboardModeBar(),
        AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          height: panelHeight,
          clipBehavior: Clip.hardEdge,
          decoration: const BoxDecoration(),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: panelHeight > 0
                ? KeyedSubtree(
                    key: ValueKey(mode),
                    child: _buildPanel(mode),
                  )
                : const SizedBox.shrink(),
          ),
        ),
      ],
    );
  }

  Widget _buildPanel(KeyboardMode mode) => switch (mode) {
    KeyboardMode.none => const SizedBox.shrink(),
    KeyboardMode.text => TextKeyboardPanel(
      controller: controller,
      onSend: onSend,
      hasText: controller.text.trim().isNotEmpty,
    ),
    KeyboardMode.emoji => _EmojiPanel(controller: controller),
    KeyboardMode.gallery => _GalleryPanel(
      onMediaSelected: onMediaSelected,
    ),
    KeyboardMode.voice => _VoicePanel(onVoiceRecorded: onVoiceRecorded),
  };
}

// =============================================================================
// Text keyboard panel
// =============================================================================

/// Text keyboard panel with multi-language layout support.
///
/// Can be used standalone via [KabukKeyboardAttachment] to attach the custom
/// keyboard to any [TextEditingController] — not just [KabukKeyboard]'s own
/// text field.
class TextKeyboardPanel extends ConsumerStatefulWidget {
  /// Creates a [TextKeyboardPanel].
  const TextKeyboardPanel({
    required this.controller,
    this.onSend,
    this.hasText = false,
    super.key,
  });

  final TextEditingController controller;
  final VoidCallback? onSend;
  final bool hasText;

  @override
  ConsumerState<TextKeyboardPanel> createState() => _TextKeyboardPanelState();
}

class _TextKeyboardPanelState extends ConsumerState<TextKeyboardPanel> {
  bool _isShifted = false;
  bool _isSymbol = false;

  static const _symbols1 = '1234567890';
  static const _symbols2 = r'@#$_&-+()/';
  static const _symbols3 = "*\"',:;!?";

  void _insertChar(String char) {
    final text = widget.controller.text;
    final selection = widget.controller.selection;
    final newText = text.replaceRange(selection.start, selection.end, char);
    widget.controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: selection.start + char.length),
    );
    if (_isShifted) setState(() => _isShifted = false);
  }

  void _backspace() {
    final text = widget.controller.text;
    final selection = widget.controller.selection;
    if (selection.start == 0 && selection.end == 0) return;

    if (selection.start != selection.end) {
      final newText = text.replaceRange(selection.start, selection.end, '');
      widget.controller.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: selection.start),
      );
    } else {
      final newText = text.replaceRange(
        selection.start - 1,
        selection.start,
        '',
      );
      widget.controller.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: selection.start - 1),
      );
    }
    HapticFeedback.lightImpact();
  }

  @override
  Widget build(BuildContext context) {
    final lang = ref.watch(keyboardLanguageProvider);
    final layout = _layouts[lang]!;
    final isRtl = lang == KeyboardLanguage.ar;

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1C1C1E),
        border: Border(top: BorderSide(color: Colors.white10, width: 0.5)),
      ),
      child: Directionality(
        textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
        child: Column(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  transitionBuilder: (child, animation) =>
                      FadeTransition(opacity: animation, child: child),
                  child: KeyedSubtree(
                    key: ValueKey((_isSymbol, lang)),
                    child: _isSymbol
                        ? _buildSymbolLayout()
                        : _buildLetterLayout(layout),
                  ),
                ),
              ),
            ),
            _buildBottomRow(lang),
          ],
        ),
      ),
    );
  }

  Widget _buildLetterLayout(_Layout layout) {
    return Column(
      children: [
        _buildKeyRow(layout.row1),
        _buildKeyRow(layout.row2, indent: true),
        _buildRow3(layout.row3),
      ],
    );
  }

  Widget _buildSymbolLayout() {
    return Column(
      children: [
        _buildKeyRow(_symbols1),
        _buildKeyRow(_symbols2),
        _buildRow3Symbols(),
      ],
    );
  }

  Widget _buildKeyRow(String keys, {bool indent = false}) {
    return Expanded(
      child: Row(
        children: [
          if (indent) const SizedBox(width: 14),
          ...keys
              .split('')
              .map(
                (k) => Expanded(
                  child: _KeyButton(
                    label: _isShifted ? k.toUpperCase() : k,
                    onTap: () => _insertChar(_isShifted ? k.toUpperCase() : k),
                  ),
                ),
              ),
          if (indent) const SizedBox(width: 14),
        ],
      ),
    );
  }

  Widget _buildRow3(String row3) {
    return Expanded(
      child: Row(
        children: [
          SizedBox(
            width: 44,
            child: _KeyButton(
              icon: _isShifted
                  ? Icons.keyboard_capslock
                  : Icons.keyboard_arrow_up,
              onTap: () => setState(() => _isShifted = !_isShifted),
              isActive: _isShifted,
              isSpecial: true,
            ),
          ),
          ...row3
              .split('')
              .map(
                (k) => Expanded(
                  child: _KeyButton(
                    label: _isShifted ? k.toUpperCase() : k,
                    onTap: () => _insertChar(_isShifted ? k.toUpperCase() : k),
                  ),
                ),
              ),
          SizedBox(
            width: 44,
            child: _KeyButton(
              icon: Icons.backspace_outlined,
              onTap: _backspace,
              onLongPress: () {
                widget.controller.clear();
                HapticFeedback.heavyImpact();
              },
              isSpecial: true,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRow3Symbols() {
    return Expanded(
      child: Row(
        children: [
          const SizedBox(width: 44),
          ..._symbols3
              .split('')
              .map(
                (k) => Expanded(
                  child: _KeyButton(label: k, onTap: () => _insertChar(k)),
                ),
              ),
          SizedBox(
            width: 44,
            child: _KeyButton(
              icon: Icons.backspace_outlined,
              onTap: _backspace,
              isSpecial: true,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null && data!.text!.isNotEmpty) {
      _insertChar(data.text!);
      HapticFeedback.mediumImpact();
    }
  }

  void _copy() {
    final selection = widget.controller.selection;
    if (selection.start != selection.end) {
      final text = widget.controller.text;
      Clipboard.setData(
        ClipboardData(text: text.substring(selection.start, selection.end)),
      );
      HapticFeedback.mediumImpact();
    }
  }

  void _cut() {
    final selection = widget.controller.selection;
    if (selection.start != selection.end) {
      final text = widget.controller.text;
      Clipboard.setData(
        ClipboardData(text: text.substring(selection.start, selection.end)),
      );
      final newText = text.replaceRange(selection.start, selection.end, '');
      widget.controller.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: selection.start),
      );
      HapticFeedback.mediumImpact();
    }
  }

  void _selectAll() {
    widget.controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: widget.controller.text.length,
    );
    HapticFeedback.selectionClick();
  }

  Widget _buildBottomRow(KeyboardLanguage lang) {
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
      child: Row(
        children: [
          // Symbol toggle.
          SizedBox(
            width: 44,
            child: _KeyButton(
              label: _isSymbol ? 'ABC' : '123',
              onTap: () => setState(() => _isSymbol = !_isSymbol),
              fontSize: 13,
              isSpecial: true,
            ),
          ),
          // Emoji button.
          SizedBox(
            width: 40,
            child: _KeyButton(
              icon: Icons.emoji_emotions_outlined,
              onTap: () {
                ref.read(keyboardModeProvider.notifier).state =
                    KeyboardMode.emoji;
              },
            ),
          ),
          // Comma key.
          SizedBox(
            width: 36,
            child: _KeyButton(label: ',', onTap: () => _insertChar(',')),
          ),
          // Language selector.
          SizedBox(
            width: 36,
            child: _KeyButton(icon: Icons.language, onTap: _showLanguagePicker),
          ),
          // Space bar (long-press for clipboard menu).
          Expanded(
            child: _KeyButton(
              label: lang.code,
              onTap: () => _insertChar(' '),
              onLongPress: () => _showClipboardMenu(context),
              fontSize: 12,
            ),
          ),
          // Period.
          SizedBox(
            width: 36,
            child: _KeyButton(label: '.', onTap: () => _insertChar('.')),
          ),
          // Send / return key.
          SizedBox(
            width: 48,
            child: _KeyButton(
              icon: widget.hasText
                  ? Icons.arrow_upward
                  : Icons.keyboard_return_rounded,
              onTap: () {
                if (widget.hasText && widget.onSend != null) {
                  widget.onSend!();
                } else {
                  _insertChar('\n');
                }
              },
              isActive: widget.hasText,
            ),
          ),
        ],
      ),
    );
  }

  void _showClipboardMenu(BuildContext context) {
    HapticFeedback.mediumImpact();
    final hasSelection =
        widget.controller.selection.start != widget.controller.selection.end;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: KabukTheme.surfaceElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(KabukTheme.radiusMd),
        ),
      ),
      builder: (ctx) => SafeArea(
        bottom: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(KabukTheme.spacingMd),
              child: Text(
                'Clipboard',
                style: TextStyle(
                  color: KabukTheme.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const Divider(height: 1, color: KabukTheme.divider),
            ListTile(
              leading: const Icon(
                Icons.content_paste_rounded,
                color: KabukTheme.textSecondary,
                size: 20,
              ),
              title: const Text(
                'Paste',
                style: TextStyle(color: KabukTheme.textPrimary, fontSize: 14),
              ),
              onTap: () {
                Navigator.of(ctx).pop();
                _paste();
              },
            ),
            if (hasSelection) ...[
              ListTile(
                leading: const Icon(
                  Icons.content_copy_rounded,
                  color: KabukTheme.textSecondary,
                  size: 20,
                ),
                title: const Text(
                  'Copy',
                  style:
                      TextStyle(color: KabukTheme.textPrimary, fontSize: 14),
                ),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _copy();
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.content_cut_rounded,
                  color: KabukTheme.textSecondary,
                  size: 20,
                ),
                title: const Text(
                  'Cut',
                  style:
                      TextStyle(color: KabukTheme.textPrimary, fontSize: 14),
                ),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _cut();
                },
              ),
            ],
            ListTile(
              leading: const Icon(
                Icons.select_all_rounded,
                color: KabukTheme.textSecondary,
                size: 20,
              ),
              title: const Text(
                'Select all',
                style: TextStyle(color: KabukTheme.textPrimary, fontSize: 14),
              ),
              onTap: () {
                Navigator.of(ctx).pop();
                _selectAll();
              },
            ),
            const SizedBox(height: KabukTheme.spacingSm),
          ],
        ),
      ),
    );
  }

  void _showLanguagePicker() {
    final currentLang = ref.read(keyboardLanguageProvider);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: KabukTheme.surfaceElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(KabukTheme.radiusMd),
        ),
      ),
      builder: (ctx) => SafeArea(
        bottom: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(KabukTheme.spacingMd),
              child: Text(
                'Keyboard Language',
                style: TextStyle(
                  color: KabukTheme.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const Divider(height: 1, color: KabukTheme.divider),
            ...KeyboardLanguage.values.map(
              (lang) => ListTile(
                leading: Text(
                  lang.code,
                  style: TextStyle(
                    color: lang == currentLang
                        ? KabukTheme.accentGreen
                        : KabukTheme.textSecondary,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                title: Text(
                  lang.displayName,
                  style: TextStyle(
                    color: lang == currentLang
                        ? KabukTheme.accentGreen
                        : KabukTheme.textPrimary,
                  ),
                ),
                trailing: lang == currentLang
                    ? const Icon(Icons.check, color: KabukTheme.accentGreen)
                    : null,
                onTap: () {
                  ref.read(keyboardLanguageProvider.notifier).state = lang;
                  Navigator.of(ctx).pop();
                },
              ),
            ),
            const SizedBox(height: KabukTheme.spacingSm),
          ],
        ),
      ),
    );
  }
}


/// A single keyboard key button with press animation and GBoard-style depth.
class _KeyButton extends StatefulWidget {
  const _KeyButton({
    this.label,
    this.icon,
    required this.onTap,
    this.onLongPress,
    this.isActive = false,
    this.isSpecial = false,
    this.fontSize = 17,
  });

  final String? label;
  final IconData? icon;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool isActive;

  /// Whether this is a special key (shift, backspace, 123) with darker bg.
  final bool isSpecial;
  final double fontSize;

  @override
  State<_KeyButton> createState() => _KeyButtonState();
}

class _KeyButtonState extends State<_KeyButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final bgColor = _pressed
        ? const Color(0xFF5A5A5C)
        : widget.isActive
            ? KabukTheme.accentGreen.withAlpha(40)
            : widget.isSpecial
                ? const Color(0xFF2C2C2E)
                : const Color(0xFF3A3A3C);

    return Padding(
      padding: const EdgeInsets.all(2.0),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) {
          setState(() => _pressed = false);
          HapticFeedback.lightImpact();
          widget.onTap();
        },
        onTapCancel: () => setState(() => _pressed = false),
        onLongPress: widget.onLongPress,
        onLongPressEnd: (_) => setState(() => _pressed = false),
        child: AnimatedScale(
          scale: _pressed ? 0.95 : 1.0,
          duration: Duration(milliseconds: _pressed ? 40 : 120),
          curve: _pressed ? Curves.easeIn : Curves.easeOutBack,
          child: AnimatedContainer(
            duration: Duration(milliseconds: _pressed ? 40 : 100),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(8),
              boxShadow: _pressed
                  ? null
                  : const [
                      BoxShadow(
                        color: Colors.black26,
                        offset: Offset(0, 1),
                        blurRadius: 0,
                      ),
                    ],
            ),
            child: Center(
              child: widget.icon != null
                  ? Icon(
                      widget.icon,
                      size: 18,
                      color: widget.isActive
                          ? KabukTheme.accentGreen
                          : KabukTheme.textPrimary,
                    )
                  : Text(
                      widget.label!,
                      style: TextStyle(
                        color: widget.isActive
                            ? KabukTheme.accentGreen
                            : KabukTheme.textPrimary,
                        fontSize: widget.fontSize,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Emoji panel
// =============================================================================

/// Emoji picker grid organized by categories.
class _EmojiPanel extends StatefulWidget {
  const _EmojiPanel({required this.controller});

  final TextEditingController controller;

  @override
  State<_EmojiPanel> createState() => _EmojiPanelState();
}

class _EmojiPanelState extends State<_EmojiPanel> {
  int _selectedCategory = 0;

  // Emoji categories with representative emojis.
  static const _categories =
      <({String name, IconData icon, List<String> emojis})>[
        (
          name: 'Smileys',
          icon: Icons.emoji_emotions_outlined,
          emojis: [
            '😀',
            '😃',
            '😄',
            '😁',
            '😆',
            '😅',
            '🤣',
            '😂',
            '🙂',
            '🙃',
            '😉',
            '😊',
            '😇',
            '🥰',
            '😍',
            '🤩',
            '😘',
            '😗',
            '😚',
            '😙',
            '🥲',
            '😋',
            '😛',
            '😜',
            '🤪',
            '😝',
            '🤑',
            '🤗',
            '🤭',
            '🤫',
            '🤔',
            '🫡',
            '🤐',
            '🤨',
            '😐',
            '😑',
            '😶',
            '🫥',
            '😏',
            '😒',
            '🙄',
            '😬',
            '🤥',
            '😌',
            '😔',
            '😪',
            '🤤',
            '😴',
            '😷',
            '🤒',
            '🤕',
            '🤢',
            '🤮',
            '🥵',
            '🥶',
            '🥴',
            '😵',
            '🤯',
            '🤠',
            '🥳',
            '🥸',
            '😎',
            '🤓',
            '🧐',
            '😕',
            '🫤',
            '😟',
            '🙁',
            '😮',
            '😯',
            '😲',
            '😳',
            '🥺',
            '🥹',
            '😦',
            '😧',
            '😨',
            '😰',
            '😥',
            '😢',
            '😭',
            '😱',
            '😖',
            '😣',
            '😞',
            '😓',
            '😩',
            '😫',
            '🥱',
            '😤',
            '😡',
            '😠',
            '🤬',
            '😈',
            '👿',
            '💀',
            '☠️',
            '💩',
            '🤡',
            '👹',
          ],
        ),
        (
          name: 'Gestures',
          icon: Icons.waving_hand_outlined,
          emojis: [
            '👋',
            '🤚',
            '🖐️',
            '✋',
            '🖖',
            '🫱',
            '🫲',
            '🫳',
            '🫴',
            '🫷',
            '🫸',
            '👌',
            '🤌',
            '🤏',
            '✌️',
            '🤞',
            '🫰',
            '🤟',
            '🤘',
            '🤙',
            '👈',
            '👉',
            '👆',
            '🖕',
            '👇',
            '☝️',
            '🫵',
            '👍',
            '👎',
            '✊',
            '👊',
            '🤛',
            '🤜',
            '👏',
            '🙌',
            '🫶',
            '👐',
            '🤲',
            '🤝',
            '🙏',
            '✍️',
            '💅',
            '🤳',
            '💪',
            '🦾',
            '🦵',
            '🦿',
            '🦶',
            '👣',
            '👂',
          ],
        ),
        (
          name: 'Hearts',
          icon: Icons.favorite_outline,
          emojis: [
            '❤️',
            '🧡',
            '💛',
            '💚',
            '💙',
            '💜',
            '🖤',
            '🤍',
            '🤎',
            '💔',
            '❤️‍🔥',
            '❤️‍🩹',
            '❣️',
            '💕',
            '💞',
            '💓',
            '💗',
            '💖',
            '💘',
            '💝',
            '💟',
            '♥️',
            '🫀',
            '💋',
            '💌',
            '💐',
            '🌹',
            '🥀',
            '🌺',
            '🌸',
          ],
        ),
        (
          name: 'Nature',
          icon: Icons.eco_outlined,
          emojis: [
            '🐶',
            '🐱',
            '🐭',
            '🐹',
            '🐰',
            '🦊',
            '🐻',
            '🐼',
            '🐻‍❄️',
            '🐨',
            '🐯',
            '🦁',
            '🐮',
            '🐷',
            '🐽',
            '🐸',
            '🐵',
            '🙈',
            '🙉',
            '🙊',
            '🐔',
            '🐧',
            '🐦',
            '🐤',
            '🦆',
            '🦅',
            '🦉',
            '🦇',
            '🐺',
            '🐗',
            '🐴',
            '🦄',
            '🐝',
            '🪱',
            '🐛',
            '🦋',
            '🐌',
            '🐞',
            '🐜',
            '🪲',
            '🌲',
            '🌳',
            '🌴',
            '🌵',
            '🌾',
            '🌿',
            '☘️',
            '🍀',
            '🍁',
            '🍂',
            '🍃',
            '🌍',
            '🌎',
            '🌏',
            '🌕',
            '⭐',
            '🌟',
            '⚡',
            '🔥',
            '💧',
          ],
        ),
        (
          name: 'Food',
          icon: Icons.restaurant_outlined,
          emojis: [
            '🍎',
            '🍐',
            '🍊',
            '🍋',
            '🍌',
            '🍉',
            '🍇',
            '🍓',
            '🫐',
            '🍈',
            '🍒',
            '🍑',
            '🥭',
            '🍍',
            '🥥',
            '🥝',
            '🍅',
            '🍆',
            '🥑',
            '🥦',
            '🌶️',
            '🫑',
            '🌽',
            '🥕',
            '🧄',
            '🧅',
            '🥔',
            '🍠',
            '🫘',
            '🥐',
            '🍞',
            '🥖',
            '🥨',
            '🧀',
            '🥚',
            '🍳',
            '🧈',
            '🥞',
            '🧇',
            '🥓',
            '🍔',
            '🍟',
            '🍕',
            '🌭',
            '🥪',
            '🌮',
            '🌯',
            '🫔',
            '🥙',
            '🧆',
            '🍜',
            '🍝',
            '🍣',
            '🍱',
            '🥟',
            '🍙',
            '🍚',
            '🍛',
            '🍲',
            '🍩',
          ],
        ),
        (
          name: 'Objects',
          icon: Icons.lightbulb_outline,
          emojis: [
            '⌚',
            '📱',
            '💻',
            '⌨️',
            '🖥️',
            '🖨️',
            '🖱️',
            '💽',
            '💾',
            '💿',
            '📷',
            '📹',
            '🎥',
            '📽️',
            '🎞️',
            '📞',
            '☎️',
            '📟',
            '📠',
            '📺',
            '📻',
            '🎙️',
            '🎚️',
            '🎛️',
            '🧭',
            '⏱️',
            '⏲️',
            '⏰',
            '🕰️',
            '⌛',
            '📡',
            '🔋',
            '🪫',
            '🔌',
            '💡',
            '🔦',
            '🕯️',
            '🧯',
            '🛢️',
            '💸',
            '💵',
            '💴',
            '💶',
            '💷',
            '🪙',
            '💰',
            '💳',
            '💎',
            '⚖️',
            '🪜',
            '🧰',
            '🪛',
            '🔧',
            '🔨',
            '⚒️',
            '🛠️',
            '⛏️',
            '🪚',
            '🔩',
            '⚙️',
          ],
        ),
        (
          name: 'Symbols',
          icon: Icons.tag,
          emojis: [
            '✅',
            '❌',
            '❓',
            '❗',
            '‼️',
            '⁉️',
            '💯',
            '🔴',
            '🟠',
            '🟡',
            '🟢',
            '🔵',
            '🟣',
            '⚫',
            '⚪',
            '🟤',
            '🔺',
            '🔻',
            '🔷',
            '🔶',
            '▶️',
            '⏸️',
            '⏹️',
            '⏺️',
            '⏭️',
            '⏮️',
            '⏩',
            '⏪',
            '🔀',
            '🔁',
            '🔂',
            '🔄',
            '⬆️',
            '⬇️',
            '➡️',
            '⬅️',
            '↗️',
            '↘️',
            '↙️',
            '↖️',
            '🆕',
            '🆓',
            '🆙',
            '🔝',
            '🔜',
            '🔚',
            '🔛',
            '🏁',
            '🚩',
            '🎌',
            '🏴',
            '🏳️',
            '🏳️‍🌈',
            '🏳️‍⚧️',
            '🏴‍☠️',
            '♻️',
            '✨',
            '🎉',
            '🎊',
            '🎈',
          ],
        ),
      ];

  @override
  Widget build(BuildContext context) {
    final cat = _categories[_selectedCategory];

    return Container(
      color: KabukTheme.surface,
      child: Column(
        children: [
          const Divider(height: 1, color: KabukTheme.divider),
          // Category tabs
          SizedBox(
            height: 40,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _categories.length,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              itemBuilder: (context, index) {
                final c = _categories[index];
                final isSelected = index == _selectedCategory;
                return Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 2,
                    vertical: 4,
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(KabukTheme.radiusSm),
                    onTap: () => setState(() => _selectedCategory = index),
                    child: Container(
                      width: 40,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(
                          KabukTheme.radiusSm,
                        ),
                        color: isSelected
                            ? KabukTheme.accentGreen.withAlpha(30)
                            : Colors.transparent,
                      ),
                      child: Icon(
                        c.icon,
                        size: 20,
                        color: isSelected
                            ? KabukTheme.accentGreen
                            : KabukTheme.textSecondary,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const Divider(height: 1, color: KabukTheme.divider),
          // Emoji grid
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(8),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 8,
                mainAxisSpacing: 4,
                crossAxisSpacing: 4,
              ),
              itemCount: cat.emojis.length,
              itemBuilder: (context, index) {
                final emoji = cat.emojis[index];
                return InkWell(
                  borderRadius: BorderRadius.circular(6),
                  onTap: () {
                    HapticFeedback.selectionClick();
                    _insertEmoji(emoji);
                  },
                  child: Center(
                    child: Text(emoji, style: const TextStyle(fontSize: 24)),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _insertEmoji(String emoji) {
    final text = widget.controller.text;
    final selection = widget.controller.selection;
    final newText = text.replaceRange(selection.start, selection.end, emoji);
    widget.controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(
        offset: selection.start + emoji.length,
      ),
    );
  }
}

// =============================================================================
// Gallery panel
// =============================================================================

/// Gallery picker panel showing recent photos from the device.
class _GalleryPanel extends ConsumerWidget {
  const _GalleryPanel({this.onMediaSelected});

  final ValueChanged<List<String>>? onMediaSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      color: KabukTheme.surface,
      child: Column(
        children: [
          const Divider(height: 1, color: KabukTheme.divider),
          // Action buttons row
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: KabukTheme.spacingMd,
              vertical: KabukTheme.spacingSm,
            ),
            child: Row(
              children: [
                _GalleryAction(
                  icon: Icons.photo_library_rounded,
                  label: 'Gallery',
                  onTap: () => _pickImages(ref),
                ),
                const SizedBox(width: KabukTheme.spacingMd),
                _GalleryAction(
                  icon: Icons.camera_alt_rounded,
                  label: 'Camera',
                  onTap: () => _takePhoto(ref),
                ),
                const SizedBox(width: KabukTheme.spacingMd),
                _GalleryAction(
                  icon: Icons.videocam_rounded,
                  label: 'Video',
                  onTap: () => _takeVideo(ref),
                ),
                const SizedBox(width: KabukTheme.spacingMd),
                _GalleryAction(
                  icon: Icons.attach_file_rounded,
                  label: 'File',
                  onTap: () => _pickFile(ref),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: KabukTheme.divider),
          // Placeholder for recent photos grid
          const Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.photo_library_outlined,
                    size: 48,
                    color: KabukTheme.textTertiary,
                  ),
                  SizedBox(height: KabukTheme.spacingSm),
                  Text(
                    'Tap an option above to select media',
                    style: TextStyle(
                      color: KabukTheme.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickImages(WidgetRef ref) async {
    final media = ref.read(mediaServiceProvider);
    final paths = await media.pickMultipleImages();
    if (paths.isNotEmpty) onMediaSelected?.call(paths);
  }

  Future<void> _takePhoto(WidgetRef ref) async {
    final media = ref.read(mediaServiceProvider);
    final path = await media.capturePhoto();
    if (path != null) onMediaSelected?.call([path]);
  }

  Future<void> _takeVideo(WidgetRef ref) async {
    final media = ref.read(mediaServiceProvider);
    final path = await media.captureVideo();
    if (path != null) onMediaSelected?.call([path]);
  }

  Future<void> _pickFile(WidgetRef ref) async {
    final media = ref.read(mediaServiceProvider);
    final path = await media.pickFile();
    if (path != null) onMediaSelected?.call([path]);
  }
}

class _GalleryAction extends StatelessWidget {
  const _GalleryAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(KabukTheme.radiusMd),
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: KabukTheme.spacingSm),
          decoration: BoxDecoration(
            color: KabukTheme.surfaceVariant,
            borderRadius: BorderRadius.circular(KabukTheme.radiusMd),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 24, color: KabukTheme.accentGreen),
              const SizedBox(height: 4),
              Text(
                label,
                style: const TextStyle(
                  color: KabukTheme.textSecondary,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Voice recording panel
// =============================================================================

/// Voice recorder panel with record/stop/preview.
class _VoicePanel extends ConsumerStatefulWidget {
  const _VoicePanel({this.onVoiceRecorded});

  final ValueChanged<String>? onVoiceRecorded;

  @override
  ConsumerState<_VoicePanel> createState() => _VoicePanelState();
}

class _VoicePanelState extends ConsumerState<_VoicePanel> {
  bool _isRecording = false;
  String? _recordedPath;
  final _stopwatch = Stopwatch();
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    _stopwatch.stop();
    super.dispose();
  }

  Future<void> _toggleRecording() async {
    final media = ref.read(mediaServiceProvider);

    if (_isRecording) {
      // Stop recording.
      _timer?.cancel();
      _stopwatch.stop();
      final path = await media.stopRecording();
      setState(() {
        _isRecording = false;
        _recordedPath = path;
      });
    } else {
      // Start recording.
      final path = await media.recordAudio();
      if (path != null) {
        _stopwatch.reset();
        _stopwatch.start();
        _timer = Timer.periodic(const Duration(seconds: 1), (_) {
          if (mounted) setState(() {});
        });
        setState(() {
          _isRecording = true;
          _recordedPath = null;
        });
      }
    }
  }

  void _sendRecording() {
    if (_recordedPath != null) {
      widget.onVoiceRecorded?.call(_recordedPath!);
      setState(() => _recordedPath = null);
    }
  }

  void _discardRecording() {
    setState(() => _recordedPath = null);
  }

  String _formatDuration() {
    final elapsed = _stopwatch.elapsed;
    final minutes = elapsed.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = elapsed.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: KabukTheme.surface,
      child: Column(
        children: [
          const Divider(height: 1, color: KabukTheme.divider),
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Timer display
                  Text(
                    _isRecording
                        ? _formatDuration()
                        : (_recordedPath != null
                              ? 'Recording saved'
                              : 'Tap to record'),
                    style: TextStyle(
                      color: _isRecording
                          ? KabukTheme.error
                          : KabukTheme.textSecondary,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: KabukTheme.spacingMd),
                  // Record / stop button
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (_recordedPath != null && !_isRecording) ...[
                        // Discard
                        IconButton.filled(
                          onPressed: _discardRecording,
                          style: IconButton.styleFrom(
                            backgroundColor: KabukTheme.surfaceVariant,
                          ),
                          icon: const Icon(
                            Icons.delete_outline,
                            color: KabukTheme.error,
                          ),
                          tooltip: 'Discard',
                        ),
                        const SizedBox(width: KabukTheme.spacingLg),
                      ],
                      // Record/Stop
                      GestureDetector(
                        onTap: () {
                          HapticFeedback.heavyImpact();
                          _toggleRecording();
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: _isRecording ? 64 : 56,
                          height: _isRecording ? 64 : 56,
                          decoration: BoxDecoration(
                            color: _isRecording
                                ? KabukTheme.error
                                : KabukTheme.primaryGreen,
                            shape: BoxShape.circle,
                            boxShadow: _isRecording
                                ? [
                                    BoxShadow(
                                      color: KabukTheme.error.withAlpha(100),
                                      blurRadius: 16,
                                      spreadRadius: 2,
                                    ),
                                  ]
                                : null,
                          ),
                          child: Icon(
                            _isRecording
                                ? Icons.stop_rounded
                                : Icons.mic_rounded,
                            color: Colors.white,
                            size: 28,
                          ),
                        ),
                      ),
                      if (_recordedPath != null && !_isRecording) ...[
                        const SizedBox(width: KabukTheme.spacingLg),
                        // Send
                        IconButton.filled(
                          onPressed: _sendRecording,
                          style: IconButton.styleFrom(
                            backgroundColor: KabukTheme.primaryGreen,
                          ),
                          icon: const Icon(
                            Icons.send_rounded,
                            color: Colors.white,
                          ),
                          tooltip: 'Send recording',
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Enter key interceptor
// =============================================================================

/// Intercepts the Enter key before it reaches the [TextField] to prevent
/// a newline from being inserted after the input is cleared.
///
/// Shift+Enter still inserts a newline as expected.
class _EnterInterceptor extends StatelessWidget {
  const _EnterInterceptor({required this.onEnter, required this.child});

  final VoidCallback onEnter;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Focus(
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.enter &&
            !HardwareKeyboard.instance.isShiftPressed) {
          onEnter();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: child,
    );
  }
}
