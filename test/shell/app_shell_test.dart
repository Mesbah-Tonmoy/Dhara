import 'dart:ui';

import 'package:dhara/features/browse/browse_controller.dart';
import 'package:dhara/features/browse/ui/browse_screen.dart';
import 'package:dhara/features/home/ui/home_screen.dart';
import 'package:dhara/features/indexer/ui/index_screen.dart';
import 'package:dhara/features/metadata/ui/titles_screen.dart';
import 'package:dhara/features/my_list/ui/lists_screen.dart';
import 'package:dhara/features/settings/ui/settings_screen.dart';
import 'package:dhara/features/sources/source_store.dart';
import 'package:dhara/features/sources/ui/server_discovery_screen.dart';
import 'package:dhara/shell/nav_rail.dart';
import 'package:dhara/shell/shell_controller.dart';
import 'package:dhara/shell/title_bar.dart';
import 'package:dhara/widgets/pressable.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_app.dart';

final _home = find.byType(HomeScreen);
final _discovery = find.byType(ServerDiscoveryScreen);
final _library = find.byType(IndexScreen);
final _titles = find.byType(TitlesScreen);
final _history = find.byType(ListsScreen);
final _settings = find.byType(SettingsScreen);
final _back = find.byKey(const Key('shell-back'));
final _search = find.byKey(const Key('shell-search'));

Future<void> _boot(
  WidgetTester tester, {
  ({Widget app, SourceStore sources})? app,
}) async {
  tester.view
    ..physicalSize = const Size(1280, 720)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget((app ?? testApp()).app);
  await tester.pumpAndSettle();
}

Future<void> _open(WidgetTester tester, String place) async {
  await tester.tap(find.byKey(Key('rail-$place')));
  await tester.pumpAndSettle();
}

/// Opens one of the tools that Settings leads to: `titles` or `library`.
Future<void> _openTool(WidgetTester tester, String tool) async {
  await _open(tester, 'settings');
  final button = find.byKey(Key('set-open-$tool'));
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
}

ShellDestination _current(WidgetTester tester) =>
    ShellScope.read(tester.element(find.byType(NavRail))).current;

Future<void> _press(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  LogicalKeyboardKey? holding,
}) async {
  if (holding != null) await tester.sendKeyDownEvent(holding);
  await tester.sendKeyEvent(key);
  if (holding != null) await tester.sendKeyUpEvent(holding);
  await tester.pumpAndSettle();
}

bool _searchHasFocus(WidgetTester tester) =>
    tester.widget<TextField>(_search).focusNode!.hasFocus;

void main() {
  group('navigation', () {
    testWidgets('starts on Home, with nothing to go back to', (tester) async {
      await _boot(tester);

      expect(_home, findsOneWidget);
      expect(_current(tester), ShellDestination.home);
      expect(_back, findsNothing);
    });

    testWidgets('the rail opens a place and lights its icon; Back returns '
        'to Home', (tester) async {
      await _boot(tester);

      await _open(tester, 'discovery');
      expect(_discovery, findsOneWidget);
      expect(_current(tester), ShellDestination.discovery);
      expect(_back, findsOneWidget);
      // Title bar and rail stay where they are.
      expect(find.byType(TitleBar), findsOneWidget);
      expect(find.byType(NavRail), findsOneWidget);

      await tester.tap(_back);
      await tester.pumpAndSettle();
      expect(_home, findsOneWidget);
      expect(_discovery, findsNothing);
      expect(_current(tester), ShellDestination.home);
      expect(_back, findsNothing);
    });

    testWidgets('a second place replaces the first, so Back leads to Home', (
      tester,
    ) async {
      await _boot(tester);

      await _open(tester, 'discovery');
      await _open(tester, 'history');
      expect(_history, findsOneWidget);
      expect(_discovery, findsNothing);
      expect(_current(tester), ShellDestination.history);

      await tester.tap(_back);
      await tester.pumpAndSettle();
      expect(_home, findsOneWidget);
    });

    testWidgets('opening the place that is open changes nothing', (
      tester,
    ) async {
      await _boot(tester);
      await _open(tester, 'history');
      final before = tester.state(_history);

      await _open(tester, 'history');

      expect(tester.state(_history), same(before));
    });

    testWidgets('Settings opens its tools on top of itself: Back leads to '
        'Settings, and the rail keeps Settings lit', (tester) async {
      await _boot(tester);
      bool lit() => tester
          .widget<Pressable>(
            find.descendant(
              of: find.byKey(const Key('rail-settings')),
              matching: find.byType(Pressable),
            ),
          )
          .selected!;
      // The tools have no icon of their own on the rail.
      expect(find.byKey(const Key('rail-library')), findsNothing);
      expect(find.byKey(const Key('rail-titles')), findsNothing);

      await _openTool(tester, 'library');
      expect(_library, findsOneWidget);
      expect(_current(tester), ShellDestination.library);
      expect(lit(), isTrue);

      await tester.tap(_back);
      await tester.pumpAndSettle();
      expect(_settings, findsOneWidget);
      expect(_library, findsNothing);
      expect(_current(tester), ShellDestination.settings);
      expect(lit(), isTrue);

      await _openTool(tester, 'titles');
      expect(_titles, findsOneWidget);

      await _open(tester, 'home');
      expect(_home, findsOneWidget);
      expect(lit(), isFalse);
    });

    testWidgets('Settings leads to Server Discovery, a place of the rail', (
      tester,
    ) async {
      await _boot(tester);
      await _open(tester, 'settings');
      final button = find.byKey(const Key('set-open-discovery'));
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();

      await tester.tap(button);
      await tester.pumpAndSettle();

      expect(_discovery, findsOneWidget);
      expect(_current(tester), ShellDestination.discovery);
    });

    testWidgets('the brand and the Home icon lead home', (tester) async {
      await _boot(tester);

      await _open(tester, 'history');
      await tester.tap(find.byKey(const Key('shell-brand')));
      await tester.pumpAndSettle();
      expect(_home, findsOneWidget);

      await _open(tester, 'discovery');
      await _open(tester, 'home');
      expect(_home, findsOneWidget);
      expect(_discovery, findsNothing);
    });

    testWidgets('pages start clear of the title bar and the rail', (
      tester,
    ) async {
      await _boot(tester);
      await _open(tester, 'discovery');

      final page = tester.getRect(_discovery);
      expect(page.top, tester.getRect(find.byType(TitleBar)).bottom);
      expect(
        page.left,
        greaterThan(tester.getRect(find.byType(NavRail)).right),
      );
    });
  });

  group('keys', () {
    testWidgets('Alt+Left and Esc go back', (tester) async {
      await _boot(tester);

      await _open(tester, 'discovery');
      await _press(
        tester,
        LogicalKeyboardKey.arrowLeft,
        holding: LogicalKeyboardKey.altLeft,
      );
      expect(_home, findsOneWidget);

      await _open(tester, 'discovery');
      await _press(tester, LogicalKeyboardKey.escape);
      expect(_home, findsOneWidget);
    });

    testWidgets('Ctrl+K and / put the keyboard into the search field', (
      tester,
    ) async {
      await _boot(tester);
      expect(_searchHasFocus(tester), isFalse);

      await _press(
        tester,
        LogicalKeyboardKey.keyK,
        holding: LogicalKeyboardKey.controlLeft,
      );
      expect(_searchHasFocus(tester), isTrue);

      // Esc in a text field only lets go of it.
      await _open(tester, 'discovery');
      await _press(
        tester,
        LogicalKeyboardKey.keyK,
        holding: LogicalKeyboardKey.controlLeft,
      );
      await _press(tester, LogicalKeyboardKey.escape);
      expect(_searchHasFocus(tester), isFalse);
      expect(_discovery, findsOneWidget);

      await _press(tester, LogicalKeyboardKey.slash);
      expect(_searchHasFocus(tester), isTrue);
    });

    testWidgets('a / typed into a text field is just a /', (tester) async {
      await _boot(tester);
      await _openTool(tester, 'library');
      final field = find.descendant(
        of: _library,
        matching: find.byType(TextField),
      );
      await tester.tap(field.first);
      await tester.pump();

      await _press(tester, LogicalKeyboardKey.slash);

      expect(_searchHasFocus(tester), isFalse);
    });

    testWidgets('typing in the search field opens Search with it', (
      tester,
    ) async {
      await _boot(tester);

      await tester.enterText(_search, 'harbor');
      await tester.pumpAndSettle();

      expect(find.byType(BrowseScreen), findsOneWidget);
      expect(_current(tester), ShellDestination.search);
      final browse = BrowseScope.read(
        tester.element(find.byType(BrowseScreen)),
      );
      expect(browse.query.text, 'harbor');
      expect(
        tester.widget<Text>(find.byKey(const Key('browse-heading'))).data,
        'Results for “harbor”',
      );
      expect(_searchHasFocus(tester), isTrue, reason: 'typing goes on');

      // More typing narrows the same page; Enter lets go of the keyboard.
      await tester.enterText(_search, 'harbor lights');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.byType(BrowseScreen), findsOneWidget);
      expect(browse.query.text, 'harbor lights');
      expect(_searchHasFocus(tester), isFalse);

      // An empty search goes nowhere.
      await _open(tester, 'home');
      await tester.enterText(_search, '   ');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(_home, findsOneWidget);
      // The search waits a moment for the next key before it asks.
      await tester.pump(const Duration(milliseconds: 200));
    });

    testWidgets('the rail browses Movies and Series through Search', (
      tester,
    ) async {
      await _boot(tester);
      bool lit(String place) =>
          tester
              .widget<Pressable>(
                find.descendant(
                  of: find.byKey(Key('rail-$place')),
                  matching: find.byType(Pressable),
                ),
              )
              .selected ??
          false;

      await _open(tester, 'movies');
      expect(find.byType(BrowseScreen), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const Key('browse-heading'))).data,
        'Movies',
      );
      expect(
        (lit('movies'), lit('series'), lit('search')),
        (true, false, false),
      );

      await _open(tester, 'series');
      expect(
        tester.widget<Text>(find.byKey(const Key('browse-heading'))).data,
        'Series',
      );
      expect((lit('movies'), lit('series')), (false, true));

      // Typing is a search, whatever is being browsed; the rail says so.
      await tester.enterText(_search, 'bay');
      await tester.pumpAndSettle();
      expect((lit('series'), lit('search')), (false, true));

      // Search on the rail takes the keyboard to the field.
      await _open(tester, 'home');
      await _open(tester, 'search');
      expect(find.byType(BrowseScreen), findsOneWidget);
      expect(_searchHasFocus(tester), isTrue);

      // A search that starts on another page is over everything again.
      await _open(tester, 'series');
      await _open(tester, 'home');
      await tester.enterText(_search, 'bay');
      await tester.pumpAndSettle();
      expect(
        BrowseScope.read(
          tester.element(find.byType(BrowseScreen)),
        ).query.hasNoFilters,
        isTrue,
      );
      await tester.pump(const Duration(milliseconds: 200));

      // Movies again: what was typed goes.
      await _open(tester, 'movies');
      expect(tester.widget<TextField>(_search).controller!.text, isEmpty);
      expect(lit('movies'), isTrue);
    });

    testWidgets('Ctrl+O asks for a URL to play', (tester) async {
      await _boot(tester);

      await _press(
        tester,
        LogicalKeyboardKey.keyO,
        holding: LogicalKeyboardKey.controlLeft,
      );

      expect(find.byKey(const Key('url-field')), findsOneWidget);
    });

    testWidgets('the back button of a mouse goes back', (tester) async {
      await _boot(tester);
      await _open(tester, 'discovery');

      final mouse = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
        buttons: kBackMouseButton,
      );
      await mouse.down(tester.getCenter(_discovery));
      await mouse.up();
      await tester.pumpAndSettle();

      expect(_home, findsOneWidget);
    });
  });

  group('Home', () {
    testWidgets('leads to the library and to playing a URL', (tester) async {
      await _boot(tester);

      await tester.tap(find.byKey(const Key('home-open-url')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('url-field')), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('home-step-key')));
      await tester.pumpAndSettle();
      expect(_titles, findsOneWidget);
    });
  });

  group('server status', () {
    final chip = find.byKey(const Key('shell-servers'));
    String text(WidgetTester tester) => tester
        .widget<Text>(find.descendant(of: chip, matching: find.byType(Text)))
        .textSpan!
        .toPlainText();

    testWidgets('says so when no server was tested yet', (tester) async {
      await _boot(
        tester,
        app: testApp(sources: [testSource('a'), testSource('b')]),
      );

      expect(text(tester), '2 servers, not tested');
    });

    testWidgets('counts the servers that answered, and opens Server '
        'Discovery', (tester) async {
      final app = testApp(
        sources: [testSource('a'), testSource('b'), testSource('c')],
      );
      await app.sources.recordHealth({
        'a': SourceHealth(
          checkedAt: DateTime(2026, 11, 14),
          reachable: true,
          readable: true,
        ),
        // Answered, though the app cannot read it: still online.
        'b': SourceHealth(
          checkedAt: DateTime(2026, 11, 14),
          reachable: true,
          readable: false,
        ),
        'c': SourceHealth(
          checkedAt: DateTime(2026, 11, 14),
          reachable: false,
          readable: false,
        ),
      });
      await _boot(tester, app: app);

      expect(text(tester), '2 / 3 servers online');

      await tester.tap(chip);
      await tester.pumpAndSettle();
      expect(_discovery, findsOneWidget);
    });
  });

  group('window', () {
    testWidgets('has no window buttons with the system\'s title bar', (
      tester,
    ) async {
      await _boot(tester);

      expect(find.byKey(const Key('window-close')), findsNothing);
    });

    testWidgets('with its own frame, the title bar has the window buttons '
        'and moves the window', (tester) async {
      final window = FakeWindow();
      await _boot(tester, app: testApp(window: window));

      expect(find.byKey(const Key('window-minimize')), findsOneWidget);
      expect(tester.getRect(find.byKey(const Key('window-close'))).right, 1280);

      // The empty stretch between the brand and the search field.
      await tester.dragFrom(const Offset(260, 20), const Offset(40, 30));
      expect(window.calls, ['drag']);

      // The top edge resizes instead.
      await tester.dragFrom(const Offset(260, 2), const Offset(0, 30));
      expect(window.calls, ['drag', 'resize top']);
      // Let the wait for a second click run out.
      await tester.pump(const Duration(milliseconds: 500));
    });

    testWidgets('typing in the search field does not move the window', (
      tester,
    ) async {
      final window = FakeWindow();
      await _boot(tester, app: testApp(window: window));

      await tester.tap(_search);
      await tester.pump();
      await tester.drag(_search, const Offset(30, 0));
      await tester.pumpAndSettle();

      expect(window.calls, isEmpty);
      expect(_searchHasFocus(tester), isTrue);
    });
  });
}
