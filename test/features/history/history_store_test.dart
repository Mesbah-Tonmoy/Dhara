import 'package:dhara/core/db/library_db.dart';
import 'package:dhara/features/history/history_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late LibraryDb library;
  late HistoryStore store;
  late DateTime clock;

  setUp(() {
    library = LibraryDb.inMemory();
    clock = DateTime(2026, 11, 15, 21);
    store = HistoryStore(library, now: () => clock);
  });

  tearDown(() => library.close());

  void watch(String name, {int minutes = 30, bool finished = false}) {
    clock = clock.add(const Duration(minutes: 1));
    store.record(
      'http://a.test/$name',
      positionMs: Duration(minutes: minutes).inMilliseconds,
      durationMs: const Duration(hours: 2).inMilliseconds,
      finished: finished,
    );
  }

  List<String> names() => [
    for (final video in store.entries()) video.url.split('/').last,
  ];

  test('lists what was watched, the latest first', () {
    watch('a.mkv');
    watch('b.mkv', minutes: 45);

    final [latest, earlier] = store.entries();
    expect(latest.url, 'http://a.test/b.mkv');
    expect(latest.watchedAt, DateTime(2026, 11, 15, 21, 2));
    expect(latest.position, const Duration(minutes: 45));
    expect(latest.duration, const Duration(hours: 2));
    expect(latest.finished, isFalse);
    expect(earlier.url, 'http://a.test/a.mkv');
    expect(store.count(), 2);
  });

  test('a video is in it once: watching it again moves it up', () {
    watch('a.mkv');
    watch('b.mkv');
    watch('a.mkv', minutes: 50);

    expect(names(), ['a.mkv', 'b.mkv']);
    expect(store.entries().first.position, const Duration(minutes: 50));
  });

  test('a video watched to the end is kept as finished, all of it', () {
    watch('a.mkv', minutes: 117, finished: true);

    final video = store.entries().single;
    expect(video.finished, isTrue);
    expect(video.position, video.duration);

    // Started again later: it is under way once more.
    watch('a.mkv', minutes: 3);
    expect(store.entries().single.finished, isFalse);
    expect(store.entries().single.position, const Duration(minutes: 3));
  });

  test('takes a time other than now', () {
    store.record(
      'http://a.test/a.mkv',
      positionMs: 1000,
      durationMs: 5000,
      finished: false,
      at: DateTime(2026, 1, 2).millisecondsSinceEpoch,
    );

    expect(store.entries().single.watchedAt, DateTime(2026, 1, 2));
  });

  test('is read a page at a time', () {
    for (var i = 0; i < 7; i++) {
      watch('$i.mkv');
    }

    expect(
      [for (final v in store.entries(limit: 3)) v.url.split('/').last],
      ['6.mkv', '5.mkv', '4.mkv'],
    );
    expect(
      [
        for (final v in store.entries(limit: 3, offset: 6))
          v.url.split('/').last,
      ],
      ['0.mkv'],
    );
  });

  test('removes one video, or all of them', () {
    watch('a.mkv');
    watch('b.mkv');

    store.remove('http://a.test/a.mkv');
    expect(names(), ['b.mkv']);

    store.clear();
    expect(names(), isEmpty);
    expect(store.count(), 0);
  });

  test('keeps only the most recently watched videos', () {
    for (var i = 0; i < 12; i++) {
      watch('$i.mkv');
    }

    expect(store.trim(keep: 10), 2);
    expect(store.count(), 10);
    expect(names().last, '2.mkv');
    expect(store.trim(keep: 10), 0);
  });

  group('the History page', () {
    /// A film (title 1) on three servers and its trailer, and the first
    /// two episodes of a show (title 2), the first on two servers.
    setUp(() {
      final db = library.db
        ..execute("INSERT INTO sources (id, source_id) VALUES (1, 'a')")
        ..execute(
          'INSERT INTO folders (id, source, url, path, depth) '
          "VALUES (1, 1, 'http://a.test/', 'All', 0)",
        )
        ..execute(
          'INSERT INTO titles (id, kind, name, year, added_at) VALUES '
          "(1, 0, 'Film', 2020, 0), (2, 1, 'Show', 2021, 0)",
        );
      void add(String name, int title, {int? episode, int? extra}) {
        db
          ..execute(
            'INSERT INTO files (folder, name, url, added_at) '
            'VALUES (1, ?, ?, 0)',
            [name, 'http://a.test/$name'],
          )
          ..execute(
            'INSERT INTO file_meta (file, parser, kind, title, season, '
            'episode, extra) VALUES (last_insert_rowid(), 1, ?, ?, ?, ?, ?)',
            [
              if (episode == null) 0 else 1,
              title,
              if (episode != null) 1 else null,
              episode,
              extra,
            ],
          );
      }

      add('film-1.mkv', 1);
      add('film-2.mkv', 1);
      add('film-3.mkv', 1);
      add('film-trailer.mkv', 1, extra: 1);
      add('show-e1.mkv', 2, episode: 1);
      add('show-e1-b.mkv', 2, episode: 1);
      add('show-e2.mkv', 2, episode: 2);
    });

    List<String> listed() => [
      for (final item in store.items(sourceIds: ['a']))
        item.video.url.split('/').last,
    ];

    test('lists a film that went on from another server once, as the copy '
        'watched last', () {
      watch('film-1.mkv', minutes: 10);
      watch('film-2.mkv', minutes: 20);
      watch('other.mkv');
      watch('film-3.mkv', minutes: 40);

      expect(listed(), ['film-3.mkv', 'other.mkv']);
      final film = store.items(sourceIds: ['a']).first;
      expect(film.video.position, const Duration(minutes: 40));
      expect(film.otherCopies, [
        'http://a.test/film-2.mkv',
        'http://a.test/film-1.mkv',
      ]);
      expect(film.title?.name, 'Film');
    });

    test('keeps episodes apart, and a trailer apart from its film', () {
      watch('show-e1.mkv');
      watch('show-e2.mkv');
      watch('show-e1-b.mkv');
      watch('film-trailer.mkv');
      watch('film-1.mkv');

      expect(listed(), [
        'film-1.mkv',
        'film-trailer.mkv',
        'show-e1-b.mkv',
        'show-e2.mkv',
      ]);
    });

    test('a video that is taken out does not come back as another copy', () {
      watch('film-1.mkv');
      watch('film-2.mkv');
      watch('show-e2.mkv');
      library.db.execute(
        'INSERT INTO playback (url, position_ms, duration_ms, updated_at) '
        "VALUES ('http://a.test/film-1.mkv', 5, 9, 1)",
      );

      final film = store.items(sourceIds: ['a'])[1];
      store.forget(film.video.url, otherCopies: film.otherCopies);

      expect(listed(), ['show-e2.mkv']);
      expect(store.count(), 1);
      expect(library.db.select('SELECT url FROM playback'), isEmpty);
    });
  });

  test('takes a URL as it is, whatever it holds', () {
    const odd = "http://a.test/it's'; DROP TABLE watch_history; --.mkv";
    store.record(odd, positionMs: 1, durationMs: 2, finished: false);

    expect(store.entries().single.url, odd);
    store.remove(odd);
    expect(store.count(), 0);
  });
}
