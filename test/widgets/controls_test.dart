import 'package:dhara/theme/tokens.dart';
import 'package:dhara/widgets/buttons.dart';
import 'package:dhara/widgets/chips.dart';
import 'package:dhara/widgets/icons.dart';
import 'package:dhara/widgets/pressable.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

BoxDecoration _decorationIn(WidgetTester tester, Finder of) =>
    tester
            .widget<AnimatedContainer>(
              find.descendant(of: of, matching: find.byType(AnimatedContainer)),
            )
            .decoration!
        as BoxDecoration;

void main() {
  setUp(useKeyboardHighlight);

  group('DharaButton', () {
    testWidgets('has the prototype\'s two sizes', (tester) async {
      await tester.pumpWidget(
        host(
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DharaButton(
                key: const Key('big'),
                label: 'Play',
                onPressed: () {},
              ),
              DharaButton(
                key: const Key('small'),
                label: 'Play',
                small: true,
                onPressed: () {},
              ),
              DharaButton(
                key: const Key('round'),
                icon: DharaIcons.info,
                tooltip: 'More info',
                onPressed: () {},
              ),
            ],
          ),
        ),
      );

      expect(tester.getSize(find.byKey(const Key('big'))).height, 2.9 * rem);
      expect(tester.getSize(find.byKey(const Key('small'))).height, 2.2 * rem);
      expect(
        tester.getSize(find.byKey(const Key('round'))),
        const Size.square(2.9 * rem),
      );
    });

    testWidgets('the primary one carries the accent gradient, the glass '
        'one a border', (tester) async {
      await tester.pumpWidget(
        host(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              DharaButton(
                key: const Key('primary'),
                label: 'Play',
                icon: DharaIcons.play,
                style: DharaButtonStyle.primary,
                onPressed: () {},
              ),
              DharaButton(
                key: const Key('glass'),
                label: 'My List',
                onPressed: () {},
              ),
              DharaButton(
                key: const Key('on'),
                label: 'In My List',
                on: true,
                onPressed: () {},
              ),
            ],
          ),
        ),
      );

      final primary = _decorationIn(tester, find.byKey(const Key('primary')));
      expect(primary.gradient, DharaColors.accentGradient);
      expect(primary.border, isNull);
      expect(primary.boxShadow, isNotEmpty);

      final glass = _decorationIn(tester, find.byKey(const Key('glass')));
      expect(glass.gradient, isNull);
      expect(glass.color, DharaColors.surface2);
      expect((glass.border! as Border).top.color, DharaColors.strokeStrong);

      final on = _decorationIn(tester, find.byKey(const Key('on')));
      expect(on.gradient, DharaColors.accentSoftGradient);
      expect((on.border! as Border).top.color, DharaColors.accentStroke);
    });

    testWidgets('is pressed by a click and by the keyboard, and shows the '
        'focus ring', (tester) async {
      var presses = 0;
      await tester.pumpWidget(
        host(DharaButton(label: 'Play', onPressed: () => presses++)),
      );
      FocusRing ring() => tester.widget(find.byType(FocusRing));

      await tester.tap(find.text('Play'));
      expect(presses, 1);
      expect(ring().visible, isFalse);

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(ring().visible, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(presses, 2);
    });

    testWidgets('a disabled one is dimmed and does nothing', (tester) async {
      await tester.pumpWidget(
        host(const DharaButton(label: 'Play', onPressed: null)),
      );

      await tester.tap(find.text('Play'));

      expect(tester.widget<Opacity>(find.byType(Opacity)).opacity, lessThan(1));
    });

    testWidgets('a danger one is red', (tester) async {
      await tester.pumpWidget(
        host(DharaButton(label: 'Clear', danger: true, onPressed: () {})),
      );

      expect(
        tester.widget<Text>(find.text('Clear')).style!.color,
        DharaColors.bad,
      );
    });

    testWidgets('an icon-only one is announced by its tooltip', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        host(
          DharaButton(
            icon: DharaIcons.info,
            tooltip: 'More info',
            onPressed: () {},
          ),
        ),
      );

      expect(find.bySemanticsLabel('More info'), findsOneWidget);
      handle.dispose();
    });
  });

  testWidgets('DharaIconButton is a labelled square that can be pressed', (
    tester,
  ) async {
    var presses = 0;
    await tester.pumpWidget(
      host(
        DharaIconButton(
          icon: DharaIcons.back,
          label: 'Back',
          onPressed: () => presses++,
        ),
      ),
    );

    await tester.tap(find.byTooltip('Back'));

    expect(presses, 1);
    expect(
      tester.getSize(find.byType(DharaIconButton)),
      const Size.square(2.1 * rem),
    );
  });

  group('PillChip', () {
    testWidgets('the chosen one carries the soft accent', (tester) async {
      String? picked;
      await tester.pumpWidget(
        host(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              PillChip(
                key: const Key('one'),
                label: 'Season 1',
                selected: true,
                onPressed: () => picked = 'one',
              ),
              PillChip(
                key: const Key('two'),
                label: 'Season 2',
                small: true,
                onPressed: () => picked = 'two',
              ),
            ],
          ),
        ),
      );

      final one = _decorationIn(tester, find.byKey(const Key('one')));
      final two = _decorationIn(tester, find.byKey(const Key('two')));
      expect(one.gradient, DharaColors.accentSoftGradient);
      expect(two.gradient, isNull);
      expect(two.color, DharaColors.surface);
      expect(tester.getSize(find.byKey(const Key('one'))).height, 2 * rem);
      expect(tester.getSize(find.byKey(const Key('two'))).height, 1.75 * rem);

      await tester.tap(find.text('Season 2'));
      expect(picked, 'two');
    });
  });

  group('SegmentedPills', () {
    testWidgets('shows every choice and reports the one picked', (
      tester,
    ) async {
      var selected = 'list';
      await tester.pumpWidget(
        host(
          StatefulBuilder(
            builder: (context, setState) => SegmentedPills<String>(
              choices: const {'list': 'My List', 'history': 'History'},
              selected: selected,
              onSelected: (value) => setState(() => selected = value),
            ),
          ),
        ),
      );
      FontWeight? weight(String label) =>
          tester.widget<Text>(find.text(label)).style!.fontWeight;
      expect(weight('My List'), DharaType.semibold);
      expect(weight('History'), DharaType.regular);

      await tester.tap(find.text('History'));
      await tester.pump();

      expect(selected, 'history');
      expect(weight('History'), DharaType.semibold);
    });

    testWidgets('the arrow keys move between the choices', (tester) async {
      String? picked;
      await tester.pumpWidget(
        host(
          SegmentedPills<String>(
            choices: const {'a': 'All', 'b': 'Movies', 'c': 'Series'},
            selected: 'a',
            onSelected: (value) => picked = value,
          ),
        ),
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);

      expect(picked, 'c');
    });
  });

  testWidgets('DharaBadge comes plain, in the accent and in green', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            DharaBadge('1080P'),
            DharaBadge('4K', style: DharaBadgeStyle.accent),
            DharaBadge('FASTEST', style: DharaBadgeStyle.good),
          ],
        ),
      ),
    );
    BoxDecoration box(String text) =>
        tester
                .widget<Container>(
                  find.ancestor(
                    of: find.text(text),
                    matching: find.byType(Container),
                  ),
                )
                .decoration!
            as BoxDecoration;

    expect(tester.getSize(find.byType(DharaBadge).first).height, 1.25 * rem);
    expect(box('1080P').gradient, isNull);
    expect(box('4K').gradient, DharaColors.accentGradient);
    expect(
      tester.widget<Text>(find.text('FASTEST')).style!.color,
      DharaColors.good,
    );
  });

  group('DharaSwitch', () {
    testWidgets('flips on a click and on Space, and says what it is', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      var value = false;
      await tester.pumpWidget(
        host(
          StatefulBuilder(
            builder: (context, setState) => DharaSwitch(
              value: value,
              label: 'Autoplay next episode',
              onChanged: (next) => setState(() => value = next),
            ),
          ),
        ),
      );
      expect(
        tester.getSize(find.byType(DharaSwitch)),
        const Size(2.5 * rem, 1.4 * rem),
      );

      await tester.tap(find.byType(DharaSwitch));
      await tester.pumpAndSettle();
      expect(value, isTrue);
      expect(
        tester.getSemantics(find.bySemanticsLabel('Autoplay next episode')),
        isSemantics(isToggled: true),
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(value, isFalse);
      handle.dispose();
    });

    testWidgets('without onChanged it stays as it is', (tester) async {
      await tester.pumpWidget(
        host(const DharaSwitch(value: true, label: 'Fixed', onChanged: null)),
      );

      await tester.tap(find.byType(DharaSwitch));
      await tester.pumpAndSettle();

      expect(
        tester.widget<DharaSwitch>(find.byType(DharaSwitch)).value,
        isTrue,
      );
    });
  });
}
