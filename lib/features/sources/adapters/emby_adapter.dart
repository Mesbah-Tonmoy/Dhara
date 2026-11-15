import 'dart:convert';

import 'package:dhara/core/net/safe_http_client.dart';
import 'package:dhara/features/sources/adapters/source_adapter.dart';
import 'package:dhara/features/sources/source.dart';

/// What an Emby or Jellyfin server says about itself to anyone.
class MediaServerInfo {
  const MediaServerInfo({
    required this.type,
    required this.name,
    required this.version,
  });

  /// [SourceType.emby] or [SourceType.jellyfin].
  final SourceType type;

  /// Server-controlled text, shortened; show it through `Text` only.
  final String name;
  final String version;
}

/// Asks the server at [baseUrl] whether it is Emby or Jellyfin, without
/// signing in. Returns `null` when it is neither.
Future<MediaServerInfo?> probeMediaServer(
  SafeHttpClient client,
  Uri baseUrl,
) async {
  final response = await client.get(
    _api(baseUrl, 'System/Info/Public'),
    maxBytes: _smallAnswer,
  );
  final json = response.isOk ? _decode(response.body) : null;
  if (json is! Map<String, dynamic>) return null;
  final version = json['Version'];
  if (version is! String || json['Id'] is! String) return null;

  // Jellyfin names itself; Emby (which it was forked from) does not.
  final product = json['ProductName'];
  final isJellyfin =
      product is String && product.toLowerCase().contains('jellyfin');
  final name = json['ServerName'];
  return MediaServerInfo(
    type: isJellyfin ? SourceType.jellyfin : SourceType.emby,
    name: name is String ? cleanServerText(name, 80) : '',
    version: cleanServerText(version, 20),
  );
}

/// Reads the library of an Emby or Jellyfin server through its API (the two
/// share it).
///
/// Unlike a folder listing, the API needs a signed-in user. Without a
/// [username] the adapter signs in as the server's guest user: the first
/// user on its public login screen that has no password, which is how BDIX
/// operators open these servers to their customers. The session token is
/// kept in memory only.
///
/// Folder entries get a URL of this adapter's own making
/// (`<base>Items?ParentId=<id>`); pass it back to [list] to look inside.
/// File entries point at the original file (`Videos/<id>/stream?static=true`).
/// Fetching one needs the session token as a header: [playbackHeaders].
class EmbyAdapter implements SourceAdapter {
  EmbyAdapter(
    this._client, {
    required Uri baseUrl,
    required String deviceId,
    String? username,
    String password = '',
  }) : _root = _api(baseUrl, ''),
       _deviceId = deviceId,
       _username = username,
       _password = password {
    // It goes into a header, so it must not be able to break out of one.
    if (!isValidDeviceId(deviceId)) {
      throw ArgumentError.value(deviceId, 'deviceId', 'letters, digits, "-"');
    }
  }

  final SafeHttpClient _client;
  final Uri _root;

  /// A random id for this installation. The server lists it under the
  /// user's devices; it must not say anything about the PC or its owner.
  final String _deviceId;
  final String? _username;
  final String _password;

  Future<_Session>? _session;

  @override
  Future<List<RemoteEntry>> list(Uri folder) async {
    final parentId = _parentIdOf(folder);
    final entries = <RemoteEntry>[];
    var start = 0;
    while (entries.length < maxEntriesPerFolder) {
      final page = await _getJson(
        'Items',
        (session) => {
          'UserId': session.userId,
          if (parentId != null) 'ParentId': parentId,
          'Fields': 'Path,MediaSources,DateCreated',
          'SortBy': 'SortName',
          'SortOrder': 'Ascending',
          'StartIndex': '$start',
          'Limit': '$_pageSize',
        },
      );
      final items = page['Items'];
      if (items is! List) {
        throw const SourceReadException(
          'The server sent an unexpected answer.',
        );
      }
      for (final item in items) {
        final entry = _entryOf(item);
        if (entry != null) entries.add(entry);
      }
      start += items.length;
      final total = page['TotalRecordCount'];
      if (items.isEmpty || total is! int || start >= total) break;
    }
    return entries;
  }

  /// The library item [folder] stands for, or `null` for the top level.
  /// Only URLs this adapter hands out are accepted, and the request is
  /// rebuilt from the id, so a stored or crafted URL is never fetched as is.
  String? _parentIdOf(Uri folder) {
    if (!folder.hasQuery && _api(folder, '') == _root) return null;

    final items = _api(_root, 'Items');
    final id = folder.queryParameters['ParentId'];
    if (folder.scheme == items.scheme &&
        folder.host == items.host &&
        folder.port == items.port &&
        folder.path == items.path &&
        !folder.hasFragment &&
        folder.queryParameters.length == 1 &&
        id != null &&
        _idPattern.hasMatch(id)) {
      return id;
    }
    throw const SourceReadException(
      'That folder does not belong to this server.',
    );
  }

  RemoteEntry? _entryOf(Object? item) {
    if (item is! Map<String, dynamic>) return null;
    final id = item['Id'];
    final rawName = item['Name'];
    if (id is! String || !_idPattern.hasMatch(id) || rawName is! String) {
      return null;
    }
    final name = cleanServerText(rawName, 200);
    if (name.isEmpty) return null;
    final created = item['DateCreated'];
    final modified = created is String
        ? DateTime.tryParse(created)?.toLocal()
        : null;
    final year = item['ProductionYear'];

    if (item['IsFolder'] == true) {
      return RemoteEntry(
        // "Name (Year)" is how a series folder is usually named on disk.
        name: item['Type'] == 'Series' && year is int ? '$name ($year)' : name,
        url: _api(_root, 'Items', {'ParentId': id}),
        isFolder: true,
        modified: modified,
      );
    }
    if (item['MediaType'] != 'Video') return null;

    final sources = item['MediaSources'];
    final source = sources is List && sources.isNotEmpty ? sources.first : null;
    final sourceId = source is Map<String, dynamic> ? source['Id'] : null;
    final size = source is Map<String, dynamic> ? source['Size'] : null;
    final container = source is Map<String, dynamic>
        ? source['Container']
        : null;

    final path = item['Path'];
    final diskName = path is String
        ? cleanServerText(path.split(_pathSeparator).last, 300)
        : '';
    final extension =
        _extensionOf(diskName) ??
        // Emby reports "mov,mp4,m4a,3gp,3g2,mj2" for an MP4 file.
        (container is String
            ? _extensionOf('.${container.split(',')[0]}')
            : null);
    final dotExtension = extension == null ? '' : '.$extension';

    final String fileName;
    final series = item['SeriesName'];
    final season = item['ParentIndexNumber'];
    final episode = item['IndexNumber'];
    if (diskName.isNotEmpty) {
      fileName = diskName;
    } else if (series is String && season is int && episode is int) {
      fileName =
          '${cleanServerText(series, 200)} '
          'S${'$season'.padLeft(2, '0')}E${'$episode'.padLeft(2, '0')} '
          '$name$dotExtension';
    } else {
      fileName = '$name${year is int ? ' ($year)' : ''}$dotExtension';
    }

    return RemoteEntry(
      name: fileName,
      url: _api(_root, 'Videos/$id/stream$dotExtension', {
        'static': 'true',
        if (sourceId is String && _idPattern.hasMatch(sourceId))
          'MediaSourceId': sourceId,
      }),
      isFolder: false,
      size: size is int && size >= 0 ? size : null,
      modified: modified,
    );
  }

  /// The request headers a file of this server is fetched with (by the
  /// player, or to ping it): signs in first if that was not done yet.
  /// They hold the session token: for this server alone, and never to be
  /// saved or logged.
  Future<Map<String, String>> playbackHeaders() async =>
      _headers((await _currentSession()).token);

  /// A signed-in GET that returns a JSON object. If the server no longer
  /// accepts the token, signs in again once.
  Future<Map<String, dynamic>> _getJson(
    String path,
    Map<String, String> Function(_Session session) query,
  ) async {
    for (var attempt = 0; ; attempt++) {
      final session = await _currentSession();
      final response = await _client.get(
        _api(_root, path, query(session)),
        headers: _headers(session.token),
        maxBytes: maxListingBytes,
      );
      if (response.statusCode == 401 && attempt == 0) {
        _session = null;
        continue;
      }
      if (!response.isOk) {
        throw SourceReadException(
          'The server answered ${response.statusCode}.',
          statusCode: response.statusCode,
        );
      }
      final json = _decode(response.body);
      if (json is! Map<String, dynamic>) {
        throw const SourceReadException(
          'The server sent an unexpected answer.',
        );
      }
      return json;
    }
  }

  Future<_Session> _currentSession() async {
    try {
      return await (_session ??= _signIn());
    } on Object {
      // Let the next call try again instead of repeating this failure.
      _session = null;
      rethrow;
    }
  }

  Future<_Session> _signIn() async {
    final response = await _client.postJson(
      _api(_root, 'Users/AuthenticateByName'),
      {'Username': _username ?? await _guestName(), 'Pw': _password},
      headers: _headers(null),
      maxBytes: _smallAnswer,
    );
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw const SourceReadException('The server refused the sign-in.');
    }
    final json = response.isOk ? _decode(response.body) : null;
    final token = json is Map<String, dynamic> ? json['AccessToken'] : null;
    final user = json is Map<String, dynamic> ? json['User'] : null;
    final userId = user is Map<String, dynamic> ? user['Id'] : null;
    if (token is! String ||
        !_tokenPattern.hasMatch(token) ||
        userId is! String ||
        !_idPattern.hasMatch(userId)) {
      throw const SourceReadException('The sign-in did not work.');
    }
    return _Session(userId, token);
  }

  /// The first user on the public login screen that needs no password.
  Future<String> _guestName() async {
    final response = await _client.get(
      _api(_root, 'Users/Public'),
      headers: _headers(null),
      maxBytes: _smallAnswer,
    );
    final users = response.isOk ? _decode(response.body) : null;
    if (users is List) {
      for (final user in users) {
        if (user is! Map<String, dynamic>) continue;
        final name = user['Name'];
        if (user['HasPassword'] == false && name is String) return name;
      }
    }
    throw const SourceReadException(
      'This server has no guest user; it needs a user name and password.',
    );
  }

  /// Who is asking, in the form both servers understand. Emby reads
  /// `X-Emby-*`; Jellyfin prefers `Authorization`.
  Map<String, String> _headers(String? token) {
    final identity =
        'MediaBrowser Client="Dhara", Device="Dhara", '
        'DeviceId="$_deviceId", Version="1"'
        '${token == null ? '' : ', Token="$token"'}';
    return {
      'Authorization': identity,
      'X-Emby-Authorization': identity,
      if (token != null) 'X-Emby-Token': token,
    };
  }
}

class _Session {
  const _Session(this.userId, this.token);

  final String userId;
  final String token;
}

const _pageSize = 100;
const _smallAnswer = 256 * 1024;

// Ids and tokens end up in URLs and headers, so only harmless characters.
final _idPattern = RegExp(r'^[A-Za-z0-9-]{1,64}$');

/// Whether [id] can be used as the `deviceId` of an [EmbyAdapter].
bool isValidDeviceId(String id) => _idPattern.hasMatch(id);
final _tokenPattern = RegExp(r'^[A-Za-z0-9._-]{1,256}$');
final _pathSeparator = RegExp(r'[/\\]');
final _extensionPattern = RegExp(r'\.([A-Za-z0-9]{2,5})$');

/// The API address [path] under [baseUrl] (which may or may not end in
/// "/"), with [query] as its only query.
Uri _api(Uri baseUrl, String path, [Map<String, String>? query]) {
  final root = baseUrl.path.endsWith('/')
      ? baseUrl
      : baseUrl.replace(path: '${baseUrl.path}/');
  final url = root.resolve(path);
  return query == null ? url : url.replace(queryParameters: query);
}

Object? _decode(String body) {
  try {
    return jsonDecode(body);
  } on FormatException {
    return null;
  }
}

String? _extensionOf(String fileName) =>
    _extensionPattern.firstMatch(fileName)?[1]?.toLowerCase();
