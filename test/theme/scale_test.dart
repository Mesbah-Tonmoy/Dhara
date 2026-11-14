import 'dart:io';

import 'package:dhara/theme/scale.dart';
import 'package:dhara/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Gives the test window [size] in logical pixels, at a pixel ratio of 1.
void _window(WidgetTester tester, Size size) {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

class _Counter extends StatefulWidget {
  const _Counter();

  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  var _count = 0;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.bottomRight,
    child: TextButton(
      onPressed: () => setState(() => _count++),
      child: Text('count $_count'),
    ),
  );
}

void main() {
  group('dharaScaleFor', () {
    test('follows the font-size rule of the prototype', () {
      final html = File('design/prototype/index.html').readAsStringSync();
      expect(
        html,
        contains('html { font-size: clamp(15px, .42vw + 9.6px, 28px); }'),
      );
      expect(rem, 15);

      expect(dharaScaleFor(800), 1);
      expect(dharaScaleFor(1280), 1);
      expect(dharaScaleFor(1536), closeTo(16.0512 / 15, 1e-9));
      expect(dharaScaleFor(1920), closeTo(17.664 / 15, 1e-9));
      expect(dharaScaleFor(3840), closeTo(25.728 / 15, 1e-9));
      expect(dharaScaleFor(8000), closeTo(28 / 15, 1e-9));
    });

    test('never shrinks as the window grows', () {
      var last = 0.0;
      for (var width = 400.0; width <= 8000; width += 40) {
        final scale = dharaScaleFor(width);
        expect(scale, greaterThanOrEqualTo(last), reason: '$width');
        last = scale;
      }
    });

    test('multiplies by the interface size the user chose', () {
      expect(dharaScaleFor(1280, userScale: 1.25), 1.25);
      expect(dharaScaleFor(1280, userScale: .9), .9);
      expect(
        dharaScaleFor(1920, userScale: 1.1),
        closeTo(17.664 / 15 * 1.1, 1e-9),
      );
    });

    test('falls back to 1 for values that make no sense', () {
      expect(dharaScaleFor(double.nan), 1);
      expect(dharaScaleFor(double.infinity), 1);
      expect(dharaScaleFor(1920, userScale: 0), 1);
      expect(dharaScaleFor(1920, userScale: -2), 1);
      expect(dharaScaleFor(1920, userScale: double.nan), 1);
    });
  });

  group('DharaScale', () {
    testWidgets('leaves a window 1280 wide as it is', (tester) async {
      _window(tester, const Size(1280, 720));
      late MediaQueryData media;
      late double scale;

      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => DharaScale(child: child!),
          home: Builder(
            builder: (context) {
              media = MediaQuery.of(context);
              scale = DharaScale.of(context);
              return const SizedBox.expand(key: Key('page'));
            },
          ),
        ),
      );

      expect(scale, 1);
      expect(media.size, const Size(1280, 720));
      expect(media.devicePixelRatio, 1);
      expect(tester.getSize(find.byKey(const Key('page'))), media.size);
    });

    testWidgets('lays a wide window out smaller and fills it by scaling', (
      tester,
    ) async {
      _window(tester, const Size(1920, 1080));
      const expected = 17.664 / 15;
      late MediaQueryData media;
      late double scale;

      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => DharaScale(child: child!),
          home: Builder(
            builder: (context) {
              media = MediaQuery.of(context);
              scale = DharaScale.of(context);
              return const SizedBox.expand(key: Key('page'));
            },
          ),
        ),
      );

      expect(scale, closeTo(expected, 1e-9));
      expect(media.size.width, closeTo(1920 / expected, 1e-6));
      expect(media.size.height, closeTo(1080 / expected, 1e-6));
      // Pictures are decoded for the pixels they really cover.
      expect(media.devicePixelRatio, closeTo(expected, 1e-9));

      final page = find.byKey(const Key('page'));
      expect(tester.getSize(page).width, closeTo(1920 / expected, 1e-6));
      // On screen it covers the whole window.
      final onScreen = tester.getRect(page);
      expect(onScreen.left, closeTo(0, 1e-6));
      expect(onScreen.top, closeTo(0, 1e-6));
      expect(onScreen.right, closeTo(1920, 1e-6));
      expect(onScreen.bottom, closeTo(1080, 1e-6));
    });

    testWidgets('a smaller interface size still fills the window', (
      tester,
    ) async {
      _window(tester, const Size(1280, 720));

      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => DharaScale(userScale: .9, child: child!),
          home: const SizedBox.expand(key: Key('page')),
        ),
      );

      final page = find.byKey(const Key('page'));
      expect(tester.getSize(page).width, closeTo(1280 / .9, 1e-6));
      final onScreen = tester.getRect(page);
      expect(onScreen.left, closeTo(0, 1e-6));
      expect(onScreen.right, closeTo(1280, 1e-6));
      expect(onScreen.bottom, closeTo(720, 1e-6));
    });

    testWidgets('taps land on scaled widgets, also in the far corner', (
      tester,
    ) async {
      _window(tester, const Size(2560, 1440));

      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => DharaScale(child: child!),
          home: const Scaffold(body: _Counter()),
        ),
      );
      await tester.tap(find.text('count 0'));
      await tester.pump();

      expect(find.text('count 1'), findsOneWidget);
    });

    testWidgets('resizing the window across 1280 keeps the state of the '
        'app', (tester) async {
      _window(tester, const Size(1200, 700));
      final app = MaterialApp(
        builder: (context, child) => DharaScale(child: child!),
        home: const Scaffold(body: _Counter()),
      );

      await tester.pumpWidget(app);
      await tester.tap(find.text('count 0'));
      await tester.pump();
      tester.view.physicalSize = const Size(1920, 1080);
      await tester.pump();

      expect(find.text('count 1'), findsOneWidget);
      expect(
        DharaScale.of(tester.element(find.text('count 1'))),
        closeTo(17.664 / 15, 1e-9),
      );
    });

    testWidgets('dialogs are scaled with the page', (tester) async {
      _window(tester, const Size(1920, 1080));

      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => DharaScale(child: child!),
          home: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => const AlertDialog(title: Text('In a dialog')),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(
        DharaScale.of(tester.element(find.text('In a dialog'))),
        closeTo(17.664 / 15, 1e-9),
      );
    });

    testWidgets('without one above, the scale is 1', (tester) async {
      late double scale;

      await tester.pumpWidget(
        Builder(
          builder: (context) {
            scale = DharaScale.of(context);
            return const SizedBox();
          },
        ),
      );

      expect(scale, 1);
    });
  });
}
