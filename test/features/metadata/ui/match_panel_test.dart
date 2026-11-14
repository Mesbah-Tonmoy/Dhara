import 'dart:io';

import 'package:dhara/core/db/library_db.dart';
import 'package:dhara/core/db/library_isolate.dart';
import 'package:dhara/core/secrets/secret_store.dart';
import 'package:dhara/features/indexer/index_controller.dart';
import 'package:dhara/features/metadata/match_controller.dart';
import 'package:dhara/features/metadata/titles_controller.dart';
import 'package:dhara/features/metadata/tmdb_key.dart';
import 'package:dhara/features/metadata/ui/match_panel.dart';
import 'package:dhara/features/sources/source.dart';
import 'package:dhara/features/sources/source_store.dart';
import 'package:dhara/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fake_tmdb.dart';
import '../../../support/local_server.dart';

const _apiKey = '0123456789abcdef0123456789abcdef';

void main() {
  late LocalServer server;
  late FakeTmdb tmdb;
  late MatchController match;
  late TmdbKeyController tmdbKey;

  // A widget test answers every request itself, with an error; these go to
  // the stand-in for TMDB on this machine.
  setUp(() => HttpOverrides.global = null);

  /// Shows the panel over an index with the films called [names], their
  /// names read. Everything that takes real time runs outside the fake
  /// clock of the widget test.
  Future<void> show(
    WidgetTester tester, {
    List<String> names = const [],
    bool withKey = true,
  }) async {
    tester.view.physicalSize = const Size(1200, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(() async {
      server = await LocalServer.start();
      tmdb = FakeTmdb(server);
      final db = LibraryDb.inMemory();
      addTearDown(db.close);
      db.db
        ..execute(
          'INSERT INTO sources (source_id, crawl_started_at, '
          "crawl_finished_at) VALUES ('icc', 1, 2)",
        )
        ..execute(
          'INSERT INTO folders (source, url, path, depth, state) '
          "VALUES (1, 'http://icc.test/', 'Movies', 1, 1)",
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
      if (withKey) await secrets.write('tmdb', _apiKey);
      tmdbKey = TmdbKeyController(secrets);
      await tmdbKey.load();
      match = MatchController(
        library: library,
        titles: titles,
        tmdbKey: tmdbKey,
        tmdbUrl: tmdb.url,
        tmdbRetries: 0,
      );
      addTearDown(() async {
        match.dispose();
        titles.dispose();
        index.dispose();
        await server.close();
      });
      await index.load();
      await titles.refresh();
      await match.load();
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: buildDharaTheme(),
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(24),
            child: MatchPanel(match: match, tmdbKey: tmdbKey),
          ),
        ),
      ),
    );
  }

  String text(WidgetTester tester, String key) =>
      tester.widget<Text>(find.byKey(Key(key))).data!;

  testWidgets('without a key it says what a key is for', (tester) async {
    await show(tester, names: ['A (2001).mkv'], withKey: false);

    expect(
      text(tester, 'match-counts'),
      '0 matched  ·  0 unsure  ·  0 not found  ·  1 not looked up yet',
    );
    expect(text(tester, 'match-status'), startsWith('Add a TMDB key'));
    expect(find.byKey(const Key('match-start-stop')), findsNothing);
  });

  testWidgets('with a key and titles to look up it offers to start', (
    tester,
  ) async {
    await show(tester, names: ['A (2001).mkv', 'B (2002).mkv']);

    expect(text(tester, 'match-counts'), endsWith('2 not looked up yet'));
    expect(text(tester, 'match-status'), contains('takes a while'));
    expect(find.text('Match now'), findsOneWidget);
  });

  testWidgets('with nothing to look up there is no button', (tester) async {
    await show(tester);

    expect(text(tester, 'match-status'), 'Nothing to look up.');
    expect(find.byKey(const Key('match-start-stop')), findsNothing);
  });

  testWidgets('a run shows its result when it is over', (tester) async {
    await show(tester, names: ['A (2001).mkv', 'B (2002).mkv']);
    tmdb.addFilm(1, 'A', 2001);

    await tester.runAsync(match.start);
    await tester.pump();

    expect(
      text(tester, 'match-counts'),
      '1 matched  ·  0 unsure  ·  1 not found  ·  0 not looked up yet',
    );
    expect(
      text(tester, 'match-status'),
      startsWith('Every title has been looked up. "Check again"'),
    );
    expect(find.text('Match now'), findsNothing);
  });

  testWidgets('with everything looked up it offers to check again', (
    tester,
  ) async {
    await show(tester, names: ['A (2001).mkv', 'B (2002).mkv']);
    tmdb.addFilm(1, 'A', 2001);
    await tester.runAsync(match.start);
    await tester.pump();
    final asked = tmdb.asked.length;

    expect(find.text('Check again'), findsOneWidget);
    await tester.runAsync(
      () => tester.tap(find.byKey(const Key('match-start-stop'))),
    );
    await tester.pump();

    expect(match.isRunning, isTrue);
    expect(find.text('Stop'), findsOneWidget);
    expect(
      text(tester, 'match-status'),
      'Judging the unsure and not-found titles again …',
    );

    await tester.runAsync(match.start);
    await tester.pump();
    // The answers that were kept are enough for this.
    expect(tmdb.asked, hasLength(asked));
    expect(
      text(tester, 'match-counts'),
      '1 matched  ·  0 unsure  ·  1 not found  ·  0 not looked up yet',
    );
    expect(find.text('Check again'), findsOneWidget);
  });

  testWidgets('with every title matched there is no button', (tester) async {
    await show(tester, names: ['A (2001).mkv']);
    tmdb.addFilm(1, 'A', 2001);

    await tester.runAsync(match.start);
    await tester.pump();

    expect(text(tester, 'match-status'), 'Every title has been looked up.');
    expect(find.byKey(const Key('match-start-stop')), findsNothing);
  });

  testWidgets('a refused key is said in so many words', (tester) async {
    await show(tester, names: ['A (2001).mkv']);
    tmdb.failWith = 401;

    await tester.runAsync(match.start);
    await tester.pump();

    expect(text(tester, 'match-status'), startsWith('TMDB does not accept'));
    expect(find.text('Match now'), findsOneWidget);
  });

  testWidgets('the button starts a run and turns into Stop', (tester) async {
    await show(
      tester,
      names: [for (var i = 0; i < 12; i++) 'Film Number $i (2001).mkv'],
    );

    // Tapped outside the fake clock, so that the run it starts can go on.
    await tester.runAsync(
      () => tester.tap(find.byKey(const Key('match-start-stop'))),
    );
    await tester.pump();

    expect(match.isRunning, isTrue);
    expect(find.text('Stop'), findsOneWidget);
    expect(text(tester, 'match-status'), startsWith('Asking TMDB'));

    await tester.runAsync(match.start);
    await tester.pump();
    expect(find.text('Stop'), findsNothing);
    expect(
      text(tester, 'match-status'),
      startsWith('Every title has been looked up.'),
    );
  });
}
