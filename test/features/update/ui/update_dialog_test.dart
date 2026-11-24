import 'dart:async';

import 'package:dhara/core/app_info.dart';
import 'package:dhara/core/settings/key_value_store.dart';
import 'package:dhara/features/update/installer_fetcher.dart';
import 'package:dhara/features/update/installer_launcher.dart';
import 'package:dhara/features/update/ui/update_dialog.dart';
import 'package:dhara/features/update/update_controller.dart';
import 'package:dhara/features/update/update_notice.dart';
import 'package:dhara/features/update/update_words.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/test_app.dart';
import '../../../support/update_notices.dart';

const _pill = Key('shell-update');
const _install = Key('update-install');
const _later = Key('update-later');

/// A production build that knows of version 7.8.9, with what a test wants
/// to look at afterwards.
class _Rig {
  _Rig({
    this.installers,
    bool withLauncher = true,
    String version = '7.8.9',
    String? notes,
  }) {
    updates = UpdateController(
      checker: FakeUpdateChecker(
        answers: [
          updateNoticeText(version: version, size: 50651234, notes: notes),
        ],
      ),
      settings: MemoryKeyValueStore(),
      current: AppVersion.parse(dharaVersion)!,
      installers: installers,
      launcher: withLauncher
          ? InstallerLauncher(
              start: (path) async {
                if (!startWorks) throw const FormatException('refused');
                started.add(path);
              },
            )
          : null,
    );
  }

  final FakeInstallerFetcher? installers;
  late final UpdateController updates;
  final window = FakeWindow();
  final started = <String>[];
  var startWorks = true;

  Future<void> boot(
    WidgetTester tester, {
    Size size = const Size(1280, 720),
  }) async {
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    addTearDown(updates.dispose);
    await updates.askNow();
    await tester.pumpWidget(
      testApp(devTools: false, updates: updates, window: window).app,
    );
    await tester.pumpAndSettle();
  }

  /// Lets a fetch that waits on timers go on, a step at a time.
  Future<void> work(WidgetTester tester, [int steps = 12]) async {
    for (var step = 0; step < steps; step++) {
      await tester.pump(const Duration(milliseconds: 5));
    }
  }
}

void main() {
  testWidgets('a build that knows of no newer version shows no pill', (
    tester,
  ) async {
    final rig = _Rig(installers: FakeInstallerFetcher(), version: dharaVersion);
    await rig.boot(tester);
    expect(rig.updates.available, isNull);
    expect(find.byKey(_pill), findsNothing);

    // Nor does a build that has nothing that asks.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(testApp(devTools: false).app);
    await tester.pumpAndSettle();
    expect(find.byKey(_pill), findsNothing);
  });

  testWidgets('the pill says there is one; a click opens the dialog and '
      'fetches nothing', (tester) async {
    final installers = FakeInstallerFetcher();
    final rig = _Rig(installers: installers, notes: 'Faster start.\nনতুন');
    await rig.boot(tester);

    expect(find.byKey(_pill), findsOneWidget);
    expect(
      find.descendant(of: find.byKey(_pill), matching: find.text('Update')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(_pill));
    await tester.pumpAndSettle();

    expect(find.text('Dhara 7.8.9 is available'), findsOneWidget);
    expect(
      find.text('This copy is $dharaVersion. The installer is 48.3 MB.'),
      findsOneWidget,
    );
    expect(find.text('Faster start.\nনতুন'), findsOneWidget);
    expect(find.textContaining('Dhara then closes'), findsOneWidget);
    expect(find.text('Download and install'), findsOneWidget);
    expect(installers.fetched, isEmpty);
    expect(rig.started, isEmpty);

    // Later leaves everything as it was.
    await tester.tap(find.byKey(_later));
    await tester.pumpAndSettle();
    expect(find.byType(UpdateDialog), findsNothing);
    expect(installers.fetched, isEmpty);
    expect(rig.started, isEmpty);
    expect(rig.window.calls, isEmpty);
    expect(find.byKey(_pill), findsOneWidget);
  });

  testWidgets('the pill has room in the narrowest window', (tester) async {
    final rig = _Rig(installers: FakeInstallerFetcher());
    await rig.boot(tester, size: const Size(940, 560));
    expect(find.byKey(_pill), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Download and install fetches, checks, starts the installer '
      'and closes the app', (tester) async {
    final installers = FakeInstallerFetcher(progress: [25325617, 50651234])
      ..hold = Completer<void>();
    final rig = _Rig(installers: installers);
    await rig.boot(tester);
    await tester.tap(find.byKey(_pill));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(_install));
    await rig.work(tester);

    // Held half way: it says how far it is, and can be stopped.
    expect(find.textContaining('Fetching the installer:'), findsOneWidget);
    expect(find.textContaining('of 48.3 MB'), findsOneWidget);
    expect(find.byKey(const Key('update-stop')), findsOneWidget);
    expect(find.byKey(_install), findsNothing);
    expect(find.byKey(_later), findsNothing);
    final bar = tester.widget<LinearProgressIndicator>(
      find.byKey(const Key('update-progress')),
    );
    expect(bar.value, 1);
    expect(rig.started, isEmpty);
    expect(rig.window.calls, isEmpty);

    installers.hold!.complete();
    await rig.work(tester);

    expect(rig.started, ['nowhere/Dhara-Setup-7.8.9.exe']);
    expect(rig.window.calls, ['close']);
    expect(find.byKey(const Key('update-started')), findsOneWidget);
  });

  testWidgets('a file that is not the signed installer is said, and '
      'nothing is started', (tester) async {
    final installers = FakeInstallerFetcher(
      problem: InstallerProblem.notTheInstaller,
    );
    final rig = _Rig(installers: installers);
    await rig.boot(tester);
    await tester.tap(find.byKey(_pill));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(_install));
    await rig.work(tester);

    expect(
      find.text(installerProblemWords(InstallerProblem.notTheInstaller)),
      findsOneWidget,
    );
    expect(rig.started, isEmpty);
    expect(rig.window.calls, isEmpty);
    expect(find.text('Try again'), findsOneWidget);
    expect(find.byKey(_later), findsOneWidget);

    // Trying again does the whole of it again.
    installers.problem = null;
    await tester.tap(find.byKey(_install));
    await rig.work(tester);
    expect(installers.fetched, hasLength(2));
    expect(rig.started, hasLength(1));
    expect(rig.window.calls, ['close']);
  });

  testWidgets('an installer Windows does not start leaves the app open', (
    tester,
  ) async {
    final rig = _Rig(installers: FakeInstallerFetcher())..startWorks = false;
    await rig.boot(tester);
    await tester.tap(find.byKey(_pill));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(_install));
    await rig.work(tester);

    expect(
      find.text(installerProblemWords(InstallerProblem.notStarted)),
      findsOneWidget,
    );
    expect(rig.window.calls, isEmpty);
  });

  testWidgets('Stop ends the fetch; Esc does not close the dialog while it '
      'works', (tester) async {
    final installers = FakeInstallerFetcher()..hold = Completer<void>();
    final rig = _Rig(installers: installers);
    await rig.boot(tester);
    await tester.tap(find.byKey(_pill));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(_install));
    await rig.work(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await rig.work(tester, 3);
    expect(find.byType(UpdateDialog), findsOneWidget);
    // Nor does a click beside it.
    await tester.tapAt(const Offset(200, 600));
    await rig.work(tester, 3);
    expect(find.byType(UpdateDialog), findsOneWidget);
    expect(installers.cancelled, 0);

    await tester.tap(find.byKey(const Key('update-stop')));
    await rig.work(tester);
    expect(installers.cancelled, 1);
    expect(rig.started, isEmpty);
    expect(rig.window.calls, isEmpty);
    // Back to the offer, with nothing said to be wrong.
    expect(find.text('Download and install'), findsOneWidget);
    expect(find.byKey(const Key('update-problem')), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(UpdateDialog), findsNothing);
  });

  testWidgets('a copy that cannot install says so and offers no button', (
    tester,
  ) async {
    final rig = _Rig(installers: null);
    await rig.boot(tester);
    await tester.tap(find.byKey(_pill));
    await tester.pumpAndSettle();
    expect(find.textContaining('cannot fetch the installer'), findsOneWidget);
    expect(find.byKey(_install), findsNothing);
    expect(find.byKey(_later), findsOneWidget);
  });

  testWidgets('Settings leads to the same dialog', (tester) async {
    final installers = FakeInstallerFetcher();
    final rig = _Rig(installers: installers);
    await rig.boot(tester);
    await tester.tap(find.byKey(const Key('rail-settings')));
    await tester.pumpAndSettle();

    final open = find.byKey(const Key('set-install-update'));
    await tester.ensureVisible(open);
    await tester.pumpAndSettle();
    expect(find.textContaining('until you choose Install.'), findsOneWidget);
    await tester.tap(open);
    await tester.pumpAndSettle();

    expect(find.byType(UpdateDialog), findsOneWidget);
    expect(installers.fetched, isEmpty, reason: 'the click fetched nothing');
  });
}
