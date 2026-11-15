import 'dart:async';

import 'package:dhara/core/net/safe_http_client.dart';
import 'package:dhara/features/sources/adapters/emby_adapter.dart';
import 'package:dhara/features/sources/source.dart';
import 'package:dhara/features/sources/source_store.dart';
import 'package:flutter/widgets.dart';

/// Signs in to the Emby and Jellyfin servers among the sources when one of
/// their videos is to be played (or pinged), and hands out the request
/// headers their files are fetched with.
///
/// A folder listing gives its files to anyone; a media server wants the
/// token of a signed-in session with every request. The sign-in is the
/// adapter's (the server's guest user), done once per server and run of
/// the app. Tokens are kept in memory only: never saved, never logged,
/// and only ever sent to the server they came from.
class MediaSessions {
  MediaSessions({
    required this.deviceId,
    required this.sources,
    this.timeout = const Duration(seconds: 4),
  });

  /// What the servers are told when signing in (see `loadOrCreateDeviceId`).
  final String deviceId;
  final SourceStore sources;

  /// How long a server has for each step of a sign-in: Play waits for it.
  final Duration timeout;

  // One adapter per server (base URL): it holds that server's session.
  final _adapters = <Uri, EmbyAdapter>{};
  SafeHttpClient? _client;

  /// The base URL of the media server [url] is a file of: an Emby or
  /// Jellyfin source whose address it lies under. `null` for any other
  /// address.
  Uri? serverOf(Uri url) {
    for (final source in sources.sources) {
      if (source.type != SourceType.emby &&
          source.type != SourceType.jellyfin) {
        continue;
      }
      for (final base in source.baseUrls) {
        final root = base.path.endsWith('/') ? base.path : '${base.path}/';
        if (url.scheme == base.scheme &&
            url.host == base.host &&
            url.port == base.port &&
            url.path.startsWith(root)) {
          return base;
        }
      }
    }
    return null;
  }

  /// The headers [url] must be asked for with: none for a file of a plain
  /// server, the session's for a file of a media server. None either if
  /// the sign-in does not work; the server then refuses the file, which
  /// is what the player reports. Never throws.
  Future<Map<String, String>> headersFor(Uri url) async {
    final server = serverOf(url);
    if (server == null) return const {};
    final adapter = _adapters[server] ??= EmbyAdapter(
      _client ??= SafeHttpClient(
        // Looked up each time: the list of sources can change.
        isAllowedHost: (host) => sources.sources.any(
          (source) => source.baseUrls.any((base) => base.host == host),
        ),
        timeout: timeout,
      ),
      baseUrl: server,
      deviceId: deviceId,
    );
    try {
      return await adapter.playbackHeaders();
    } on Object {
      return const {};
    }
  }

  /// [headersFor] for each of [urls] that needs any, all at once.
  Future<Map<Uri, Map<String, String>>> headersForAll(
    Iterable<Uri> urls,
  ) async {
    final wanted = {
      for (final url in urls)
        if (serverOf(url) != null) url,
    };
    if (wanted.isEmpty) return const {};
    final found = await Future.wait([
      for (final url in wanted) headersFor(url),
    ]);
    return {
      for (final (index, url) in wanted.indexed)
        if (found[index].isNotEmpty) url: found[index],
    };
  }

  /// Signs in afresh the next time: the server no longer takes the
  /// session it gave.
  void forget(Uri url) {
    final server = serverOf(url);
    if (server != null) _adapters.remove(server);
  }

  void close() => _client?.close();
}

/// Gives the pages and the player the app's [MediaSessions]. Without it,
/// or with none in it (tests), files of media servers are asked for
/// without a session.
class MediaSessionsScope extends InheritedWidget {
  const MediaSessionsScope({
    super.key,
    required this.sessions,
    required super.child,
  });

  final MediaSessions? sessions;

  static MediaSessions? read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<MediaSessionsScope>()?.sessions;

  @override
  bool updateShouldNotify(MediaSessionsScope old) => false;
}
