@TestOn('windows')
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dhara/features/update/installer_fetcher.dart';
import 'package:dhara/features/update/update_notice.dart';
import 'package:dhara/features/update/update_signature.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/local_server.dart';

void main() {
  late LocalServer server;
  late Directory scratch;
  late Directory folder;
  // Not a program: the fetcher never looks at what the bytes are.
  final installer = Uint8List.fromList(
    List.generate(300000, (at) => (at * 31 + (at >> 7)) % 256),
  );

  setUp(() async {
    server = await LocalServer.start();
    scratch = Directory.systemTemp.createTempSync('dhara update ');
    folder = Directory('${scratch.path}${Platform.pathSeparator}update');
  });

  tearDown(() async {
    await server.close();
    scratch.deleteSync(recursive: true);
  });

  InstallerFetcher fetcher() => InstallerFetcher(
    folder: folder,
    host: '127.0.0.1',
    newClient: server.client,
  );

  /// What a signed notice would say of [bytes] lying at [path].
  UpdateNotice notice(
    List<int> bytes, {
    String path = '/installer',
    String version = '1.2.0',
    int? size,
    String? sha256,
  }) => UpdateNotice(
    version: AppVersion.parse(version)!,
    installer: server.url(path),
    size: size ?? bytes.length,
    sha256: sha256 ?? hexOf(sha256Of(bytes)),
  );

  void serve(
    String path,
    List<int> bytes, {
    String type = 'application/octet-stream',
    int status = HttpStatus.ok,
    bool sayLength = true,
  }) {
    server.routes[path] = (request) async {
      request.response
        ..statusCode = status
        ..headers.set(HttpHeaders.contentTypeHeader, type);
      if (sayLength) request.response.contentLength = bytes.length;
      request.response.add(bytes);
      await request.response.close();
    };
  }

  List<String> left() => folder.existsSync()
      ? [
          for (final entry in folder.listSync())
            entry.path.split(Platform.pathSeparator).last,
        ]
      : [];

  test('the file the notice names is fetched, checked and kept', () async {
    serve('/installer', installer);
    final progress = <int>[];
    var checking = 0;

    final fetched = await fetcher().fetch(
      notice(installer),
      onProgress: progress.add,
      onChecking: () => checking++,
    );

    expect(fetched.problem, isNull);
    final checked = fetched.installer!;
    expect(checked.version, const AppVersion(1, 2, 0));
    expect(checked.file.parent.path, folder.path);
    expect(left(), ['Dhara-Setup-1.2.0.exe']);
    expect(checked.file.readAsBytesSync(), installer);
    expect(progress.last, installer.length);
    expect(progress, orderedEquals([...progress]..sort()));
    expect(checking, 1);
  });

  test('says nothing about the user or this copy', () async {
    serve('/installer', installer);
    await fetcher().fetch(notice(installer));
    final request = server.requests.single;
    final sent = <String>{};
    request.headers.forEach((name, values) => sent.add(name));
    expect(sent, {'user-agent', 'accept-encoding', 'host'});
    expect(request.headers.value('user-agent'), 'Dhara');
    expect(request.uri.toString(), '/installer');
  });

  group('what is not the file the notice names is refused and removed:', () {
    Future<void> refused(
      List<int> served,
      UpdateNotice told,
      String why, {
      bool sayLength = true,
    }) async {
      serve('/installer', served, sayLength: sayLength);
      final fetched = await fetcher().fetch(told);
      expect(fetched.installer, isNull, reason: why);
      expect(fetched.problem, InstallerProblem.notTheInstaller, reason: why);
      expect(left(), isEmpty, reason: 'nothing is left of it: $why');
    }

    test('one bit is another', () async {
      for (final at in [0, 150000, installer.length - 1]) {
        final changed = Uint8List.fromList(installer)..[at] ^= 0x01;
        await refused(changed, notice(installer), 'bit at $at');
      }
    });

    test('it is shorter', () async {
      await refused(
        installer.sublist(0, installer.length - 1),
        notice(installer),
        'a byte less',
      );
      await refused(const [], notice(installer), 'nothing');
    });

    test('it is longer, whether the place says so or not', () async {
      final longer = [...installer, 0];
      await refused(longer, notice(installer), 'a byte more');
      await refused(
        longer,
        notice(installer),
        'a byte more, unannounced',
        sayLength: false,
      );
      // Even if the digest of the longer file is the one named.
      await refused(
        longer,
        notice(longer, size: installer.length),
        'the right digest, the wrong length',
      );
    });

    test('another file of the same length', () async {
      await refused(
        Uint8List(installer.length),
        notice(installer),
        'all zeros',
      );
    });

    test('the right file, held against another digest', () async {
      await refused(
        installer,
        notice(installer, sha256: 'a' * 64),
        'another digest',
      );
    });
  });

  group('no file comes:', () {
    Future<void> gives(InstallerProblem problem, UpdateNotice told) async {
      final fetched = await fetcher().fetch(told);
      expect(fetched.installer, isNull);
      expect(fetched.problem, problem);
      expect(left(), isEmpty);
    }

    test('it is not there', () async {
      await gives(InstallerProblem.notThere, notice(installer, path: '/gone'));
      serve('/partly', installer, status: HttpStatus.partialContent);
      await gives(
        InstallerProblem.notThere,
        notice(installer, path: '/partly'),
      );
    });

    test('a page comes in its place, even one of the right length', () async {
      serve('/installer', installer, type: 'text/html; charset=utf-8');
      await gives(InstallerProblem.notThere, notice(installer));
    });

    test('the place sends the app on to another host', () async {
      final other = await LocalServer.start();
      addTearDown(other.close);
      other.routes['/installer'] = (request) async {
        request.response.add(installer);
        await request.response.close();
      };
      server.redirect(
        '/installer',
        'http://localhost:${other.url('/').port}/installer',
      );
      await gives(InstallerProblem.notThere, notice(installer));
      expect(other.requests, isEmpty);
    });

    test('the notice names another host than the one that was asked', () async {
      serve('/installer', installer);
      final elsewhere = UpdateNotice(
        version: const AppVersion(1, 2, 0),
        installer: Uri.parse('http://localhost:1/installer'),
        size: installer.length,
        sha256: hexOf(sha256Of(installer)),
      );
      await gives(InstallerProblem.notThere, elsewhere);
      expect(server.requests, isEmpty);
    });

    test('the place does not answer', () async {
      final told = notice(installer);
      final asking = fetcher();
      await server.close();
      final fetched = await asking.fetch(told);
      expect(fetched.problem, InstallerProblem.unreachable);
      expect(left(), isEmpty);
    });

    test('it cannot be saved', () async {
      serve('/installer', installer);
      // A file where the folder should be.
      File(folder.path).writeAsStringSync('in the way');
      final fetched = await fetcher().fetch(notice(installer));
      expect(fetched.problem, InstallerProblem.notSaved);
    });
  });

  test('a fetch that is ended leaves nothing', () async {
    final started = Completer<void>();
    final hold = Completer<void>();
    server.routes['/installer'] = (request) async {
      request.response
        ..contentLength = installer.length
        ..add(installer.sublist(0, 100000));
      await request.response.flush();
      started.complete();
      await hold.future;
      try {
        await request.response.close();
      } on Object {
        // The app hung up.
      }
    };
    final asking = fetcher();
    final fetching = asking.fetch(notice(installer));
    await started.future;
    asking.cancel();
    final fetched = await fetching;
    hold.complete();

    expect(fetched.installer, isNull);
    expect(fetched.problem, InstallerProblem.unreachable);
    expect(left(), isEmpty);

    // And the next one works.
    serve('/installer', installer);
    expect((await asking.fetch(notice(installer))).installer, isNotNull);
  });

  test('what earlier fetches left goes, and nothing else does', () async {
    folder.createSync(recursive: true);
    String inFolder(String name) =>
        '${folder.path}${Platform.pathSeparator}$name';
    for (final name in const [
      'Dhara-Setup-1.1.5.exe',
      'Dhara-Setup-1.2.0.exe.part',
      'notes.txt',
      'Dhara-Setup-1.2.0.exe.bak',
      'Other-Setup-1.2.0.exe',
    ]) {
      File(inFolder(name)).writeAsStringSync('old');
    }
    Directory(inFolder('Dhara-Setup-9.9.9.exe')).createSync();

    await fetcher().clear();
    expect(left()..sort(), [
      'Dhara-Setup-1.2.0.exe.bak',
      'Dhara-Setup-9.9.9.exe',
      'Other-Setup-1.2.0.exe',
      'notes.txt',
    ]);

    // A fetch does the same before it begins, and writes over nothing.
    File(inFolder('Dhara-Setup-1.2.0.exe')).writeAsStringSync('unchecked');
    serve('/installer', installer);
    final fetched = await fetcher().fetch(notice(installer));
    expect(fetched.installer!.file.readAsBytesSync(), installer);

    // Clearing a folder that is not there does nothing.
    folder.deleteSync(recursive: true);
    await fetcher().clear();
    expect(folder.existsSync(), isFalse);
  });
}
