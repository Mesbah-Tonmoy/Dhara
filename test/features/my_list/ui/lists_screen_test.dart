import 'package:dhara/core/db/library_db.dart';
import 'package:dhara/core/db/library_isolate.dart';
import 'package:dhara/features/history/history_controller.dart';
import 'package:dhara/features/history/history_store.dart';
import 'package:dhara/features/home/ui/poster_card.dart';
import 'package:dhara/features/indexer/index_controller.dart';
import 'package:dhara/features/metadata/titles_controller.dart';
import 'package:dhara/features/my_list/my_list_controller.dart';
import 'package:dhara/features/my_list/ui/lists_screen.dart';
import 'package:dhara/features/player/resume_store.dart';
import 'package:dhara/features/sources/source_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/test_app.dart';

final _now = DateTime.now();

/// Three films and the show "The Bay" on the source "a".
LibraryDb _library() {
  final library = LibraryDb.inMemory();
  final db = library.db
    ..execute("INSERT INTO sources (id, source_id) VALUES (1, 'a')")
    ..execute(
      'INSERT INTO folders (id, source, url, path, depth) '
      "VALUES (1, 1, 'http://10.0.0.1/a/', 'All', 0)",
    );
  void add(int id, int kind, String name, {int? episode}) {
    db
      ..execute(
        'INSERT OR IGNORE INTO titles (id, kind, name, year, tmdb_id, '
        'match_state, runtime, added_at) VALUES (?, ?, ?, 2019, ?, 1, 98, 0)',
        [id, kind, name, id],
      )
      ..execute(
        'INSERT INTO files (folder, name, url, added_at) VALUES (1, ?, ?, 0)',
        [
          '$name ${episode ?? ''}.mkv',
          'http://10.0.0.1/a/$id-${episode ?? 0}.mkv',
        ],
      )
      ..execute(
        'INSERT INTO file_meta (file, parser, kind, title, season, episode, '
        'episode_name, height) '
        'VALUES (last_insert_rowid(), 1, ?, ?, ?, ?, ?, 1080)',
        [
          kind,
          id,
          if (episode != null) 1 else null,
          episode,
          if (episode != null) 'Part $episode' else null,
        ],
      );
  }

  for (var n = 1; n <= 3; n++) {
    add(n, 0, 'Film $n');
  }
  add(9, 1, 'The Bay', episode: 1);
  add(9, 1, 'The Bay', episode: 2);
  return library;
}

/// Notes that [url] was watched [ago] ago, to the end or up to a quarter.
void _watched(
  LibraryDb db,
  String url, {
  required Duration ago,
  bool finished = false,
}) {
  final at = _now.subtract(ago).millisecondsSinceEpoch;
  db.db.execute(
    'INSERT INTO watch_history '
    '(url, watched_at, position_ms, duration_ms, finished) '
    'VALUES (?, ?, ?, 2400000, ?)',
    [url, at, finished ? 2400000 : 600000, finished ? 1 : 0],
  );
  if (!finished) {
    db.db.execute(
      'INSERT INTO playback (url, position_ms, duration_ms, updated_at) '
      'VALUES (?, 600000, 2400000, ?)',
      [url, at],
    );
  }
}

/// The app on [db] with the page of [tab] open.
Future<void> _open(WidgetTester tester, LibraryDb db, String tab) async {
  tester.view
    ..physicalSize = const Size(1280, 900)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final (:app, :sources) = testApp(db: db, sources: [testSource('a')]);
  await sources.setEnabled(['a'], enabled: true);
  await tester.pumpWidget(app);
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(Key('rail-$tab')));
  await tester.pumpAndSettle();
}

String _text(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(Key(key))).data!;

List<String> _posters(WidgetTester tester) => [
  for (final card in tester.widgetList<PosterCard>(find.byType(PosterCard)))
    card.title.name,
];

void main() {
  group('My List', () {
    testWidgets('shows the saved titles, the one added last first', (
      tester,
    ) async {
      final db = _library();
      db.db
        ..execute('INSERT INTO my_list (title, added_at) VALUES (2, 10)')
        ..execute('INSERT INTO my_list (title, added_at) VALUES (9, 20)');
      await _open(tester, db, 'myList');

      expect(_text(tester, 'lists-heading'), 'My List');
      expect(_text(tester, 'lists-info'), '2 saved titles');
      expect(_posters(tester), ['The Bay', 'Film 2']);
    });

    testWidgets('the button on a poster takes it off, for good', (
      tester,
    ) async {
      final db = _library();
      db.db
        ..execute('INSERT INTO my_list (title, added_at) VALUES (2, 10)')
        ..execute('INSERT INTO my_list (title, added_at) VALUES (9, 20)');
      await _open(tester, db, 'myList');

      await tester.tap(find.byKey(const Key('unlist-9')));
      await tester.pumpAndSettle();

      expect(_posters(tester), ['Film 2']);
      expect(_text(tester, 'lists-info'), '1 saved title');
      expect(find.textContaining('was taken off My List.'), findsOneWidget);
      expect(db.db.select('SELECT title FROM my_list').single.values, [2]);
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('says so when nothing is saved', (tester) async {
      await _open(tester, _library(), 'myList');

      expect(find.byKey(const Key('my-list-empty')), findsOneWidget);
      expect(find.text('Your list is empty'), findsOneWidget);
    });

    testWidgets('keeps a title whose videos are gone', (tester) async {
      final db = _library();
      db.db
        ..execute('INSERT INTO my_list (title, added_at) VALUES (2, 10)')
        ..execute('DELETE FROM files WHERE url LIKE ?', ['%/2-0.mkv']);
      await _open(tester, db, 'myList');

      expect(_posters(tester), ['Film 2']);
    });
  });

  group('History', () {
    testWidgets('lists what was watched, day by day, the latest first', (
      tester,
    ) async {
      final db = _library();
      _watched(db, 'http://10.0.0.1/a/1-0.mkv', ago: const Duration(hours: 1));
      _watched(
        db,
        'http://10.0.0.1/a/9-2.mkv',
        ago: const Duration(days: 1, hours: 1),
        finished: true,
      );
      _watched(
        db,
        'http://elsewhere.test/My%20Clip.mkv',
        ago: const Duration(days: 40),
      );
      await _open(tester, db, 'history');

      expect(_text(tester, 'lists-heading'), 'History');
      expect(
        _text(tester, 'lists-info'),
        '3 recently watched · kept on this PC only',
      );
      // Today (or yesterday, if the test runs just after midnight).
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Text &&
              (widget.data == 'TODAY' || widget.data == 'YESTERDAY'),
        ),
        findsWidgets,
      );
      expect(find.text('Film 1'), findsOneWidget);
      expect(find.text('2019 · 1h 38m'), findsOneWidget);
      expect(find.textContaining('via Server a · 30 min left'), findsOneWidget);
      expect(find.text('Resume'), findsNWidgets(2));
      expect(find.text('The Bay'), findsOneWidget);
      expect(find.text('S1 · E2 · Part 2'), findsOneWidget);
      expect(find.textContaining('via Server a · Finished'), findsOneWidget);
      expect(find.text('Watch again'), findsOneWidget);
      expect(find.text('My Clip.mkv'), findsOneWidget);
      expect(find.text('Not in the library'), findsOneWidget);
      // In the order they were watched.
      expect(
        tester.getTopLeft(find.text('Film 1')).dy,
        lessThan(tester.getTopLeft(find.text('The Bay')).dy),
      );
    });

    testWidgets('one video can be taken out, and is not offered to '
        'continue any more', (tester) async {
      final db = _library();
      _watched(db, 'http://10.0.0.1/a/1-0.mkv', ago: const Duration(hours: 1));
      _watched(db, 'http://10.0.0.1/a/2-0.mkv', ago: const Duration(hours: 2));
      await _open(tester, db, 'history');

      await tester.tap(find.byTooltip('Remove from the history').first);
      await tester.pumpAndSettle();

      expect(find.text('Film 1'), findsNothing);
      expect(find.text('Film 2'), findsOneWidget);
      expect(db.db.select('SELECT url FROM watch_history').single.values, [
        'http://10.0.0.1/a/2-0.mkv',
      ]);
      expect(db.db.select('SELECT count(*) FROM playback').single.values, [1]);
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('all of it can be cleared, after asking', (tester) async {
      final db = _library();
      _watched(db, 'http://10.0.0.1/a/1-0.mkv', ago: const Duration(hours: 1));
      _watched(db, 'http://10.0.0.1/a/2-0.mkv', ago: const Duration(hours: 2));
      await _open(tester, db, 'history');

      await tester.tap(find.byKey(const Key('history-clear')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('history-clear-cancel')));
      await tester.pumpAndSettle();
      expect(find.text('Film 1'), findsOneWidget);

      await tester.tap(find.byKey(const Key('history-clear')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('history-clear-confirm')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('history-empty')), findsOneWidget);
      expect(find.byKey(const Key('history-clear')), findsNothing);
      expect(db.db.select('SELECT count(*) FROM watch_history').single.values, [
        0,
      ]);
      expect(db.db.select('SELECT count(*) FROM playback').single.values, [0]);
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('an address that is no longer allowed is not played', (
      tester,
    ) async {
      final db = _library();
      _watched(
        db,
        'ftp://elsewhere.test/clip.mkv',
        ago: const Duration(hours: 1),
      );
      await _open(tester, db, 'history');

      await tester.tap(find.text('Resume'));
      await tester.pump();

      expect(
        find.text('This address cannot be played any more.'),
        findsOneWidget,
      );
      await tester.pump(const Duration(seconds: 4));
    });
  });

  testWidgets('the two lists are one page with two tabs', (tester) async {
    await _open(tester, _library(), 'myList');

    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();
    expect(_text(tester, 'lists-heading'), 'History');
    expect(find.byKey(const Key('history-empty')), findsOneWidget);

    await tester.tap(find.text('My List').last);
    await tester.pumpAndSettle();
    expect(_text(tester, 'lists-heading'), 'My List');
  });

  group('labels', () {
    test('a day is named from today', () {
      final now = DateTime(2026, 11, 15, 9);
      expect(dayLabel(DateTime(2026, 11, 15, 0, 5), now), 'Today');
      expect(dayLabel(DateTime(2026, 11, 14, 23, 55), now), 'Yesterday');
      expect(dayLabel(DateTime(2026, 11, 3, 12), now), '3 Nov 2026');
      expect(clockLabel(DateTime(2026, 11, 15, 8, 5)), '08:05');
    });
  });

  group('HistoryController', () {
    test('removing and clearing reach the resume positions too', () async {
      final db = _library();
      addTearDown(db.close);
      _watched(db, 'http://10.0.0.1/a/1-0.mkv', ago: const Duration(hours: 1));
      _watched(db, 'http://10.0.0.1/a/2-0.mkv', ago: const Duration(hours: 2));
      final library = LocalLibrary(db);
      final sources = SourceStore(starter: [testSource('a')]);
      await sources.setEnabled(['a'], enabled: true);
      final index = IndexController(
        library: library,
        sources: sources,
        deviceId: 'dhara-test',
      );
      final titles = TitlesController(library: library, index: index);
      final resume = ResumeStore(library);
      await resume.load();
      final history = HistoryController(
        library: library,
        titles: titles,
        resume: resume,
      );
      addTearDown(() {
        history.dispose();
        titles.dispose();
        index.dispose();
      });
      final first = Uri.parse('http://10.0.0.1/a/1-0.mkv');
      final second = Uri.parse('http://10.0.0.1/a/2-0.mkv');
      expect(resume.positionFor(first), isNotNull);

      await history.load();
      expect(
        [for (final item in history.items!) item.title?.name],
        ['Film 1', 'Film 2'],
      );
      expect(history.items!.first.sourceId, 'a');

      await history.remove(history.items!.first);
      expect(resume.positionFor(first), isNull);
      expect(resume.positionFor(second), isNotNull);
      expect(HistoryStore(db).count(), 1);

      await history.clear();
      expect(resume.positionFor(second), isNull);
      expect(history.items, isEmpty);
      expect(HistoryStore(db).count(), 0);
    });

    test('My List gives its titles as cards', () async {
      final db = _library();
      addTearDown(db.close);
      final list = MyListController(library: LocalLibrary(db));
      addTearDown(list.dispose);
      list
        ..toggle(1)
        ..toggle(9);
      await pumpEventQueue();

      final cards = await list.cards(['a']);
      expect([for (final card in cards) card.name], ['The Bay', 'Film 1']);
      expect(cards.first.episodes, 2);
      // With its server off it is still listed.
      expect([for (final card in await list.cards([])) card.videos], [0, 0]);
    });
  });
}
