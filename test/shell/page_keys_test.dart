import 'package:dhara/shell/nav_rail.dart';
import 'package:dhara/shell/page_keys.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_app.dart';

final _scroll = find.byKey(const Key('settings-scroll'));

/// How far the Settings page is scrolled.
double _offset(WidgetTester tester) => tester
    .state<ScrollableState>(
      find.descendant(of: _scroll, matching: find.byType(Scrollable)).first,
    )
    .position
    .pixels;

double _end(WidgetTester tester) => tester
    .state<ScrollableState>(
      find.descendant(of: _scroll, matching: find.byType(Scrollable)).first,
    )
    .position
    .maxScrollExtent;

Future<void> _press(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pumpAndSettle();
}

/// The app with Settings open: a page taller than the window.
Future<void> _boot(WidgetTester tester) async {
  tester.view
    ..physicalSize = const Size(1280, 720)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(testApp().app);
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('rail-settings')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Page Down and Page Up scroll the page with nothing chosen on '
      'it', (tester) async {
    await _boot(tester);
    final view = tester.getSize(_scroll).height;
    expect(_offset(tester), 0);

    await _press(tester, LogicalKeyboardKey.pageDown);
    expect(
      _offset(tester),
      moreOrLessEquals(view * PageScrollKeys.pageFraction),
    );

    await _press(tester, LogicalKeyboardKey.pageUp);
    expect(_offset(tester), 0);
  });

  testWidgets('End and Home go to the bottom and the top', (tester) async {
    await _boot(tester);

    await _press(tester, LogicalKeyboardKey.end);
    expect(_offset(tester), _end(tester));
    expect(_offset(tester), greaterThan(0));

    await _press(tester, LogicalKeyboardKey.home);
    expect(_offset(tester), 0);
  });

  testWidgets('they also work from the rail and from the search field, where '
      'Home and End stay with the text', (tester) async {
    await _boot(tester);
    final page = tester.getSize(_scroll).height * PageScrollKeys.pageFraction;

    await tester.tap(find.byKey(const Key('shell-search')));
    await tester.pump();
    await _press(tester, LogicalKeyboardKey.pageDown);
    expect(_offset(tester), moreOrLessEquals(page));
    await _press(tester, LogicalKeyboardKey.end);
    expect(
      _offset(tester),
      moreOrLessEquals(page),
      reason: 'End moves the caret in a field',
    );
    await _press(tester, LogicalKeyboardKey.pageUp);
    expect(_offset(tester), 0);

    // On from the search field: the server count, then the rail.
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(
      FocusManager.instance.primaryFocus?.context
          ?.findAncestorWidgetOfExactType<NavRail>(),
      isNotNull,
    );
    await _press(tester, LogicalKeyboardKey.pageDown);
    expect(_offset(tester), moreOrLessEquals(page));
  });

  testWidgets('a dialog keeps its keys to itself', (tester) async {
    await _boot(tester);
    final clear = find.byKey(const Key('set-clear-history'));
    await tester.ensureVisible(clear);
    await tester.pumpAndSettle();
    final before = _offset(tester);
    await tester.tap(clear);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('history-clear-cancel')), findsOneWidget);

    await _press(tester, LogicalKeyboardKey.home);

    expect(_offset(tester), before);
  });
}
