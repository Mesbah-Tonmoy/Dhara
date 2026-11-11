import 'dart:ui';

import 'package:dhara/features/player/widgets/seek_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _width = 400.0;
const _duration = Duration(minutes: 100);

Future<List<Duration>> _pumpBar(
  WidgetTester tester, {
  Duration position = Duration.zero,
  Duration duration = _duration,
  Duration buffered = Duration.zero,
}) async {
  final seeks = <Duration>[];
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: _width,
            child: SeekBar(
              position: position,
              duration: duration,
              buffered: buffered,
              onSeek: seeks.add,
            ),
          ),
        ),
      ),
    ),
  );
  return seeks;
}

Offset _at(WidgetTester tester, double fraction) {
  final rect = tester.getRect(find.byType(SeekBar));
  return Offset(rect.left + rect.width * fraction, rect.center.dy);
}

void main() {
  testWidgets('fill follows the playback position', (tester) async {
    await _pumpBar(tester, position: const Duration(minutes: 25));

    final fill = tester.widget<FractionallySizedBox>(
      find.byKey(const Key('seek-fill')),
    );
    expect(fill.widthFactor, closeTo(.25, .001));
  });

  testWidgets('a click seeks to that point', (tester) async {
    final seeks = await _pumpBar(tester);

    await tester.tapAt(_at(tester, .5));
    await tester.pump();

    expect(seeks, hasLength(1));
    expect(seeks.single.inSeconds, closeTo(50 * 60, 30));
  });

  testWidgets('dragging seeks once, on release', (tester) async {
    final seeks = await _pumpBar(tester);

    final gesture = await tester.startGesture(_at(tester, .25));
    await gesture.moveTo(_at(tester, .5));
    await tester.pump();
    await gesture.moveTo(_at(tester, .75));
    await tester.pump();

    expect(seeks, isEmpty, reason: 'no seek while still dragging');
    final fill = tester.widget<FractionallySizedBox>(
      find.byKey(const Key('seek-fill')),
    );
    expect(fill.widthFactor, closeTo(.75, .01));

    await gesture.up();
    await tester.pump();

    expect(seeks, hasLength(1));
    expect(seeks.single.inSeconds, closeTo(75 * 60, 30));
  });

  testWidgets('positions outside the bar are clamped', (tester) async {
    final seeks = await _pumpBar(tester);

    final gesture = await tester.startGesture(_at(tester, .5));
    await gesture.moveTo(_at(tester, .9));
    await gesture.moveTo(_at(tester, 1) + const Offset(300, 0));
    await gesture.up();
    await tester.pump();

    expect(seeks.single, _duration);
  });

  testWidgets('hovering shows the time under the pointer', (tester) async {
    await _pumpBar(tester);
    expect(find.byKey(const Key('seek-tip')), findsNothing);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(_at(tester, .5));
    await tester.pump();

    expect(find.text('50:00'), findsOneWidget);
  });

  testWidgets('does nothing while the duration is unknown', (tester) async {
    final seeks = await _pumpBar(tester, duration: Duration.zero);

    await tester.tapAt(_at(tester, .5));
    await tester.dragFrom(_at(tester, .2), const Offset(100, 0));
    await tester.pump();

    expect(seeks, isEmpty);
  });
}
