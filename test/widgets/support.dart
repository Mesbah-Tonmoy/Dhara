import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// [child] in the middle of a bare app, for testing one widget.
Widget host(Widget child, {bool disableAnimations = false}) => MaterialApp(
  debugShowCheckedModeBanner: false,
  builder: (context, page) => MediaQuery(
    data: MediaQuery.of(context).copyWith(disableAnimations: disableAnimations),
    child: page!,
  ),
  home: Material(
    type: MaterialType.transparency,
    child: Center(child: child),
  ),
);

/// Makes focus show as it does when the keyboard is in use (tests otherwise
/// count as touch, where nothing is outlined). Call from `setUp`.
void useKeyboardHighlight() {
  FocusManager.instance.highlightStrategy =
      FocusHighlightStrategy.alwaysTraditional;
  addTearDown(
    () => FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.automatic,
  );
}
