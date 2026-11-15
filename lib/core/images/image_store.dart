import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dhara/core/net/safe_http_client.dart';

/// Posters, backdrops and stills from TMDB's image server, and covers from
/// AniList's, kept on disk so that each is downloaded once.
///
/// - Talks to `image.tmdb.org` and `s4.anilist.co` over https only, through
///   a [SafeHttpClient]; every download has a time limit and a size limit.
/// - Only the sizes in [sizes] and paths of the shape TMDB uses
///   (`/abc123.jpg`) are asked for: the path becomes part of an address
///   and of a file name, so nothing else is let through.
/// - What comes back is kept only if it starts like a JPEG, PNG or WebP
///   file. Pictures are shown by Flutter's own decoders, never opened by
///   another program.
/// - The folder is kept below [maxTotalBytes] by [trim], which removes the
///   pictures that were not looked at for the longest.
/// - At most four downloads run at a time; of those that wait, the one
///   asked for last goes first, because that is the picture on screen now.
/// - A download that failed is not tried again at once: after
///   [retrySoonAfter] if the server could not be reached or took too long
///   (it may well work in a moment), after [retryLaterAfter] if it
///   answered with something that is no picture.
class RemoteImageStore {
  RemoteImageStore({
    required Directory? folder,
    SafeHttpClient? http,
    Uri? baseUrl,
    Uri? anilistBaseUrl,
    this.maxTotalBytes = 300 * 1024 * 1024,
    this.maxImageBytes = 3 * 1024 * 1024,
    DateTime Function() now = DateTime.now,
  }) : _folder = folder,
       _base = baseUrl ?? Uri.https(host, '/t/p'),
       _anilistBase = anilistBaseUrl ?? Uri.https(anilistImageHost),
       _http =
           http ??
           SafeHttpClient(
             isAllowedHost: (name) =>
                 name == (baseUrl?.host ?? host) ||
                 name == (anilistBaseUrl?.host ?? anilistImageHost),
           ),
       _ownsHttp = http == null,
       _now = now;

  static const host = 'image.tmdb.org';

  /// How long a picture that could not be fetched is left alone: a short
  /// while after a failure of the connection, long after a refusal.
  static const retrySoonAfter = Duration(seconds: 15);
  static const retryLaterAfter = Duration(minutes: 10);

  /// The widths TMDB offers that the app uses: posters (`w154`, `w342`,
  /// `w500`), backdrops (`w780`, `w1280`) and stills (`w300`).
  static const sizes = {'w154', 'w300', 'w342', 'w500', 'w780', 'w1280'};

  final int maxTotalBytes;
  final int maxImageBytes;

  final Directory? _folder;
  final Uri _base;
  final Uri _anilistBase;
  final SafeHttpClient _http;
  final bool _ownsHttp;
  final DateTime Function() _now;

  final _underWay = <String, Future<File?>>{};
  // When each picture that failed may be asked for again.
  final _notBefore = <String, DateTime>{};
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
    final separator = Platform.pathSeparator;
    return _kept(
      '$size$path',
      File(
        '${folder.path}${separator}tmdb$separator$size$separator'
        '${path.substring(1)}',
      ),
      _base.replace(path: '${_base.path}/$size$path'),
    );
  }

  /// The cover of an anime at [path] on AniList's picture server (as
  /// `anilistCoverPath` returns it), as a file on disk; downloaded if it is
  /// not there yet. `null` in the same cases as [file]. Never throws.
  Future<File?> anilistCover(String path) {
    final folder = _folder;
    if (folder == null || !anilistCoverFile.hasMatch(path)) {
      return Future.value();
    }
    final separator = Platform.pathSeparator;
    final [..., size, name] = path.split('/');
    return _kept(
      'anilist$path',
      File('${folder.path}${separator}anilist$separator$size$separator$name'),
      _anilistBase.replace(path: path),
    );
  }

  /// The picture kept as [file], fetched from [url] if it is not there;
  /// asked for once at a time under [key].
  Future<File?> _kept(String key, File file, Uri url) =>
      _underWay[key] ??= _get(key, file, url).whenComplete(() {
        // In braces: returning the removed future would make it wait for
        // itself.
        _underWay.remove(key);
      });

  /// Removes the pictures that were not looked at for the longest until
  /// the folder is well below [maxTotalBytes], and downloads that were
  /// cut short. Returns how many bytes were freed. Never throws.
  Future<int> trim() async {
    final folder = _folder;
    if (folder == null) return 0;
    var freed = 0;
    try {
      final kept = <(File, int, DateTime)>[];
      var total = 0;
      final stale = _now().subtract(const Duration(hours: 1));
      final entries = <FileSystemEntity>[];
      for (final provider in const ['tmdb', 'anilist']) {
        final root = Directory(
          '${folder.path}${Platform.pathSeparator}$provider',
        );
        if (!await root.exists()) continue;
        entries.addAll(
          await root.list(recursive: true, followLinks: false).toList(),
        );
      }
      for (final entry in entries) {
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

  Future<File?> _get(String key, File file, Uri url) async {
    try {
      if (await file.exists() && await file.length() > 0) {
        await _markUsed(file);
        return file;
      }
      // What failed a moment ago is not asked for with every rebuild.
      final notBefore = _notBefore[key];
      if (notBefore != null && _now().isBefore(notBefore)) return null;
      final (bytes, retryAfter) = await _download(url);
      if (bytes == null) {
        _notBefore[key] = _now().add(retryAfter);
        return null;
      }
      _notBefore.remove(key);
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

  /// The picture at [url], or `null` and how long to leave it alone.
  Future<(Uint8List?, Duration)> _download(Uri url) async {
    if (_downloads >= _maxDownloads) {
      final turn = Completer<void>();
      _waiting.add(turn);
      await turn.future;
    } else {
      _downloads++;
    }
    try {
      final response = await _http.get(
        url,
        timeout: const Duration(seconds: 20),
        maxBytes: maxImageBytes,
      );
      if (response.isOk && _isPicture(response.bodyBytes)) {
        return (response.bodyBytes, Duration.zero);
      }
      // Busy or out of order is worth another try soon; "no such
      // picture", or something that is no picture, is not.
      final busy =
          response.statusCode == HttpStatus.tooManyRequests ||
          response.statusCode >= 500;
      return (null, busy ? retrySoonAfter : retryLaterAfter);
    } on SafeHttpException catch (error) {
      final passing =
          error.failure == SafeHttpFailure.timeout ||
          error.failure == SafeHttpFailure.network;
      return (null, passing ? retrySoonAfter : retryLaterAfter);
    } finally {
      // The place goes to the picture asked for last: it is the one on
      // screen now, while those that waited longest may have scrolled
      // away.
      if (_waiting.isNotEmpty) {
        _waiting.removeLast().complete();
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
const _partSuffix = '.part';

/// "/abc123.jpg": one name, no folders, a picture's extension.
final _imagePath = RegExp(r'^/[A-Za-z0-9_-]{1,64}\.(jpg|jpeg|png|webp)$');

/// The host AniList serves its pictures from.
const anilistImageHost = 's4.anilist.co';

/// The path of a cover on AniList's picture server: a size and one file
/// name with a picture's extension, nothing else. The path ends up in an
/// address and in a file name.
final anilistCoverFile = RegExp(
  r'^/file/anilistcdn/media/anime/cover/(small|medium|large)/'
  r'[A-Za-z0-9_-]{1,80}\.(jpg|jpeg|png|webp)$',
);
