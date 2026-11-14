import 'dart:convert';
import 'dart:io';

import 'package:dhara/core/images/image_store.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/local_server.dart';

/// A real picture: one transparent pixel as PNG.
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA'
  '60e6kgAAAABJRU5ErkJggg==',
);

/// What a JPEG and a WebP file start with; nothing here decodes them.
final _jpeg = [0xFF, 0xD8, 0xFF, 0xE0, 0, 16, 74, 70, 73, 70, 0, 1, 1, 1];
final _webp = [...'RIFF'.codeUnits, 26, 0, 0, 0, ...'WEBPVP8 '.codeUnits, 0, 0];

void main() {
  late LocalServer server;
  late Directory folder;
  late RemoteImageStore store;
  late DateTime clock;

  /// Serves [bytes] at [path] of the stand-in image server.
  void serve(String path, List<int> bytes, {int status = HttpStatus.ok}) {
    server.routes[path] = (request) async {
      request.response
        ..statusCode = status
        ..headers.set(HttpHeaders.contentTypeHeader, 'image/jpeg')
        ..add(bytes);
      await request.response.close();
    };
  }

  RemoteImageStore open({
    Directory? into,
    bool noFolder = false,
    int maxTotalBytes = 1000,
    int maxImageBytes = 500,
  }) {
    final made = RemoteImageStore(
      folder: noFolder ? null : into ?? folder,
      http: server.client(),
      baseUrl: server.url('/t/p'),
      maxTotalBytes: maxTotalBytes,
      maxImageBytes: maxImageBytes,
      now: () => clock,
    );
    addTearDown(made.close);
    return made;
  }

  File onDisk(String size, String name) =>
      File([folder.path, 'tmdb', size, name].join(Platform.pathSeparator));

  List<String> kept() => [
    for (final entry in folder.listSync(recursive: true))
      if (entry is File)
        entry.path
            .substring(folder.path.length + 1)
            .replaceAll(Platform.pathSeparator, '/'),
  ]..sort();

  setUp(() async {
    server = await LocalServer.start();
    folder = Directory.systemTemp.createTempSync('dhara_images_test');
    clock = DateTime.now();
    store = open();
  });

  tearDown(() async {
    await server.close();
    folder.deleteSync(recursive: true);
  });

  group('file', () {
    test('downloads a picture once and keeps it on disk', () async {
      serve('/t/p/w342/pGlassHarbor01.jpg', _jpeg);

      final first = await store.file('w342', '/pGlassHarbor01.jpg');
      final again = await store.file('w342', '/pGlassHarbor01.jpg');

      expect(first!.path, onDisk('w342', 'pGlassHarbor01.jpg').path);
      expect(first.readAsBytesSync(), _jpeg);
      expect(again!.path, first.path);
      expect(server.requests, hasLength(1));
      expect(server.requests.single.uri.path, '/t/p/w342/pGlassHarbor01.jpg');
      expect(kept(), ['tmdb/w342/pGlassHarbor01.jpg']);
    });

    test('is still there for another store over the same folder', () async {
      serve('/t/p/w154/a.png', _png);
      await store.file('w154', '/a.png');

      final later = await open().file('w154', '/a.png');

      expect(later!.readAsBytesSync(), _png);
      expect(server.requests, hasLength(1));
    });

    test('keeps each size apart, and takes JPEG, PNG and WebP', () async {
      serve('/t/p/w154/a.jpg', _jpeg);
      serve('/t/p/w500/a.jpg', [..._jpeg, 1, 2, 3]);
      serve('/t/p/w300/b.png', _png);
      serve('/t/p/w780/c.webp', _webp);

      expect(await store.file('w154', '/a.jpg'), isNotNull);
      expect(await store.file('w500', '/a.jpg'), isNotNull);
      expect(await store.file('w300', '/b.png'), isNotNull);
      expect(await store.file('w780', '/c.webp'), isNotNull);

      expect(kept(), [
        'tmdb/w154/a.jpg',
        'tmdb/w300/b.png',
        'tmdb/w500/a.jpg',
        'tmdb/w780/c.webp',
      ]);
      expect(onDisk('w500', 'a.jpg').lengthSync(), _jpeg.length + 3);
    });

    test('asks once when several ask for one picture at a time', () async {
      serve('/t/p/w342/a.jpg', _jpeg);

      final files = await Future.wait([
        for (var i = 0; i < 6; i++) store.file('w342', '/a.jpg'),
      ]);

      expect(files.every((file) => file != null), isTrue);
      expect(server.requests, hasLength(1));
    });

    test('has at most four downloads under way', () async {
      var open = 0;
      var most = 0;
      for (var i = 0; i < 10; i++) {
        server.routes['/t/p/w342/p$i.jpg'] = (request) async {
          open++;
          if (open > most) most = open;
          await Future<void>.delayed(const Duration(milliseconds: 60));
          open--;
          request.response.add(_jpeg);
          await request.response.close();
        };
      }

      final files = await Future.wait([
        for (var i = 0; i < 10; i++) store.file('w342', '/p$i.jpg'),
      ]);

      expect(files.every((file) => file != null), isTrue);
      expect(most, 4);
    });

    test(
      'asks for nothing but a known size and a plain picture name',
      () async {
        for (final (size, path) in [
          ('original', '/a.jpg'),
          ('w92', '/a.jpg'),
          ('../w342', '/a.jpg'),
          ('', '/a.jpg'),
          ('w342', 'a.jpg'),
          ('w342', '/../a.jpg'),
          ('w342', '/a/b.jpg'),
          ('w342', r'/a\b.jpg'),
          ('w342', '/a.svg'),
          ('w342', '/a.exe'),
          ('w342', '/a.jpg.exe'),
          ('w342', '/.jpg'),
          ('w342', 'http://evil.test/a.jpg'),
          ('w342', '/a.jpg?x=1'),
          ('w342', '/${'a' * 80}.jpg'),
          ('w342', ''),
        ]) {
          expect(await store.file(size, path), isNull, reason: '$size $path');
        }
        expect(server.requests, isEmpty);
        expect(kept(), isEmpty);
      },
    );

    test('keeps nothing that is not a picture', () async {
      server.serve('/t/p/w342/a.jpg', '<html>Sign in to the Wi-Fi</html>');
      serve('/t/p/w342/b.jpg', const []);
      serve('/t/p/w342/c.jpg', 'MZ this is a program'.codeUnits);

      expect(await store.file('w342', '/a.jpg'), isNull);
      expect(await store.file('w342', '/b.jpg'), isNull);
      expect(await store.file('w342', '/c.jpg'), isNull);

      expect(kept(), isEmpty);
    });

    test('keeps nothing larger than the limit', () async {
      serve('/t/p/w342/a.jpg', [..._jpeg, ...List.filled(600, 7)]);

      expect(await store.file('w342', '/a.jpg'), isNull);
      expect(kept(), isEmpty);
    });

    test(
      'a picture that is not there is not asked for again at once',
      () async {
        serve('/t/p/w342/gone.jpg', _jpeg, status: HttpStatus.notFound);

        expect(await store.file('w342', '/gone.jpg'), isNull);
        expect(await store.file('w342', '/gone.jpg'), isNull);
        expect(server.requests, hasLength(1));

        // It may have been a hiccup: later it is asked for again.
        clock = clock.add(const Duration(minutes: 11));
        serve('/t/p/w342/gone.jpg', _jpeg);
        expect(await store.file('w342', '/gone.jpg'), isNotNull);
      },
    );

    test('gives nothing when the server cannot be reached', () async {
      final offline = open();
      await server.close();

      expect(await offline.file('w342', '/a.jpg'), isNull);
      expect(kept(), isEmpty);
    });

    test('gives nothing without a folder, and asks for nothing', () async {
      serve('/t/p/w342/a.jpg', _jpeg);

      expect(await open(noFolder: true).file('w342', '/a.jpg'), isNull);
      expect(await open(noFolder: true).trim(), 0);
      expect(server.requests, isEmpty);
    });

    test('downloads again what is empty on disk', () async {
      serve('/t/p/w342/a.jpg', _jpeg);
      onDisk('w342', 'a.jpg')
        ..createSync(recursive: true)
        ..writeAsBytesSync(const []);

      final file = await store.file('w342', '/a.jpg');

      expect(file!.readAsBytesSync(), _jpeg);
    });
  });

  group('trim', () {
    /// A kept picture of [size] bytes, last looked at [age] ago.
    File keep(String name, int size, Duration age) {
      final file = onDisk('w342', name)
        ..createSync(recursive: true)
        ..writeAsBytesSync(List.filled(size, 1))
        ..setLastModifiedSync(clock.subtract(age));
      return file;
    }

    test('does nothing while the folder is below the limit', () async {
      keep('a.jpg', 400, const Duration(days: 9));
      keep('b.jpg', 400, const Duration(days: 1));

      expect(await store.trim(), 0);
      expect(kept(), hasLength(2));
    });

    test('removes what was not looked at for the longest', () async {
      keep('oldest.jpg', 300, const Duration(days: 30));
      keep('old.jpg', 300, const Duration(days: 20));
      keep('newer.jpg', 300, const Duration(days: 3));
      keep('newest.jpg', 300, const Duration(hours: 1));

      // 1200 bytes kept, 1000 allowed: down to 800 or less.
      expect(await store.trim(), 600);

      expect(kept(), ['tmdb/w342/newer.jpg', 'tmdb/w342/newest.jpg']);
    });

    test('a picture that is looked at counts as new again', () async {
      final old = keep('old.jpg', 300, const Duration(days: 30));
      keep('middle.jpg', 300, const Duration(days: 20));
      keep('newer.jpg', 300, const Duration(days: 3));
      keep('newest.jpg', 300, const Duration(days: 2));

      expect((await store.file('w342', '/old.jpg'))!.path, old.path);
      await store.trim();

      expect(kept(), ['tmdb/w342/newest.jpg', 'tmdb/w342/old.jpg']);
      expect(server.requests, isEmpty);
    });

    test('removes downloads that were cut short long ago', () async {
      keep('a.jpg', 100, const Duration(days: 1));
      keep('cut.jpg.part', 100, const Duration(hours: 5));
      keep('underway.jpg.part', 100, const Duration(minutes: 1));

      expect(await store.trim(), 100);

      expect(kept(), ['tmdb/w342/a.jpg', 'tmdb/w342/underway.jpg.part']);
    });

    test('has nothing to do in a folder that was never used', () async {
      expect(await store.trim(), 0);
    });
  });

  test('talks to image.tmdb.org unless told otherwise', () {
    expect(RemoteImageStore.host, 'image.tmdb.org');
    expect(RemoteImageStore.sizes, containsAll(['w154', 'w342', 'w1280']));
    expect(RemoteImageStore.sizes, isNot(contains('original')));
  });
}
