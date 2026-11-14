import 'package:dhara/theme/tokens.dart';
import 'package:flutter/widgets.dart';

/// How much larger than its design size the interface is drawn in a window
/// [windowWidth] logical pixels wide.
///
/// This is the prototype's `html { font-size: clamp(15px, .42vw + 9.6px,
/// 28px) }`: 1 up to a width of about 1280, about 1.18 at 1920 and 1.72 at
/// 3840. [userScale] is the "Interface size" setting on top of that.
double dharaScaleFor(double windowWidth, {double userScale = 1}) {
  if (!windowWidth.isFinite || !userScale.isFinite || userScale <= 0) return 1;
  final fontSize = (.0042 * windowWidth + 9.6).clamp(rem, _maxFontSize);
  return fontSize / rem * userScale;
}

const _maxFontSize = 28.0;

/// Draws [child] enlarged by [dharaScaleFor] the window, so that text,
/// artwork and spacing grow together and every size in the app can be
/// written once, for a window 1280 wide.
///
/// The child is laid out in a smaller space and then scaled up to fill the
/// window. Below it, `MediaQuery` reports that smaller space and a pixel
/// ratio raised to match, so pictures are still decoded sharp enough. Text
/// stays sharp too: it is drawn at its final size, not stretched.
///
/// Place it above the app's `Navigator` (`MaterialApp.builder`), so that
/// dialogs and menus are scaled as well.
class DharaScale extends StatelessWidget {
  const DharaScale({super.key, required this.child, this.userScale = 1});

  final Widget child;

  /// The "Interface size" setting: 1 is 100%.
  final double userScale;

  /// The scale in force at [context]; 1 without a [DharaScale] above.
  static double of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_ScaleScope>()?.scale ?? 1;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final scale = dharaScaleFor(media.size.width, userScale: userScale);
    // The same widgets at every scale, also at 1: otherwise resizing the
    // window across 1280 would rebuild the whole app from nothing.
    return _ScaleScope(
      scale: scale,
      child: FractionallySizedBox(
        widthFactor: 1 / scale,
        heightFactor: 1 / scale,
        child: Transform.scale(
          scale: scale,
          child: MediaQuery(
            data: media.copyWith(
              size: media.size / scale,
              devicePixelRatio: media.devicePixelRatio * scale,
              padding: media.padding / scale,
              viewPadding: media.viewPadding / scale,
              viewInsets: media.viewInsets / scale,
              systemGestureInsets: media.systemGestureInsets / scale,
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _ScaleScope extends InheritedWidget {
  const _ScaleScope({required this.scale, required super.child});

  final double scale;

  @override
  bool updateShouldNotify(_ScaleScope old) => scale != old.scale;
}
