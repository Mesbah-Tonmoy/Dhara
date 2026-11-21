import 'dart:io';

import 'package:dhara/features/sources/adapters/khulnaplex_adapter.dart';
import 'package:dhara/features/sources/adapters/source_adapter.dart';
import 'package:dhara/features/sources/source.dart';
import 'package:dhara/features/sources/source_tester.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;

import '../../../support/local_server.dart';

void main() {
  late LocalServer server;
  late KhulnaplexAdapter adapter;

  setUp(() async {
    server = await LocalServer.start();
    adapter = KhulnaplexAdapter(server.client(), baseUrl: server.url('/'));
  });
  tearDown(() => server.close());

  /// Answers [file] by what the address asks for: [pages] by the whole of
  /// what follows the "?", and notes each of those.
  List<String> serveBy(String file, Map<String, String> pages) {
    final asked = <String>[];
    server.routes['/$file'] = (request) async {
      asked.add(request.uri.query);
      final body = pages[request.uri.query];
      request.response
        ..statusCode = body == null ? HttpStatus.notFound : HttpStatus.ok
        ..headers.set(HttpHeaders.contentTypeHeader, 'text/html; charset=utf-8')
        ..write(body ?? '');
      await request.response.close();
    };
    return asked;
  }

  RemoteEntry folder(String name, String address, {bool fixed = true}) =>
      RemoteEntry(
        name: name,
        url: server.url('/$address'),
        isFolder: true,
        modified: fixed ? KhulnaplexAdapter.unchanging : null,
      );
  RemoteEntry file(String name, String address) =>
      RemoteEntry(name: name, url: server.url('/$address'), isFolder: false);

  String card(
    String onclick, {
    String title = 'A Film',
    String year = '2020',
  }) =>
      '<div class="movie-card" onclick="$onclick"><h3>$title</h3>'
      '<span class="year">$year</span></div>';
  String watchPage({
    String title = 'A Film',
    String source = 'uploads/videos/a.mp4',
    String meta = '<span><i class="fas fa-calendar"></i> 2021</span>',
    String more = '',
  }) =>
      '<video id="moviePlayer"><source src="$source" type="video/mp4"></video>'
      '<div class="video-info"><h1>$title</h1>'
      '<div class="video-meta">$meta</div></div>$more';

  test('a page of the site is told by its menu and its script', () {
    for (final page in ['home', 'movies_page_1', 'watch_movie']) {
      expect(
        isKhulnaplex(html.parse(fixture('khulnaplex/$page.html'))),
        isTrue,
        reason: page,
      );
    }
    expect(isKhulnaplex(html.parse(fixture('flixhub/home.html'))), isFalse);
    expect(
      isKhulnaplex(
        html.parse('<a href="movies.php"></a><a href="series.php"></a>'),
      ),
      isFalse,
    );
  });

  test('the site holds two folders, without being asked', () async {
    expect(await adapter.list(server.url('/')), [
      folder('Movies', 'movies.php', fixed: false),
      folder('TV Shows', 'series.php', fixed: false),
    ]);
    expect(server.requests, isEmpty);
  });

  group('real pages', () {
    test('Movies: a folder for every film of every page', () async {
      final asked = serveBy('movies.php', {
        'page=1': fixture('khulnaplex/movies_page_1.html'),
        'page=2': fixture('khulnaplex/movies_page_last.html'),
        'page=3': fixture('khulnaplex/movies_page_past_the_end.html'),
      });

      expect(await adapter.list(server.url('/movies.php')), [
        folder(
          'Harry Potter 20th Anniversary: Return to Hogwarts (2022)',
          'watch.php?id=1357&type=movie',
        ),
        folder(
          'Harry Potter and the Deathly Hallows: Part 1 (2010)',
          'watch.php?id=1356&type=movie',
        ),
        folder(
          'Harry Potter and the Deathly Hallows: Part 2 (2011)',
          'watch.php?id=1355&type=movie',
        ),
        folder('Ghaati (2025)', 'watch.php?id=13&type=movie'),
        folder('Love Untangled (2025)', 'watch.php?id=12&type=movie'),
      ]);
      // It ends at the page that shows nothing.
      expect(asked, ['page=1', 'page=2', 'page=3']);
    });

    test('TV Shows: a folder for every show, read again every time', () async {
      serveBy('series.php', {
        'page=1': fixture('khulnaplex/series_page_1.html'),
        'page=2': fixture('khulnaplex/movies_page_past_the_end.html'),
      });

      final shows = await adapter.list(server.url('/series.php'));

      expect(shows.map((show) => show.url), [
        server.url('/watch.php?id=136&type=series'),
        server.url('/watch.php?id=135&type=series'),
        server.url('/watch.php?id=134&type=series'),
      ]);
      // A show's card gives no year.
      expect(shows.map((show) => show.name), [
        'The Blue Road',
        'The Remarried Empress',
        'Dead-End Job',
      ]);
      expect(shows.every((show) => show.isFolder), isTrue);
      expect(shows.map((show) => show.modified), everyElement(isNull));
    });

    test(
      'a film: its one file, named from the page and the real file',
      () async {
        serveBy('watch.php', {
          'id=1357&type=movie': fixture('khulnaplex/watch_movie.html'),
        });

        expect(await adapter.list(server.url('/watch.php?id=1357&type=movie')), [
          file(
            'Harry Potter 20th Anniversary: Return to Hogwarts (2022).mp4',
            'uploads/videos/1795242668_Harry_Potter_20th_Anniversary_Return_to_'
                'Hogwarts_2022.mp4',
          ),
        ]);
      },
    );

    test('a show: a folder for each episode', () async {
      serveBy('watch.php', {
        'id=1&type=series': fixture('khulnaplex/watch_series.html'),
      });

      expect(await adapter.list(server.url('/watch.php?id=1&type=series')), [
        folder('S01E01', 'watch.php?id=1&type=series&season=1&episode=1'),
        folder('S01E02', 'watch.php?id=1&type=series&season=1&episode=2'),
        folder('S01E03', 'watch.php?id=1&type=series&season=1&episode=3'),
      ]);
    });

    test('an episode: its one file', () async {
      const address = 'id=1&type=series&season=1&episode=2';
      serveBy('watch.php', {
        address: fixture('khulnaplex/watch_episode_2.html'),
      });

      expect(await adapter.list(server.url('/watch.php?$address')), [
        file(
          'Genie, Make a Wish (2025) S01E02 1080p.mp4',
          'wp-content/uploads/Web/Genie%2C%20Make%20a%20Wish%20%5BHindi%5D-'
              'S1E2-1080P.mp4',
        ),
      ]);
    });
  });

  group('a list', () {
    test('stops when a page brings nothing new', () async {
      final asked = serveBy('movies.php', {
        'page=1': card('openMovie(1)') + card('openMovie(2)'),
        // The same again, as some sites answer past their last page.
        'page=2': card('openMovie(2)') + card('openMovie(1)'),
        'page=3': card('openMovie(3)'),
      });

      expect(await adapter.list(server.url('/movies.php')), hasLength(2));
      expect(asked, ['page=1', 'page=2']);
    });

    test('takes a number out of a card and nothing else', () async {
      serveBy('movies.php', {
        'page=1': [
          card('openMovie(7)', title: 'Kept'),
          card('openSeries(8)'),
          card("openMovie(9); fetch('http://elsewhere.test/')"),
          card('openMovie(-1)'),
          card('openMovie(1234567890)'),
          card("window.location='http://elsewhere.test/'"),
          card('openMovie(10)', title: ' '),
          card('openMovie(11)', title: 'AC/DC: Live\\Loud', year: 'soon'),
        ].join(),
        'page=2': '',
      });

      expect(await adapter.list(server.url('/movies.php')), [
        folder('Kept (2020)', 'watch.php?id=7&type=movie'),
        folder('AC DC: Live Loud', 'watch.php?id=11&type=movie'),
      ]);
    });
  });

  group('the video a page names', () {
    Future<List<RemoteEntry>> filmWith(String source) {
      serveBy('watch.php', {'id=5&type=movie': watchPage(source: source)});
      return adapter.list(server.url('/watch.php?id=5&type=movie'));
    }

    test('is taken when it is a video file of the site', () async {
      expect(await filmWith('uploads/videos/Some%20Film%20720p.MKV'), [
        file('A Film (2021) 720p.mkv', 'uploads/videos/Some%20Film%20720p.MKV'),
      ]);
      expect(await filmWith('/wp-content/uploads/Movie/x.mp4'), [
        file('A Film (2021).mp4', 'wp-content/uploads/Movie/x.mp4'),
      ]);
    });

    test('is left when it leads anywhere else or is no video', () async {
      for (final source in [
        'http://elsewhere.test/uploads/videos/a.mp4',
        '//elsewhere.test/a.mp4',
        'ftp://127.0.0.1/a.mp4',
        'file:///C:/Windows/a.mp4',
        'javascript:alert(1)',
        'uploads/videos/a.mp4?token=1',
        'uploads/videos/a.mp4#t=1',
        'uploads/videos/a.exe',
        'uploads/videos/a.mp4.exe',
        'uploads/videos/',
        '',
      ]) {
        expect(await filmWith(source), isEmpty, reason: source);
      }
    });

    test('written with a way up is the plain address it comes to', () async {
      // Still a file of the site: nothing of the page decides the host.
      expect(await filmWith('uploads/%2e%2e/other/a.mp4'), [
        file('A Film (2021).mp4', 'other/a.mp4'),
      ]);
      expect(await filmWith('../../../a.mp4'), [
        file('A Film (2021).mp4', 'a.mp4'),
      ]);
    });

    test('with another port of the same host is left too', () async {
      final other = server.url('/a.mp4').replace(port: 9);

      expect(await filmWith('$other'), isEmpty);
    });
  });

  test('a page without a title holds no file', () async {
    serveBy('watch.php', {'id=5&type=movie': watchPage(title: ' ')});

    expect(
      await adapter.list(server.url('/watch.php?id=5&type=movie')),
      isEmpty,
    );
  });

  test('a show: only the links to its own episodes count', () async {
    String link(String address) =>
        '<div class="episode-item">'
        '<a class="play-episode-btn" href="$address"></a></div>';
    serveBy('watch.php', {
      'id=4&type=series': watchPage(
        more: [
          link('watch.php?id=4&type=series&season=2&episode=10'),
          link('watch.php?id=4&amp;type=series&amp;season=2&amp;episode=10'),
          link('watch.php?id=5&type=series&season=1&episode=1'),
          link('watch.php?id=4&type=movie&season=1&episode=1'),
          link('watch.php?id=4&type=series&season=x&episode=1'),
          link('watch.php?id=4&type=series&season=1'),
          link(
            'http://elsewhere.test/watch.php?id=4&type=series&season=3&episode=1',
          ),
          link('#'),
        ].join(),
      ),
    });

    expect(await adapter.list(server.url('/watch.php?id=4&type=series')), [
      folder('S02E10', 'watch.php?id=4&type=series&season=2&episode=10'),
      // Of a link only its numbers are used: the address is the site's.
      folder('S03E01', 'watch.php?id=4&type=series&season=3&episode=1'),
    ]);
  });

  test('an episode the site answers with another one holds no file', () async {
    const meta = '<span><i class="fas fa-tv"></i> Season 1, Episode 1</span>';
    serveBy('watch.php', {
      'id=4&type=series&season=1&episode=9': watchPage(meta: meta),
      'id=4&type=series&season=1&episode=1': watchPage(meta: meta),
    });

    expect(
      await adapter.list(
        server.url('/watch.php?id=4&type=series&season=1&episode=9'),
      ),
      isEmpty,
    );
    expect(
      await adapter.list(
        server.url('/watch.php?id=4&type=series&season=1&episode=1'),
      ),
      [file('A Film S01E01.mp4', 'uploads/videos/a.mp4')],
    );
  });

  test('a film that is gone (the site passes on to its front page) is '
      'refused', () {
    server
      ..redirect('/watch.php', '/index.php')
      ..serve('/index.php', fixture('khulnaplex/home.html'));

    expect(
      adapter.list(server.url('/watch.php?id=99999&type=movie')),
      throwsA(isA<SourceReadException>()),
    );
  });

  test('an error of the site is passed on with its status', () {
    server.serve('/series.php', 'busy', status: 503);

    expect(
      adapter.list(server.url('/series.php')),
      throwsA(
        isA<SourceReadException>().having((e) => e.statusCode, 'status', 503),
      ),
    );
  });

  test('anything that is not one of its folders is refused unasked', () async {
    for (final url in [
      server.url('/uploads/videos/'),
      server.url('/movies.php?category=hindi'),
      server.url('/watch.php'),
      server.url('/watch.php?id=x&type=movie'),
      server.url('/watch.php?id=1&type=other'),
      server.url('/watch.php?id=1&type=movie&extra=1'),
      server.url('/watch.php?id=1&type=series&season=1'),
      server.url('/admin.php'),
      Uri.parse('http://10.9.9.9/movies.php'),
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
    server.serve('/', fixture('khulnaplex/home.html'));

    final result = await SourceTester(deviceId: 'dhara-test').testAll([
      Source(
        id: 'khulnaplex',
        name: 'Khulnaplex',
        type: SourceType.customSite,
        category: SourceCategory.mixed,
        baseUrls: [server.url('/')],
      ),
    ]).single;

    expect(result.readableType, SourceType.khulnaplex);
    expect(result.urls.single.sample, ['Movies', 'TV Shows']);
  });
}
