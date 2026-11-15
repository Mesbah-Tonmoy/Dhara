// Runs against test/support/fake_emby.dart; see there for what is a real
// capture and what is written from the API documentation.
import 'dart:convert';
import 'dart:io';

import 'package:dhara/core/net/safe_http_client.dart';
import 'package:dhara/features/sources/adapters/emby_adapter.dart';
import 'package:dhara/features/sources/adapters/source_adapter.dart';
import 'package:dhara/features/sources/source.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fake_emby.dart';
import '../../../support/local_server.dart';

void main() {
  late LocalServer server;
  late SafeHttpClient client;
  late FakeEmby emby;

  setUp(() async {
    server = await LocalServer.start();
    client = server.client();
    emby = FakeEmby(server);
  });

  tearDown(() async {
    client.close();
    await server.close();
  });

  EmbyAdapter adapter({String? username, String password = '', Uri? baseUrl}) =>
      EmbyAdapter(
        client,
        baseUrl: baseUrl ?? server.url('/'),
        deviceId: 'dhara-test-1',
        username: username,
        password: password,
      );

  Matcher refuses(String part) => throwsA(
        isA<SourceReadException>()
            .having((e) => e.message, 'message', contains(part)),
      );

  test('playbackHeaders signs in and carries the session token', () async {
    final headers = await adapter().playbackHeaders();

    expect(headers['X-Emby-Token'], 'token-1');
    expect(headers['Authorization'], contains('Token="token-1"'));
    expect(headers['Authorization'], contains('DeviceId="dhara-test-1"'));
    expect(emby.signIns, hasLength(1));

    // With them the server gives the file; without, it does not.
    final file = server.url('/Videos/101/stream.mkv');
    expect((await client.probe(file, headers: headers)).statusCode, 206);
    expect((await client.probe(file)).statusCode, 401);
  });

  test('playbackHeaders uses the session the listing signed in for', () async {
    final one = adapter();
    await one.list(server.url('/'));
    await one.playbackHeaders();
    await one.playbackHeaders();

    expect(emby.signIns, hasLength(1));
  });

  test('playbackHeaders fails where the sign-in does', () async {
    emby.publicUsers = '[]';

    await expectLater(adapter().playbackHeaders(), refuses('no guest user'));
  });

  group('probeMediaServer', () {
    test('recognises Emby from its real public answer', () async {
      final info = await probeMediaServer(client, server.url('/'));

      expect(info?.type, SourceType.emby);
      expect(info?.version, '4.8.5.0');
      expect(info?.name, 'server');
    });

    test('recognises Jellyfin by its product name', () async {
      server.serve(
        '/System/Info/Public',
        jsonEncode({
          'LocalAddress': 'http://10.0.0.8:8096',
          'ServerName': 'media\nbox',
          'Version': '10.10.3',
          'ProductName': 'Jellyfin Server',
          'Id': '0123456789abcdef0123456789abcdef',
          'StartupWizardCompleted': true,
        }),
        contentType: 'application/json',
      );

      final info = await probeMediaServer(client, server.url(''));

      expect(info?.type, SourceType.jellyfin);
      expect(info?.name, 'media box', reason: 'kept to one line');
    });

    test('says no to anything else', () async {
      server
        ..serve('/a/System/Info/Public', '<html>Welcome</html>')
        ..serve('/b/System/Info/Public', '{"ServerName": "x"}')
        ..serve('/c/System/Info/Public', '[1, 2]');

      for (final base in ['/a/', '/b/', '/c/', '/missing/']) {
        expect(
          await probeMediaServer(client, server.url(base)),
          isNull,
          reason: base,
        );
      }
    });
  });

  group('as the guest user', () {
    test('signs in with the first password-less public user', () async {
      await adapter().list(server.url('/'));

      expect(emby.signIns, [
        {'Username': 'Taltola.Net', 'Pw': ''},
      ]);
      final signIn = emby.requestsTo('/Users/AuthenticateByName').single;
      final identity = signIn.headers.value('x-emby-authorization')!;
      expect(identity, contains('Client="Dhara"'));
      expect(identity, contains('DeviceId="dhara-test-1"'));
      expect(identity, isNot(contains('Token')));
      expect(signIn.headers.value('authorization'), identity);

      final items = emby.requestsTo('/Items').single;
      expect(items.headers.value('x-emby-token'), 'token-1');
      expect(
        items.headers.value('authorization'),
        contains('Token="token-1"'),
      );
    });

    test('lists the libraries at the top level', () async {
      final entries = await adapter().list(server.url('/'));

      expect(entries, [
        RemoteEntry(
          name: 'Movies',
          url: server.url('/Items?ParentId=3'),
          isFolder: true,
        ),
        RemoteEntry(
          name: 'Series',
          url: server.url('/Items?ParentId=5'),
          isFolder: true,
        ),
      ]);
    });

    test('lists videos with file name, size, date and stream URL', () async {
      final emby = adapter();
      final libraries = await emby.list(server.url('/'));

      final movies = await emby.list(libraries.first.url);

      expect(movies, [
        RemoteEntry(
          name: 'Quiet.River.2019.1080p.BluRay.x264.mkv',
          url: server.url(
            '/Videos/101/stream.mkv?static=true&MediaSourceId=ms101',
          ),
          isFolder: false,
          size: 2147483648,
          modified: DateTime.utc(2024, 3, 4, 15, 9).toLocal(),
        ),
        // No path from the server: the name is built from the metadata, and
        // the extension from the first container name.
        RemoteEntry(
          name: 'Paper Kites (2021).mov',
          url: server.url(
            '/Videos/102/stream.mov?static=true&MediaSourceId=abcdef0123',
          ),
          isFolder: false,
          size: 1500,
        ),
        // (The audio item is left out.)
        RemoteEntry(
          name: 'Glass.Orchard.2020.720p.mp4',
          url: server.url('/Videos/104/stream.mp4?static=true'),
          isFolder: false,
        ),
      ]);
    });

    test('names series folders and episodes so they can be parsed', () async {
      final emby = adapter();

      final series = await emby.list(server.url('/Items?ParentId=5'));
      final episodes = await emby.list(series.single.url);

      expect(series.single.name, 'Harbor Lights (2022)');
      expect(series.single.url, server.url('/Items?ParentId=200'));
      expect(episodes.single.name, 'Harbor Lights S01E02 Pilot.mkv');
    });

    test('reads a long folder page by page', () async {
      emby.library = {
        '9': [
          for (var i = 0; i < 250; i++)
            {'Name': 'Clip $i', 'Id': '${1000 + i}', 'MediaType': 'Video'},
        ],
      };

      final entries = await adapter().list(server.url('/Items?ParentId=9'));

      expect(entries, hasLength(250));
      expect(entries.last.name, 'Clip 249');
      expect(
        emby
            .requestsTo('/Items')
            .map((r) => r.uri.queryParameters['StartIndex']),
        ['0', '100', '200'],
      );
    });

    test('signs in once, and again only when the token stops working',
        () async {
      final emby_ = adapter();
      await emby_.list(server.url('/'));
      await emby_.list(server.url('/Items?ParentId=3'));
      expect(emby.signIns, hasLength(1));

      // The server forgets the session (restart, expiry).
      emby.token = 'token-2';
      final entries = await emby_.list(server.url('/'));

      expect(entries, hasLength(2));
      expect(emby.signIns, hasLength(2));
    });

    test('gives up when a fresh sign-in is refused as well', () async {
      final emby_ = adapter();
      // Signing in "works", but the token never does.
      emby.refuseEveryToken();

      await expectLater(emby_.list(server.url('/')), refuses('401'));
      expect(emby.signIns, hasLength(2));
    });

    test('says so when the server has no guest user', () async {
      emby.publicUsers = jsonEncode([
        {'Name': 'admin', 'HasPassword': true},
      ]);
      final emby_ = adapter();

      await expectLater(emby_.list(server.url('/')), refuses('guest'));
      expect(emby.signIns, isEmpty);

      // The failure is not remembered: once a guest exists, it works.
      emby.publicUsers = fixture('emby/emby_users_public.json');
      expect(await emby_.list(server.url('/')), hasLength(2));
    });
  });

  group('with a user name and password', () {
    test('signs in as that user without asking for public users', () async {
      emby.password = 'correct horse';

      final entries = await adapter(
        username: 'mehedi',
        password: 'correct horse',
      ).list(server.url('/'));

      expect(entries, hasLength(2));
      expect(emby.requestsTo('/Users/Public'), isEmpty);
    });

    test('reports a refused sign-in', () async {
      emby.password = 'correct horse';

      await expectLater(
        adapter(username: 'mehedi', password: 'wrong').list(server.url('/')),
        refuses('refused the sign-in'),
      );
    });
  });

  group('untrusted input', () {
    test('only its own folder URLs are accepted', () async {
      final emby_ = adapter();
      for (final url in [
        'http://10.0.0.99/Items?ParentId=3',
        server.url('/Other?ParentId=3').toString(),
        server.url('/Items').toString(),
        server.url('/Items?ParentId=3&UserId=admin').toString(),
        server.url('/Items?ParentId=..%2F..%2FSystem').toString(),
        server.url('/Items?ParentId=3#x').toString(),
        server.url('/Videos/101/stream.mkv?static=true').toString(),
      ]) {
        await expectLater(
          emby_.list(Uri.parse(url)),
          refuses('does not belong'),
          reason: url,
        );
      }
      expect(server.requests, isEmpty);
    });

    test('items with unusable ids or names are skipped, text is cleaned',
        () async {
      emby.library = {
        null: [
          {'Name': 'Bad id', 'Id': '../../System/Shutdown', 'IsFolder': true},
          {'Name': 'No id', 'IsFolder': true},
          {'Name': '   ', 'Id': '1', 'IsFolder': true},
          {'Name': 7, 'Id': '2', 'IsFolder': true},
          {'Name': 'Line\r\nbreak', 'Id': '3', 'IsFolder': true},
          {
            'Name': 'Odd source',
            'Id': '4',
            'MediaType': 'Video',
            'Path': '/x/../../etc/passwd',
            'MediaSources': [
              {'Id': 'a&b=c', 'Size': -5, 'Container': '../evil'},
            ],
          },
        ],
      };
      emby.server.routes['/Items'] = (request) async {
        request.response
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode({
              'Items': [...emby.library[null]!, 'text', 42, null],
              'TotalRecordCount': 9,
            }),
          );
        await request.response.close();
      };

      final entries = await adapter().list(server.url('/'));

      expect(entries, [
        RemoteEntry(
          name: 'Line  break',
          url: server.url('/Items?ParentId=3'),
          isFolder: true,
        ),
        RemoteEntry(
          name: 'passwd',
          url: server.url('/Videos/4/stream?static=true'),
          isFolder: false,
        ),
      ]);
    });

    test('a token that could break out of a header is refused', () async {
      emby.token = 'abc\r\nX-Injected: 1';

      await expectLater(
        adapter().list(server.url('/')),
        refuses('sign-in did not work'),
      );
      expect(emby.requestsTo('/Items'), isEmpty);
    });

    test('answers that are not the expected JSON are reported', () async {
      for (final body in ['<html>Login</html>', '[]', '{"Items": "none"}']) {
        server.serve('/Items', body, contentType: 'application/json');

        await expectLater(
          adapter().list(server.url('/')),
          refuses('unexpected answer'),
          reason: body,
        );
      }
    });

    test('a device id that is not plain is rejected up front', () {
      expect(
        () => EmbyAdapter(
          client,
          baseUrl: server.url('/'),
          deviceId: 'pc", Token="x',
        ),
        throwsArgumentError,
      );
    });
  });

  test('works for a server under a sub-path, slash or not', () async {
    final nested = FakeEmby(server, prefix: '/emby');

    final entries =
        await adapter(baseUrl: server.url('/emby')).list(server.url('/emby'));

    expect(entries.first.url, server.url('/emby/Items?ParentId=3'));
    expect(nested.requestsTo('/emby/Items'), hasLength(1));
    expect(
      (await probeMediaServer(client, server.url('/emby')))?.type,
      SourceType.emby,
    );
  });
}
