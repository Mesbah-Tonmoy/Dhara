import 'dart:convert';

import 'package:dhara/core/db/library_db.dart';
import 'package:dhara/core/db/library_isolate.dart';
import 'package:dhara/core/settings/key_value_store.dart';
import 'package:dhara/features/player/resume_store.dart';
import 'package:flutter_test/flutter_test.dart';

const _key = ResumeStore.legacyKey;
const _movie = Duration(hours: 2);

Uri _url(String name) => Uri.parse('http://10.16.100.244/movies/$name');

void main() {
  late LibraryDb db;
  late LocalLibrary library;
  var now = DateTime(2026, 11, 13, 20);

  setUp(() {
    db = LibraryDb.inMemory();
    library = LocalLibrary(db);
    now = DateTime(2026, 11, 13, 20);
  });

  tearDown(() => db.close());

  /// A store on the same database, as after a restart of the app.
  Future<ResumeStore> open({KeyValueStore? legacy}) async {
    final resume = ResumeStore(library, () => now);
    await resume.load(legacy: legacy);
    return resume;
  }

  /// Lets the writes that were sent off reach the database.
  Future<void> written() => pumpEventQueue();

  List<Object?> savedUrls() => [
    for (final row in db.db.select(
      'SELECT url FROM playback ORDER BY updated_at',
    ))
      row['url'],
  ];

  void watch(ResumeStore resume, String name, {int minutes = 5}) {
    // Every save is a moment later than the one before.
    now = now.add(const Duration(seconds: 1));
    resume.save(
      _url(name),
      position: Duration(minutes: minutes),
      duration: _movie,
    );
  }

  test('remembers a position and survives a restart', () async {
    final resume = await open();
    resume.save(
      _url('a.mkv'),
      position: const Duration(minutes: 42, seconds: 7),
      duration: _movie,
    );
    await written();

    expect(
      (await open()).positionFor(_url('a.mkv')),
      const Duration(minutes: 42, seconds: 7),
    );
  });

  test('has nothing for a video never played', () async {
    expect((await open()).positionFor(_url('a.mkv')), isNull);
  });

  test('keeps videos apart', () async {
    final resume = await open();
    watch(resume, 'a.mkv', minutes: 5);
    watch(resume, 'b.mkv', minutes: 9);

    expect(resume.positionFor(_url('a.mkv')), const Duration(minutes: 5));
    expect(resume.positionFor(_url('b.mkv')), const Duration(minutes: 9));
  });

  test('ignores the URL fragment but not the query', () async {
    final resume = await open()
      ..save(
        Uri.parse('http://h.example/a.mkv?v=1#t=5'),
        position: const Duration(minutes: 5),
        duration: _movie,
      );

    expect(
      resume.positionFor(Uri.parse('http://h.example/a.mkv?v=1')),
      const Duration(minutes: 5),
    );
    expect(resume.positionFor(Uri.parse('http://h.example/a.mkv?v=2')), isNull);
  });

  test(
    'forgets a video that is stopped near the start or in the credits',
    () async {
      final resume = await open();
      watch(resume, 'a.mkv');
      resume.save(
        _url('a.mkv'),
        position: const Duration(seconds: 3),
        duration: _movie,
      );
      expect(resume.positionFor(_url('a.mkv')), isNull);

      watch(resume, 'a.mkv');
      watch(resume, 'a.mkv', minutes: 118);
      expect(resume.positionFor(_url('a.mkv')), isNull);

      await written();
      expect(savedUrls(), isEmpty);
    },
  );

  test('does not touch anything while the duration is unknown', () async {
    final resume = await open();
    watch(resume, 'a.mkv');
    resume.save(
      _url('a.mkv'),
      position: Duration.zero,
      duration: Duration.zero,
    );

    expect(resume.positionFor(_url('a.mkv')), const Duration(minutes: 5));
  });

  test('clear forgets a video, also after a restart', () async {
    final resume = await open();
    watch(resume, 'a.mkv');
    watch(resume, 'b.mkv');
    resume.clear(_url('a.mkv'));
    await written();

    expect(resume.positionFor(_url('a.mkv')), isNull);
    final again = await open();
    expect(again.positionFor(_url('a.mkv')), isNull);
    expect(again.positionFor(_url('b.mkv')), const Duration(minutes: 5));
  });

  group('watch history', () {
    List<List<Object?>> history() => db.db
        .select(
          'SELECT url, position_ms, duration_ms, finished FROM watch_history '
          'ORDER BY watched_at',
        )
        .rows;

    test('a video watched far enough to resume is in it', () async {
      final resume = await open();
      watch(resume, 'a.mkv');
      watch(resume, 'a.mkv', minutes: 9);
      await written();

      expect(history(), [
        [
          '${_url('a.mkv')}',
          const Duration(minutes: 9).inMilliseconds,
          _movie.inMilliseconds,
          0,
        ],
      ]);
      expect(
        db.db.select('SELECT watched_at FROM watch_history').single.values,
        [now.millisecondsSinceEpoch],
      );
    });

    test('a video left in its first moments is not', () async {
      final resume = await open();
      resume.save(
        _url('a.mkv'),
        position: const Duration(seconds: 4),
        duration: _movie,
      );
      await written();

      expect(history(), isEmpty);
    });

    test('one that ended is kept as watched, and starts over', () async {
      final resume = await open();
      watch(resume, 'a.mkv', minutes: 100);
      now = now.add(const Duration(minutes: 20));
      resume.finish(_url('a.mkv'), duration: _movie);
      await written();

      expect(resume.positionFor(_url('a.mkv')), isNull);
      expect(savedUrls(), isEmpty);
      expect(history(), [
        ['${_url('a.mkv')}', _movie.inMilliseconds, _movie.inMilliseconds, 1],
      ]);
      expect((await open()).positionFor(_url('a.mkv')), isNull);
    });

    test('one left during the credits counts as watched too', () async {
      final resume = await open();
      watch(resume, 'a.mkv', minutes: 60);
      watch(resume, 'a.mkv', minutes: 117);
      await written();

      expect(resume.positionFor(_url('a.mkv')), isNull);
      expect(history().single.last, 1);
    });

    test('going back to the start forgets the position, not that it was '
        'watched', () async {
      final resume = await open();
      watch(resume, 'a.mkv', minutes: 60);
      resume.save(_url('a.mkv'), position: Duration.zero, duration: _movie);
      await written();

      expect(resume.positionFor(_url('a.mkv')), isNull);
      expect(history().single, [
        '${_url('a.mkv')}',
        const Duration(minutes: 60).inMilliseconds,
        _movie.inMilliseconds,
        0,
      ]);
    });

    test(
      'a video that ended before its length was known leaves no row',
      () async {
        final resume = await open();
        resume.finish(_url('a.mkv'), duration: Duration.zero);
        await written();

        expect(history(), isEmpty);
      },
    );

    test('clear forgets the position only', () async {
      final resume = await open();
      watch(resume, 'a.mkv');
      resume.clear(_url('a.mkv'));
      await written();

      expect(history(), hasLength(1));
    });

    test('outlives the positions, up to its own limit', () async {
      final resume = await open();
      for (var i = 0; i < ResumeStore.maxEntries + 5; i++) {
        watch(resume, '$i.mkv');
      }
      await written();

      expect(savedUrls(), hasLength(ResumeStore.maxEntries));
      expect(history(), hasLength(ResumeStore.maxEntries + 5));
    });
  });

  test('keeps only the most recently watched videos', () async {
    final resume = await open();
    for (var i = 0; i < ResumeStore.maxEntries + 5; i++) {
      watch(resume, '$i.mkv');
    }
    // Watching an old one again makes it recent.
    watch(resume, '5.mkv', minutes: 6);
    watch(resume, 'new.mkv');

    expect(resume.positionFor(_url('0.mkv')), isNull);
    expect(resume.positionFor(_url('4.mkv')), isNull);
    expect(resume.positionFor(_url('6.mkv')), isNull);
    expect(resume.positionFor(_url('5.mkv')), const Duration(minutes: 6));
    expect(resume.positionFor(_url('new.mkv')), isNotNull);

    await written();
    expect(savedUrls(), hasLength(ResumeStore.maxEntries));
    final again = await open();
    expect(again.positionFor(_url('6.mkv')), isNull);
    expect(again.positionFor(_url('5.mkv')), const Duration(minutes: 6));
  });

  test('a restart keeps the order in which videos were watched', () async {
    final resume = await open();
    watch(resume, 'first.mkv');
    watch(resume, 'second.mkv');
    watch(resume, 'first.mkv', minutes: 8);
    await written();

    expect(savedUrls(), ['${_url('second.mkv')}', '${_url('first.mkv')}']);
  });

  test('without a library, positions last for this run', () async {
    final resume = ResumeStore();
    await resume.load();
    watch(resume, 'a.mkv');

    expect(resume.positionFor(_url('a.mkv')), const Duration(minutes: 5));
    resume.clear(_url('a.mkv'));
    expect(resume.positionFor(_url('a.mkv')), isNull);
  });

  test('carries on if the database does not answer', () async {
    db.close();
    final resume = ResumeStore(LocalLibrary(db));
    await resume.load();
    watch(resume, 'a.mkv');
    await written();

    expect(resume.positionFor(_url('a.mkv')), const Duration(minutes: 5));
    // For tearDown, which closes it again.
    db = LibraryDb.inMemory();
  });

  group('positions from before the database', () {
    String rows(List<Object?> list) => jsonEncode(list);

    test('are moved over once, oldest first', () async {
      final settings = MemoryKeyValueStore({
        _key: rows([
          ['${_url('old.mkv')}', 60000, 7200000],
          ['${_url('newer.mkv')}', 120000, 7200000],
        ]),
        'player.volume': 80,
      });

      final resume = await open(legacy: settings);

      expect(resume.positionFor(_url('old.mkv')), const Duration(minutes: 1));
      expect(resume.positionFor(_url('newer.mkv')), const Duration(minutes: 2));
      expect(savedUrls(), ['${_url('old.mkv')}', '${_url('newer.mkv')}']);
      // Gone from the settings, which are otherwise untouched.
      expect(settings.values, {'player.volume': 80});

      final again = await open(legacy: settings);
      expect(again.positionFor(_url('old.mkv')), const Duration(minutes: 1));
    });

    test('do not replace what the database already knows', () async {
      final first = await open();
      watch(first, 'a.mkv', minutes: 30);
      await written();
      final settings = MemoryKeyValueStore({
        _key: rows([
          ['${_url('a.mkv')}', 60000, 7200000],
          ['${_url('b.mkv')}', 120000, 7200000],
        ]),
      });

      final resume = await open(legacy: settings);

      expect(resume.positionFor(_url('a.mkv')), const Duration(minutes: 30));
      expect(resume.positionFor(_url('b.mkv')), const Duration(minutes: 2));
      expect(
        (await open()).positionFor(_url('a.mkv')),
        const Duration(minutes: 30),
      );
    });

    test('stay in the settings when there is no library to move to', () async {
      final settings = MemoryKeyValueStore({
        _key: rows([
          ['${_url('old.mkv')}', 60000, 7200000],
        ]),
      });
      final resume = ResumeStore();

      await resume.load(legacy: settings);

      expect(resume.positionFor(_url('old.mkv')), const Duration(minutes: 1));
      expect(settings.getString(_key), isNotNull);
    });

    test('stay in the settings when the database cannot take them', () async {
      final settings = MemoryKeyValueStore({
        _key: rows([
          ['${_url('old.mkv')}', 60000, 7200000],
        ]),
      });
      db.close();
      final resume = ResumeStore(LocalLibrary(db));

      await resume.load(legacy: settings);

      expect(resume.positionFor(_url('old.mkv')), const Duration(minutes: 1));
      expect(settings.getString(_key), isNotNull);
      db = LibraryDb.inMemory();
    });

    test('are ignored when they are not JSON, or not a list', () async {
      for (final Object value in ['not json', '{"a": 1}', 42]) {
        final resume = await open(legacy: MemoryKeyValueStore({_key: value}));
        expect(resume.positionFor(_url('a.mkv')), isNull, reason: '$value');
      }
    });

    test('skip malformed rows and keep the good ones', () async {
      final resume = await open(
        legacy: MemoryKeyValueStore({
          _key: rows([
            'nonsense',
            ['http://10.16.100.244/movies/short-row.mkv', 5],
            ['http://10.16.100.244/movies/text.mkv', 'five', 100],
            ['http://10.16.100.244/movies/negative.mkv', -5, 100],
            ['http://10.16.100.244/movies/past-end.mkv', 500, 100],
            [42, 5, 100],
            ['http://10.16.100.244/movies/good.mkv', 60000, 7200000],
          ]),
        }),
      );

      for (final name in ['short-row', 'text', 'negative', 'past-end']) {
        expect(resume.positionFor(_url('$name.mkv')), isNull, reason: name);
      }
      expect(resume.positionFor(_url('good.mkv')), const Duration(minutes: 1));
      expect(savedUrls(), ['${_url('good.mkv')}']);
    });
  });
}
