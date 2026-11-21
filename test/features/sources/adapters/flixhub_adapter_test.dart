import 'dart:convert';
import 'dart:io';

import 'package:dhara/features/sources/adapters/flixhub_adapter.dart';
import 'package:dhara/features/sources/adapters/source_adapter.dart';
import 'package:dhara/features/sources/source.dart';
import 'package:dhara/features/sources/source_tester.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;

import '../../../support/local_server.dart';

void main() {
  late LocalServer server;
  late FlixHubAdapter adapter;

  setUp(() async {
    server = await LocalServer.start();
    adapter = FlixHubAdapter(server.client(), baseUrl: server.url('/'));
  });
  tearDown(() => server.close());

  /// Answers `/movies?page=N` with [pages], as JSON, and notes the pages
  /// asked for.
  List<String> serveFilms(Map<String, String> pages) {
    final asked = <String>[];
    server.routes['/movies'] = (request) async {
      final page = request.uri.queryParameters['page'] ?? '';
      asked.add(page);
      final body = pages[page];
      request.response
        ..statusCode = body == null ? HttpStatus.notFound : HttpStatus.ok
        ..headers.set(
          HttpHeaders.contentTypeHeader,
          'application/json; charset=utf-8',
        )
        ..write(body ?? '');
      await request.response.close();
    };
    return asked;
  }

  RemoteEntry film(String name, String address) => RemoteEntry(
    name: name,
    url: server.url('/stream/movie/$address'),
    isFolder: false,
  );
  RemoteEntry episode(String name, String address) => RemoteEntry(
    name: name,
    url: server.url('/stream/episode/$address'),
    isFolder: false,
  );

  test('a page of the site is told by its navigation bar', () {
    expect(isFlixHub(html.parse(fixture('flixhub/home.html'))), isTrue);
    expect(isFlixHub(html.parse(fixture('flixhub/series.html'))), isTrue);
    expect(isFlixHub(html.parse(fixture('listings/h5ai_root.html'))), isFalse);
    expect(isFlixHub(html.parse('<title>Some site</title>')), isFalse);
  });

  test('the site holds two folders, without being asked', () async {
    expect(await adapter.list(server.url('/')), [
      RemoteEntry(name: 'Movies', url: server.url('/movies'), isFolder: true),
      RemoteEntry(
        name: 'TV Shows',
        url: server.url('/tv-shows'),
        isFolder: true,
      ),
    ]);
    expect(server.requests, isEmpty);
  });

  group('real pages', () {
    test('Movies: every page of the list, a film a file', () async {
      final asked = serveFilms({
        '1': fixture('flixhub/movies_page_1.json'),
        '2': fixture('flixhub/movies_page_2.json'),
      });

      final films = await adapter.list(server.url('/movies'));

      expect(films, [
        film('Perfect Liars (2026) 1080p.mp4', 'perfect-liars'),
        film('The Raid (2026) 1080p.mp4', 'the-raid-1'),
        film('Lucky Baskhar (2024) 1080p.mp4', 'lucky-baskhar'),
        film(
          'A Big Bold Beautiful Journey (2025) 720p.mp4',
          'a-big-bold-beautiful-journey',
        ),
        film('96 Minutes (2025) 1080p.mp4', '96-minutes'),
      ]);
      expect(asked, ['1', '2']);
      // Asked the way the site's own script asks.
      final request = server.requests.first;
      expect(request.headers.value('x-requested-with'), 'XMLHttpRequest');
      expect(request.headers.value('accept'), 'application/json');
    });

    test('TV Shows: a folder for each show, once', () async {
      server.serve('/tv-shows', fixture('flixhub/tv_shows.html'));

      expect(await adapter.list(server.url('/tv-shows')), [
        RemoteEntry(
          name: 'The Freelancer (2023)',
          url: server.url('/watch/series/the-freelancer'),
          isFolder: true,
        ),
        RemoteEntry(
          name: 'MobLand (2025)',
          url: server.url('/watch/series/mobland'),
          isFolder: true,
        ),
        RemoteEntry(
          name: 'VisionQuest (2026)',
          url: server.url('/watch/series/visionquest'),
          isFolder: true,
        ),
      ]);
    });

    test('a show: every episode of every season, named as files are', () async {
      server.serve('/watch/series/reacher', fixture('flixhub/series.html'));

      expect(await adapter.list(server.url('/watch/series/reacher')), [
        episode(
          'Reacher S01E01 Welcome to Margrave.mkv',
          'welcome-to-margrave',
        ),
        episode('Reacher S01E02 First Dance.mkv', 'first-dance'),
        episode('Reacher S01E03 Spoonful.mkv', 'spoonful'),
        episode('Reacher S02E01 ATM.mkv', 'atm'),
        episode(
          'Reacher S02E02 What Happens in Atlantic City.mkv',
          'what-happens-in-atlantic-city',
        ),
      ]);
    });
  });

  group('the list of films', () {
    String page(List<String> cards, {Object? next, bool more = true}) =>
        jsonEncode({'html': cards.join(), 'has_more': more, 'next_page': next});
    String card(String link, {String title = 'A Film', String badge = ''}) =>
        '<div class="movies-grid-item" data-year="2020">'
        '<article data-card-type="movie" data-watch-url="$link">'
        '<a href="$link" aria-label="$title"></a>'
        '${badge.isEmpty ? '' : '<span class="badge-quality">$badge</span>'}'
        '</article></div>';

    test('ends where the site says it ends', () async {
      final asked = serveFilms({
        '1': page([card('/watch/movie/one')], next: 2),
        '2': page([card('/watch/movie/two')], next: null, more: false),
        '3': page([card('/watch/movie/three')], next: 4),
      });

      expect(await adapter.list(server.url('/movies')), hasLength(2));
      expect(asked, ['1', '2']);
    });

    test('does not follow a page that points anywhere but onwards', () async {
      for (final next in [1, 7, '2', null]) {
        final asked = serveFilms({
          '1': page([card('/watch/movie/one')], next: next),
        });

        expect(await adapter.list(server.url('/movies')), hasLength(1));
        expect(asked, ['1'], reason: '$next');
      }
    });

    test('stops at a page past the end', () async {
      serveFilms({
        '1': page([card('/watch/movie/one')], next: 2),
        '2': fixture('flixhub/movies_page_past_the_end.json'),
      });

      expect(await adapter.list(server.url('/movies')), hasLength(1));
    });

    test('takes only the name out of a link, and builds the address of the '
        'video itself', () async {
      serveFilms({
        '1': page([
          // Another site's address: its name is taken, never its host.
          card('https://elsewhere.test/watch/movie/kept', title: 'Kept'),
          card('/watch/movie/../../etc/passwd'),
          card('/watch/movie/Has%20Space'),
          card('/watch/movie/UPPER'),
          card('/watch/series/a-show'),
          card('/stream/movie/direct'),
          card('javascript:alert(1)'),
          card('/watch/movie/${'x' * 151}'),
          card('/watch/movie/kept', title: 'The same again'),
        ], next: null),
      });

      expect(await adapter.list(server.url('/movies')), [
        film('Kept (2020).mp4', 'kept'),
      ]);
    });

    test('makes a file name of what the site calls a film', () async {
      serveFilms({
        '1': page([
          card('/watch/movie/a', title: 'AC/DC: Live\\Loud', badge: '4K'),
          card('/watch/movie/b', title: '  Two\n lines\t here ', badge: 'CAM'),
          card('/watch/movie/c', title: ''),
          card('/watch/movie/d', title: 'x' * 400, badge: 'HD'),
        ], next: null),
      });

      final films = await adapter.list(server.url('/movies'));

      expect(films.map((film) => film.name).take(2), [
        'AC DC: Live Loud (2020) 2160p.mp4',
        // A badge that names no picture size is left out.
        'Two lines here (2020).mp4',
      ]);
      // A card without a title is no film; a long title is cut.
      expect(films, hasLength(3));
      expect(films.last.name, '${'x' * 150} (2020) 720p.mp4');
    });

    test('an answer that is not the list is said to be unreadable', () async {
      for (final body in ['<html>Sign in</html>', '[]', '{"html": 7}']) {
        serveFilms({'1': body});

        await expectLater(
          adapter.list(server.url('/movies')),
          throwsA(
            isA<SourceReadException>().having(
              (error) => error.message,
              'message',
              'The list of films is not readable.',
            ),
          ),
          reason: body,
        );
      }
    });
  });

  test('a show without numbered episodes has no files', () async {
    server.serve(
      '/watch/series/odd',
      '<nav id="flixhubNavbar"></nav><h1 class="movie-title">Odd</h1>'
          '<article class="player-sidebar-card" data-season-number="1">'
          '<a href="/watch/episode/special"></a>'
          '<h3 class="player-sidebar-card-title">Behind the scenes</h3>'
          '</article>'
          '<article class="player-sidebar-card" data-season-number="x">'
          '<a href="/watch/episode/two"></a>'
          '<h3 class="player-sidebar-card-title">E2</h3></article>'
          '<article class="player-sidebar-card" data-season-number="3">'
          '<a href="/watch/episode/three"></a>'
          '<h3 class="player-sidebar-card-title">E12</h3></article>',
    );

    expect(await adapter.list(server.url('/watch/series/odd')), [
      episode('Odd S03E12.mkv', 'three'),
    ]);
  });

  test('a page the site answers in place of the one asked for is refused', () {
    server
      ..redirect('/tv-shows', '/login')
      ..serve('/login', '<nav id="flixhubNavbar"></nav>Sign in');

    expect(
      adapter.list(server.url('/tv-shows')),
      throwsA(isA<SourceReadException>()),
    );
  });

  test('an error of the site is passed on with its status', () {
    server.serve('/tv-shows', 'busy', status: 503);

    expect(
      adapter.list(server.url('/tv-shows')),
      throwsA(
        isA<SourceReadException>().having((e) => e.statusCode, 'status', 503),
      ),
    );
  });

  test('anything that is not one of its folders is refused unasked', () async {
    for (final url in [
      server.url('/stream/movie/x'),
      server.url('/watch/movie/x'),
      server.url('/watch/series/Bad%20Name'),
      server.url('/watch/series/a/b'),
      server.url('/admin'),
      Uri.parse('http://10.9.9.9/movies'),
    ]) {
      await expectLater(
        adapter.list(url),
        throwsA(isA<SourceReadException>()),
        reason: '$url',
      );
    }
    expect(server.requests, isEmpty);
  });

  test('the tester knows the site by its front page and can read it', () async {
    server.serve('/', fixture('flixhub/home.html'));

    final result = await SourceTester(deviceId: 'dhara-test').testAll([
      Source(
        id: 'flixhub',
        name: 'FlixHub',
        type: SourceType.customSite,
        category: SourceCategory.mixed,
        baseUrls: [server.url('/')],
      ),
    ]).single;

    expect(result.detectedType, SourceType.flixHub);
    expect(result.readable, isTrue);
    expect(result.readableType, SourceType.flixHub);
    expect(result.urls.single.sample, ['Movies', 'TV Shows']);
  });
}
