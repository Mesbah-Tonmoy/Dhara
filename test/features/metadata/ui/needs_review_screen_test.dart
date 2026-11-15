import 'dart:io';

import 'package:dhara/core/db/library_db.dart';
import 'package:dhara/core/db/library_isolate.dart';
import 'package:dhara/core/secrets/secret_store.dart';
import 'package:dhara/features/indexer/index_controller.dart';
import 'package:dhara/features/metadata/match_controller.dart';
import 'package:dhara/features/metadata/match_store.dart';
import 'package:dhara/features/metadata/review_controller.dart';
import 'package:dhara/features/metadata/titles_controller.dart';
import 'package:dhara/features/metadata/tmdb_key.dart';
import 'package:dhara/features/metadata/ui/needs_review_screen.dart';
import 'package:dhara/features/sources/source.dart';
import 'package:dhara/features/sources/source_store.dart';
import 'package:dhara/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fake_tmdb.dart';
import '../../../support/local_server.dart';

const _apiKey = '0123456789abcdef0123456789abcdef';

void main() {
  late LibraryDb db;
  late FakeTmdb tmdb;
  late MatchController match;
  late ReviewController review;

  // A widget test answers every request itself, with an error; these go to
  // the stand-in for TMDB on this machine.
  setUp(() => HttpOverrides.global = null);

  /// Shows the screen over a library with the films called [names], looked
  /// up on a stand-in for TMDB that knows a few films. Everything that
  /// takes real time runs outside the fake clock of the widget test.
  Future<void> show(
    WidgetTester tester, {
    List<String> names = const [
      'Stillwater (2018) 1080p WEBDL.mkv',
      'Hell.mkv',
      'A Wrong Name (1999) 720p.mkv',
    ],
    int pageSize = 500,
  }) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(() async {
      final server = await LocalServer.start();
      tmdb = FakeTmdb(server)
        ..addFilm(1, 'Stillwater', 2018)
        ..addFilm(2, 'Hell', 2011, votes: 500)
        ..addFilm(3, 'Hell', 2005)
        ..addFilm(4, 'The Real Name', 1999);
      db = LibraryDb.inMemory();
      db.db
        ..execute(
          'INSERT INTO sources (source_id, crawl_started_at, '
          "crawl_finished_at) VALUES ('icc', 1, 2)",
        )
        ..execute(
          'INSERT INTO folders (source, url, path, depth, state) '
          "VALUES (1, 'http://icc.test/', 'Movies/English', 1, 1)",
        );
      for (final name in names) {
        db.db.execute(
          'INSERT INTO files (folder, name, url, added_at) VALUES (1, ?, ?, 0)',
          [name, 'http://icc.test/$name'],
        );
      }
      final sources = SourceStore(
        starter: [
          Source(
            id: 'icc',
            name: 'ICC',
            type: SourceType.directoryListing,
            category: SourceCategory.mixed,
            baseUrls: [Uri.parse('http://10.0.0.1/icc/')],
          ),
        ],
      );
      await sources.setEnabled(['icc'], enabled: true);
      final library = LocalLibrary(db);
      final index = IndexController(
        library: library,
        sources: sources,
        deviceId: 'dhara-test',
      );
      final titles = TitlesController(library: library, index: index);
      final secrets = MemorySecretStore();
      await secrets.write('tmdb', _apiKey);
      final tmdbKey = TmdbKeyController(secrets);
      await tmdbKey.load();
      match = MatchController(
        library: library,
        titles: titles,
        tmdbKey: tmdbKey,
        tmdbUrl: tmdb.url,
        tmdbRetries: 0,
      );
      review = ReviewController(
        library: library,
        titles: titles,
        match: match,
        tmdbKey: tmdbKey,
        tmdbUrl: tmdb.url,
        tmdbRetries: 0,
        pageSize: pageSize,
      );
      addTearDown(() async {
        review.dispose();
        match.dispose();
        titles.dispose();
        index.dispose();
        db.close();
        await server.close();
      });
      await index.load();
      await titles.refresh();
      await match.start();
      await review.load();
    });
    await tester.pumpWidget(
      ReviewScope(
        controller: review,
        child: MaterialApp(
          theme: buildDharaTheme(),
          home: const NeedsReviewScreen(),
        ),
      ),
    );
    await tester.pump();
  }

  /// Opens the title that shows as [label].
  Future<void> open(WidgetTester tester, String label) async {
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  int state(String name) =>
      db.db.select('SELECT match_state FROM titles WHERE name = ?', [
            name,
          ]).single['match_state']
          as int;

  testWidgets('lists the titles TMDB was not sure about', (tester) async {
    await show(tester);

    expect(find.text('2 TITLES'), findsOneWidget);
    expect(find.text('Hell (2011)'), findsOneWidget);
    expect(find.text('Unsure · 78'), findsOneWidget);
    expect(find.text('A Wrong Name (1999)'), findsOneWidget);
    expect(find.text('Not found'), findsOneWidget);
    expect(find.text('Movies/English / Hell.mkv'), findsOneWidget);
    expect(find.text('Stillwater (2018)'), findsNothing, reason: 'it is sure');
  });

  testWidgets('a list that is read a part at a time reads on by itself as '
      'its end comes into view', (tester) async {
    // One title at a time: showing the first asks for the second.
    await show(tester, pageSize: 1);
    expect(review.total, 2);
    expect(find.text('Hell (2011)'), findsOneWidget);

    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();

    expect(review.hasMore, isFalse);
    expect(find.text('2 TITLES'), findsOneWidget);
    expect(find.text('A Wrong Name (1999)'), findsOneWidget);
    expect(find.byKey(const Key('review-more')), findsNothing);
  });

  testWidgets('says so when there is nothing to review', (tester) async {
    await show(tester, names: ['Stillwater (2018) 1080p WEBDL.mkv']);

    expect(find.text('NOTHING TO REVIEW'), findsOneWidget);
  });

  testWidgets('a title opens with what TMDB offered for it', (tester) async {
    await show(tester);
    final asked = tmdb.asked.length;

    await open(tester, 'Hell (2011)');

    expect(find.text('Which film is this?'), findsOneWidget);
    expect(find.text('PICK THE RIGHT ONE'), findsOneWidget);
    expect(find.byKey(const Key('review-candidate-2')), findsOneWidget);
    expect(find.byKey(const Key('review-candidate-3')), findsOneWidget);
    expect(find.text('Hell (2005)'), findsOneWidget);
    expect(find.text('About Hell.'), findsNWidgets(2));
    final name = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(const Key('review-name')),
        matching: find.byType(TextField),
      ),
    );
    expect(name.controller!.text, 'Hell');
    expect(tmdb.asked, hasLength(asked), reason: 'no request for this');

    await tester.tap(find.byKey(const Key('review-close')));
    await tester.pumpAndSettle();
    expect(find.text('Which film is this?'), findsNothing);
    expect(find.text('2 TITLES'), findsOneWidget);
  });

  testWidgets('picking a candidate settles the title', (tester) async {
    await show(tester);
    await open(tester, 'Hell (2011)');

    await tester.tap(find.byKey(const Key('review-candidate-3')));
    await tester.pumpAndSettle();

    expect(find.text('Which film is this?'), findsNothing);
    expect(find.text('1 TITLE'), findsOneWidget);
    expect(find.text('Hell (2011)'), findsNothing);
    expect(state('Hell'), MatchState.byHand);
    expect(
      db.db.select("SELECT year FROM titles WHERE name = 'Hell'").single.values,
      [2005],
    );
  });

  testWidgets('a title can be left as its files name it', (tester) async {
    await show(tester);
    await open(tester, 'A Wrong Name (1999)');
    expect(find.text('TMDB KNOWS NOTHING BY THAT NAME'), findsOneWidget);
    final year = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(const Key('review-year')),
        matching: find.byType(TextField),
      ),
    );
    expect(year.controller!.text, '1999');

    await tester.tap(find.byKey(const Key('review-leave')));
    await tester.pumpAndSettle();

    expect(find.text('1 TITLE'), findsOneWidget);
    expect(find.text('A Wrong Name (1999)'), findsNothing);
    expect(state('A Wrong Name'), MatchState.leftAlone);
  });

  testWidgets('searching by another name finds the film', (tester) async {
    await show(tester);
    await open(tester, 'A Wrong Name (1999)');

    await tester.enterText(
      find.byKey(const Key('review-name')),
      'The Real Name',
    );
    // Tapped outside the fake clock, so that the request can go out; each
    // step of it only goes on when the widget test lets it.
    await tester.runAsync(
      () => tester.tap(find.byKey(const Key('review-search'))),
    );
    final found = find.byKey(const Key('review-candidate-4'));
    for (var i = 0; i < 100 && found.evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }

    expect(found, findsOneWidget);
    expect(find.text('The Real Name (1999)'), findsOneWidget);
    expect(find.text('100'), findsOneWidget);

    await tester.tap(found);
    await tester.pumpAndSettle();
    expect(find.text('1 TITLE'), findsOneWidget);
    expect(state('The Real Name'), MatchState.byHand);
  });

  testWidgets('a search TMDB does not answer says why', (tester) async {
    await show(tester);
    await open(tester, 'A Wrong Name (1999)');
    tmdb.failWith = 401;

    await tester.enterText(find.byKey(const Key('review-name')), 'Other');
    await tester.runAsync(
      () => tester.tap(find.byKey(const Key('review-search'))),
    );
    final failure = find.byKey(const Key('review-failure'));
    for (var i = 0; i < 100 && failure.evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }

    expect(tester.widget<Text>(failure).data, 'TMDB does not accept the key.');
    expect(find.text('NO ANSWER'), findsOneWidget);
  });
}
