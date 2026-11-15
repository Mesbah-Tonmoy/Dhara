// Runs against test/support/fake_emby.dart.
import 'package:dhara/features/playback/media_sessions.dart';
import 'package:dhara/features/sources/source.dart';
import 'package:dhara/features/sources/source_store.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_emby.dart';
import '../../support/local_server.dart';

void main() {
  late LocalServer server;
  late FakeEmby emby;
  late SourceStore sources;
  late MediaSessions sessions;

  Source source(String id, SourceType type, Uri base) => Source(
    id: id,
    name: 'Server $id',
    type: type,
    category: SourceCategory.movies,
    baseUrls: [base],
  );

  setUp(() async {
    server = await LocalServer.start();
    emby = FakeEmby(server, prefix: '/emby');
    sources = SourceStore(
      starter: [
        source('media', SourceType.emby, server.url('/emby')),
        source('plain', SourceType.h5ai, server.url('/files/')),
      ],
    );
    sessions = MediaSessions(deviceId: 'dhara-test', sources: sources);
  });

  tearDown(() async {
    sessions.close();
    await server.close();
  });

  test('knows which addresses are files of a media server', () {
    expect(
      sessions.serverOf(server.url('/emby/Videos/101/stream.mkv')),
      server.url('/emby'),
    );
    // A plain server's file, another path, another host: none.
    expect(sessions.serverOf(server.url('/files/film.mkv')), isNull);
    expect(sessions.serverOf(server.url('/embyfiles/film.mkv')), isNull);
    expect(
      sessions.serverOf(
        server.url('/emby/Videos/1/stream.mkv').replace(host: 'localhost'),
      ),
      isNull,
    );
  });

  test('signs in once and hands out the headers of that session', () async {
    final first = await sessions.headersFor(
      server.url('/emby/Videos/101/stream.mkv'),
    );
    final second = await sessions.headersFor(
      server.url('/emby/Videos/102/stream.mkv'),
    );

    expect(first['X-Emby-Token'], 'token-1');
    expect(second, first);
    expect(emby.signIns, hasLength(1));
    expect(emby.signIns.single['Username'], 'Taltola.Net');
  });

  test('a plain server needs no headers, and is not signed in to', () async {
    expect(await sessions.headersFor(server.url('/files/film.mkv')), isEmpty);
    expect(server.requests, isEmpty);
  });

  test('all at once: only the files of media servers get headers', () async {
    final media = server.url('/emby/Videos/101/stream.mkv');
    final other = server.url('/emby/Videos/102/stream.mkv');
    final plain = server.url('/files/film.mkv');

    final headers = await sessions.headersForAll([media, plain, other]);

    expect(headers.keys, unorderedEquals([media, other]));
    expect(headers[media]!['X-Emby-Token'], 'token-1');
    expect(emby.signIns, hasLength(1));
    expect(await sessions.headersForAll([plain]), isEmpty);
  });

  test('a sign-in that does not work gives no headers, and no error', () async {
    emby.publicUsers = '[]';

    expect(
      await sessions.headersFor(server.url('/emby/Videos/101/stream.mkv')),
      isEmpty,
    );
    // Tried again the next time.
    emby.publicUsers = fixture('emby/emby_users_public.json');
    expect(
      await sessions.headersFor(server.url('/emby/Videos/101/stream.mkv')),
      isNotEmpty,
    );
  });

  test('a server that is not there gives no headers', () async {
    final url = server.url('/emby/Videos/101/stream.mkv');
    await server.close();

    expect(await sessions.headersFor(url), isEmpty);
  });

  test('after forget the next video signs in afresh', () async {
    final url = server.url('/emby/Videos/101/stream.mkv');
    await sessions.headersFor(url);
    emby.token = 'token-2';

    // The old session is still handed out ...
    expect((await sessions.headersFor(url))['X-Emby-Token'], 'token-1');
    // ... until it is forgotten.
    sessions.forget(url);
    expect((await sessions.headersFor(url))['X-Emby-Token'], 'token-2');
    expect(emby.signIns, hasLength(2));
  });
}
