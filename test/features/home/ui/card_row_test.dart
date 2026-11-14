import 'package:dhara/features/home/ui/card_row.dart';
import 'package:dhara/theme/tokens.dart';
import 'package:dhara/widgets/pressable.dart';
import 'package:dhara/widgets/surfaces.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../widgets/support.dart';

final _prev = find.byKey(const Key('row-prev'));
final _next = find.byKey(const Key('row-next'));

/// A row of [count] numbered cards in a box 900 wide.
Future<List<int>> _pump(
  WidgetTester tester, {
  int count = 40,
  int? titles,
  VoidCallback? onSeeAll,
  bool disableAnimations = false,
}) async {
  final built = <int>[];
  tester.view
    ..physicalSize = const Size(1280, 720)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    host(
      disableAnimations: disableAnimations,
      SizedBox(
        width: 900,
        child: CardRow(
          title: 'Movies',
          count: titles,
          onSeeAll: onSeeAll,
          leftInset: 20,
          itemCount: count,
          itemBuilder: (context, index) {
            built.add(index);
            return Pressable(
              key: Key('card-$index'),
              autofocus: index == 0,
              onPressed: () {},
              builder: (context, state) => ColoredBox(
                color: state.focused ? Colors.white : Colors.grey,
                child: Center(child: Text('$index')),
              ),
            );
          },
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return built;
}

double _opacity(WidgetTester tester, Finder button) => tester
    .widget<AnimatedOpacity>(
      find.descendant(of: button, matching: find.byType(AnimatedOpacity)),
    )
    .opacity;

double _offset(WidgetTester tester) =>
    tester.state<ScrollableState>(find.byType(Scrollable)).position.pixels;

Future<TestGesture> _hover(WidgetTester tester) async {
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: Offset.zero);
  addTearDown(mouse.removePointer);
  await mouse.moveTo(tester.getCenter(find.byType(CardRow)));
  await tester.pumpAndSettle();
  return mouse;
}

void main() {
  testWidgets('has a heading, a count and a way to see all', (tester) async {
    var seen = 0;
    await _pump(tester, titles: 2310, onSeeAll: () => seen++);

    expect(find.text('Movies'), findsOneWidget);
    expect(find.text('2310 titles'), findsOneWidget);
    expect(tester.getTopLeft(find.text('Movies')).dx, 190 + 20);

    await tester.tap(find.text('See all'));
    expect(seen, 1);
  });

  testWidgets('without a count or anything more to see, shows neither', (
    tester,
  ) async {
    await _pump(tester);

    expect(find.textContaining('titles'), findsNothing);
    expect(find.text('See all'), findsNothing);

    await _pump(tester, titles: 1);
    expect(find.text('1 title'), findsOneWidget);
  });

  testWidgets('only builds the cards in view and a few beside them', (
    tester,
  ) async {
    final built = await _pump(tester, count: 5000);

    expect(built, contains(0));
    expect(built.toSet().length, lessThan(12));
    expect(find.byKey(const Key('card-0')), findsOneWidget);
    expect(find.byKey(const Key('card-4000')), findsNothing);
  });

  testWidgets('cards are posters of the standard width, a gap apart', (
    tester,
  ) async {
    await _pump(tester);

    final first = tester.getRect(find.byKey(const Key('card-0')));
    final second = tester.getRect(find.byKey(const Key('card-1')));
    expect(first.width, DharaLayout.posterWidth);
    expect(first.height, moreOrLessEquals(DharaLayout.posterWidth * 1.5));
    expect(second.left - first.right, DharaLayout.cardGap);
    expect(first.left, 190 + 20, reason: 'starts under its heading');
  });

  group('the buttons at its ends', () {
    testWidgets('show while the pointer is over the row, where there is '
        'more', (tester) async {
      await _pump(tester);
      expect(_opacity(tester, _prev), 0);
      expect(_opacity(tester, _next), 0);

      await _hover(tester);

      expect(_opacity(tester, _prev), 0, reason: 'nothing to the left');
      expect(_opacity(tester, _next), 1);
    });

    testWidgets('scroll most of a screenful', (tester) async {
      await _pump(tester);
      await _hover(tester);

      await tester.tap(_next);
      await tester.pumpAndSettle();

      expect(_offset(tester), 900 - DharaLayout.posterWidth);
      expect(_opacity(tester, _prev), 1);

      await tester.tap(_prev);
      await tester.pumpAndSettle();
      expect(_offset(tester), 0);
      expect(_opacity(tester, _prev), 0);
    });

    testWidgets('stop at the end of the row', (tester) async {
      await _pump(tester, count: 8);
      await _hover(tester);

      await tester.tap(_next);
      await tester.pumpAndSettle();

      final position = tester
          .state<ScrollableState>(find.byType(Scrollable))
          .position;
      expect(position.pixels, position.maxScrollExtent);
      expect(_opacity(tester, _next), 0);
    });

    testWidgets('are not shown for a row that fits', (tester) async {
      await _pump(tester, count: 3);
      await _hover(tester);

      expect(_opacity(tester, _prev), 0);
      expect(_opacity(tester, _next), 0);
    });

    testWidgets('jump when animations are switched off', (tester) async {
      await _pump(tester, disableAnimations: true);
      await _hover(tester);

      await tester.tap(_next);
      await tester.pump();

      expect(_offset(tester), 900 - DharaLayout.posterWidth);
    });

    testWidgets('are for the mouse: the keyboard never lands on them', (
      tester,
    ) async {
      await _pump(tester, count: 3);

      for (var i = 0; i < 6; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        final focused = FocusManager.instance.primaryFocus!.context!;
        expect(
          focused.findAncestorWidgetOfExactType<Pressable>(),
          isNotNull,
          reason: 'step $i',
        );
      }
    });
  });

  testWidgets('the arrow keys walk the cards, and the row follows', (
    tester,
  ) async {
    useKeyboardHighlight();
    await _pump(tester);

    Finder focusedCard() => find.byWidgetPredicate(
      (widget) => widget is ColoredBox && widget.color == Colors.white,
    );
    String focused() => tester
        .widget<Text>(
          find.descendant(of: focusedCard(), matching: find.byType(Text)),
        )
        .data!;
    expect(focused(), '0');

    for (var i = 0; i < 6; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
    }

    expect(focused(), '6');
    expect(_offset(tester), greaterThan(0));
    final card = tester.getRect(focusedCard());
    expect(card.right, lessThanOrEqualTo(190 + 900));

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(focused(), '5');
  });

  testWidgets('its placeholder is a grey heading over grey cards', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        disableAnimations: true,
        const SizedBox(width: 900, child: CardRowSkeleton(leftInset: 20)),
      ),
    );

    final boxes = tester.widgetList<Skeleton>(find.byType(Skeleton)).toList();
    expect(boxes.length, greaterThan(4));
    expect(boxes[1].width, DharaLayout.posterWidth);
    expect(tester.takeException(), isNull);
  });
}
