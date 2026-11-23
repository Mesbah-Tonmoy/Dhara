import 'dart:io';

import 'package:dhara/features/snapshot/snapshot_fetcher.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/local_server.dart';

void main() {
  group('the address a build was given', () {
    test('is taken if it is a plain https address', () {
      expect(
        snapshotUrlFrom('https://files.example/library.gz').toString(),
        'https://files.example/library.gz',
      );
      expect(
        snapshotUrlFrom(' https://files.example/get?id=abc_1-2&confirm=t '),
        Uri.parse('https://files.example/get?id=abc_1-2&confirm=t'),
      );
    });

    test('is not taken if it is anything else', () {
      for (final value in const [
        '',
        'library.gz',
        'http://files.example/library.gz',
        'ftp://files.example/library.gz',
        'file:///C:/library.gz',
        'https:///library.gz',
        'https://user:pass@files.example/library.gz',
        'https://files.example/library.gz#part',
        'https://files.example:port/library.gz',
      ]) {
        expect(snapshotUrlFrom(value), isNull, reason: value);
      }
    });
  });

  group('fetching', () {
    late LocalServer server;
    late Directory folder;
    late File file;
    final snapshot = gzip.encode(List.filled(5000, 0x61));

    setUp(() async {
      server = await LocalServer.start();
      folder = Directory.systemTemp.createTempSync('dhara-fetch-');
      file = File('${folder.path}${Platform.pathSeparator}library.gz');
    });

    tearDown(() async {
      await server.close();
      folder.deleteSync(recursive: true);
    });

    void serveBytes(
      String path,
      List<int> bytes, {
      String type = 'application/octet-stream',
    }) {
      server.routes[path] = (request) async {
        request.response
          ..headers.set(HttpHeaders.contentTypeHeader, type)
          ..contentLength = bytes.length
          ..add(bytes);
        await request.response.close();
      };
    }

    SnapshotFetcher fetcher(String path) =>
        SnapshotFetcher(server.url(path), client: server.client());

    test('saves the file, which has its name only once it is whole', () async {
      serveBytes('/library.gz', snapshot);
      final progress = <(int, int?)>[];

      final fetched = await fetcher('/library.gz').fetch(
        file,
        onProgress: (received, total) {
          progress.add((received, total));
          expect(file.existsSync(), isFalse);
        },
      );

      expect(fetched.ok, isTrue);
      expect(fetched.bytes, snapshot.length);
      expect(file.readAsBytesSync(), snapshot);
      expect(progress.last, (snapshot.length, snapshot.length));
      expect(folder.listSync(), hasLength(1));
      // Nothing about the user or the library goes with the request.
      final request = server.requests.single;
      expect(request.cookies, isEmpty);
      expect(request.headers.value('user-agent'), 'Dhara');
      expect(request.headers.value('authorization'), isNull);
      expect(request.uri.query, isEmpty);
    });

    test('replaces a file that lies there already', () async {
      file.writeAsStringSync('an older one');
      serveBytes('/library.gz', snapshot);

      final fetched = await fetcher('/library.gz').fetch(file);

      expect(fetched.ok, isTrue);
      expect(file.readAsBytesSync(), snapshot);
    });

    test('a file that is gone is not there', () async {
      final fetched = await fetcher('/missing.gz').fetch(file);

      expect(fetched.problem, SnapshotFetchProblem.notThere);
      expect(folder.listSync(), isEmpty);
    });

    test('a page in place of the file is not the file', () async {
      // What a file host answers when it wants a click first.
      server.serve('/library.gz', '<html>Confirm the download</html>');
      serveBytes('/plain.gz', 'not gzip at all'.codeUnits);

      expect(
        (await fetcher('/library.gz').fetch(file)).problem,
        SnapshotFetchProblem.notThere,
      );
      expect(
        (await fetcher('/plain.gz').fetch(file)).problem,
        SnapshotFetchProblem.notThere,
      );
      expect(folder.listSync(), isEmpty);
    });

    test('a redirect to another host is not followed', () async {
      server.redirect('/library.gz', 'http://example.invalid/library.gz');

      final fetched = await fetcher('/library.gz').fetch(file);

      expect(fetched.problem, SnapshotFetchProblem.notThere);
      expect(folder.listSync(), isEmpty);
    });

    test('a place that does not answer is unreachable', () async {
      final gone = await LocalServer.start();
      final url = gone.url('/library.gz');
      await gone.close();

      final fetched = await SnapshotFetcher(
        url,
        client: server.client(),
      ).fetch(file);

      expect(fetched.problem, SnapshotFetchProblem.unreachable);
      expect(folder.listSync(), isEmpty);
    });

    test('a file larger than a snapshot may be is not taken', () async {
      server.routes['/library.gz'] = (request) async {
        // Says how large it is, and sends only the beginning.
        request.response
          ..contentLength = SnapshotFetcher.maxBytes + 1
          ..add(const [0x1f, 0x8b, 8, 0]);
        await request.response.flush();
      };

      final fetched = await fetcher('/library.gz').fetch(file);

      expect(fetched.problem, SnapshotFetchProblem.tooLarge);
      expect(folder.listSync(), isEmpty);
    });

    test('a file that cannot be saved says so', () async {
      serveBytes('/library.gz', snapshot);
      // A folder where the file is to go.
      Directory('${file.path}.part').createSync();

      final fetched = await fetcher('/library.gz').fetch(file);

      expect(fetched.problem, SnapshotFetchProblem.notSaved);
    });
  });
}
