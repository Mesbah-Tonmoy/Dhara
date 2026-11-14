import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dhara/core/net/safe_http_client.dart';

/// Posters, backdrops and stills from TMDB's image server, kept on disk so
/// that each is downloaded once.
///
/// - Talks to `image.tmdb.org` over https only, through a [SafeHttpClient];
///   every download has a time limit and a size limit.
/// - Only the sizes in [sizes] and paths of the shape TMDB uses
///   (`/abc123.jpg`) are asked for: the path becomes part of an address
///   and of a file name, so nothing else is let through.
/// - What comes back is kept only if it starts like a JPEG, PNG or WebP
///   file. Pictures are shown by Flutter's own decoders, never opened by
///   another program.
/// - The folder is kept below [maxTotalBytes] by [trim], which removes the
///   pictures that were not looked at for the longest.
class RemoteImageStore {
  RemoteImageStore({
    required Directory? folder,
    SafeHttpClient? http,
    Uri? baseUrl,
    this.maxTotalBytes = 300 * 1024 * 1024,
    this.maxImageBytes = 3 * 1024 * 1024,
    DateTime Function() now = DateTime.now,
  }) : _folder = folder,
       _base = baseUrl ?? Uri.https(host, '/t/p'),
       _http =
           http ??
           SafeHttpClient(
             isAllowedHost: (name) => name == (baseUrl?.host ?? host),
           ),
       _ownsHttp = http == null,
       _now = now;

  static const host = 'image.tmdb.org';

  /// The widths TMDB offers that the app uses: posters (`w154`, `w342`,
  /// `w500`), backdrops (`w780`, `w1280`) and stills (`w300`).
  static const sizes = {'w154', 'w300', 'w342', 'w500', 'w780', 'w1280'};

  final int maxTotalBytes;
  final int maxImageBytes;

  final Directory? _folder;
  final Uri _base;
  final SafeHttpClient _http;
  final bool _ownsHttp;
  final DateTime Function() _now;

  final _underWay = <String, Future<File?>>{};
  final _failedAt = <String, DateTime>{};
  final _waiting = <Completer<void>>[];
  var _downloads = 0;

  /// The picture at [path] (as TMDB gives it: `/abc123.jpg`) in [size], as
  /// a file on disk; downloaded if it is not there yet.
  ///
  /// `null` if there is no such picture, it cannot be fetched right now,
  /// what came back is not a picture, or there is no folder to keep it in.
  /// Never throws.
  Future<File?> file(String size, String path) {
    final folder = _folder;
    if (folder == null || !sizes.contains(size) || !_imagePath.hasMatch(path)) {
      return Future.value();
    }
    final key = '$size$path';
    return _underWay[key] ??= _get(folder, size, path).whenComplete(() {
      // In braces: returning the removed future would make it wait for
      // itself.
      _underWay.remove(key);
    });
  }

  /// Removes the pictures that were not looked at for the longest until
  /// the folder is well below [maxTotalBytes], and downloads that were
  /// cut short. Returns how many bytes were freed. Never throws.
  Future<int> trim() async {
    final folder = _folder;
    if (folder == null) return 0;
    var freed = 0;
    try {
      final root = Directory('${folder.path}${Platform.pathSeparator}tmdb');
      if (!await root.exists()) return 0;
      final kept = <(File, int, DateTime)>[];
      var total = 0;
      final stale = _now().subtract(const Duration(hours: 1));
      await for (final entry in root.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entry is! File) continue;
        final stat = await entry.stat();
        if (entry.path.endsWith(_partSuffix)) {
          if (stat.modified.isBefore(stale)) {
            await entry.delete();
            freed += stat.size;
          }
          continue;
        }
        kept.add((entry, stat.size, stat.modified));
        total += stat.size;
      }
      if (total <= maxTotalBytes) return freed;
      // Well below, so that the next few pictures do not start it again.
      final target = maxTotalBytes * 8 ~/ 10;
      kept.sort((a, b) => a.$3.compareTo(b.$3));
      for (final (file, size, _) in kept) {
        if (total <= target) break;
        await file.delete();
        total -= size;
        freed += size;
      }
    } on FileSystemException {
      // Whatever could not be removed stays until next time.
    }
    return freed;
  }

  /// Drops the connections, if this store made them itself.
  void close() {
    if (_ownsHttp) _http.close();
  }

  Future<File?> _get(Directory folder, String size, String path) async {
    final separator = Platform.pathSeparator;
    final file = File(
      '${folder.path}${separator}tmdb$separator$size$separator'
      '${path.substring(1)}',
    );
    try {
      if (await file.exists() && await file.length() > 0) {
        await _markUsed(file);
        return file;
      }
      // What failed a moment ago is not asked for with every rebuild.
      final failed = _failedAt['$size$path'];
      if (failed != null && _now().difference(failed) < _retryAfter) {
        return null;
      }
      final bytes = await _download(size, path);
      if (bytes == null) {
        _failedAt['$size$path'] = _now();
        return null;
      }
      await file.parent.create(recursive: true);
      // Written beside it first, so a download that is cut short never
      // passes for a picture.
      final part = File('${file.path}$_partSuffix');
      await part.writeAsBytes(bytes, flush: true);
      await part.rename(file.path);
      return file;
    } on FileSystemException {
      return null;
    }
  }

  Future<Uint8List?> _download(String size, String path) async {
    if (_downloads >= _maxDownloads) {
      final turn = Completer<void>();
      _waiting.add(turn);
      await turn.future;
    } else {
      _downloads++;
    }
    try {
      final response = await _http.get(
        _base.replace(path: '${_base.path}/$size$path'),
        timeout: const Duration(seconds: 20),
        maxBytes: maxImageBytes,
      );
      if (!response.isOk || !_isPicture(response.bodyBytes)) return null;
      return response.bodyBytes;
    } on SafeHttpException {
      return null;
    } finally {
      // The place goes straight to whoever waits longest.
      if (_waiting.isNotEmpty) {
        _waiting.removeAt(0).complete();
      } else {
        _downloads--;
      }
    }
  }

  /// Notes that [file] was looked at, for [trim]; at most once a day per
  /// file.
  Future<void> _markUsed(File file) async {
    try {
      final now = _now();
      final modified = await file.lastModified();
      if (now.difference(modified) > const Duration(days: 1)) {
        await file.setLastModified(now);
      }
    } on FileSystemException {
      // Only the order of removal depends on it.
    }
  }
}

/// Whether [bytes] start the way a JPEG, PNG or WebP file does.
bool _isPicture(Uint8List bytes) {
  bool startsWith(List<int> start, [int at = 0]) {
    if (bytes.length < at + start.length) return false;
    for (var i = 0; i < start.length; i++) {
      if (bytes[at + i] != start[i]) return false;
    }
    return true;
  }

  return startsWith(const [0xFF, 0xD8, 0xFF]) ||
      startsWith(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) ||
      // "RIFF" .... "WEBP"
      (startsWith(const [0x52, 0x49, 0x46, 0x46]) &&
          startsWith(const [0x57, 0x45, 0x42, 0x50], 8));
}

const _maxDownloads = 4;
const _retryAfter = Duration(minutes: 10);
const _partSuffix = '.part';

/// "/abc123.jpg": one name, no folders, a picture's extension.
final _imagePath = RegExp(r'^/[A-Za-z0-9_-]{1,64}\.(jpg|jpeg|png|webp)$');
