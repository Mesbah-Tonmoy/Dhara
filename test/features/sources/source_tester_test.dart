import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dhara/features/sources/source.dart';
import 'package:dhara/features/sources/source_tester.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_emby.dart';
import '../../support/local_server.dart';

void main() {
  late LocalServer server;

  setUp(() async => server = await LocalServer.start());
  tearDown(() => server.close());

  Source source(String id, List<String> paths) => Source(
        id: id,
        name: id,
        type: SourceType.customSite,
        category: SourceCategory.mixed,
        baseUrls: [for (final path in paths) server.url(path)],
      );

  SourceTester tester({int concurrency = 6, Duration? timeout}) => SourceTester(
        deviceId: 'dhara-test-1',
        concurrency: concurrency,
        timeout: timeout ?? const Duration(seconds: 5),
      );

  /// Tests one source with one base URL and returns that URL's result.
  Future<UrlTestResult> testUrl(String path, {Duration? timeout}) async {
    final results = await tester(timeout: timeout).testAll([
      source('one', [path])
    ]).toList();
    return results.single.urls.single;
  }

  group('finds out what a server is', () {
    test('h5ai, with a sample of what is on it', () async {
      server.serve('/DHAKA-FLIX-7/', fixture('listings/h5ai_root.html'));

      final result = await testUrl('/DHAKA-FLIX-7/');

      expect(result.reachable, isTrue);
      expect(result.readable, isTrue);
      expect(result.detectedType, SourceType.h5ai);
      expect(result.entryCount, 4);
      expect(result.sample, [
        '3D Movies',
        'English Movies',
        'Foreign Language Movies',
        'Kolkata Bangla Movies',
      ]);
      expect(result.problem, isNull);
      expect(result.ping, isNotNull);
    });

    test('a plain folder listing, with the server software', () async {
      server.routes['/s1d1/'] = (request) async {
        request.response
          ..headers.set('server', 'Apache/2.2.22 (Ubuntu)')
          ..headers.contentType = ContentType.html
          ..write(fixture('listings/apache_table_named_months.html'));
        await request.response.close();
      };

      final result = await testUrl('/s1d1/');

      expect(result.detectedType, SourceType.directoryListing);
      expect(result.software, 'Apache/2.2.22 (Ubuntu)');
      expect(result.readable, isTrue);
      expect(result.sample, hasLength(5));
      expect(result.sample.first, 'Hindi-2021');
      expect(result.entryCount, greaterThan(5));
    });

    test('Emby, signing in as guest to list its libraries', () async {
      FakeEmby(server, prefix: '/emby');

      final result = await testUrl('/emby/');

      expect(result.detectedType, SourceType.emby);
      expect(result.software, 'Emby 4.8.5.0');
      expect(result.readable, isTrue);
      expect(result.sample, ['Movies', 'Series']);
      expect(result.entryCount, 2);
    });

    test('Jellyfin, by its product name', () async {
      FakeEmby(server, prefix: '/jf');
      server.serve(
        '/jf/System/Info/Public',
        jsonEncode({
          'ServerName': 'box',
          'Version': '10.10.3',
          'ProductName': 'Jellyfin Server',
          'Id': '0123456789abcdef0123456789abcdef',
        }),
        contentType: 'application/json',
      );

      final result = await testUrl('/jf/');

      expect(result.detectedType, SourceType.jellyfin);
      expect(result.software, 'Jellyfin 10.10.3');
    });

    test('some other website: reachable, but nothing the app can read',
        () async {
      server.serve('/', fixture('listings/not_a_listing.html'));

      final result = await testUrl('/');

      expect(result.reachable, isTrue);
      expect(result.readable, isFalse);
      expect(result.detectedType, SourceType.customSite);
      expect(result.sample, ['Example Net - Home']);
      expect(result.entryCount, isNull);
      expect(result.problem, isNull);
    });
  });

  group('reports what is wrong', () {
    test('a server that answers with an error', () async {
      server.serve('/private/', 'Forbidden', status: 403);

      final result = await testUrl('/private/');

      expect(result.reachable, isTrue);
      expect(result.readable, isFalse);
      expect(result.problem, contains('403'));
      expect(result.detectedType, isNull);
      expect(result.ping, isNotNull);
    });

    test('a media server that will not let a guest in', () async {
      FakeEmby(server, prefix: '/emby').publicUsers = '[]';

      final result = await testUrl('/emby/');

      expect(result.reachable, isTrue);
      expect(result.detectedType, SourceType.emby);
      expect(result.readable, isFalse);
      expect(result.problem, contains('guest'));
      expect(result.sample, isEmpty);
    });

    test('a server that is not there', () async {
      final gone = await LocalServer.start();
      final url = gone.url('/files/');
      await gone.close();
      final dead = Source(
        id: 'dead',
        name: 'Dead',
        type: SourceType.h5ai,
        category: SourceCategory.mixed,
        baseUrls: [url],
      );

      final result = (await tester().testAll([dead]).single).urls.single;

      expect(result.reachable, isFalse);
      expect(result.readable, isFalse);
      expect(result.ping, isNull);
      expect(result.problem, contains('could not be reached'));
    });

    test('a server that does not answer in time', () async {
      server.routes['/silent/'] = (request) => Completer<void>().future;

      final result = await testUrl(
        '/silent/',
        timeout: const Duration(milliseconds: 300),
      );

      expect(result.reachable, isFalse);
      expect(result.problem, contains('did not answer'));
    });

    test('a server that redirects to a host outside the list', () async {
      server.redirect('/moved/', 'http://example.com/files/');

      final result = await testUrl('/moved/');

      expect(result.reachable, isTrue);
      expect(result.readable, isFalse);
      expect(result.problem, contains('not allowed'));
    });

    test('a listing page that is too large to be a first page', () async {
      server.routes['/huge/'] = (request) async {
        request.response
          ..contentLength = 2 * 1024 * 1024
          ..add(List.filled(2 * 1024 * 1024, 0x20));
        await request.response.close();
      };

      final result = await testUrl('/huge/');

      expect(result.reachable, isTrue);
      expect(result.problem, contains('larger'));
    });
  });

  group('a source with several base URLs', () {
    test('is reachable and readable if any of them is', () async {
      server.serve('/DHAKA-FLIX-7/', fixture('listings/h5ai_root.html'));

      final result = await tester().testAll([
        source('mixed', ['/missing/', '/DHAKA-FLIX-7/']),
      ]).single;

      expect(result.urls.map((url) => url.readable), [false, true]);
      expect(result.reachable, isTrue);
      expect(result.readable, isTrue);
      expect(result.detectedType, SourceType.h5ai);
      expect(result.ping, isNotNull);
      expect(result.source.id, 'mixed');
    });

    test('is unreachable only if none of them answers', () async {
      server.routes['/silent/'] = (request) => Completer<void>().future;

      final result =
          await tester(timeout: const Duration(milliseconds: 300)).testAll([
        source('dead', ['/silent/', '/silent/']),
      ]).single;

      expect(result.reachable, isFalse);
      expect(result.readable, isFalse);
      expect(result.ping, isNull);
      expect(result.detectedType, isNull);
    });
  });

  group('a run', () {
    test('tests every source, a few at a time', () async {
      var running = 0;
      var mostAtOnce = 0;
      for (var i = 0; i < 12; i++) {
        server.routes['/s$i/'] = (request) async {
          running++;
          if (running > mostAtOnce) mostAtOnce = running;
          await Future<void>.delayed(const Duration(milliseconds: 60));
          running--;
          request.response.write('<title>Index of /s$i/</title>');
          await request.response.close();
        };
      }

      final results = await tester(concurrency: 3).testAll([
        for (var i = 0; i < 12; i++) source('s$i', ['/s$i/']),
      ]).toList();

      expect(results.map((r) => r.source.id).toSet(), hasLength(12));
      expect(results.every((r) => r.readable), isTrue);
      expect(mostAtOnce, 3);
    });

    test('reports each source as soon as it is done', () async {
      server.routes['/slow/'] = (request) async {
        await Future<void>.delayed(const Duration(milliseconds: 300));
        await request.response.close();
      };
      server.serve('/fast/', '<title>Index of /fast/</title>');

      final results = await tester().testAll([
        source('slow', ['/slow/']),
        source('fast', ['/fast/']),
      ]).toList();

      expect(results.map((r) => r.source.id), ['fast', 'slow']);
    });

    test('stops when the listener cancels', () async {
      for (var i = 0; i < 10; i++) {
        server.routes['/s$i/'] = (request) async {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          request.response.write('<title>Index of /s$i/</title>');
          await request.response.close();
        };
      }
      final first = Completer<void>();
      final subscription = tester(concurrency: 1).testAll([
        for (var i = 0; i < 10; i++) source('s$i', ['/s$i/']),
      ]).listen((_) {
        if (!first.isCompleted) first.complete();
      });

      await first.future;
      await subscription.cancel();
      await Future<void>.delayed(const Duration(milliseconds: 300));

      expect(server.requests.length, lessThan(4));
    });

    test('with nothing to test just ends', () async {
      expect(await tester().testAll(const []).toList(), isEmpty);
    });

    test('never contacts a host that is not in the list', () async {
      // The source says "localhost"; the page links and redirects are for
      // "127.0.0.1", which this run was not given.
      server.redirect('/files/', server.url('/elsewhere/').toString());
      final local = Source(
        id: 'local',
        name: 'Local',
        type: SourceType.h5ai,
        category: SourceCategory.mixed,
        baseUrls: [server.url('/files/').replace(host: 'localhost')],
      );

      final result = (await tester().testAll([local]).single).urls.single;

      expect(result.problem, contains('not allowed'));
      expect(server.requests.map((r) => r.uri.path), ['/files/']);
    });
  });

  test('a device id that is not plain is rejected up front', () {
    expect(() => SourceTester(deviceId: 'pc", Token="x'), throwsArgumentError);
  });
}
