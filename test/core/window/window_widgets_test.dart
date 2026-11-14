import 'package:dhara/core/window/window_controller.dart';
import 'package:dhara/core/window/window_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_app.dart';

Widget _host(WindowController? window, Widget child) {
  final app = MaterialApp(
    home: Align(alignment: Alignment.topCenter, child: child),
  );
  return window == null ? app : WindowScope(controller: window, child: app);
}

void main() {
  group('WindowButtons', () {
    testWidgets('minimize, maximize and close the window', (tester) async {
      final window = FakeWindow();
      await tester.pumpWidget(_host(window, const WindowButtons()));

      await tester.tap(find.byKey(const Key('window-minimize')));
      await tester.tap(find.byKey(const Key('window-maximize')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('window-close')));

      expect(window.calls, ['minimize', 'toggleMaximize', 'close']);
    });

    testWidgets('offer Restore while the window is maximized', (tester) async {
      final window = FakeWindow();
      await tester.pumpWidget(_host(window, const WindowButtons()));
      expect(find.byTooltip('Maximize'), findsOneWidget);

      window.change(maximized: true);
      await tester.pump();

      expect(find.byTooltip('Restore'), findsOneWidget);
      expect(find.byTooltip('Maximize'), findsNothing);
    });

    testWidgets('are absent with the system\'s title bar, and in fullscreen', (
      tester,
    ) async {
      await tester.pumpWidget(_host(null, const WindowButtons()));
      expect(find.byKey(const Key('window-close')), findsNothing);

      final window = FakeWindow(hasCustomFrame: false);
      await tester.pumpWidget(_host(window, const WindowButtons()));
      expect(find.byKey(const Key('window-close')), findsNothing);

      window.change(customFrame: true);
      await tester.pump();
      expect(find.byKey(const Key('window-close')), findsOneWidget);

      window.change(fullscreen: true);
      await tester.pump();
      expect(find.byKey(const Key('window-close')), findsNothing);
    });
  });

  group('WindowDragArea', () {
    const area = WindowDragArea(
      child: SizedBox(key: Key('bar'), width: 400, height: 40),
    );

    testWidgets('a drag moves the window, a double click maximizes it', (
      tester,
    ) async {
      final window = FakeWindow();
      await tester.pumpWidget(_host(window, area));
      final bar = find.byKey(const Key('bar'));

      await tester.drag(bar, const Offset(60, 20));
      expect(window.calls, ['drag']);

      await tester.tap(bar);
      await tester.pump(const Duration(milliseconds: 80));
      await tester.tap(bar);
      await tester.pumpAndSettle();
      expect(window.calls, ['drag', 'toggleMaximize']);
    });

    testWidgets('a button in front of it takes its click at once', (
      tester,
    ) async {
      final window = FakeWindow();
      var pressed = 0;
      await tester.pumpWidget(
        _host(
          window,
          SizedBox(
            width: 400,
            height: 40,
            child: Stack(
              children: [
                const Positioned.fill(
                  child: WindowDragArea(child: SizedBox.expand()),
                ),
                Center(
                  child: TextButton(
                    onPressed: () => pressed++,
                    child: const Text('Button'),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      await tester.tap(find.text('Button'));
      // No waiting for a second click.
      await tester.pump();

      expect(pressed, 1);
      expect(window.calls, isEmpty);
    });

    testWidgets('does nothing with the system\'s title bar', (tester) async {
      final window = FakeWindow(hasCustomFrame: false);
      await tester.pumpWidget(_host(window, area));

      await tester.drag(find.byKey(const Key('bar')), const Offset(60, 20));

      expect(window.calls, isEmpty);
      expect(find.byType(GestureDetector), findsNothing);
    });
  });

  group('WindowTopResizeEdge', () {
    testWidgets('resizes by the top edge and its two corners', (tester) async {
      tester.view
        ..physicalSize = const Size(800, 600)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final window = FakeWindow();
      await tester.pumpWidget(_host(window, const WindowTopResizeEdge()));

      for (final x in [2.0, 400.0, 798.0]) {
        await tester.dragFrom(Offset(x, 2), const Offset(0, 30));
      }

      expect(window.calls, ['resize topLeft', 'resize top', 'resize topRight']);
    });

    testWidgets('is gone while maximized, fullscreen or system-framed', (
      tester,
    ) async {
      final window = FakeWindow();
      await tester.pumpWidget(_host(window, const WindowTopResizeEdge()));
      expect(find.byType(GestureDetector), findsNWidgets(3));

      for (final change in [
        () => window.change(maximized: true),
        () => window.change(maximized: false, fullscreen: true),
        () => window.change(fullscreen: false, customFrame: false),
      ]) {
        change();
        await tester.pump();
        expect(find.byType(GestureDetector), findsNothing);
      }
    });
  });
}
