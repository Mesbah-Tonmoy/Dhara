// "127.0.0.1" and "localhost" reach the same local server but count as two
// hosts, which is what the redirect rule is about.
import 'dart:io';

import 'package:dhara/features/playback/copy_probe.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/local_server.dart';

void main() {
  late LocalServer server;

  /// A media server's answer for a video, after [delay].
  void video(String path, {Duration delay = Duration.zero}) {
    server.routes[path] = (request) async {
      await Future<void>.delayed(delay);
      request.response
        ..statusCode = HttpStatus.partialContent
        ..headers.contentType = ContentType('video', 'x-matroska');
      try {
        request.response.add(List.filled(64 * 1024, 0));
        await request.response.close();
      } on Object {
        // The client hung up, as it should.
      }
    };
  }

  CopyProber prober({
    Set<String> hosts = const {'127.0.0.1'},
    Duration timeout = const Duration(seconds: 2),
  }) {
    final prober = CopyProber(isAllowedHost: hosts.contains, timeout: timeout);
    addTearDown(prober.close);
    return prober;
  }

  setUp(() async => server = await LocalServer.start());
  tearDown(() => server.close());

  test('a video that is there answers with its ping and its address', () async {
    video('/film.mkv');
    final url = server.url('/film.mkv');

    final probe = await prober().probeOne(url);

    expect(probe.ok, isTrue);
    expect(probe.url, url);
    expect(probe.address, url);
    expect(probe.time, lessThan(const Duration(seconds: 1)));
    expect(probe.problem, isNull);
    // One byte is asked for, not the film.
    expect(server.requests.single.headers.value('range'), 'bytes=0-0');
  });

  test('every copy is asked at once, and the fastest answers first', () async {
    video('/slow.mkv', delay: const Duration(milliseconds: 400));
    video('/fast.mkv', delay: const Duration(milliseconds: 20));
    video('/middle.mkv', delay: const Duration(milliseconds: 200));
    final watch = Stopwatch()..start();

    final probes = await prober().probe([
      server.url('/slow.mkv'),
      server.url('/fast.mkv'),
      server.url('/middle.mkv'),
    ]).toList();

    expect(probes.map((probe) => probe.url.path), [
      '/fast.mkv',
      '/middle.mkv',
      '/slow.mkv',
    ]);
    expect(probes.every((probe) => probe.ok), isTrue);
    expect(probes[0].time, lessThan(probes[2].time!));
    // Side by side, not one after the other (20 + 200 + 400 ms).
    expect(watch.elapsed, lessThan(const Duration(milliseconds: 600)));
  });

  test('a video that is gone, or refused, is no copy to play', () async {
    server
      ..serve('/refused.mkv', 'no', status: HttpStatus.forbidden)
      ..serve('/broken.mkv', 'oops', status: HttpStatus.internalServerError);

    final gone = await prober().probeOne(server.url('/gone.mkv'));
    final refused = await prober().probeOne(server.url('/refused.mkv'));
    final broken = await prober().probeOne(server.url('/broken.mkv'));

    expect(gone.ok, isFalse);
    expect(gone.problem, contains('not on the server'));
    expect(gone.blocked, isFalse);
    expect(refused.problem, contains('does not let'));
    expect(broken.problem, 'The server answered 500.');
  });

  test('a server that takes too long counts as not answering', () async {
    video('/late.mkv', delay: const Duration(seconds: 3));

    final watch = Stopwatch()..start();
    final probe = await prober(
      timeout: const Duration(milliseconds: 300),
    ).probeOne(server.url('/late.mkv'));

    expect(probe.ok, isFalse);
    expect(probe.time, isNull);
    expect(probe.problem, contains('in time'));
    expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
  });

  test('a server that is not there counts as not answering', () async {
    final url = server.url('/film.mkv');
    await server.close();

    final probe = await prober().probeOne(url);

    expect(probe.ok, isFalse);
    expect(probe.blocked, isFalse);
    // (Windows takes its time to refuse a connection: either is right.)
    expect(
      probe.problem,
      anyOf(contains('could not be reached'), contains('in time')),
    );
  });

  test('a redirect on the server, or to another source, gives the final '
      'address', () async {
    video('/video.mkv');
    final elsewhere = server.url('/video.mkv').replace(host: 'localhost');
    server
      ..redirect('/play/1', '/video.mkv')
      ..redirect('/play/2', '$elsewhere');

    final same = await prober().probeOne(server.url('/play/1'));
    final other = await prober(
      hosts: {'127.0.0.1', 'localhost'},
    ).probeOne(server.url('/play/2'));

    expect(same.ok, isTrue);
    expect(same.address, server.url('/video.mkv'));
    expect(other.ok, isTrue);
    expect(other.address, elsewhere);
  });

  test('a redirect to a host that is no source blocks the copy', () async {
    final elsewhere = server.url('/video.mkv').replace(host: 'localhost');
    server
      ..redirect('/play/1', '$elsewhere')
      ..redirect('/loop', '/loop');

    final away = await prober().probeOne(server.url('/play/1'));
    final loop = await prober().probeOne(server.url('/loop'));

    expect(away.ok, isFalse);
    expect(away.blocked, isTrue);
    expect(away.problem, contains('not one of your sources'));
    expect(loop.blocked, isTrue);
    expect(loop.problem, contains('keeps redirecting'));
  });

  test('a host that is no source is never asked', () async {
    video('/film.mkv');

    final probe = await prober(hosts: {}).probeOne(server.url('/film.mkv'));

    expect(probe.ok, isFalse);
    expect(server.requests, isEmpty);
  });

  test('the same address is asked once; no addresses, no answers', () async {
    video('/film.mkv');
    final url = server.url('/film.mkv');

    expect(await prober().probe([url, url]).toList(), hasLength(1));
    expect(await prober().probe([]).toList(), isEmpty);
    expect(server.requests, hasLength(1));
  });
}
