// A stand-in for an Emby server. The public answers are real captures from
// the Emby server in the starter list; everything behind the sign-in is
// written by hand from the Emby/Jellyfin API documentation, with made-up
// titles, and has not been checked against a real server yet.
import 'dart:convert';
import 'dart:io';

import 'local_server.dart';

const _guestId = '91450e318b574e69aa36c056d83a4acd';

const fakeEmbyLibrary = <String?, List<Map<String, Object?>>>{
  null: [
    {'Name': 'Movies', 'Id': '3', 'IsFolder': true, 'Type': 'CollectionFolder'},
    {'Name': 'Series', 'Id': '5', 'IsFolder': true, 'Type': 'CollectionFolder'},
  ],
  '3': [
    {
      'Name': 'Quiet River',
      'Id': '101',
      'Type': 'Movie',
      'MediaType': 'Video',
      'IsFolder': false,
      'ProductionYear': 2019,
      'Path': '/mnt/disk1/Movies/Quiet River (2019)/'
          'Quiet.River.2019.1080p.BluRay.x264.mkv',
      'DateCreated': '2024-03-04T15:09:00.0000000Z',
      'MediaSources': [
        {'Id': 'ms101', 'Container': 'mkv', 'Size': 2147483648},
      ],
    },
    {
      'Name': 'Paper Kites',
      'Id': '102',
      'Type': 'Movie',
      'MediaType': 'Video',
      'ProductionYear': 2021,
      'MediaSources': [
        {
          'Id': 'abcdef0123',
          'Container': 'mov,mp4,m4a,3gp,3g2,mj2',
          'Size': 1500
        },
      ],
    },
    {'Name': 'Soundtrack', 'Id': '103', 'Type': 'Audio', 'MediaType': 'Audio'},
    {
      'Name': 'Glass Orchard',
      'Id': '104',
      'MediaType': 'Video',
      'Path': r'D:\Media\Movies\Glass.Orchard.2020.720p.mp4',
    },
  ],
  '5': [
    {
      'Name': 'Harbor Lights',
      'Id': '200',
      'Type': 'Series',
      'IsFolder': true,
      'ProductionYear': 2022,
    },
  ],
  '200': [
    {
      'Name': 'Pilot',
      'Id': '301',
      'Type': 'Episode',
      'MediaType': 'Video',
      'SeriesName': 'Harbor Lights',
      'ParentIndexNumber': 1,
      'IndexNumber': 2,
      'MediaSources': [
        {'Id': 'ms301', 'Container': 'mkv', 'Size': 10},
      ],
    },
  ],
};

/// The parts of an Emby server the adapter talks to.
class FakeEmby {
  FakeEmby(this.server, {String prefix = ''}) : _prefix = prefix {
    server
      // A real server answers its base URL with the web app's page.
      ..serve('$prefix/', '<html><head><title>Emby</title></head></html>')
      ..serve(
        '$prefix/System/Info/Public',
        fixture('emby/emby_system_info_public.json'),
        contentType: 'application/json; charset=utf-8',
      )
      ..routes['$prefix/Users/Public'] = _users
      ..routes['$prefix/Users/AuthenticateByName'] = _authenticate
      ..routes['$prefix/Items'] = _items;
  }

  final LocalServer server;
  final String _prefix;

  Map<String?, List<Map<String, Object?>>> library = fakeEmbyLibrary;
  String publicUsers = fixture('emby/emby_users_public.json');

  /// The token handed out by the next sign-in; only it is accepted.
  String token = 'token-1';
  String? password;
  final signIns = <Map<String, dynamic>>[];

  Future<void> _json(HttpRequest request, Object? body, [int status = 200]) {
    request.response
      ..statusCode = status
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(body));
    return request.response.close();
  }

  Future<void> _users(HttpRequest request) {
    request.response
      ..headers.contentType = ContentType.json
      ..write(publicUsers);
    return request.response.close();
  }

  Future<void> _authenticate(HttpRequest request) async {
    final body =
        jsonDecode(await utf8.decodeStream(request)) as Map<String, dynamic>;
    signIns.add(body);
    final accepted = request.method == 'POST' &&
        (password == null
            ? body['Username'] == 'Taltola.Net' && body['Pw'] == ''
            : body['Username'] == 'mehedi' && body['Pw'] == password);
    if (!accepted) return _json(request, 'Invalid user or password.', 401);
    return _json(request, {
      'User': {'Name': body['Username'], 'Id': _guestId},
      'AccessToken': token,
      'ServerId': '60918f598ceb4317b2ed24a9d9ad937f',
    });
  }

  Future<void> _items(HttpRequest request) {
    final query = request.uri.queryParameters;
    if (request.headers.value('x-emby-token') != token ||
        query['UserId'] != _guestId) {
      request.response.statusCode = 401;
      return request.response.close();
    }
    final all = library[query['ParentId']] ?? const [];
    final start = int.parse(query['StartIndex']!);
    final limit = int.parse(query['Limit']!);
    return _json(request, {
      'Items': all.skip(start).take(limit).toList(),
      'TotalRecordCount': all.length,
    });
  }

  List<HttpRequest> requestsTo(String path) => [
        for (final request in server.requests)
          if (request.uri.path == path) request,
      ];

  /// Makes every library request fail with 401, whatever the token.
  void refuseEveryToken() {
    server.routes['$_prefix/Items'] = (request) async {
      request.response.statusCode = 401;
      await request.response.close();
    };
  }
}
