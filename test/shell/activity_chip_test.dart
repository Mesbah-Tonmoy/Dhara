import 'package:dhara/features/snapshot/first_start_controller.dart';
import 'package:dhara/shell/activity_chip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_first_start.dart';
import '../support/test_app.dart';

void main() {
  group('what the title bar says about work in the background', () {
    test('is nothing while nothing is being done', () {
      expect(backgroundActivity(), isNull);
      // Names are read in a blink when there are none to read.
      expect(backgroundActivity(readingNames: true), isNull);
    });

    test('is how far each kind of work is', () {
      final ready = backgroundActivity(
        gettingReady: true,
        readyProgress: .456,
      )!;
      expect(ready.label, 'Getting ready 45%');
      expect(ready.progress, .456);

      final servers = backgroundActivity(
        readingServers: true,
        serversDone: 12,
        servers: 29,
      )!;
      expect(servers.label, 'Reading servers 12/29');
      expect(servers.progress, closeTo(12 / 29, 1e-9));
      expect(servers.explanation, contains('new films and shows'));

      final names = backgroundActivity(
        readingNames: true,
        namesRead: 250,
        namesToRead: 1000,
      )!;
      expect(names.label, 'Reading names 25%');

      final posters = backgroundActivity(
        lookingUp: true,
        lookedUp: 30,
        toLookUp: 40,
      )!;
      expect(posters.label, 'Finding posters 75%');
      expect(posters.progress, .75);
    });

    test('does without a number it does not have', () {
      expect(backgroundActivity(gettingReady: true)!.label, 'Getting ready');
      expect(backgroundActivity(gettingReady: true)!.progress, isNull);
      expect(
        backgroundActivity(readingServers: true)!.label,
        'Reading servers',
      );
      expect(backgroundActivity(lookingUp: true)!.label, 'Finding posters');
      // More done than there was to do is all of it.
      expect(
        backgroundActivity(lookingUp: true, lookedUp: 9, toLookUp: 4)!.progress,
        1,
      );
    });

    test('names the work that comes first when several are under way', () {
      expect(
        backgroundActivity(
          gettingReady: true,
          readingServers: true,
          lookingUp: true,
        )!.label,
        'Getting ready',
      );
      expect(
        backgroundActivity(
          readingServers: true,
          servers: 3,
          readingNames: true,
          namesToRead: 5,
          lookingUp: true,
        )!.label,
        'Reading servers 0/3',
      );
      expect(
        backgroundActivity(
          readingNames: true,
          namesToRead: 5,
          lookingUp: true,
        )!.label,
        'Reading names 0%',
      );
    });
  });

  group('in the title bar', () {
    Future<void> boot(
      WidgetTester tester, {
      required bool devTools,
      FirstStartController? firstStart,
    }) async {
      tester.view
        ..physicalSize = const Size(1280, 720)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        testApp(devTools: devTools, firstStart: firstStart).app,
      );
      await tester.pump(const Duration(milliseconds: 300));
    }

    testWidgets('a production build says what it is doing, and nothing '
        'when it does nothing', (tester) async {
      final start = FakeFirstStart()
        ..isWorking = true
        ..step = FirstStartStep.reading
        ..progress = .3;
      await boot(tester, devTools: false, firstStart: start);

      expect(find.byKey(const Key('shell-activity')), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const Key('shell-activity-label'))).data,
        'Getting ready 30%',
      );
      // It stands between the brand and the search field, over neither.
      final chip = tester.getRect(find.byKey(const Key('shell-activity')));
      expect(
        chip.left,
        greaterThan(tester.getRect(find.byKey(const Key('shell-brand'))).right),
      );
      expect(
        chip.right,
        lessThan(tester.getRect(find.byKey(const Key('shell-search'))).left),
      );

      start
        ..isWorking = false
        ..step = null
        ..change();
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('shell-activity')), findsNothing);
    });

    testWidgets('a development build has its pages for that, and no chip', (
      tester,
    ) async {
      final start = FakeFirstStart()..isWorking = true;
      await boot(tester, devTools: true, firstStart: start);

      expect(find.byKey(const Key('shell-activity')), findsNothing);
    });
  });
}
