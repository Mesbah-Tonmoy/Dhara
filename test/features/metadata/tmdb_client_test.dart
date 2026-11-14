import 'dart:async';
import 'dart:io';

import 'package:dhara/features/metadata/tmdb_client.dart';
import 'package:dhara/features/metadata/video_identity.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/local_server.dart';

/// Shaped like TMDB's, made up.
final _token = 'eyJhbGciOiJIUzI1NiJ9.${'a' * 120}.${'b' * 43}';
const _apiKey = '0123456789abcdef0123456789abcdef';

void main() {
  late LocalServer server;
  late DateTime clock;
  late List<Duration> waits;

  /// A client for the stand-in server whose waiting takes no time: it only
  /// moves the clock.
  TmdbClient client({
    TmdbKeyKind kind = TmdbKeyKind.accessToken,
    int retries = 3,
    int maxInFlight = 4,
  }) {
    final made = TmdbClient(
      key: kind == TmdbKeyKind.accessToken ? _token : _apiKey,
      kind: kind,
      http: server.client(),
      baseUrl: server.url('/3'),
      retries: retries,
      maxInFlight: maxInFlight,
      wait: (time) async {
        waits.add(time);
        clock = clock.add(time);
      },
      now: () => clock,
    );
    addTearDown(made.close);
    return made;
  }

  void json(String path, String body, {int status = HttpStatus.ok}) =>
      server.serve(
        path,
        body,
        status: status,
        contentType: 'application/json;charset=utf-8',
      );

  /// Answers [path] with one status after the other; the last one stays.
  void answers(
    String path,
    List<int> statuses, {
    String body = '{"success":true}',
    String? retryAfter,
  }) {
    var calls = 0;
    server.routes[path] = (request) async {
      final status =
          statuses[calls < statuses.length ? calls : statuses.length - 1];
      calls++;
      request.response.statusCode = status;
      if (status == HttpStatus.tooManyRequests && retryAfter != null) {
        request.response.headers.set(HttpHeaders.retryAfterHeader, retryAfter);
      }
      request.response.headers.set(
        HttpHeaders.contentTypeHeader,
        'application/json',
      );
      request.response.write(body);
      await request.response.close();
    };
  }

  Matcher fails(TmdbFailure failure) => throwsA(
    isA<TmdbException>().having((error) => error.failure, 'failure', failure),
  );

  setUp(() async {
    server = await LocalServer.start();
    clock = DateTime(2026, 11, 14, 12);
    waits = [];
  });

  tearDown(() => server.close());

  group('search', () {
    test('asks for films by title and year, signed with the token', () async {
      json('/3/search/movie', fixture('tmdb/search_movie.json'));

      await client().searchMovies('  The Glass Harbor ', year: 2019);

      final request = server.requests.single;
      expect(request.method, 'GET');
      expect(request.uri.path, '/3/search/movie');
      expect(request.uri.queryParameters, {
        'query': 'The Glass Harbor',
        'year': '2019',
        'include_adult': 'false',
        'language': 'en-US',
        'page': '1',
      });
      expect(
        request.headers.value(HttpHeaders.authorizationHeader),
        'Bearer $_token',
      );
      expect(
        request.headers.value(HttpHeaders.acceptHeader),
        'application/json',
      );
      expect(request.headers.value(HttpHeaders.userAgentHeader), 'Dhara');
      expect(request.cookies, isEmpty);
    });

    test('signs with an API key in the address instead', () async {
      json('/3/search/movie', fixture('tmdb/search_movie.json'));

      await client(kind: TmdbKeyKind.apiKey).searchMovies('Glass');

      final request = server.requests.single;
      expect(request.uri.queryParameters['api_key'], _apiKey);
      expect(request.uri.queryParameters.containsKey('year'), isFalse);
      expect(request.headers.value(HttpHeaders.authorizationHeader), isNull);
    });

    test(
      'reads the films found, the best few, and skips broken ones',
      () async {
        json('/3/search/movie', fixture('tmdb/search_movie.json'));

        final found = await client().searchMovies('The Glass Harbor');

        expect(
          [for (final film in found) film.id],
          [90001, 90002, 90003, 90005, 90006],
          reason:
              'no id, no title and not an object are skipped; five are kept',
        );
        expect(found, hasLength(TmdbClient.maxCandidates));

        final first = found.first;
        expect(first.kind, TitleKind.movie);
        expect(first.title, 'The Glass Harbor');
        expect(first.originalTitle, isNull, reason: 'the same as the title');
        expect(first.year, 2019);
        expect(first.overview, startsWith('A lighthouse keeper'));
        expect(first.overview, endsWith('any chart.'));
        expect(first.popularity, 41.3);
        expect(first.votes, 1840);
        expect(first.rating, 7.1);
        expect(first.language, 'en');
        expect(first.posterPath, '/pGlassHarbor01.jpg');
        expect(first.backdropPath, '/bkGlassHarbor01.jpg');

        final unrated = found[1];
        expect(unrated.originalTitle, 'Le Port de verre');
        expect(unrated.year, 1987);
        expect(unrated.overview, isNull);
        expect(unrated.rating, isNull, reason: 'nobody has voted');
        expect(unrated.posterPath, isNull);

        // An image path that is not one of TMDB's is not passed on.
        final odd = found[2];
        expect(odd.year, isNull);
        expect(odd.posterPath, isNull);
        expect(odd.backdropPath, isNull);
        expect(found[3].posterPath, '/pHarborGlass05.png');
      },
    );

    test('asks for shows by name and reads them', () async {
      json('/3/search/tv', fixture('tmdb/search_tv.json'));

      final found = await client().searchShows('quiet signal', year: 2019);

      final request = server.requests.single;
      expect(request.uri.path, '/3/search/tv');
      expect(request.uri.queryParameters['query'], 'quiet signal');
      expect(request.uri.queryParameters['year'], '2019');
      expect([for (final show in found) show.id], [70001, 70002]);
      expect(found.first.kind, TitleKind.series);
      expect(found.first.title, 'The Quiet Signal');
      expect(found.first.year, 2017);
      expect(found.first.rating, 8.2);
      expect(found.last.originalTitle, 'しずかな合図');
      expect(found.last.year, isNull, reason: 'not a date');
      expect(found.last.posterPath, '/pShizukana02.webp');
    });

    test('finds nothing without asking when there is nothing to ask', () async {
      expect(await client().searchMovies('   '), isEmpty);
      expect(server.requests, isEmpty);
    });

    test('no results is an answer, not an error', () async {
      json('/3/search/movie', '{"page":1,"results":[],"total_results":0}');
      expect(await client().searchMovies('zzzz'), isEmpty);

      json('/3/search/movie', '{"page":1}');
      expect(await client().searchMovies('zzzz'), isEmpty);
    });

    test('cuts an endless title short', () async {
      json('/3/search/movie', '{"results":[]}');

      await client().searchMovies('x' * 5000);

      expect(server.requests.single.uri.queryParameters['query'], 'x' * 200);
    });
  });

  group('details', () {
    test('of a film', () async {
      json('/3/movie/90001', fixture('tmdb/movie.json'));

      final film = await client().movie(90001);

      expect(server.requests.single.uri.path, '/3/movie/90001');
      expect(film.summary.id, 90001);
      expect(film.summary.title, 'The Glass Harbor');
      expect(film.summary.year, 2019);
      expect(film.summary.rating, 7.1);
      expect(film.genres, ['Drama', 'Thriller']);
      expect(film.runtime, 104);
      expect(film.seasons, isEmpty);
    });

    test('of a show, with its seasons', () async {
      json('/3/tv/70001', fixture('tmdb/tv.json'));

      final show = await client().show(70001);

      expect(show.summary.kind, TitleKind.series);
      expect(show.summary.title, 'The Quiet Signal');
      expect(show.summary.year, 2017);
      expect(show.genres, ['Drama', 'Mystery']);
      expect(show.runtime, isNull);
      expect([for (final season in show.seasons) season.number], [0, 1, 2]);
      final first = show.seasons[1];
      expect(first.name, 'Season 1');
      expect(first.episodeCount, 6);
      expect(first.airDate, '2017-09-12');
      expect(first.posterPath, '/pQuietSignalS1.jpg');
      expect(show.seasons.first.posterPath, isNull);
    });

    test('of a season, with its episodes', () async {
      json('/3/tv/70001/season/1', fixture('tmdb/season.json'));

      final season = await client().season(70001, 1);

      expect(server.requests.single.uri.path, '/3/tv/70001/season/1');
      expect(season.number, 1);
      expect(season.name, 'Season 1');
      expect(season.overview, 'The first message.');
      expect(season.airDate, '2017-09-12');
      expect([for (final episode in season.episodes) episode.number], [1, 2]);
      final first = season.episodes.first;
      expect(first.name, 'Static');
      expect(first.overview, 'The first night shift.');
      expect(first.airDate, '2017-09-12');
      expect(first.runtime, 47);
      expect(first.stillPath, '/sQuietSignal0101.jpg');
      final second = season.episodes.last;
      expect(second.overview, isNull);
      expect(second.runtime, isNull);
      expect(second.stillPath, isNull);
    });

    test('that are not there', () async {
      json(
        '/3/movie/1',
        '{"success":false,"status_code":34,"status_message":"Not found."}',
        status: HttpStatus.notFound,
      );

      expect(client().movie(1), fails(TmdbFailure.notFound));
    });

    test('without a name are a bad answer', () async {
      json('/3/movie/2', '{"id":2}');

      expect(client().movie(2), fails(TmdbFailure.badAnswer));
    });
  });

  group('answers that are not answers', () {
    test('a refused key', () async {
      json(
        '/3/search/movie',
        '{"status_code":7,"status_message":"Invalid API key.","success":false}',
        status: HttpStatus.unauthorized,
      );

      await expectLater(
        client().searchMovies('x'),
        fails(TmdbFailure.invalidKey),
      );
      expect(server.requests, hasLength(1), reason: 'asking again is no use');
    });

    test('text that is not JSON, or JSON that is not an object', () async {
      server.serve(
        '/3/search/movie',
        '<html>Sign in to the hotel Wi-Fi</html>',
      );
      await expectLater(
        client().searchMovies('x'),
        fails(TmdbFailure.badAnswer),
      );

      json('/3/search/movie', '[1, 2, 3]');
      await expectLater(
        client().searchMovies('x'),
        fails(TmdbFailure.badAnswer),
      );

      json('/3/search/movie', '{}', status: HttpStatus.forbidden);
      await expectLater(
        client().searchMovies('x'),
        fails(TmdbFailure.badAnswer),
      );
    });

    test('never name the key or the address', () async {
      final texts = <String>[];
      Future<void> collect(Future<Object?> request) async {
        try {
          await request;
        } on TmdbException catch (error) {
          texts.add('$error ${error.message}');
        }
      }

      answers('/3/search/movie', [HttpStatus.unauthorized]);
      answers('/3/movie/1', [HttpStatus.notFound]);
      answers('/3/movie/2', [HttpStatus.internalServerError]);
      answers('/3/movie/3', [HttpStatus.tooManyRequests]);
      server.serve('/3/movie/4', 'nonsense');
      for (final kind in TmdbKeyKind.values) {
        final tmdb = client(kind: kind);
        await collect(tmdb.searchMovies('x'));
        for (var id = 1; id <= 4; id++) {
          await collect(tmdb.movie(id));
        }
      }
      final offline = client(kind: TmdbKeyKind.apiKey, retries: 0);
      await server.close();
      await collect(offline.movie(1));

      expect(texts, hasLength(11));
      for (final text in texts) {
        expect(text, isNot(contains(_token)));
        expect(text, isNot(contains(_apiKey)));
        expect(text, isNot(contains('127.0.0.1')));
        expect(text, isNot(contains('api_key')));
      }
    });
  });

  group('trying again', () {
    test('after a server error, a little later each time', () async {
      answers('/3/movie/1', [
        500,
        503,
        502,
        200,
      ], body: fixture('tmdb/movie.json'));

      final film = await client().movie(1);

      expect(film.summary.id, 90001);
      expect(server.requests, hasLength(4));
      expect(waits.where((time) => time.inSeconds >= 1), const [
        Duration(seconds: 1),
        Duration(seconds: 3),
        Duration(seconds: 9),
      ]);
    });

    test('gives up after the last try', () async {
      answers('/3/movie/1', [500]);

      await expectLater(
        client(retries: 2).movie(1),
        fails(TmdbFailure.unreachable),
      );
      expect(server.requests, hasLength(3));
    });

    test('when the server cannot be reached at all', () async {
      final tmdb = client(retries: 2);
      await server.close();

      await expectLater(tmdb.movie(1), fails(TmdbFailure.unreachable));
      expect(waits.where((time) => time.inSeconds >= 1), const [
        Duration(seconds: 1),
        Duration(seconds: 3),
      ]);
    });
  });

  group('when told to slow down', () {
    test('waits as long as TMDB asks, then carries on', () async {
      answers(
        '/3/movie/1',
        [429, 200],
        body: fixture('tmdb/movie.json'),
        retryAfter: '7',
      );

      final film = await client().movie(1);

      expect(film.summary.id, 90001);
      expect(waits, contains(const Duration(seconds: 7)));
      expect(server.requests, hasLength(2));
    });

    test('waits two seconds if TMDB does not say how long', () async {
      answers('/3/movie/1', [429, 200], body: fixture('tmdb/movie.json'));

      await client().movie(1);

      expect(waits, contains(const Duration(seconds: 2)));
    });

    test('never waits longer than half a minute at a time', () async {
      answers(
        '/3/movie/1',
        [429, 200],
        body: fixture('tmdb/movie.json'),
        retryAfter: '86400',
      );

      await client().movie(1);

      expect(waits, contains(const Duration(seconds: 30)));
    });

    test('holds back every other request as well', () async {
      answers(
        '/3/movie/1',
        [429, 200],
        body: fixture('tmdb/movie.json'),
        retryAfter: '5',
      );
      json('/3/movie/2', fixture('tmdb/movie.json'));
      // Waiting here lasts until the test says so, and the clock stands
      // still meanwhile.
      final over = Completer<void>();
      final held = <Duration>[];
      final tmdb = TmdbClient(
        key: _token,
        kind: TmdbKeyKind.accessToken,
        http: server.client(),
        baseUrl: server.url('/3'),
        wait: (time) {
          held.add(time);
          return over.future;
        },
        now: () => clock,
      );
      addTearDown(tmdb.close);

      final slowed = tmdb.movie(1);
      // Real requests: give the first answer time to arrive.
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(held, const [Duration(seconds: 5)]);

      final other = tmdb.movie(2);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(held.last, greaterThanOrEqualTo(const Duration(seconds: 5)));
      expect(server.requests, hasLength(1), reason: 'nothing goes out');

      over.complete();
      await Future.wait([slowed, other]);
      expect(server.requests, hasLength(3));
    });

    test('gives up if it never ends', () async {
      answers('/3/movie/1', [429], retryAfter: '1');

      await expectLater(
        client(retries: 2).movie(1),
        fails(TmdbFailure.rateLimited),
      );
      expect(server.requests, hasLength(3));
    });
  });

  group('politeness', () {
    test('leaves an eighth of a second between requests', () async {
      json('/3/movie/1', fixture('tmdb/movie.json'));
      final tmdb = client();

      for (var i = 0; i < 5; i++) {
        await tmdb.movie(1);
      }

      // The clock here only moves by waiting, so every request but the
      // first found the one before it less than the spacing ago.
      expect(waits, List.filled(4, const Duration(milliseconds: 125)));
    });

    test('does not wait when enough time has passed anyway', () async {
      json('/3/movie/1', fixture('tmdb/movie.json'));
      final tmdb = client();

      await tmdb.movie(1);
      clock = clock.add(const Duration(seconds: 1));
      await tmdb.movie(1);

      expect(waits, isEmpty);
    });

    test('has at most four requests under way', () async {
      var open = 0;
      var most = 0;
      final release = Completer<void>();
      server.routes['/3/movie/1'] = (request) async {
        open++;
        if (open > most) most = open;
        await release.future;
        open--;
        request.response
          ..headers.set(HttpHeaders.contentTypeHeader, 'application/json')
          ..write(fixture('tmdb/movie.json'));
        await request.response.close();
      };
      final tmdb = client();

      final all = [for (var i = 0; i < 12; i++) tmdb.movie(1)];
      // Real requests: give them time to arrive.
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(most, 4);
      release.complete();
      final films = await Future.wait(all);

      expect(films, hasLength(12));
      expect(most, 4);
      expect(server.requests, hasLength(12));
    });
  });

  group('checkKey', () {
    test('says whether TMDB accepts the key', () async {
      json(
        '/3/authentication',
        '{"success":true,"status_code":1,"status_message":"Success."}',
      );
      expect(await client().checkKey(), TmdbKeyCheck.accepted);
      expect(server.requests.single.uri.path, '/3/authentication');
      expect(server.requests.single.uri.hasQuery, isFalse);

      json(
        '/3/authentication',
        '{"status_code":7,"status_message":"Invalid API key.","success":false}',
        status: HttpStatus.unauthorized,
      );
      expect(await client().checkKey(), TmdbKeyCheck.refused);
    });

    test('says so when it cannot tell, without trying for long', () async {
      answers('/3/authentication', [503]);
      expect(await client().checkKey(), TmdbKeyCheck.unreachable);
      expect(server.requests, hasLength(1));

      server.serve('/3/authentication', 'Sign in to the hotel Wi-Fi');
      expect(await client().checkKey(), TmdbKeyCheck.unreachable);

      final tmdb = client();
      await server.close();
      expect(await tmdb.checkKey(), TmdbKeyCheck.unreachable);
      expect(waits.where((time) => time.inSeconds >= 1), isEmpty);
    });
  });

  group('TmdbCandidate', () {
    test('comes back from JSON as it went in', () async {
      json('/3/search/movie', fixture('tmdb/search_movie.json'));
      json('/3/search/tv', fixture('tmdb/search_tv.json'));
      final tmdb = client();

      for (final candidate in [
        ...await tmdb.searchMovies('x'),
        ...await tmdb.searchShows('x'),
      ]) {
        final copy = TmdbCandidate.fromJson(candidate.toJson())!;
        expect(copy.toJson(), candidate.toJson());
        expect(copy.kind, candidate.kind);
      }
    });

    test('is not read from anything else', () {
      for (final json in [
        null,
        'text',
        <Object?>[],
        <String, Object?>{},
        {'id': 1},
        {'id': 0, 'title': 'x'},
        {'id': 'one', 'title': 'x'},
        {'id': 1, 'title': '   '},
      ]) {
        expect(TmdbCandidate.fromJson(json), isNull, reason: '$json');
      }
      final cleaned = TmdbCandidate.fromJson({
        'id': 5,
        'title': 'Kept',
        'year': 'soon',
        'poster_path': '/../x.jpg',
        'popularity': 'high',
        'votes': -3,
      })!;
      expect((cleaned.year, cleaned.posterPath), (null, null));
      expect((cleaned.popularity, cleaned.votes), (0, 0));
    });
  });

  test('talks to api.themoviedb.org over https unless told otherwise', () {
    expect(TmdbClient.apiHost, 'api.themoviedb.org');
  });
}
