import 'package:flutter/widgets.dart';

/// The edges of the window that the app itself has to offer for resizing
/// once it draws its own title bar: the others keep their system border.
enum WindowEdge { top, topLeft, topRight }

/// The app's own window: whether the app draws its title bar itself, and
/// what the title bar's buttons do.
///
/// Listeners are told when [hasCustomFrame], [isMaximized] or
/// [isFullscreen] change.
abstract class WindowController extends ChangeNotifier {
  /// True once the system's title bar is gone and the app has to offer
  /// dragging, the three window buttons and the top resize edge itself.
  bool get hasCustomFrame;

  bool get isMaximized;

  /// The window covers the whole screen (the player's fullscreen).
  bool get isFullscreen;

  /// Hands the pointer that is down to the system, as if it had gone down
  /// on a title bar: the window follows it, and snaps as usual.
  void startDrag();

  /// The same for resizing by [edge].
  void startResize(WindowEdge edge);

  void minimize();

  /// Maximizes the window, or puts it back to the size it had.
  void toggleMaximize();

  /// Closes the window, and with it the app.
  void close();
}

/// Makes the [WindowController] available to the widget tree. Without one
/// above, the title bar of the system is in use and the app draws no
/// window buttons.
class WindowScope extends InheritedNotifier<WindowController> {
  const WindowScope({
    super.key,
    required WindowController controller,
    required super.child,
  }) : super(notifier: controller);

  /// The controller, if the app has one; the calling widget rebuilds
  /// whenever its state changes.
  static WindowController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<WindowScope>()?.notifier;
}
