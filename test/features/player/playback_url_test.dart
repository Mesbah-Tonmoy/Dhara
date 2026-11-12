// "127.0.0.1" and "localhost" reach the same local server but count as two
// hosts, which is what the redirect rule is about.
import 'dart:async';
import 'dart:io';

import 'package:dhara/core/net/safe_http_client.dart';
import 'package:dhara/features/player/playback_url.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/local_server.dart';

void main() {
  late LocalServer server;

  setUp(() async {
    server = await LocalServer.start();
    server.routes['/video.mkv'] = (request) async {
      // A media server: sends the file, however long it is.
      request.response
        ..statusCode = HttpStatus.partialContent
        ..headers.contentType = ContentType('video', 'x-matroska');
      try {
        for (var i = 0; i < 200; i++) {
          request.response.add(List.filled(64 * 1024, 0));
          await request.response.flush();
          await Future<void>.delayed(const Duration(milliseconds: 1));
        }
        await request.response.close();
      } on Object {
        // The client hung up, as it should.
      }
    };
  });

  tearDown(() => server.close());

  /// A client like the player screen's: the host asked for is allowed,
  /// plus [sources].
  SafeHttpClient clientFor(Uri url, {Set<String> sources = const {}}) {
    final client = SafeHttpClient(
      isAllowedHost: (host) => host == url.host || sources.contains(host),
      timeout: const Duration(seconds: 5),
    );
    addTearDown(client.close);
    return client;
  }

  Uri onLocalhost(String path) => server.url(path).replace(host: 'localhost');

  Matcher blocked(String part) => throwsA(
        isA<PlaybackBlocked>()
            .having((e) => e.message, 'message', contains(part)),
      );

  test('a direct video keeps its address, and is not downloaded', () async {
    final url = server.url('/video.mkv');
    final watch = Stopwatch()..start();

    final address = await resolvePlaybackUrl(clientFor(url), url);

    expect(address, url);
    expect(watch.elapsed, lessThan(const Duration(seconds: 3)));
    expect(server.requests.single.headers.value('range'), 'bytes=0-0');
  });

  test('a redirect on the same server gives the final address', () async {
    server
      ..redirect('/play/42', '/files/video.mkv')
      ..redirect('/files/video.mkv', '/video.mkv');
    final url = server.url('/play/42');

    final address = await resolvePlaybackUrl(clientFor(url), url);

    expect(address, server.url('/video.mkv'));
  });

  test('a redirect to another configured source is followed', () async {
    server.redirect('/play/42', '${onLocalhost('/video.mkv')}');
    final url = server.url('/play/42');

    final address = await resolvePlaybackUrl(
      clientFor(url, sources: {'localhost'}),
      url,
    );

    expect(address, onLocalhost('/video.mkv'));
  });

  test('a redirect to any other host blocks playback', () async {
    server.redirect('/play/42', '${onLocalhost('/video.mkv')}');
    final url = server.url('/play/42');

    await expectLater(
      resolvePlaybackUrl(clientFor(url), url),
      blocked('not one of your sources'),
    );
    expect(server.requests, hasLength(1), reason: 'the target is not asked');
  });

  test('a redirect to something that is not a web address blocks playback',
      () async {
    final url = server.url('/play/42');
    for (final target in ['file:///C:/Windows/win.ini', 'smb://nas/share/a']) {
      server.redirect('/play/42', target);

      await expectLater(
        resolvePlaybackUrl(clientFor(url), url),
        blocked('not one of your sources'),
        reason: target,
      );
    }
  });

  test('a redirect loop blocks playback', () async {
    server.redirect('/loop', '/loop');
    final url = server.url('/loop');

    await expectLater(
      resolvePlaybackUrl(clientFor(url), url),
      blocked('keeps redirecting'),
    );
  });

  test('an error status is left for the player to report', () async {
    final url = server.url('/missing.mkv');

    expect(await resolvePlaybackUrl(clientFor(url), url), url);
  });

  test('a server that cannot be asked is left for the player to report',
      () async {
    final url = server.url('/video.mkv');
    final client = clientFor(url);
    await server.close();

    expect(await resolvePlaybackUrl(client, url), url);
  });

  test('a server that is too slow is left for the player to report', () async {
    server.routes['/slow.mkv'] = (request) => Completer<void>().future;
    final url = server.url('/slow.mkv');
    final client = SafeHttpClient(
      isAllowedHost: (host) => host == url.host,
      timeout: const Duration(milliseconds: 300),
    );
    addTearDown(client.close);

    expect(await resolvePlaybackUrl(client, url), url);
  });

  test('a URL with a user name is passed on unchecked', () async {
    final url = server.url('/video.mkv').replace(userInfo: 'me:secret');

    expect(await resolvePlaybackUrl(clientFor(url), url), url);
    expect(server.requests, isEmpty);
  });
}
