import 'dart:async';

import 'package:dhara/core/settings/key_value_store.dart';
import 'package:dhara/features/update/installer_fetcher.dart';
import 'package:dhara/features/update/installer_launcher.dart';
import 'package:dhara/features/update/update_checker.dart';
import 'package:dhara/features/update/update_controller.dart';
import 'package:dhara/features/update/update_notice.dart';
import 'package:dhara/features/update/update_words.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/update_notices.dart';

/// Settings whose file cannot be written.
class _ReadOnlyStore extends MemoryKeyValueStore {
  @override
  Future<void> setInt(String key, int value) async =>
      throw const FormatException('read-only');

  @override
  Future<void> setString(String key, String value) async =>
      throw const FormatException('read-only');

  @override
  Future<void> remove(String key) async =>
      throw const FormatException('read-only');
}

void main() {
  const current = AppVersion(1, 1, 0);
  var now = DateTime(2026, 11, 25, 10);
  late MemoryKeyValueStore settings;

  setUp(() {
    now = DateTime(2026, 11, 25, 10);
    settings = MemoryKeyValueStore();
  });

  UpdateController controller(FakeUpdateChecker checker) {
    final made = UpdateController(
      checker: checker,
      settings: settings,
      current: current,
      clock: () => now,
    );
    addTearDown(made.dispose);
    return made;
  }

  group('asking', () {
    test('finds a newer version, and keeps what it found', () async {
      final text = updateNoticeText(version: '1.2.0', notes: 'Faster.');
      final checker = FakeUpdateChecker(answers: [text]);
      final updates = controller(checker);
      expect(updates.available, isNull);
      expect(updates.askedAt, isNull);

      await updates.askNow();

      expect(checker.asked, 1);
      expect(updates.available!.version, const AppVersion(1, 2, 0));
      expect(updates.available!.notes, 'Faster.');
      expect(updates.problem, isNull);
      expect(updates.askedAt, now);
      expect(settings.getString(UpdateController.noticeKey), text);
    });

    test('a notice of this version or an older one is no update', () async {
      for (final version in const ['1.1.0', '1.0.9', '0.9.0']) {
        settings = MemoryKeyValueStore({
          UpdateController.noticeKey: 'left over',
        });
        final updates = controller(
          FakeUpdateChecker(answers: [updateNoticeText(version: version)]),
        );
        await updates.askNow();
        expect(updates.available, isNull, reason: version);
        expect(updates.problem, isNull, reason: version);
        expect(settings.getString(UpdateController.noticeKey), isNull);
        expect(updates.askedAt, now);
      }
    });

    test('says while it asks, and tells its listeners', () async {
      final gate = Completer<void>();
      final checker = FakeUpdateChecker(answers: [updateNoticeText()])
        ..hold = gate.future;
      final updates = controller(checker);
      final seen = <bool>[];
      updates.addListener(() => seen.add(updates.isAsking));

      final asking = updates.askNow();
      expect(updates.isAsking, isTrue);
      // A second click asks no second time.
      final again = updates.askNow();
      gate.complete();
      await Future.wait([asking, again]);

      expect(checker.asked, 1);
      expect(updates.isAsking, isFalse);
      expect(seen, [true, false]);
    });

    test(
      'that fails says why, and what was known before still holds',
      () async {
        final checker = FakeUpdateChecker(
          answers: [
            updateNoticeText(version: '1.2.0'),
            UpdateAskProblem.unreachable,
          ],
        );
        final updates = controller(checker);
        await updates.askNow();
        expect(updates.available, isNotNull);

        await updates.askNow();
        expect(updates.problem, UpdateAskProblem.unreachable);
        expect(updates.available!.version, const AppVersion(1, 2, 0));
        expect(settings.getString(UpdateController.noticeKey), isNotNull);
      },
    );

    test('takes nothing whose signature does not fit', () async {
      final checker = FakeUpdateChecker(
        answers: [updateNoticeText(version: '9.0.0')],
        fits: false,
      );
      final updates = controller(checker);
      await updates.askNow();
      expect(updates.available, isNull);
      expect(updates.problem, UpdateAskProblem.notSigned);
      expect(settings.getString(UpdateController.noticeKey), isNull);
    });
  });

  group('settings that cannot be written', () {
    test(
      'do not stop it from asking, nor let it ask again and again',
      () async {
        final checker = FakeUpdateChecker(
          answers: [updateNoticeText(version: '1.2.0')],
        );
        final updates = UpdateController(
          checker: checker,
          settings: _ReadOnlyStore(),
          current: current,
          clock: () => now,
        );
        addTearDown(updates.dispose);

        await updates.askIfDue();
        expect(checker.asked, 1);
        expect(updates.available!.version, const AppVersion(1, 2, 0));
        expect(updates.askedAt, now);

        now = now.add(const Duration(hours: 2));
        await updates.askIfDue();
        expect(checker.asked, 1, reason: 'it remembers for this run');
      },
    );
  });

  group('by itself', () {
    test('it asks once a day at most', () async {
      final checker = FakeUpdateChecker(answers: [updateNoticeText()]);
      final updates = controller(checker);

      await updates.askIfDue();
      expect(checker.asked, 1, reason: 'never asked before');

      now = now.add(const Duration(hours: 23, minutes: 59));
      await updates.askIfDue();
      expect(checker.asked, 1, reason: 'not a day ago');

      now = now.add(const Duration(minutes: 1));
      await updates.askIfDue();
      expect(checker.asked, 2, reason: 'a day ago');

      await updates.askIfDue();
      expect(checker.asked, 2);
    });

    test('an asking that failed counts as one too', () async {
      final checker = FakeUpdateChecker(
        answers: [UpdateAskProblem.unreachable],
      );
      final updates = controller(checker);
      await updates.askIfDue();
      now = now.add(const Duration(hours: 3));
      await updates.askIfDue();
      expect(checker.asked, 1);
      // The user can still ask.
      await updates.askNow();
      expect(checker.asked, 2);
    });

    test('a time of asking that lies in the future says nothing', () async {
      settings = MemoryKeyValueStore({
        UpdateController.askedAtKey: now
            .add(const Duration(days: 40))
            .millisecondsSinceEpoch,
      });
      final checker = FakeUpdateChecker(answers: [updateNoticeText()]);
      await controller(checker).askIfDue();
      expect(checker.asked, 1);
    });

    test(
      'after it is started it asks when a day has passed, not before',
      () async {
        final checker = FakeUpdateChecker(answers: [updateNoticeText()]);
        // Closed by the test itself.
        final updates = UpdateController(
          checker: checker,
          settings: settings,
          current: current,
          clock: () => now,
        );
        updates.start(
          first: const Duration(milliseconds: 5),
          look: const Duration(milliseconds: 20),
        );
        expect(checker.asked, 0, reason: 'not while the app starts');

        await Future<void>.delayed(const Duration(milliseconds: 60));
        expect(checker.asked, 1);
        expect(updates.available, isNotNull);

        // It goes on looking, and asks again once the day is over.
        now = now.add(const Duration(days: 1, minutes: 1));
        await Future<void>.delayed(const Duration(milliseconds: 60));
        expect(checker.asked, 2);

        updates.dispose();
        now = now.add(const Duration(days: 3));
        await Future<void>.delayed(const Duration(milliseconds: 60));
        expect(checker.asked, 2, reason: 'nothing asks after it is closed');
      },
    );

    test('started within a day of the last asking, it does not ask', () async {
      settings = MemoryKeyValueStore({
        UpdateController.askedAtKey: now
            .subtract(const Duration(hours: 5))
            .millisecondsSinceEpoch,
      });
      final checker = FakeUpdateChecker(answers: [updateNoticeText()]);
      controller(checker).start(
        first: const Duration(milliseconds: 5),
        look: const Duration(milliseconds: 20),
      );
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(checker.asked, 0);
    });
  });

  group('what an earlier run found', () {
    test('is known again at the start, without asking', () {
      settings = MemoryKeyValueStore({
        UpdateController.noticeKey: updateNoticeText(version: '1.3.0'),
        UpdateController.askedAtKey: now.millisecondsSinceEpoch,
      });
      final checker = FakeUpdateChecker(answers: [updateNoticeText()]);
      final updates = controller(checker)..start();
      expect(updates.available!.version, const AppVersion(1, 3, 0));
      expect(checker.asked, 0);
    });

    test('is dropped once this copy is that version', () {
      settings = MemoryKeyValueStore({
        UpdateController.noticeKey: updateNoticeText(version: '1.1.0'),
      });
      final updates = controller(FakeUpdateChecker(answers: ['']))..start();
      expect(updates.available, isNull);
      expect(settings.getString(UpdateController.noticeKey), isNull);
    });

    test('is checked again: a notice changed on disk is not believed', () {
      for (final kept in [
        'not a notice',
        updateNoticeText(installer: 'https://elsewhere.example/setup'),
      ]) {
        settings = MemoryKeyValueStore({UpdateController.noticeKey: kept});
        final updates = controller(FakeUpdateChecker(answers: ['']))..start();
        expect(updates.available, isNull, reason: kept);
        expect(settings.getString(UpdateController.noticeKey), isNull);
      }
      // And one whose signature does not fit the key of this copy.
      settings = MemoryKeyValueStore({
        UpdateController.noticeKey: updateNoticeText(version: '9.9.9'),
      });
      final updates = controller(FakeUpdateChecker(answers: [''], fits: false))
        ..start();
      expect(updates.available, isNull);
      expect(settings.getString(UpdateController.noticeKey), isNull);
    });
  });

  group('the installer', () {
    UpdateController withInstallers(
      FakeInstallerFetcher? installers, {
      String version = '1.2.0',
    }) {
      final made = UpdateController(
        checker: FakeUpdateChecker(
          answers: [updateNoticeText(version: version, size: 4000)],
        ),
        settings: settings,
        current: current,
        installers: installers,
        clock: () => now,
      );
      addTearDown(made.dispose);
      return made;
    }

    test('is not fetched by asking, nor by starting', () async {
      final installers = FakeInstallerFetcher();
      final updates = withInstallers(installers)
        ..start(
          first: const Duration(milliseconds: 1),
          look: const Duration(milliseconds: 5),
        );
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(updates.available, isNotNull);
      expect(installers.fetched, isEmpty);
      expect(updates.step, isNull);
      // What an earlier run left is cleared as the app starts.
      expect(installers.cleared, 1);
    });

    test(
      'is fetched and checked when told to, and says how far it is',
      () async {
        final installers = FakeInstallerFetcher(progress: [1000, 4000]);
        final updates = withInstallers(installers);
        await updates.askNow();
        expect(updates.canFetchInstaller, isTrue);

        final steps = <(UpdateStep?, int)>[];
        updates.addListener(
          () => steps.add((updates.step, updates.bytesFetched)),
        );
        final fetching = updates.fetchInstaller();
        // A second click fetches no second time.
        final again = updates.fetchInstaller();
        final installer = await fetching;

        expect(await again, same(installer));
        expect(installers.fetched, hasLength(1));
        expect(installers.fetched.single.version, const AppVersion(1, 2, 0));
        expect(installer!.version, const AppVersion(1, 2, 0));
        expect(updates.installerProblem, isNull);
        expect(steps.first.$1, UpdateStep.fetching);
        expect(steps, contains((UpdateStep.checking, 4000)));
        expect(steps.last.$1, isNull);
        expect(updates.step, isNull);
      },
    );

    test(
      'that is not the file of the notice gives nothing, and says why',
      () async {
        for (final problem in InstallerProblem.values) {
          final installers = FakeInstallerFetcher(problem: problem);
          final updates = withInstallers(installers);
          await updates.askNow();
          expect(await updates.fetchInstaller(), isNull, reason: problem.name);
          expect(updates.installerProblem, problem);
          expect(updates.step, isNull);
          // The next try starts clean.
          installers.problem = null;
          expect(await updates.fetchInstaller(), isNotNull);
          expect(updates.installerProblem, isNull);
        }
      },
    );

    test('is not fetched while no newer version is known', () async {
      final installers = FakeInstallerFetcher();
      final updates = withInstallers(installers, version: '1.1.0');
      expect(await updates.fetchInstaller(), isNull);
      await updates.askNow();
      expect(updates.available, isNull);
      expect(await updates.fetchInstaller(), isNull);
      expect(installers.fetched, isEmpty);
      expect(updates.installerProblem, isNull);
    });

    test('cannot be fetched by a copy that has no folder for it', () async {
      final updates = withInstallers(null);
      await updates.askNow();
      expect(updates.available, isNotNull);
      expect(updates.canFetchInstaller, isFalse);
      expect(await updates.fetchInstaller(), isNull);
    });

    test('a fetch the user ends gives nothing and is no problem', () async {
      final installers = FakeInstallerFetcher()..hold = Completer<void>();
      final updates = withInstallers(installers);
      await updates.askNow();

      final fetching = updates.fetchInstaller();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(updates.step, UpdateStep.fetching);
      updates.stopFetching();

      expect(await fetching, isNull);
      expect(installers.cancelled, 1);
      expect(updates.installerProblem, isNull);
      expect(updates.step, isNull);
      // Ending what is not running does nothing.
      updates.stopFetching();
      expect(installers.cancelled, 1);
    });
  });

  group('installing', () {
    late List<String> started;
    var startWorks = true;
    setUp(() {
      started = [];
      startWorks = true;
    });

    UpdateController installing(
      FakeInstallerFetcher? installers, {
      bool withLauncher = true,
      String version = '1.2.0',
    }) {
      final made = UpdateController(
        checker: FakeUpdateChecker(
          answers: [updateNoticeText(version: version, size: 4000)],
        ),
        settings: settings,
        current: current,
        installers: installers,
        launcher: withLauncher
            ? InstallerLauncher(
                start: (path) async {
                  if (!startWorks) throw const FormatException('refused');
                  started.add(path);
                },
              )
            : null,
        clock: () => now,
      );
      addTearDown(made.dispose);
      return made;
    }

    test('nothing is started by asking, by starting the app or by '
        'fetching', () async {
      final installers = FakeInstallerFetcher();
      final updates = installing(installers)
        ..start(
          first: const Duration(milliseconds: 1),
          look: const Duration(milliseconds: 5),
        );
      await Future<void>.delayed(const Duration(milliseconds: 40));
      await updates.askNow();
      expect(updates.available, isNotNull);
      expect(await updates.fetchInstaller(), isNotNull);
      expect(started, isEmpty);
      expect(updates.installerStarted, isFalse);
    });

    test('fetches, checks, then starts the checked file, in that '
        'order', () async {
      final installers = FakeInstallerFetcher(progress: [1000, 4000]);
      final updates = installing(installers);
      await updates.askNow();
      expect(updates.canInstall, isTrue);

      final steps = <UpdateStep?>[];
      updates.addListener(() {
        if (steps.isEmpty || steps.last != updates.step) {
          steps.add(updates.step);
        }
        // Nothing is started before the check is over.
        if (updates.step != UpdateStep.starting && updates.step != null) {
          expect(started, isEmpty);
        }
      });
      final installing1 = updates.install();
      expect(updates.isInstalling, isTrue);
      // A second click does it no second time.
      final installing2 = updates.install();

      expect(await installing1, isTrue);
      expect(await installing2, isTrue);
      expect(installers.fetched, hasLength(1));
      expect(started, ['nowhere/Dhara-Setup-1.2.0.exe']);
      expect(steps, [
        UpdateStep.fetching,
        UpdateStep.checking,
        // Between the check and the start.
        null,
        UpdateStep.starting,
        null,
      ]);
      expect(updates.installerStarted, isTrue);
      expect(updates.installerProblem, isNull);
      expect(updates.isInstalling, isFalse);
    });

    test('whatever the fetch or the check finds wrong, nothing is '
        'started', () async {
      for (final problem in InstallerProblem.values) {
        final installers = FakeInstallerFetcher(problem: problem);
        final updates = installing(installers);
        await updates.askNow();
        expect(await updates.install(), isFalse, reason: problem.name);
        expect(started, isEmpty, reason: problem.name);
        expect(updates.installerProblem, problem);
        expect(updates.installerStarted, isFalse);
        expect(updates.step, isNull);
      }
    });

    test('an installer Windows does not start is said, and not kept', () async {
      final installers = FakeInstallerFetcher();
      final updates = installing(installers);
      await updates.askNow();
      startWorks = false;

      expect(await updates.install(), isFalse);
      expect(updates.installerProblem, InstallerProblem.notStarted);
      expect(updates.installerStarted, isFalse);
      expect(installers.cleared, 1);

      // The next try fetches and checks anew.
      startWorks = true;
      expect(await updates.install(), isTrue);
      expect(installers.fetched, hasLength(2));
      expect(updates.installerProblem, isNull);
    });

    test('a fetch the user ends starts nothing', () async {
      final installers = FakeInstallerFetcher()..hold = Completer<void>();
      final updates = installing(installers);
      await updates.askNow();

      final running = updates.install();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      updates.stopFetching();

      expect(await running, isFalse);
      expect(started, isEmpty);
      expect(updates.installerProblem, isNull);
      expect(updates.isInstalling, isFalse);
    });

    test('nothing is installed while no newer version is known', () async {
      final installers = FakeInstallerFetcher();
      final updates = installing(installers, version: '1.1.0');
      await updates.askNow();
      expect(await updates.install(), isFalse);
      expect(installers.fetched, isEmpty);
      expect(started, isEmpty);
    });

    test('a copy without the means installs nothing', () async {
      final installers = FakeInstallerFetcher();
      final noLauncher = installing(installers, withLauncher: false);
      await noLauncher.askNow();
      expect(noLauncher.canInstall, isFalse);
      expect(await noLauncher.install(), isFalse);
      expect(installers.fetched, isEmpty, reason: 'not even fetched');

      final noFolder = installing(null);
      await noFolder.askNow();
      expect(noFolder.canInstall, isFalse);
      expect(await noFolder.install(), isFalse);
      expect(started, isEmpty);
    });
  });

  group('what Settings says', () {
    String words({
      bool asking = false,
      String? available,
      UpdateAskProblem? problem,
      Duration? asked,
    }) => updateStatus(
      current: current,
      asking: asking,
      available: available == null
          ? null
          : UpdateNotice(
              version: AppVersion.parse(available)!,
              installer: Uri.parse('https://updates.example/installer'),
              size: 1,
              sha256: '0' * 64,
            ),
      problem: problem,
      askedAt: asked == null ? null : now.subtract(asked),
      now: now,
    );

    test('before the first asking: what it will do', () {
      expect(words(), contains('asks once a day'));
      expect(words(), contains('Nothing is fetched or installed by itself'));
    });

    test('while asking, and after', () {
      expect(words(asking: true, available: '1.2.0'), startsWith('Asking'));
      expect(
        words(asked: const Duration(seconds: 20)),
        'This copy, 1.1.0, is the newest version. Asked just now.',
      );
      expect(
        words(asked: const Duration(minutes: 12)),
        endsWith('12 minutes ago.'),
      );
      expect(
        words(asked: const Duration(minutes: 70)),
        endsWith('an hour ago.'),
      );
      expect(words(asked: const Duration(hours: 5)), endsWith('5 hours ago.'));
      expect(words(asked: const Duration(hours: 30)), endsWith('yesterday.'));
      expect(words(asked: const Duration(days: 4)), endsWith('4 days ago.'));
    });

    test('a newer version comes before a problem of the last asking', () {
      final said = words(
        available: '1.2.0',
        problem: UpdateAskProblem.unreachable,
        asked: const Duration(hours: 1),
      );
      expect(
        said,
        startsWith('Version 1.2.0 is available; this copy is 1.1.0.'),
      );
    });

    test('a copy that can install says that nothing happens before a '
        'click', () {
      final said = updateStatus(
        current: current,
        asking: false,
        available: UpdateNotice(
          version: const AppVersion(1, 2, 0),
          installer: Uri.parse('https://updates.example/installer'),
          size: 1,
          sha256: '0' * 64,
        ),
        problem: null,
        askedAt: now,
        now: now,
        canInstall: true,
      );
      expect(said, startsWith('Version 1.2.0 is available; this copy is'));
      expect(said, endsWith('until you choose Install.'));
    });

    test('every problem of an installer has its own words, and each says '
        'that nothing was installed', () {
      final said = {
        for (final problem in InstallerProblem.values)
          installerProblemWords(problem),
      };
      expect(said, hasLength(InstallerProblem.values.length));
      expect(said, everyElement(endsWith('Nothing was installed.')));
      expect(megabytes(50651234), '48.3 MB');
      expect(megabytes(0), '0.0 MB');
    });

    test('every problem has its own words', () {
      final said = {
        for (final problem in UpdateAskProblem.values)
          words(problem: problem, asked: const Duration(hours: 1)),
      };
      expect(said, hasLength(UpdateAskProblem.values.length));
      expect(said.where((text) => text.contains('newest version')), isEmpty);
    });
  });
}
