import 'dart:io';

import 'package:dhara/core/net/safe_http_client.dart';

/// The address a production build fetches its library snapshot from, out
/// of what it was given when it was built (`DHARA_SNAPSHOT_URL`); `null`
/// if that is nothing, or nothing it may ask: only an https address
/// without a user name or password will do.
Uri? snapshotUrlFrom(String value) {
  final url = Uri.tryParse(value.trim());
  if (url == null ||
      url.scheme != 'https' ||
      url.host.isEmpty ||
      url.userInfo.isNotEmpty ||
      url.hasFragment) {
    return null;
  }
  return url;
}

/// Why a snapshot was not fetched.
enum SnapshotFetchProblem {
  /// The place it is kept did not answer: no connection, or it is down.
  unreachable,

  /// It answered, but not with the file: the file is gone or not shared
  /// any more, or the place asks for something first.
  notThere,

  /// The file is larger than a snapshot may be.
  tooLarge,

  /// It could not be saved on this PC.
  notSaved,
}

/// What [SnapshotFetcher.fetch] did.
class SnapshotFetched {
  const SnapshotFetched({this.problem, this.bytes = 0});

  /// Why there is no file; `null` if it was fetched.
  final SnapshotFetchProblem? problem;
  final int bytes;

  bool get ok => problem == null;
}

/// Fetches the library snapshot a production build starts from.
///
/// It asks the one address it was made with and no other: a redirect to
/// another host is refused. The request carries nothing about the user or
/// the library (no cookie, no header of its own), and what comes back is
/// only saved as a file, for `readSnapshot` to read as untrusted input.
class SnapshotFetcher {
  SnapshotFetcher(this.url, {SafeHttpClient? client})
    : _client =
          client ?? SafeHttpClient(isAllowedHost: (host) => host == url.host);

  /// The largest file that is taken. A snapshot of 577,000 videos is 77 MB.
  static const maxBytes = 512 * 1024 * 1024;

  final Uri url;
  final SafeHttpClient _client;

  /// Fetches the snapshot into [file], replacing what is there; the file
  /// only gets its name once it is whole. [onProgress] hears how many
  /// bytes have come, and how many there will be if the place says.
  /// Never throws.
  Future<SnapshotFetched> fetch(
    File file, {
    void Function(int received, int? total)? onProgress,
  }) async {
    final part = File('${file.path}.part');
    SnapshotFetchProblem? problem;
    try {
      await part.parent.create(recursive: true);
      final response = await _client.download(
        url,
        part,
        maxBytes: maxBytes,
        onProgress: onProgress,
      );
      if (response.statusCode != HttpStatus.ok ||
          // A page that asks to confirm or to sign in, not the file.
          (response.header(HttpHeaders.contentTypeHeader) ?? '')
              .toLowerCase()
              .startsWith('text/') ||
          !await _isGzip(part)) {
        problem = SnapshotFetchProblem.notThere;
      } else {
        final bytes = await part.length();
        await part.rename(file.path);
        return SnapshotFetched(bytes: bytes);
      }
    } on SafeHttpException catch (error) {
      problem = switch (error.failure) {
        SafeHttpFailure.tooLarge => SnapshotFetchProblem.tooLarge,
        SafeHttpFailure.timeout ||
        SafeHttpFailure.network => SnapshotFetchProblem.unreachable,
        SafeHttpFailure.blockedUrl ||
        SafeHttpFailure.blockedRedirect ||
        SafeHttpFailure.tooManyRedirects => SnapshotFetchProblem.notThere,
      };
    } on FileSystemException {
      problem = SnapshotFetchProblem.notSaved;
    }
    try {
      if (await part.exists()) await part.delete();
    } on FileSystemException {
      // The next fetch writes over it.
    }
    return SnapshotFetched(problem: problem);
  }

  /// Ends a fetch under way, which then reports the place as unreachable.
  void close() => _client.close();

  /// Whether the file starts the way a gzip file does.
  static Future<bool> _isGzip(File file) async {
    final start = await file.openRead(0, 2).expand((bytes) => bytes).toList();
    return start.length == 2 && start[0] == 0x1f && start[1] == 0x8b;
  }
}
