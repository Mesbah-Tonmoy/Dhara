import 'package:dhara/core/window/window_controller.dart';
import 'package:dhara/theme/tokens.dart';
import 'package:flutter/material.dart';

/// Lets the window be moved by dragging [child], and maximized by a double
/// click on it, as a title bar does. With the system's own title bar in
/// use it is just [child].
///
/// Put it behind buttons and fields (below them in a `Stack`), not around
/// them: around them, every click would first wait to see whether it turns
/// into a double click.
class WindowDragArea extends StatelessWidget {
  const WindowDragArea({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final window = WindowScope.maybeOf(context);
    if (window == null || !window.hasCustomFrame || window.isFullscreen) {
      return child;
    }
    return GestureDetector(
      // Opaque: what lies behind it must not take the same clicks.
      behavior: HitTestBehavior.opaque,
      onPanStart: (_) => window.startDrag(),
      onDoubleTap: window.toggleMaximize,
      child: child,
    );
  }
}

/// A strip along the top of the window that resizes it, where the system's
/// title bar used to offer that. Place it above everything else at the top
/// of a page. Nothing with the system's title bar, or while the window is
/// maximized or fullscreen.
class WindowTopResizeEdge extends StatelessWidget {
  const WindowTopResizeEdge({super.key});

  static const thickness = 5.0;
  static const cornerWidth = 12.0;

  @override
  Widget build(BuildContext context) {
    final window = WindowScope.maybeOf(context);
    if (window == null ||
        !window.hasCustomFrame ||
        window.isMaximized ||
        window.isFullscreen) {
      return const SizedBox.shrink();
    }
    Widget grip(WindowEdge edge, MouseCursor cursor, {double? width}) =>
        MouseRegion(
          cursor: cursor,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: (_) => window.startResize(edge),
            child: SizedBox(width: width, height: thickness),
          ),
        );
    return Row(
      children: [
        grip(
          WindowEdge.topLeft,
          SystemMouseCursors.resizeUpLeft,
          width: cornerWidth,
        ),
        Expanded(child: grip(WindowEdge.top, SystemMouseCursors.resizeUp)),
        grip(
          WindowEdge.topRight,
          SystemMouseCursors.resizeUpRight,
          width: cornerWidth,
        ),
      ],
    );
  }
}

/// Minimize, maximize (or restore) and close, as the prototype's title bar
/// has them. Nothing with the system's own title bar, which has its own.
///
/// They are for the mouse; the keyboard has the system's shortcuts
/// (Alt+F4, Win+arrows), so they are not in the Tab order.
class WindowButtons extends StatelessWidget {
  const WindowButtons({super.key});

  @override
  Widget build(BuildContext context) {
    final window = WindowScope.maybeOf(context);
    if (window == null || !window.hasCustomFrame || window.isFullscreen) {
      return const SizedBox.shrink();
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _WindowButton(
          key: const Key('window-minimize'),
          label: 'Minimize',
          glyph: _Glyph.minimize,
          onPressed: window.minimize,
        ),
        _WindowButton(
          key: const Key('window-maximize'),
          label: window.isMaximized ? 'Restore' : 'Maximize',
          glyph: window.isMaximized ? _Glyph.restore : _Glyph.maximize,
          onPressed: window.toggleMaximize,
        ),
        _WindowButton(
          key: const Key('window-close'),
          label: 'Close',
          glyph: _Glyph.close,
          hoverColor: const Color(0xFFE81123),
          onPressed: window.close,
        ),
      ],
    );
  }
}

enum _Glyph { minimize, maximize, restore, close }

class _WindowButton extends StatefulWidget {
  const _WindowButton({
    super.key,
    required this.label,
    required this.glyph,
    required this.onPressed,
    this.hoverColor = DharaColors.surface2,
  });

  final String label;
  final _Glyph glyph;
  final VoidCallback onPressed;
  final Color hoverColor;

  @override
  State<_WindowButton> createState() => _WindowButtonState();
}

class _WindowButtonState extends State<_WindowButton> {
  var _hovered = false;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: widget.label,
    child: Tooltip(
      message: widget.label,
      waitDuration: const Duration(milliseconds: 700),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onPressed,
          child: AnimatedContainer(
            duration: DharaMotion.fast,
            width: 2.9 * rem,
            height: DharaLayout.titleBarHeight,
            color: _hovered ? widget.hoverColor : const Color(0x00000000),
            alignment: Alignment.center,
            child: CustomPaint(
              size: const Size.square(.7 * rem),
              painter: _GlyphPainter(
                widget.glyph,
                _hovered ? DharaColors.text : DharaColors.text2,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _GlyphPainter extends CustomPainter {
  const _GlyphPainter(this.glyph, this.color);

  final _Glyph glyph;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final w = size.width;
    final h = size.height;
    switch (glyph) {
      case _Glyph.minimize:
        canvas.drawLine(Offset(0, h * .55), Offset(w, h * .55), line);
      case _Glyph.maximize:
        canvas.drawRect(Rect.fromLTWH(.5, .5, w - 1, h - 1), line);
      case _Glyph.restore:
        final inset = w * .22;
        canvas
          ..drawRect(
            Rect.fromLTWH(.5, inset + .5, w - inset - 1, h - inset - 1),
            line,
          )
          ..drawPath(
            Path()
              ..moveTo(inset + .5, inset + .5)
              ..lineTo(inset + .5, .5)
              ..lineTo(w - .5, .5)
              ..lineTo(w - .5, h - inset - .5)
              ..lineTo(w - inset - .5, h - inset - .5),
            line,
          );
      case _Glyph.close:
        canvas
          ..drawLine(Offset.zero, Offset(w, h), line)
          ..drawLine(Offset(w, 0), Offset(0, h), line);
    }
  }

  @override
  bool shouldRepaint(_GlyphPainter old) =>
      glyph != old.glyph || color != old.color;
}
