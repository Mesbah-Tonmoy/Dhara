import 'package:dhara/core/db/library_db.dart';
import 'package:dhara/core/db/library_isolate.dart';
import 'package:dhara/features/home/ui/first_start_view.dart';
import 'package:dhara/features/indexer/index_controller.dart';
import 'package:dhara/features/snapshot/first_start_controller.dart';
import 'package:dhara/features/snapshot/snapshot_fetcher.dart';
import 'package:dhara/features/snapshot/snapshot_reader.dart';
import 'package:dhara/features/sources/source_store.dart';
import 'package:dhara/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fake_first_start.dart';
import '../../../support/test_app.dart';

void main() {
  late FakeFirstStart start;

  setUp(() => start = FakeFirstStart());

  /// Shows the view over a source list of one server, switched on or not.
  Future<void> show(
    WidgetTester tester, {
    bool withStart = true,
    bool serverOn = false,
  }) async {
    final db = LibraryDb.inMemory();
    addTearDown(db.close);
    final store = SourceStore(starter: [testSource('alpha')]);
    if (serverOn) await store.setEnabled(['alpha'], enabled: true);
    final index = IndexController(
      library: LocalLibrary(db),
      sources: store,
      deviceId: 'dhara-test',
    );
    addTearDown(index.dispose);
    Widget view = const Center(
      child: FirstStartView(empty: Text('nothing here')),
    );
    if (withStart) view = FirstStartScope(controller: start, child: view);
    await tester.pumpWidget(
      IndexScope(
        controller: index,
        child: MaterialApp(
          theme: buildDharaTheme(),
          home: Scaffold(body: view),
        ),
      ),
    );
  }

  String step(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(const Key('home-first-start-step'))).data!;

  testWidgets('with nothing to say about a first start it is what it was '
      'given', (tester) async {
    await show(tester);
    expect(find.text('nothing here'), findsOneWidget);

    // A development build has no first start at all.
    await show(tester, withStart: false);
    expect(find.text('nothing here'), findsOneWidget);
  });

  testWidgets('says what a first start is doing, and how far it is', (
    tester,
  ) async {
    start
      ..isWorking = true
      ..step = FirstStartStep.testingServers;
    await show(tester);

    expect(find.byKey(const Key('home-first-start')), findsOneWidget);
    expect(find.text('Getting your library ready'), findsOneWidget);
    expect(find.text('nothing here'), findsNothing);
    expect(step(tester), startsWith('Finding the servers that answer'));

    start
      ..step = FirstStartStep.fetching
      ..bytesFetched = 24 * 1024 * 1024
      ..change();
    await tester.pump();
    expect(step(tester), 'Fetching the library … 24 MB');

    start
      ..bytesExpected = 77 * 1024 * 1024
      ..progress = 24 / 77
      ..change();
    await tester.pump();
    expect(step(tester), 'Fetching the library … 24 of 77 MB');

    start
      ..step = FirstStartStep.reading
      ..progress = .456
      ..change();
    await tester.pump();
    expect(step(tester), 'Putting the library in place … 45%');

    // Done: back to what Home shows without it.
    start
      ..isWorking = false
      ..step = null
      ..change();
    await tester.pumpAndSettle();
    expect(find.text('nothing here'), findsOneWidget);
  });

  testWidgets('a library that could not be fetched can be tried again, or '
      'the servers be read instead', (tester) async {
    start
      ..problem = FirstStartProblem.notFetched
      ..fetchProblem = SnapshotFetchProblem.unreachable
      ..serversFound = 1;
    await show(tester, serverOn: true);

    expect(find.text('The library could not be fetched'), findsOneWidget);
    expect(find.textContaining('did not answer'), findsOneWidget);
    expect(find.textContaining('read the servers itself'), findsOneWidget);
    expect(find.byKey(const Key('home-read-servers')), findsOneWidget);

    await tester.tap(find.byKey(const Key('home-first-start-retry')));
    expect(start.retries, 1);
  });

  testWidgets('says so when no server answered either', (tester) async {
    start
      ..problem = FirstStartProblem.notFetched
      ..fetchProblem = SnapshotFetchProblem.notThere
      ..serversFound = 0;
    await show(tester);

    expect(find.textContaining('is not where this copy'), findsOneWidget);
    expect(find.textContaining('None of the servers answered'), findsOneWidget);
    // Nothing is switched on, so there is nothing to read.
    expect(find.byKey(const Key('home-read-servers')), findsNothing);
    expect(find.byKey(const Key('home-empty-servers')), findsOneWidget);
  });

  testWidgets('says why a snapshot that was fetched was not taken', (
    tester,
  ) async {
    start
      ..problem = FirstStartProblem.notRead
      ..readProblem = SnapshotProblem.newerVersion;
    await show(tester);

    expect(find.textContaining('newer version of Dhara'), findsOneWidget);
    expect(find.byKey(const Key('home-first-start-retry')), findsOneWidget);
  });

  testWidgets('a build that has nothing to fetch offers no second try', (
    tester,
  ) async {
    start
      ..problem = FirstStartProblem.nothingToFetch
      ..serversFound = 1;
    await show(tester, serverOn: true);

    expect(find.text('Nothing to watch yet'), findsOneWidget);
    expect(find.textContaining('no library to start from'), findsOneWidget);
    expect(find.byKey(const Key('home-first-start-retry')), findsNothing);
    expect(find.byKey(const Key('home-read-servers')), findsOneWidget);
  });
}
