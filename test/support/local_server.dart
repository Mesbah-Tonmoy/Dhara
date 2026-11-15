import 'dart:async';
import 'dart:io';

import 'package:dhara/core/net/safe_http_client.dart';

/// A saved server answer from `test/fixtures`.
String fixture(String path) => File('test/fixtures/$path').readAsStringSync();

/// A web server on the loopback interface that answers from [routes], so
/// adapter tests exercise real HTTP without any BDIX connection.
class LocalServer {
  LocalServer._(this._server) {
    _server.listen((request) async {
      requests.add(request);
      // Keyed by the path exactly as sent (still percent-encoded).
      final route = routes[request.uri.path];
      if (route == null) {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      } else {
        await route(request);
      }
    });
  }

  static Future<LocalServer> start() async =>
      LocalServer._(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));

  final HttpServer _server;
  final routes = <String, FutureOr<void> Function(HttpRequest)>{};

  /// Every request received, oldest first.
  final requests = <HttpRequest>[];

  Uri url(String path) => Uri.parse('http://127.0.0.1:${_server.port}$path');

  /// A client that may only talk to this server.
  SafeHttpClient client() => SafeHttpClient(
        isAllowedHost: (host) => host == '127.0.0.1',
        timeout: const Duration(seconds: 5),
      );

  void serve(
    String path,
    String body, {
    int status = HttpStatus.ok,
    String contentType = 'text/html; charset=utf-8',
  }) {
    routes[path] = (request) async {
      request.response
        ..statusCode = status
        ..headers.set(HttpHeaders.contentTypeHeader, contentType)
        ..write(body);
      await request.response.close();
    };
  }

  void redirect(String path, String location) {
    routes[path] = (request) async {
      request.response
        ..statusCode = HttpStatus.movedPermanently
        ..headers.set(HttpHeaders.locationHeader, location);
      await request.response.close();
    };
  }

  /// Serves [file] the way a media server does: the whole of it, or the
  /// part a `Range: bytes=from-to` header asks for.
  void serveFile(String path, File file) {
    routes[path] = (request) async {
      final length = file.lengthSync();
      final range = RegExp(r'^bytes=(\d+)-(\d*)$')
          .firstMatch(request.headers.value(HttpHeaders.rangeHeader) ?? '');
      final response = request.response
        ..headers.set(HttpHeaders.acceptRangesHeader, 'bytes')
        ..headers.set(HttpHeaders.contentTypeHeader, 'video/x-matroska');
      var from = 0;
      var to = length - 1;
      if (range != null) {
        from = int.parse(range[1]!);
        if (range[2]!.isNotEmpty) to = int.parse(range[2]!);
        if (to >= length) to = length - 1;
        if (from > to) {
          response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
          await response.close();
          return;
        }
        response
          ..statusCode = HttpStatus.partialContent
          ..headers.set(
            HttpHeaders.contentRangeHeader,
            'bytes $from-$to/$length',
          );
      }
      response.contentLength = to - from + 1;
      try {
        await response.addStream(file.openRead(from, to + 1));
        await response.close();
      } on Object {
        // The player dropped the connection (a seek, or it was closed).
      }
    };
  }

  Future<void> close() => _server.close(force: true);
}
