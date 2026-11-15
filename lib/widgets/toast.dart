import 'dart:async';

import 'package:dhara/theme/tokens.dart';
import 'package:dhara/widgets/pressable.dart';
import 'package:flutter/widgets.dart';

/// Shows short messages at the bottom of the window ("Added to My List"),
/// one at a time, each for [ToastHost.showFor].
///
/// Wrap the app in one, above its navigator, so that a message outlives
/// the page that sent it. Messages are plain text: nothing in them is ever
/// read as markup.
class ToastHost extends StatefulWidget {
  const ToastHost({super.key, required this.child});

  final Widget child;

  static const showFor = Duration(milliseconds: 2600);

  /// Shows [message], replacing the one on screen. [lead] is set in front
  /// of it, highlighted: the title something was done to.
  ///
  /// It stays for [showFor]: longer for a message that says what went
  /// wrong, which takes reading.
  ///
  /// Does nothing if there is no [ToastHost] above [context].
  static void show(
    BuildContext context,
    String message, {
    String? lead,
    Duration showFor = ToastHost.showFor,
  }) => context.findAncestorStateOfType<_ToastHostState>()?._show(
    lead,
    message,
    showFor,
  );

  @override
  State<ToastHost> createState() => _ToastHostState();
}

class _ToastHostState extends State<ToastHost> {
  String? _lead;
  var _message = '';
  var _visible = false;
  Timer? _hide;

  void _show(String? lead, String message, Duration showFor) {
    _hide?.cancel();
    _hide = Timer(showFor, () {
      if (mounted) setState(() => _visible = false);
    });
    setState(() {
      _lead = lead;
      _message = message;
      _visible = true;
    });
  }

  @override
  void dispose() {
    _hide?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lead = _lead;
    final duration = motion(context, DharaMotion.base);
    return Stack(
      fit: StackFit.passthrough,
      children: [
        widget.child,
        Positioned(
          left: 0,
          right: 0,
          bottom: 1.6 * rem,
          child: IgnorePointer(
            child: Center(
              child: AnimatedSlide(
                offset: _visible ? Offset.zero : const Offset(0, .4),
                duration: duration,
                curve: DharaMotion.easeOut,
                child: AnimatedOpacity(
                  opacity: _visible ? 1 : 0,
                  duration: duration,
                  child: FractionallySizedBox(
                    widthFactor: .8,
                    child: Center(
                      child: Semantics(
                        liveRegion: true,
                        container: true,
                        child: Container(
                          key: const Key('toast'),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 1.1 * rem,
                            vertical: .7 * rem,
                          ),
                          decoration: BoxDecoration(
                            color: DharaColors.bgElev,
                            borderRadius: BorderRadius.circular(DharaRadii.md),
                            border: Border.all(color: DharaColors.strokeStrong),
                            boxShadow: DharaShadows.pop,
                          ),
                          child: Text.rich(
                            TextSpan(
                              children: [
                                if (lead != null)
                                  TextSpan(
                                    text: '$lead ',
                                    style: const TextStyle(
                                      color: DharaColors.accent2,
                                      fontWeight: DharaType.bold,
                                    ),
                                  ),
                                TextSpan(text: _message),
                              ],
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            // Complete in itself: above the navigator there
                            // is no text style to inherit.
                            style: const TextStyle(
                              inherit: false,
                              fontFamily: DharaFonts.ui,
                              fontSize: DharaType.sm,
                              fontWeight: DharaType.regular,
                              height: DharaType.snug,
                              color: DharaColors.text,
                              decoration: TextDecoration.none,
                              textBaseline: TextBaseline.alphabetic,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
