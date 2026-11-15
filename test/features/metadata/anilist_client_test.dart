import 'dart:convert';
import 'dart:io';

import 'package:dhara/features/metadata/anilist_client.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/local_server.dart';

void _coverTests() {
  group('a cover', () {
    const path = '/file/anilistcdn/media/anime/cover/large/bx21-YCDoj1.jpg';

    test('is taken by its path if it is on AniList\'s picture server', () {
      expect(anilistCoverPath('https://s4.anilist.co$path'), path);
    });

    test('is dropped if its address is anything else', () {
      for (final url in [
        'http://s4.anilist.co$path',
        'https://s4.anilist.co.evil.test$path',
        'https://evil.test$path',
        'https://user:pw@s4.anilist.co$path',
        'https://s4.anilist.co:8443$path',
        'https://s4.anilist.co$path?x=1',
        'https://s4.anilist.co$path#x',
        'https://s4.anilist.co/file/anilistcdn/media/anime/cover/large/'
            '..%2F..%2Fa.jpg',
        'https://s4.anilist.co/other/a.jpg',
        'file:///C:/Windows/a.jpg',
        '',
      ]) {
        expect(anilistCoverPath(url), isNull, reason: url);
      }
      expect(anilistCoverPath(null), isNull);
      expect(anilistCoverPath(42), isNull);
    });

    test('is kept with the entry, and checked again when it is read back', () {
      const entry = AnimeEntry(id: 21, english: 'ONE PIECE', coverPath: path);

      expect(AnimeEntry.fromJson(entry.toJson())!.coverPath, path);
      expect(
        AnimeEntry.fromJson({
          ...entry.toJson(),
          'cover': '/../a.jpg',
        })!.coverPath,
        isNull,
      );
      expect(
        AnimeEntry.fromJson({'id': 21, 'english': 'ONE PIECE'})!.coverPath,
        isNull,
        reason: 'lists kept before covers were',
      );
    });
  });
}

void main() {
  _coverTests();
  late LocalServer server;
  late List<Duration> waits;
  late List<Map<String, Object?>> bodies;

  AniListClient client() {
    final made = AniListClient(
      http: server.client(),
      url: server.url('/'),
      wait: (time) async => waits.add(time),
    );
    addTearDown(made.close);
    return made;
  }

  /// Answers every request with one status after the other (the last one
  /// stays) and notes what was asked.
  void answers(List<int> statuses, {String? body, String? retryAfter}) {
    var calls = 0;
    server.routes['/'] = (request) async {
      bodies.add(
        jsonDecode(await utf8.decoder.bind(request).join())
            as Map<String, Object?>,
      );
      final status =
          statuses[calls < statuses.length ? calls : statuses.length - 1];
      calls++;
      request.response.statusCode = status;
      if (status == HttpStatus.tooManyRequests && retryAfter != null) {
        request.response.headers.set(HttpHeaders.retryAfterHeader, retryAfter);
      }
      request.response.headers.set(
        HttpHeaders.contentTypeHeader,
        'application/json; charset=utf-8',
      );
      request.response.write(body ?? fixture('anilist/trending.json'));
      await request.response.close();
    };
  }

  Matcher fails(AniListFailure failure) => throwsA(
    isA<AniListException>().having(
      (error) => error.failure,
      'failure',
      failure,
    ),
  );

  setUp(() async {
    server = await LocalServer.start();
    waits = [];
    bodies = [];
  });

  tearDown(() => server.close());

  test('asks for what is trending and reads the answer', () async {
    answers([200]);

    final list = await client().trending();

    final request = server.requests.single;
    expect(request.method, 'POST');
    expect(request.headers.contentType?.mimeType, 'application/json');
    expect(request.headers.value(HttpHeaders.authorizationHeader), isNull);
    expect(request.cookies, isEmpty);
    final body = bodies.single;
    expect(body['query'], contains('isAdult: false'));
    expect(body['variables'], {
      'sort': ['TRENDING_DESC', 'POPULARITY_DESC'],
      'perPage': 50,
    });

    // The answer is a real one, cut to three anime (14 November 2026).
    expect([for (final anime in list) anime.id], [219904, 195516, 21]);
    final announced = list.first;
    expect(announced.english, isNull);
    expect(announced.name, startsWith('Re:Zero kara Hajimeru'));
    expect(announced.synonyms, hasLength(1));
    expect(
      (announced.year, announced.episodes, announced.score),
      (null, null, null),
    );
    final diaries = list[1];
    expect(diaries.name, 'The Apothecary Diaries Season 3');
    expect(diaries.romaji, 'Kusuriya no Hitorigoto 3rd Season');
    expect(diaries.format, 'TV');
    expect((diaries.year, diaries.episodes, diaries.score), (2026, 12, 85));
    expect(diaries.isFilm, isFalse);
    expect(diaries.names.take(2), [
      'The Apothecary Diaries Season 3',
      'Kusuriya no Hitorigoto 3rd Season',
    ]);
  });

  test('asks for a season by its name and year', () async {
    answers([200]);

    await client().season(AnimeSeason.fall, 2026);

    expect(bodies.single['variables'], {
      'sort': ['POPULARITY_DESC'],
      'season': 'FALL',
      'year': 2026,
      'perPage': 50,
    });
  });

  test('skips entries without an id and cleans the rest', () async {
    answers(
      [200],
      body: jsonEncode({
        'data': {
          'Page': {
            'media': [
              {
                'title': {'english': 'No id'},
              },
              'not an object',
              {
                'id': 7,
                'title': {'english': '  A Film  ', 'romaji': ''},
                'synonyms': ['One', 2, '  '],
                'format': 'MOVIE',
                'episodes': 0,
                'averageScore': 'high',
                'startDate': null,
              },
            ],
          },
        },
      }),
    );

    final film = (await client().trending()).single;

    expect(film.id, 7);
    expect(film.name, 'A Film');
    expect(film.romaji, isNull);
    expect(film.synonyms, ['One']);
    expect(film.isFilm, isTrue);
    expect((film.episodes, film.score, film.year), (null, null, null));
  });

  test('waits as long as AniList asks when told to slow down, once', () async {
    answers([429, 200], retryAfter: '37');
    expect(await client().trending(), hasLength(3));
    expect(waits, const [Duration(seconds: 37)]);
    expect(server.requests, hasLength(2));

    waits.clear();
    answers([429, 429], retryAfter: '5000');
    await expectLater(client().trending(), fails(AniListFailure.rateLimited));
    expect(waits, const [Duration(seconds: 90)], reason: 'never for long');
  });

  test('says so when AniList gives no proper answer', () async {
    answers([503]);
    await expectLater(client().trending(), fails(AniListFailure.unreachable));

    answers([200], body: '<html>Sign in to the Wi-Fi</html>');
    await expectLater(client().trending(), fails(AniListFailure.badAnswer));

    answers([200], body: '{"errors":[{"message":"Syntax error"}]}');
    await expectLater(client().trending(), fails(AniListFailure.badAnswer));

    answers([400], body: '{"errors":[]}');
    await expectLater(client().trending(), fails(AniListFailure.badAnswer));

    final offline = client();
    await server.close();
    await expectLater(offline.trending(), fails(AniListFailure.unreachable));
  });

  test('an anime comes back from JSON as it went in', () async {
    answers([200]);
    for (final anime in await client().trending()) {
      expect(AnimeEntry.fromJson(anime.toJson())!.toJson(), anime.toJson());
    }
    for (final json in [
      null,
      'x',
      <Object?>[],
      {'id': 0},
      {'id': 'a'},
    ]) {
      expect(AnimeEntry.fromJson(json), isNull, reason: '$json');
    }
    expect(const AnimeEntry(id: 9).name, 'Anime 9');
  });

  test('knows which season a date is in', () {
    expect(AnimeSeason.of(DateTime(2026, 1, 1)), AnimeSeason.winter);
    expect(AnimeSeason.of(DateTime(2026, 3, 31)), AnimeSeason.winter);
    expect(AnimeSeason.of(DateTime(2026, 4, 1)), AnimeSeason.spring);
    expect(AnimeSeason.of(DateTime(2026, 8, 15)), AnimeSeason.summer);
    expect(AnimeSeason.of(DateTime(2026, 11, 14)), AnimeSeason.fall);
    expect(AniListClient.host, 'graphql.anilist.co');
  });
}
