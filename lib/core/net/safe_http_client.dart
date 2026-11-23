import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dhara/core/net/media_url.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

/// Why [SafeHttpClient] gave up on a request.
enum SafeHttpFailure {
  /// The URL is not http(s), carries credentials, or its host is not allowed.
  blockedUrl,

  /// The server redirected somewhere the app may not go.
  blockedRedirect,
  tooManyRedirects,

  /// The body is larger than the size limit.
  tooLarge,
  timeout,

  /// Connection, TLS or protocol error.
  network,
}

class SafeHttpException implements Exception {
  const SafeHttpException(this.failure, this.message);

  final SafeHttpFailure failure;

  /// Plain English, safe to show and to log: it never contains a full URL,
  /// a header or anything else that could hold a secret.
  final String message;

  @override
  String toString() => 'SafeHttpException(${failure.name}): $message';
}

/// A complete response: the body has been read, within the size limit.
class SafeHttpResponse {
  SafeHttpResponse._({
    required this.url,
    required this.statusCode,
    required this.responseTime,
    required this.bodyBytes,
    required Map<String, String> headers,
    required String? charset,
  })  : _headers = headers,
        _charset = charset;

  /// The URL that answered, after any redirects.
  final Uri url;
  final int statusCode;

  /// From sending the request until the answer's headers arrived, with
  /// connecting and any redirects included. This is the app's "ping".
  final Duration responseTime;
  final Uint8List bodyBytes;
  final Map<String, String> _headers;
  final String? _charset;

  bool get isOk => statusCode >= 200 && statusCode < 300;

  /// A response header by its lower-case name, e.g. `server`.
  String? header(String name) => _headers[name];

  /// The body as text. UTF-8 unless the server declares Latin-1; bytes that
  /// are not valid text become U+FFFD instead of failing.
  ///
  /// Server-controlled: parse it, never render or run it.
  late final String body = switch (_charset) {
    'iso-8859-1' || 'latin1' || 'windows-1252' => latin1.decode(bodyBytes),
    _ => utf8.decode(bodyBytes, allowMalformed: true),
  };
}

/// The only way the app talks to source servers (BRIEF section 7, Network).
///
/// - `http` and `https` only, and only to hosts [isAllowedHost] accepts.
///   Private addresses are not blocked: many BDIX servers use 10.x or
///   172.16.x.
/// - Redirects are followed by hand, at most [maxRedirects] times, and only
///   to the host first asked or to another allowed host. Request headers
///   (which may carry a session token or the TMDB key) are never sent on
///   to a different host, nor from an https address down to plain http.
/// - Every request has a total time limit and a body size limit. The size
///   limit counts decompressed bytes.
/// - No cookies are kept and no proxy settings are read.
class SafeHttpClient {
  SafeHttpClient({
    required bool Function(String host) isAllowedHost,
    this.timeout = const Duration(seconds: 15),
    this.maxBytes = 4 * 1024 * 1024,
    this.maxRedirects = 5,
  })  : _isAllowedHost = isAllowedHost,
        _inner = HttpClient()
          ..userAgent = 'Dhara'
          ..connectionTimeout = const Duration(seconds: 8)
          ..idleTimeout = const Duration(seconds: 15);

  final bool Function(String host) _isAllowedHost;
  final HttpClient _inner;

  /// Total time allowed for one call, redirects and body included.
  final Duration timeout;
  final int maxBytes;
  final int maxRedirects;

  /// Fetches [url]. Any status code is returned as a response; a
  /// [SafeHttpException] means the request was refused or did not finish.
  Future<SafeHttpResponse> get(
    Uri url, {
    Map<String, String> headers = const {},
    Duration? timeout,
    int? maxBytes,
  }) =>
      _send('GET', url, headers, null, timeout, maxBytes);

  /// Posts [body] as JSON. Unlike [get] this never follows a redirect: the
  /// 3xx response is returned as it is.
  Future<SafeHttpResponse> postJson(
    Uri url,
    Object? body, {
    Map<String, String> headers = const {},
    Duration? timeout,
    int? maxBytes,
  }) =>
      _send('POST', url, headers, jsonEncode(body), timeout, maxBytes);

  /// Finds out where [url] leads and what answers there, without
  /// downloading it: redirects are followed under the same rules as [get],
  /// and the connection is dropped as soon as the final answer's headers
  /// are in. Made for media files, which are far too large to fetch.
  ///
  /// The returned response has an empty body.
  Future<SafeHttpResponse> probe(
    Uri url, {
    Map<String, String> headers = const {},
    Duration? timeout,
  }) =>
      _send(
        'GET',
        url,
        // Asks for one byte, for servers that would otherwise start
        // sending the whole file.
        {HttpHeaders.rangeHeader: 'bytes=0-0', ...headers},
        null,
        timeout,
        0,
        readBody: false,
      );

  /// Fetches [url] into [file], for an answer too large to hold in memory:
  /// the body goes to the file as it arrives, replacing what the file
  /// held. Redirects are followed under the same rules as [get].
  ///
  /// Only a plain "200 OK" is saved; with any other status the file is not
  /// touched, and the response says what the server answered. The returned
  /// response has an empty body.
  ///
  /// The body may be [maxBytes] long at most. The call may take [timeout]
  /// in all, and fails as soon as nothing has arrived for [stallTimeout].
  /// [onProgress] hears how many bytes are saved, and how many there will
  /// be if the server said.
  ///
  /// After a [SafeHttpException], or a [FileSystemException] if the file
  /// cannot be written, the file may hold a part of the body: the caller
  /// removes it.
  Future<SafeHttpResponse> download(
    Uri url,
    File file, {
    required int maxBytes,
    Map<String, String> headers = const {},
    Duration timeout = const Duration(hours: 1),
    Duration stallTimeout = const Duration(seconds: 30),
    void Function(int received, int? total)? onProgress,
  }) =>
      _send(
        'GET',
        url,
        headers,
        null,
        timeout,
        maxBytes,
        save: _Save(file, stallTimeout, onProgress),
      );

  /// Drops every connection, including requests still running.
  void close() => _inner.close(force: true);

  Future<SafeHttpResponse> _send(
    String method,
    Uri url,
    Map<String, String> headers,
    String? jsonBody,
    Duration? timeout,
    int? maxBytes, {
    bool readBody = true,
    _Save? save,
  }) {
    final limit = timeout ?? this.timeout;
    final call = _Call();
    return _run(
      call,
      method,
      url,
      headers,
      jsonBody,
      maxBytes ?? this.maxBytes,
      readBody: readBody,
      save: save,
    ).timeout(
      limit,
      onTimeout: () {
        call.cancel();
        throw SafeHttpException(
          SafeHttpFailure.timeout,
          '${url.host} did not answer within ${limit.inSeconds} s.',
        );
      },
    );
  }

  Future<SafeHttpResponse> _run(
    _Call call,
    String method,
    Uri url,
    Map<String, String> headers,
    String? jsonBody,
    int maxBytes, {
    required bool readBody,
    _Save? save,
  }) async {
    if (!_isWebUrl(url) || !_isAllowedHost(url.host)) {
      throw const SafeHttpException(
        SafeHttpFailure.blockedUrl,
        'The address is not an enabled http or https source.',
      );
    }

    var current = url;
    final watch = Stopwatch()..start();
    try {
      for (var redirects = 0;; redirects++) {
        final request = await _inner.openUrl(method, current);
        call.request = request;
        if (call.cancelled) {
          request.abort();
          throw const _Cancelled();
        }
        request.followRedirects = false;
        if (carriesHeaders(url, current)) {
          headers.forEach(request.headers.set);
        }
        if (jsonBody != null) {
          final bytes = utf8.encode(jsonBody);
          request.headers.contentType = ContentType.json;
          // With the length given the body goes out in one piece. Without
          // it dart:io sends it "chunked", which some servers (Emby, for
          // one) do not read.
          request.contentLength = bytes.length;
          request.add(bytes);
        }

        final response = await request.close();
        final location = response.headers.value(HttpHeaders.locationHeader);
        if (method != 'GET' || !response.isRedirect || location == null) {
          final responseTime = watch.elapsed;
          return SafeHttpResponse._(
            url: current,
            statusCode: response.statusCode,
            responseTime: responseTime,
            headers: _headerMap(response.headers),
            charset: _charsetOf(response.headers),
            bodyBytes: save != null
                ? response.statusCode == HttpStatus.ok
                    ? await _saveBody(call, response, maxBytes, save)
                    : _dropBody(response)
                : readBody
                    ? await _readBody(call, response, maxBytes)
                    : _dropBody(response),
          );
        }

        // Not interested in a redirect's body.
        _dropBody(response);
        if (redirects >= maxRedirects) {
          throw SafeHttpException(
            SafeHttpFailure.tooManyRedirects,
            '${url.host} redirected more than $maxRedirects times.',
          );
        }
        current = _redirectTarget(url, current, location);
      }
    } on SocketException {
      throw _networkError(url, 'could not be reached');
    } on TlsException {
      throw _networkError(url, 'failed the TLS (https) check');
    } on HttpException {
      throw _networkError(url, 'sent a broken answer');
    }
  }

  /// Whether the request headers go along to [current], where a request
  /// for [first] was sent on to by redirects.
  ///
  /// They may hold a session token or a key: meant for the first host
  /// only, and, if the request was encrypted, not for anyone listening on
  /// the way either. A server that sends an https request on to plain
  /// http gets the request, but not the headers.
  @visibleForTesting
  static bool carriesHeaders(Uri first, Uri current) =>
      current.host == first.host &&
      (first.scheme != 'https' || current.scheme == 'https');

  /// Where a redirect from [current] may go, or a [SafeHttpException].
  Uri _redirectTarget(Uri first, Uri current, String location) {
    final Uri target;
    try {
      target = current.resolve(location);
    } on FormatException {
      throw _blockedRedirect(first);
    }
    final allowed = _isWebUrl(target) &&
        (target.host == first.host || _isAllowedHost(target.host));
    if (!allowed) throw _blockedRedirect(first);
    return target;
  }

  /// Hangs up without reading what the server is sending.
  static Uint8List _dropBody(HttpClientResponse response) {
    unawaited(response.listen((_) {}).cancel());
    return Uint8List(0);
  }

  Future<Uint8List> _readBody(
    _Call call,
    HttpClientResponse response,
    int maxBytes,
  ) {
    final done = Completer<Uint8List>();
    final bytes = BytesBuilder(copy: false);

    void tooLarge() {
      unawaited(call.body?.cancel());
      done.completeError(
        SafeHttpException(
          SafeHttpFailure.tooLarge,
          'The answer is larger than ${maxBytes ~/ 1024} KB.',
        ),
      );
    }

    call.body = response.listen(
      (chunk) {
        if (done.isCompleted) return;
        if (bytes.length + chunk.length > maxBytes) return tooLarge();
        bytes.add(chunk);
      },
      onError: (Object error, StackTrace stack) {
        if (!done.isCompleted) done.completeError(error, stack);
      },
      onDone: () {
        if (!done.isCompleted) done.complete(bytes.takeBytes());
      },
      cancelOnError: true,
    );
    // No need to read at all when the server admits it is too much.
    if (response.contentLength > maxBytes) tooLarge();
    return done.future;
  }

  /// Writes the body to a file as it arrives, and returns no bytes.
  Future<Uint8List> _saveBody(
    _Call call,
    HttpClientResponse response,
    int maxBytes,
    _Save save,
  ) async {
    SafeHttpException tooLarge() => SafeHttpException(
          SafeHttpFailure.tooLarge,
          'The answer is larger than ${maxBytes ~/ (1024 * 1024)} MB.',
        );

    final total = response.contentLength < 0 ? null : response.contentLength;
    if (total != null && total > maxBytes) {
      _dropBody(response);
      throw tooLarge();
    }
    final RandomAccessFile out;
    try {
      out = await save.file.open(mode: FileMode.write);
    } on FileSystemException {
      _dropBody(response);
      rethrow;
    }
    var received = 0;
    try {
      // Each piece is written before the next is taken, so a disk slower
      // than the connection cannot fill the memory.
      await for (final chunk in response.timeout(save.stallTimeout)) {
        // The whole call ran out of time while this was waiting.
        if (call.cancelled) throw const _Cancelled();
        received += chunk.length;
        if (received > maxBytes) throw tooLarge();
        await out.writeFrom(chunk);
        save.onProgress?.call(received, total);
      }
    } on TimeoutException {
      throw SafeHttpException(
        SafeHttpFailure.timeout,
        'Nothing more arrived within ${save.stallTimeout.inSeconds} s.',
      );
    } finally {
      await out.close();
    }
    return Uint8List(0);
  }

  static bool _isWebUrl(Uri url) =>
      allowedUrlSchemes.contains(url.scheme) &&
      url.host.isNotEmpty &&
      url.userInfo.isEmpty;

  static SafeHttpException _blockedRedirect(Uri first) => SafeHttpException(
        SafeHttpFailure.blockedRedirect,
        '${first.host} redirected to an address that is not allowed.',
      );

  static SafeHttpException _networkError(Uri first, String what) =>
      SafeHttpException(SafeHttpFailure.network, '${first.host} $what.');

  static Map<String, String> _headerMap(HttpHeaders headers) {
    final map = <String, String>{};
    headers.forEach((name, values) => map[name] = values.join(', '));
    return map;
  }

  static String? _charsetOf(HttpHeaders headers) {
    try {
      return headers.contentType?.charset?.toLowerCase();
    } on Exception {
      // A Content-Type that cannot be parsed: treat as undeclared.
      return null;
    }
  }
}

/// Where the body of a download goes.
class _Save {
  const _Save(this.file, this.stallTimeout, this.onProgress);

  final File file;
  final Duration stallTimeout;
  final void Function(int received, int? total)? onProgress;
}

/// The parts of a running call that a timeout has to stop.
class _Call {
  HttpClientRequest? request;
  StreamSubscription<List<int>>? body;
  bool cancelled = false;

  void cancel() {
    cancelled = true;
    request?.abort();
    unawaited(body?.cancel());
  }
}

/// Ends a call that timed out while connecting. Nobody sees it: the caller
/// already got the timeout error.
class _Cancelled implements Exception {
  const _Cancelled();
}
