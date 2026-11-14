import 'package:dhara/theme/tokens.dart';
import 'package:flutter/material.dart';

/// What the pointer and the keyboard are doing to a [Pressable].
@immutable
class PressState {
  const PressState({
    this.hovered = false,
    this.focused = false,
    this.pressed = false,
    this.enabled = true,
  });

  final bool hovered;

  /// It has the keyboard, and the keyboard is what the user is steering
  /// with: after a click nothing is outlined.
  final bool focused;
  final bool pressed;
  final bool enabled;

  /// Under the pointer or holding the keyboard: what a card lights up for.
  bool get active => enabled && (hovered || focused);
}

/// The one way anything in the app is clicked: reacts to the mouse, takes
/// the keyboard focus in Tab and arrow-key order, and is pressed by Enter
/// or Space. [builder] draws it for the state it is in.
///
/// Without [onPressed] it is disabled: not focusable, not clickable.
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.onPressed,
    required this.builder,
    this.focusNode,
    this.autofocus = false,
    this.semanticLabel,
    this.selected,
    this.toggled,
    this.tooltip,
    this.onActiveChanged,
  });

  final VoidCallback? onPressed;
  final Widget Function(BuildContext context, PressState state) builder;
  final FocusNode? focusNode;
  final bool autofocus;

  /// Read out instead of the text inside; needed for icon-only buttons.
  final String? semanticLabel;

  /// For screen readers: the chosen one of several, or a switch that is on.
  final bool? selected;
  final bool? toggled;
  final String? tooltip;

  /// Called when [PressState.active] changes, e.g. to bring a card that
  /// took the keyboard into view.
  final ValueChanged<bool>? onActiveChanged;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  var _hovered = false;
  var _focused = false;
  var _pressed = false;

  bool get _enabled => widget.onPressed != null;

  PressState get _state => PressState(
    hovered: _hovered,
    focused: _focused,
    pressed: _pressed,
    enabled: _enabled,
  );

  void _change(VoidCallback change) {
    final wasActive = _state.active;
    setState(change);
    final active = _state.active;
    if (active != wasActive) widget.onActiveChanged?.call(active);
  }

  void _press() => widget.onPressed?.call();

  @override
  Widget build(BuildContext context) {
    final enabled = _enabled;
    Widget result = FocusableActionDetector(
      enabled: enabled,
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      mouseCursor: enabled
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) => _press(),
        ),
        ButtonActivateIntent: CallbackAction<ButtonActivateIntent>(
          onInvoke: (_) => _press(),
        ),
      },
      onShowHoverHighlight: (value) => _change(() => _hovered = value),
      onShowFocusHighlight: (value) => _change(() => _focused = value),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? _press : null,
        onTapDown: enabled ? (_) => _change(() => _pressed = true) : null,
        onTapUp: enabled ? (_) => _change(() => _pressed = false) : null,
        onTapCancel: enabled ? () => _change(() => _pressed = false) : null,
        child: widget.builder(context, _state),
      ),
    );
    result = Semantics(
      container: true,
      button: true,
      enabled: enabled,
      label: widget.semanticLabel,
      selected: widget.selected,
      toggled: widget.toggled,
      child: result,
    );
    final tooltip = widget.tooltip;
    return tooltip == null ? result : Tooltip(message: tooltip, child: result);
  }
}

/// The outline around whatever holds the keyboard: two pixels of accent,
/// two pixels away, as the prototype's `:focus-visible`.
class FocusRing extends StatelessWidget {
  const FocusRing({
    super.key,
    required this.visible,
    required this.child,
    this.radius = const BorderRadius.all(Radius.circular(DharaRadii.sm)),
  });

  final bool visible;

  /// The corners of [child]; the ring follows them.
  final BorderRadius radius;
  final Widget child;

  @override
  Widget build(BuildContext context) => CustomPaint(
    foregroundPainter: visible ? _RingPainter(radius) : null,
    child: child,
  );
}

class _RingPainter extends CustomPainter {
  const _RingPainter(this.radius);

  static const _width = 2.0;
  static const _gap = 2.0;

  final BorderRadius radius;

  @override
  void paint(Canvas canvas, Size size) => canvas.drawRRect(
    radius.toRRect(Offset.zero & size).inflate(_gap + _width / 2),
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _width
      ..color = DharaColors.accent,
  );

  @override
  bool shouldRepaint(_RingPainter old) => radius != old.radius;
}

/// How long a change of state takes to show: [duration], or no time at all
/// when the system (or the Reduce motion setting) asks for no animations.
Duration motion(BuildContext context, Duration duration) =>
    MediaQuery.disableAnimationsOf(context) ? Duration.zero : duration;
