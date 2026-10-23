import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';

typedef HardwareKeyCallback = KeyEventResult Function(KeyEvent event);

class HardwareKeyboardListener extends StatefulWidget {
  const HardwareKeyboardListener({
    super.key,
    required this.child,
    this.onKeyDown,
    this.onKeyUp,
    this.onKeyRepeat,
    this.shortcuts = const {},
    this.autofocus = true,
    this.focusNode,
    this.canRequestFocus = true,
  });

  final Widget child;

  final HardwareKeyCallback? onKeyDown;
  final HardwareKeyCallback? onKeyUp;
  final HardwareKeyCallback? onKeyRepeat;

  /// Комбінації клавіш та їх обробники.
  final Map<ShortcutActivator, VoidCallback> shortcuts;

  final bool autofocus;
  final FocusNode? focusNode;
  final bool canRequestFocus;

  @override
  State<HardwareKeyboardListener> createState() => _HardwareKeyboardListenerState();
}

class _HardwareKeyboardListenerState extends State<HardwareKeyboardListener> {
  late final FocusNode _internalFocusNode = FocusNode(debugLabel: 'HardwareKeyboardListener');

  FocusNode get _focusNode => widget.focusNode ?? _internalFocusNode;

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    // Спочатку перевіряємо shortcuts.
    // Виконуємо тільки на KeyDown, щоб не дублювати виклик.
    if (event is KeyDownEvent) {
      for (final entry in widget.shortcuts.entries) {
        if (entry.key.accepts(event, HardwareKeyboard.instance)) {
          entry.value();
          return KeyEventResult.handled;
        }
      }
    }

    if (event is KeyDownEvent) {
      return widget.onKeyDown?.call(event) ?? KeyEventResult.ignored;
    }

    if (event is KeyUpEvent) {
      return widget.onKeyUp?.call(event) ?? KeyEventResult.ignored;
    }

    if (event is KeyRepeatEvent) {
      return widget.onKeyRepeat?.call(event) ?? KeyEventResult.ignored;
    }

    return KeyEventResult.ignored;
  }

  @override
  void dispose() {
    _internalFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      autofocus: widget.autofocus,
      canRequestFocus: widget.canRequestFocus,
      onKeyEvent: _handleKeyEvent,
      child: widget.child,
    );
  }
}
