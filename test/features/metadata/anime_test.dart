import 'dart:convert';
import 'dart:io';

import 'package:dhara/core/db/library_db.dart';
import 'package:dhara/core/db/library_isolate.dart';
import 'package:dhara/features/metadata/anilist_client.dart';
import 'package:dhara/features/metadata/anime_controller.dart';
import 'package:dhara/features/metadata/anime_store.dart';
import 'package:dhara/features/metadata/match_store.dart';
import 'package:dhara/features/metadata/metadata_store.dart';
import 'package:dhara/features/metadata/tmdb_client.dart';
import 'package:dhara/features/metadata/video_identity.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import '../../support/local_server.dart';

AnimeEntry _anime(
  int id,
  String english, {
  String? romaji,
  List<String> synonyms = const [],
  String format = 'TV',
  int? year,
}) => AnimeEntry(
  id: id,
  english: english,
  romaji: romaji,
  synonyms: synonyms,
  format: format,
  year: year,
);

void main() {
  late LibraryDb library;
  late Database db;
  late DateTime clock;
  var urls = 0;

  setUp(() {
    library = LibraryDb.inMemory();
    db = library.db;
    clock = DateTime(2026, 11, 14, 12);
    addTearDown(library.close);
  });

  /// Puts a video into the index, reads its name and returns its title.
  int add(String path, String name) {
    db.execute(
      "INSERT INTO sources (source_id) VALUES ('icc') "
      'ON CONFLICT (source_id) DO NOTHING',
    );
    db.execute(
      'INSERT INTO folders (source, url, path, depth) VALUES (1, ?, ?, 1)',
      ['http://icc.test/${urls++}/', path],
    );
    db.execute(
      'INSERT INTO files (folder, name, url, added_at) VALUES (?, ?, ?, 0)',
      [db.lastInsertRowId, name, 'http://icc.test/${urls++}/$name'],
    );
    final file = db.lastInsertRowId;
    MetadataStore(library).saveIdentities({
      file: identifyVideo(path: path, name: name, latestYear: 2027),
    });
    return db.select('SELECT title FROM file_meta WHERE file = ?', [
          file,
        ]).single['title']
        as int;
  }

  group('AnimeStore.match', () {
    late AnimeStore store;

    setUp(() => store = AnimeStore(library, now: () => clock));

    test('finds a show by any of the names an anime goes by', () {
      final frieren = add(
        'Anime/Frieren',
        '[SubsPlease] Sousou no Frieren - 05 (1080p).mkv',
      );
      final piece = add('Anime/One Piece', 'One Piece - 1071 [1080p].mkv');

      final rows = store.match([
        _anime(1, "Frieren: Beyond Journey's End", romaji: 'Sousou no Frieren'),
        _anime(2, 'ONE PIECE'),
        _anime(3, 'Something Else', synonyms: ['Else Thing']),
      ]);

      expect([for (final row in rows) row.titleId], [frieren, piece, null]);
      expect(rows.first.titleKind, TitleKind.series);
      expect(rows.first.inLibrary, isTrue);
      expect(rows.last.inLibrary, isFalse);
      expect(
        db
            .select('SELECT anilist_id FROM titles ORDER BY id')
            .map((row) => row['anilist_id']),
        [1, 2],
      );
    });

    test('a season of a show finds the show', () {
      final show = add(
        'Anime/The Apothecary Diaries Season 1',
        'The Apothecary Diaries S01E03.mkv',
      );

      final rows = store.match([
        _anime(
          195516,
          'The Apothecary Diaries Season 3',
          romaji: 'Kusuriya no Hitorigoto 3rd Season',
        ),
        _anime(5, 'Other Show: Part 2'),
        _anime(6, 'The Apothecary Diaries: The Final Season'),
      ]);

      expect([for (final row in rows) row.titleId], [show, null, show]);
      // The id of the first season found stays.
      expect(db.select('SELECT anilist_id FROM titles').single.values, [
        195516,
      ]);
    });

    test('a film is told from others of its name by the year', () {
      final old = add('Anime Movies', 'Ghost in the Shell (1995) 1080p.mkv');
      final recent = add('Anime Movies', 'Ghost in the Shell (2017) 720p.mkv');

      List<int?> found(int? year) => [
        for (final row in store.match([
          _anime(9, 'Ghost in the Shell', format: 'MOVIE', year: year),
        ]))
          row.titleId,
      ];

      expect(found(2017), [recent]);
      expect(found(1995), [old]);
      expect(found(null), [old], reason: 'the earliest, for want of a year');
      expect(
        store
            .match([_anime(9, 'Ghost in the Shell', format: 'MOVIE')])
            .single
            .titleKind,
        TitleKind.movie,
      );
    });

    test('a film filed as a show, or the other way, is still found', () {
      final show = add('Anime/Demon Slayer', 'Demon Slayer S01E01.mkv');

      final rows = store.match([
        _anime(4, 'Demon Slayer', format: 'MOVIE', year: 2020),
      ]);

      expect(
        (rows.single.titleId, rows.single.titleKind),
        (show, TitleKind.series),
      );
    });

    test('finds a title by the name TMDB gave it', () {
      final title = add('Anime/Shingeki', 'Shingeki S01E01.mkv');
      MatchStore(library).apply(
        title,
        const TmdbCandidate(
          id: 1429,
          kind: TitleKind.series,
          title: 'Attack on Titan',
          originalTitle: '進撃の巨人',
        ),
        confidence: 100,
        byHand: true,
      );

      final rows = store.match([
        _anime(16498, 'Attack on Titan', romaji: 'Shingeki no Kyojin'),
        _anime(2, 'Attack', romaji: 'Titan'),
      ]);

      expect([for (final row in rows) row.titleId], [title, null]);
    });
  });

  group('AnimeStore lists', () {
    test('are kept for half a day', () {
      final store = AnimeStore(library, now: () => clock);
      expect(store.keptList('trending'), isNull);

      store.keepList('trending', [_anime(1, 'One'), _anime(2, 'Two')]);

      expect(
        [for (final a in store.keptList('trending')!) a.name],
        ['One', 'Two'],
      );
      expect(store.keptList('season|fall|2026'), isNull);
      clock = clock.add(const Duration(hours: 11));
      expect(store.keptList('trending'), isNotNull);
      clock = clock.add(const Duration(hours: 2));
      expect(store.keptList('trending'), isNull);
    });

    test('that cannot be read count as not kept', () {
      final store = AnimeStore(library, now: () => clock);
      MetadataStore(
        library,
        now: () => clock,
      ).cacheAnswer(AnimeStore.provider, 'trending', '{"not":"a list"}');

      expect(store.keptList('trending'), isNull);
    });
  });

  group('AnimeController', () {
    late LocalServer server;
    late AnimeController anime;
    late int status;

    setUp(() async {
      server = await LocalServer.start();
      status = HttpStatus.ok;
      server.routes['/'] = (request) async {
        final body =
            jsonDecode(await utf8.decoder.bind(request).join())
                as Map<String, Object?>;
        final variables = body['variables']! as Map<String, Object?>;
        final season = variables['season'];
        request.response
          ..statusCode = status
          ..headers.set(
            HttpHeaders.contentTypeHeader,
            'application/json; charset=utf-8',
          )
          ..write(
            season == null
                ? fixture('anilist/trending.json')
                : jsonEncode({
                    'data': {
                      'Page': {
                        'media': [
                          {
                            'id': 500,
                            'title': {
                              'english': 'Of $season ${variables['year']}',
                            },
                            'format': 'TV',
                          },
                        ],
                      },
                    },
                  }),
          );
        await request.response.close();
      };
      add('Anime/One Piece', 'One Piece - 1071 [1080p].mkv');
      anime = AnimeController(
        library: LocalLibrary(library),
        aniListUrl: server.url('/'),
        clock: () => clock,
      );
      addTearDown(anime.dispose);
    });

    tearDown(() => server.close());

    test('fetches both lists and marks what the library has', () async {
      expect(anime.trending, isNull);
      expect((anime.season, anime.seasonYear), (AnimeSeason.fall, 2026));

      final load = anime.load();
      expect(anime.isLoading, isTrue);
      await load;

      expect(anime.isLoading, isFalse);
      expect(anime.failure, isNull);
      expect(
        [for (final row in anime.trending!) (row.anime.id, row.inLibrary)],
        [(219904, false), (195516, false), (21, true)],
      );
      expect(anime.seasonal!.single.anime.name, 'Of FALL 2026');
      expect(server.requests, hasLength(2));
    });

    test('asks AniList again only when asked to, or half a day on', () async {
      await anime.load();
      await anime.load();
      expect(server.requests, hasLength(2));

      // What the library has is worked out anew all the same.
      add('Anime/Kusuriya', 'Kusuriya no Hitorigoto S03E01.mkv');
      await anime.load();
      expect(anime.trending![1].inLibrary, isTrue);
      expect(server.requests, hasLength(2));

      await anime.load(fresh: true);
      expect(server.requests, hasLength(4));

      clock = clock.add(const Duration(hours: 13));
      await anime.load();
      expect(server.requests, hasLength(6));
    });

    test('keeps the lists it had when AniList gives no answer', () async {
      await anime.load();
      status = HttpStatus.serviceUnavailable;

      await anime.load(fresh: true);

      expect(anime.failure, 'AniList is out of order at the moment.');
      expect(anime.trending, hasLength(3));
      expect(anime.seasonal, hasLength(1));
    });

    test('has nothing to show when the first answer never comes', () async {
      status = HttpStatus.serviceUnavailable;

      await anime.load();

      expect(anime.failure, isNotNull);
      expect(anime.trending, isNull);
      expect(anime.seasonal, isNull);
    });

    test('without a library it says so and does not break', () async {
      final lost = AnimeController(library: const NoLibrary());
      addTearDown(lost.dispose);

      await lost.load();

      expect(lost.failure, contains('error in the app'));
      expect(lost.trending, isNull);
    });
  });
}
