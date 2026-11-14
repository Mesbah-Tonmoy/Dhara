import 'dart:ui';

import 'package:dhara/widgets/pressable.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  setUp(useKeyboardHighlight);

  Widget probe({
    required VoidCallback? onPressed,
    List<PressState>? states,
    ValueChanged<bool>? onActiveChanged,
    String? tooltip,
  }) => host(
    Pressable(
      onPressed: onPressed,
      onActiveChanged: onActiveChanged,
      tooltip: tooltip,
      semanticLabel: 'Probe',
      builder: (context, state) {
        states?.add(state);
        return const SizedBox(width: 80, height: 40);
      },
    ),
  );

  testWidgets('a click presses it', (tester) async {
    var presses = 0;
    await tester.pumpWidget(probe(onPressed: () => presses++));

    await tester.tap(find.byType(Pressable));

    expect(presses, 1);
  });

  testWidgets('Tab reaches it, and Enter and Space press it', (tester) async {
    var presses = 0;
    final states = <PressState>[];
    await tester.pumpWidget(probe(onPressed: () => presses++, states: states));
    expect(states.last.focused, isFalse);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(states.last.focused, isTrue);
    expect(states.last.active, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.sendKeyEvent(LogicalKeyboardKey.numpadEnter);
    expect(presses, 3);
  });

  testWidgets('the pointer over it shows as hovered, a press as pressed', (
    tester,
  ) async {
    final states = <PressState>[];
    final active = <bool>[];
    await tester.pumpWidget(
      probe(onPressed: () {}, states: states, onActiveChanged: active.add),
    );
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);

    await mouse.moveTo(tester.getCenter(find.byType(Pressable)));
    await tester.pump();
    expect(states.last.hovered, isTrue);
    expect(states.last.focused, isFalse);

    await mouse.down(tester.getCenter(find.byType(Pressable)));
    await tester.pump();
    expect(states.last.pressed, isTrue);
    await mouse.up();
    await tester.pump();
    expect(states.last.pressed, isFalse);

    await mouse.moveTo(Offset.zero);
    await tester.pump();
    expect(states.last.hovered, isFalse);
    expect(active, [true, false]);
  });

  testWidgets('without onPressed it cannot be clicked or focused', (
    tester,
  ) async {
    final states = <PressState>[];
    await tester.pumpWidget(probe(onPressed: null, states: states));

    await tester.tap(find.byType(Pressable));
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();

    expect(states.last.enabled, isFalse);
    expect(states.last.focused, isFalse);
    expect(states.last.active, isFalse);
  });

  testWidgets('is announced as a button, by its label', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(probe(onPressed: () {}));

    expect(
      tester.getSemantics(find.bySemanticsLabel('Probe')),
      matchesSemantics(
        label: 'Probe',
        isButton: true,
        isEnabled: true,
        hasEnabledState: true,
        isFocusable: true,
        hasFocusAction: true,
        hasTapAction: true,
      ),
    );
    handle.dispose();
  });

  testWidgets('the focus ring is drawn only while visible', (tester) async {
    Widget ring({required bool visible}) => host(
      FocusRing(visible: visible, child: const SizedBox(width: 40, height: 40)),
    );
    CustomPaint paint() => tester.widget(
      find.descendant(
        of: find.byType(FocusRing),
        matching: find.byType(CustomPaint),
      ),
    );

    await tester.pumpWidget(ring(visible: false));
    expect(paint().foregroundPainter, isNull);

    await tester.pumpWidget(ring(visible: true));
    expect(paint().foregroundPainter, isNotNull);
  });

  testWidgets('motion is instant when animations are switched off', (
    tester,
  ) async {
    late Duration normal;
    late Duration reduced;
    await tester.pumpWidget(
      host(
        Builder(
          builder: (context) {
            normal = motion(context, const Duration(milliseconds: 220));
            return MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
              child: Builder(
                builder: (context) {
                  reduced = motion(context, const Duration(milliseconds: 220));
                  return const SizedBox();
                },
              ),
            );
          },
        ),
      ),
    );

    expect(normal, const Duration(milliseconds: 220));
    expect(reduced, Duration.zero);
  });
}
