import 'package:dhara/shell/shell_controller.dart';
import 'package:dhara/theme/tokens.dart';
import 'package:dhara/widgets/pressable.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Lets Page Up, Page Down, Home and End scroll the page that is on
/// screen in the shell, wherever on it the keyboard is: also on the rail,
/// in the title bar, or nowhere yet, as when the app has just started.
///
/// Flutter by itself only scrolls with these keys while something inside
/// the list holds the keyboard. Put this above the app's navigator; it
/// leaves dialogs and the player alone, which are not inside the shell.
class PageScrollKeys extends StatelessWidget {
  const PageScrollKeys({super.key, required this.child});

  final Widget child;

  /// How much of what is visible a Page key moves on by; the rest stays
  /// in view, to read on from.
  static const pageFraction = .85;

  @override
  Widget build(BuildContext context) => Focus(
    canRequestFocus: false,
    skipTraversal: true,
    onKeyEvent: (node, event) => _onKey(context, event),
    child: child,
  );

  static KeyEventResult _onKey(BuildContext context, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final paging =
        key == LogicalKeyboardKey.pageDown || key == LogicalKeyboardKey.pageUp;
    final ends =
        key == LogicalKeyboardKey.home || key == LogicalKeyboardKey.end;
    if (!paging && !ends) return KeyEventResult.ignored;
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isControlPressed ||
        keyboard.isAltPressed ||
        keyboard.isMetaPressed ||
        keyboard.isShiftPressed) {
      return KeyEventResult.ignored;
    }

    final focus = FocusManager.instance.primaryFocus?.context;
    if (focus == null) return KeyEventResult.ignored;
    final shell = ShellScope.maybeRead(focus);
    if (shell == null) return KeyEventResult.ignored;
    // In a text field Home and End move the caret.
    if (ends && _isTextField(focus)) return KeyEventResult.ignored;

    final scrollable =
        _verticalAround(focus) ?? _firstVerticalIn(shell.pageContext);
    if (scrollable == null) return KeyEventResult.ignored;
    final position = scrollable.position;
    final min = position.minScrollExtent;
    final max = position.maxScrollExtent;
    if (max <= min) return KeyEventResult.ignored;

    final page = position.viewportDimension * pageFraction;
    final target =
        (key == LogicalKeyboardKey.pageDown
                ? position.pixels + page
                : key == LogicalKeyboardKey.pageUp
                ? position.pixels - page
                : key == LogicalKeyboardKey.home
                ? min
                : max)
            .clamp(min, max);
    final duration = motion(context, DharaMotion.base);
    // A key held down follows at once; a glide would lag behind it.
    if (duration == Duration.zero || event is KeyRepeatEvent) {
      position.jumpTo(target);
    } else {
      position
          .animateTo(target, duration: duration, curve: DharaMotion.easeOut)
          .ignore();
    }
    return KeyEventResult.handled;
  }

  static bool _isTextField(BuildContext context) =>
      context.widget is EditableText ||
      context.findAncestorWidgetOfExactType<EditableText>() != null;

  static bool _isVertical(ScrollableState state) =>
      axisDirectionToAxis(state.axisDirection) == Axis.vertical;

  /// The list that scrolls up and down around [context], if it is in one.
  static ScrollableState? _verticalAround(BuildContext context) {
    ScrollableState? found;
    context.visitAncestorElements((element) {
      if (element case StatefulElement(
        state: final ScrollableState state,
      ) when _isVertical(state)) {
        found = state;
        return false;
      }
      return true;
    });
    return found;
  }

  /// The first list that scrolls up and down inside [page]: the page's
  /// own, as every page is built around one.
  static ScrollableState? _firstVerticalIn(BuildContext? page) {
    if (page == null || !page.mounted) return null;
    ScrollableState? found;
    void visit(Element element) {
      if (found != null) return;
      if (element case StatefulElement(
        state: final ScrollableState state,
      ) when _isVertical(state)) {
        found = state;
        return;
      }
      element.visitChildren(visit);
    }

    page.visitChildElements(visit);
    return found;
  }
}
