// Runs against a server on the loopback interface, so it works anywhere.
// "127.0.0.1" and "localhost" reach the same server but are different hosts
// to the client, which is what the redirect rules are about.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dhara/core/net/safe_http_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late HttpServer server;
  late SafeHttpClient client;
  late List<HttpRequest> seen;

  /// What the server does for each path.
  late Map<String, FutureOr<void> Function(HttpRequest)> routes;

  Uri at(String path, {String host = '127.0.0.1'}) =>
      Uri.parse('http://$host:${server.port}$path');

  void redirect(HttpRequest request, String location) {
    request.response
      ..statusCode = HttpStatus.found
      ..headers.set(HttpHeaders.locationHeader, location)
      ..close();
  }

  setUp(() async {
    seen = [];
    routes = {
      '/hello': (request) => request.response
        ..write('hello')
        ..close(),
    };
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      seen.add(request);
      final route = routes[request.uri.path];
      if (route == null) {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      } else {
        await route(request);
      }
    });
    client = SafeHttpClient(
      isAllowedHost: const {'127.0.0.1', 'localhost'}.contains,
      timeout: const Duration(seconds: 5),
    );
  });

  tearDown(() async {
    client.close();
    await server.close(force: true);
  });

  Matcher failsWith(SafeHttpFailure failure) => throwsA(
        isA<SafeHttpException>().having((e) => e.failure, 'failure', failure),
      );

  test('returns status, headers, body and the URL that answered', () async {
    routes['/page'] = (request) => request.response
      ..headers.set('server', 'TestServer/1.0')
      ..write('<html>ok</html>')
      ..close();

    final response = await client.get(at('/page'));

    expect(response.statusCode, 200);
    expect(response.isOk, isTrue);
    expect(response.body, '<html>ok</html>');
    expect(response.header('server'), 'TestServer/1.0');
    expect(response.url, at('/page'));
    expect(seen.single.headers.value('user-agent'), 'Dhara');
  });

  test('measures the time to the answer, not the time to read the body',
      () async {
    routes['/slow-body'] = (request) async {
      await Future<void>.delayed(const Duration(milliseconds: 150));
      request.response.write('start');
      await request.response.flush();
      await Future<void>.delayed(const Duration(milliseconds: 600));
      await request.response.close();
    };

    final response = await client.get(at('/slow-body'));

    expect(
        response.responseTime, greaterThan(const Duration(milliseconds: 140)));
    expect(response.responseTime, lessThan(const Duration(milliseconds: 600)));
  });

  test('an error status is a response, not an exception', () async {
    final response = await client.get(at('/missing'));

    expect(response.statusCode, 404);
    expect(response.isOk, isFalse);
  });

  test('sends the headers it is given', () async {
    await client.get(at('/hello'), headers: {'X-Emby-Token': 'abc'});

    expect(seen.single.headers.value('x-emby-token'), 'abc');
  });

  group('refuses, without contacting anyone,', () {
    test('a host that is not allowed', () async {
      final strict = SafeHttpClient(isAllowedHost: (host) => false);
      addTearDown(strict.close);

      await expectLater(
        strict.get(at('/hello')),
        failsWith(SafeHttpFailure.blockedUrl),
      );
      expect(seen, isEmpty);
    });

    test('anything that is not plain http or https', () async {
      for (final url in [
        'file:///C:/Windows/win.ini',
        'ftp://127.0.0.1/',
        'smb://127.0.0.1/share',
        'http://user:pass@127.0.0.1:${server.port}/hello',
        '/hello',
      ]) {
        await expectLater(
          client.get(Uri.parse(url)),
          failsWith(SafeHttpFailure.blockedUrl),
          reason: url,
        );
      }
      expect(seen, isEmpty);
    });
  });

  group('redirects', () {
    test('are followed on the same host, relative or absolute', () async {
      routes['/a'] = (request) => redirect(request, 'b');
      routes['/b'] = (request) => redirect(request, at('/hello').toString());

      final response = await client.get(at('/a'), headers: {'X-Token': 't'});

      expect(response.body, 'hello');
      expect(response.url, at('/hello'));
      expect(seen.last.headers.value('x-token'), 't');
    });

    test('may go to another allowed host, without the request headers',
        () async {
      routes['/a'] = (request) =>
          redirect(request, at('/hello', host: 'localhost').toString());

      final response = await client.get(at('/a'), headers: {'X-Token': 't'});

      expect(response.body, 'hello');
      expect(response.url.host, 'localhost');
      expect(seen.first.headers.value('x-token'), 't');
      expect(seen.last.headers.value('x-token'), isNull);
    });

    test(
        'take the request headers along on the first host only, and not '
        'from https down to http', () {
      bool carries(String first, String current) =>
          SafeHttpClient.carriesHeaders(Uri.parse(first), Uri.parse(current));

      expect(carries('http://10.0.0.1/a', 'http://10.0.0.1/b'), isTrue);
      expect(carries('http://10.0.0.1/a', 'https://10.0.0.1/a'), isTrue);
      expect(carries('https://t.example/a', 'https://t.example/b'), isTrue);
      expect(carries('http://10.0.0.1:8096/a', 'http://10.0.0.1/a'), isTrue);

      expect(carries('http://10.0.0.1/a', 'http://10.0.0.2/a'), isFalse);
      expect(carries('https://t.example/a', 'http://t.example/a'), isFalse);
      expect(carries('https://t.example/a', 'https://u.example/a'), isFalse);
    });

    test('to a host that is not allowed are blocked', () async {
      routes['/a'] = (request) => redirect(request, 'http://example.com/x');

      await expectLater(
        client.get(at('/a')),
        failsWith(SafeHttpFailure.blockedRedirect),
      );
      expect(seen, hasLength(1));
    });

    test('to the first host are fine even if it is not on the list', () async {
      // The caller vouches for the first host by asking for it; here the
      // list only knows "localhost".
      final narrow = SafeHttpClient(
        isAllowedHost: (host) => host == 'localhost',
      );
      addTearDown(narrow.close);
      routes['/a'] = (request) => redirect(request, '/hello');

      final response = await narrow.get(at('/a', host: 'localhost'));

      expect(response.body, 'hello');
    });

    test('to other schemes or broken addresses are blocked', () async {
      for (final location in [
        'file:///C:/Windows/win.ini',
        'ftp://127.0.0.1/',
        'javascript:alert(1)',
        'http://user:pass@127.0.0.1/',
        'http://[broken',
      ]) {
        routes['/a'] = (request) => redirect(request, location);

        await expectLater(
          client.get(at('/a')),
          failsWith(SafeHttpFailure.blockedRedirect),
          reason: location,
        );
      }
    });

    test('are capped', () async {
      routes['/loop'] = (request) => redirect(request, '/loop');

      await expectLater(
        client.get(at('/loop')),
        failsWith(SafeHttpFailure.tooManyRedirects),
      );
      expect(seen, hasLength(client.maxRedirects + 1));
    });

    test('are not followed for a POST', () async {
      routes['/login'] = (request) => redirect(request, '/hello');

      final response = await client.postJson(at('/login'), {'a': 1});

      expect(response.statusCode, 302);
      expect(seen, hasLength(1));
    });
  });

  group('the size limit', () {
    test('stops a body that says it is too large', () async {
      routes['/big'] = (request) => request.response
        ..contentLength = 2000
        ..add(List.filled(2000, 0x61))
        ..close();

      await expectLater(
        client.get(at('/big'), maxBytes: 1000),
        failsWith(SafeHttpFailure.tooLarge),
      );
    });

    test('stops a body of unknown length once it gets too large', () async {
      routes['/stream'] = (request) async {
        // Chunked (no Content-Length): 1 MB in small pieces, unless the
        // client hangs up first, as it should.
        try {
          for (var i = 0; i < 256; i++) {
            request.response.add(List.filled(4096, 0x61));
            await request.response.flush();
            await Future<void>.delayed(const Duration(milliseconds: 1));
          }
          await request.response.close();
        } on Object {
          // Client went away.
        }
      };

      await expectLater(
        client.get(at('/stream'), maxBytes: 64 * 1024),
        failsWith(SafeHttpFailure.tooLarge),
      );
    });

    test('counts decompressed bytes', () async {
      final bomb = gzip.encode(List.filled(1024 * 1024, 0x61));
      expect(bomb.length, lessThan(8 * 1024));
      routes['/gzip'] = (request) => request.response
        ..headers.set(HttpHeaders.contentEncodingHeader, 'gzip')
        ..add(bomb)
        ..close();

      await expectLater(
        client.get(at('/gzip'), maxBytes: 64 * 1024),
        failsWith(SafeHttpFailure.tooLarge),
      );
    });

    test('lets a body of exactly the limit through', () async {
      routes['/exact'] = (request) => request.response
        ..add(List.filled(1000, 0x61))
        ..close();

      final response = await client.get(at('/exact'), maxBytes: 1000);

      expect(response.bodyBytes, hasLength(1000));
    });
  });

  group('the time limit', () {
    test('ends a request the server never answers', () async {
      routes['/silent'] = (request) => Completer<void>().future;

      await expectLater(
        client.get(at('/silent'), timeout: const Duration(milliseconds: 300)),
        failsWith(SafeHttpFailure.timeout),
      );
    });

    test('covers a body that stalls half way', () async {
      routes['/stall'] = (request) async {
        request.response.write('first part');
        await request.response.flush();
        // Never finishes.
      };

      await expectLater(
        client.get(at('/stall'), timeout: const Duration(milliseconds: 300)),
        failsWith(SafeHttpFailure.timeout),
      );
    });
  });

  test('reports a server that cannot be reached', () async {
    final url = at('/hello');
    await server.close(force: true);

    await expectLater(client.get(url), failsWith(SafeHttpFailure.network));
  });

  test('error messages name the host but never the path or query', () async {
    routes['/secret'] = (request) => redirect(request, 'ftp://elsewhere/');

    try {
      await client.get(at('/secret', host: 'localhost').replace(query: 'k=v'));
      fail('The redirect was followed');
    } on SafeHttpException catch (error) {
      expect(error.message, contains('localhost'));
      expect(error.message, isNot(contains('secret')));
      expect(error.message, isNot(contains('k=v')));
      expect(error.toString(), isNot(contains('k=v')));
    }
  });

  group('text decoding', () {
    test('is UTF-8 by default and never fails on bad bytes', () async {
      routes['/utf8'] = (request) => request.response
        ..add(utf8.encode('বাংলা সিনেমা'))
        ..add([0xFF])
        ..close();

      final response = await client.get(at('/utf8'));

      expect(response.body, 'বাংলা সিনেমা\u{FFFD}');
    });

    test('is Latin-1 when the server says so', () async {
      routes['/latin1'] = (request) => request.response
        ..headers.set('content-type', 'text/html; charset=ISO-8859-1')
        ..add(latin1.encode('Amélie'))
        ..close();

      final response = await client.get(at('/latin1'));

      expect(response.body, 'Amélie');
    });
  });

  group('probe', () {
    test('reports where a URL leads without downloading it', () async {
      var sent = 0;
      routes['/a'] = (request) => redirect(request, '/big.mkv');
      routes['/big.mkv'] = (request) async {
        try {
          for (var i = 0; i < 200; i++) {
            request.response.add(List.filled(64 * 1024, 0));
            sent += 64 * 1024;
            await request.response.flush();
            await Future<void>.delayed(const Duration(milliseconds: 1));
          }
          await request.response.close();
        } on Object {
          // The client hung up.
        }
      };

      final response = await client.probe(at('/a'));

      expect(response.url, at('/big.mkv'));
      expect(response.statusCode, 200);
      expect(response.bodyBytes, isEmpty);
      expect(seen.last.headers.value('range'), 'bytes=0-0');
      // Far more than the client's size limit would have allowed anyway;
      // the point is that it did not wait for it.
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(sent, lessThan(200 * 64 * 1024));
    });

    test('follows the same redirect rules as get', () async {
      routes['/out'] = (request) => redirect(request, 'http://example.com/v');
      routes['/loop'] = (request) => redirect(request, '/loop');

      await expectLater(
        client.probe(at('/out')),
        failsWith(SafeHttpFailure.blockedRedirect),
      );
      await expectLater(
        client.probe(at('/loop')),
        failsWith(SafeHttpFailure.tooManyRedirects),
      );
    });

    test('returns an error status like any other answer', () async {
      final response = await client.probe(at('/missing'));

      expect(response.statusCode, 404);
    });
  });

  test('postJson sends a JSON body and returns the answer', () async {
    routes['/login'] = (request) async {
      final body = await utf8.decodeStream(request);
      request.response
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({'echo': jsonDecode(body)}));
      await request.response.close();
    };

    final response = await client.postJson(
      at('/login'),
      {'Username': 'guest', 'Pw': ''},
      headers: {'X-Auth': 'x'},
    );

    expect(seen.single.method, 'POST');
    // Sent with its length, not chunked: Emby ignores a chunked body.
    expect(seen.single.headers.contentLength, 28);
    expect(seen.single.headers.chunkedTransferEncoding, isFalse);
    expect(seen.single.headers.contentType?.mimeType, 'application/json');
    expect(seen.single.headers.value('x-auth'), 'x');
    expect(jsonDecode(response.body), {
      'echo': {'Username': 'guest', 'Pw': ''},
    });
  });

  group('download', () {
    late Directory folder;

    setUp(() => folder = Directory.systemTemp.createTempSync('dhara-http-'));
    tearDown(() => folder.deleteSync(recursive: true));

    File target([String name = 'file.bin']) =>
        File('${folder.path}${Platform.pathSeparator}$name');

    test('saves a large body to a file as it arrives', () async {
      final body = List.generate(300000, (i) => i % 251);
      routes['/file'] = (request) async {
        request.response
          ..contentLength = body.length
          ..headers.contentType = ContentType.binary;
        for (var from = 0; from < body.length; from += 50000) {
          request.response.add(body.sublist(from, from + 50000));
          await request.response.flush();
        }
        await request.response.close();
      };
      target().writeAsStringSync('what was there before');
      final progress = <(int, int?)>[];

      final response = await client.download(
        at('/file'),
        target(),
        maxBytes: 1000000,
        onProgress: (received, total) => progress.add((received, total)),
      );

      expect(response.statusCode, 200);
      expect(response.bodyBytes, isEmpty);
      expect(response.header('content-type'), 'application/octet-stream');
      expect(target().readAsBytesSync(), body);
      expect(progress.last, (300000, 300000));
      expect(progress.length, greaterThan(1));
      // Like every request: no cookie, nothing about the user.
      expect(seen.single.cookies, isEmpty);
      expect(seen.single.headers.value('user-agent'), 'Dhara');
    });

    test('saves nothing unless the answer is a plain 200', () async {
      routes['/gone'] = (request) => request.response
        ..statusCode = HttpStatus.notFound
        ..write('no such file')
        ..close();

      final response = await client.download(
        at('/gone'),
        target(),
        maxBytes: 1000,
      );

      expect(response.statusCode, 404);
      expect(target().existsSync(), isFalse);
    });

    test('follows the same redirect rules as get', () async {
      routes['/moved'] = (request) => redirect(request, '/hello');
      routes['/away'] =
          (request) => redirect(request, 'http://example.invalid/file');

      final response =
          await client.download(at('/moved'), target(), maxBytes: 1000);
      expect(response.url, at('/hello'));
      expect(target().readAsStringSync(), 'hello');

      await expectLater(
        client.download(at('/away'), target('other.bin'), maxBytes: 1000),
        failsWith(SafeHttpFailure.blockedRedirect),
      );
      await expectLater(
        client.download(
          Uri.parse('http://example.invalid/file'),
          target('other.bin'),
          maxBytes: 1000,
        ),
        failsWith(SafeHttpFailure.blockedUrl),
      );
      expect(target('other.bin').existsSync(), isFalse);
    });

    test('stops a body that is too large, said or not', () async {
      routes['/big'] = (request) => request.response
        ..contentLength = 2000
        ..add(List.filled(2000, 0x61))
        ..close();
      routes['/stream'] = (request) async {
        try {
          for (var i = 0; i < 64; i++) {
            request.response.add(List.filled(4096, 0x61));
            await request.response.flush();
            await Future<void>.delayed(const Duration(milliseconds: 1));
          }
          await request.response.close();
        } on Object {
          // The client hung up, as it should.
        }
      };

      await expectLater(
        client.download(at('/big'), target(), maxBytes: 1000),
        failsWith(SafeHttpFailure.tooLarge),
      );
      // Refused before a byte was written.
      expect(target().existsSync(), isFalse);

      await expectLater(
        client.download(at('/stream'), target(), maxBytes: 10000),
        failsWith(SafeHttpFailure.tooLarge),
      );
      expect(target().lengthSync(), lessThanOrEqualTo(10000));
    });

    test('gives up on a body that stops arriving', () async {
      routes['/stall'] = (request) async {
        request.response.add(List.filled(1000, 0x61));
        await request.response.flush();
        // Never finishes.
      };

      await expectLater(
        client.download(
          at('/stall'),
          target(),
          maxBytes: 100000,
          stallTimeout: const Duration(milliseconds: 300),
        ),
        failsWith(SafeHttpFailure.timeout),
      );
    });

    test('says so when the file cannot be written', () async {
      final nowhere = File(
        '${folder.path}${Platform.pathSeparator}missing'
        '${Platform.pathSeparator}file.bin',
      );

      await expectLater(
        client.download(at('/hello'), nowhere, maxBytes: 1000),
        throwsA(isA<FileSystemException>()),
      );
    });
  });
}
