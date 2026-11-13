import 'dart:io';

import 'package:dhara/core/db/library_db.dart';
import 'package:dhara/core/db/library_isolate.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

// Work has to be top-level to cross to the other isolate.

int _savePosition(LibraryDb db, (String, int) row) {
  db.db.execute(
    'INSERT INTO playback (url, position_ms, duration_ms, updated_at) '
    'VALUES (?, ?, 5000, 0)',
    [row.$1, row.$2],
  );
  return db.db.select('SELECT count(*) AS n FROM playback').single['n'] as int;
}

List<int> _positions(LibraryDb db, void _) => [
  for (final row in db.db.select(
    'SELECT position_ms FROM playback ORDER BY position_ms',
  ))
    row['position_ms'] as int,
];

Future<String> _slowEcho(LibraryDb db, String text) async {
  await Future<void>.delayed(const Duration(milliseconds: 50));
  return text;
}

void _throwException(LibraryDb db, void _) =>
    throw const FormatException('bad input');

void _throwError(LibraryDb db, void _) => throw StateError('a bug');

Object _unsendable(LibraryDb db, void _) => db.db;

void main() {
  group('LibraryIsolate', () {
    late LibraryIsolate library;

    setUp(() async => library = await LibraryIsolate.spawn());
    tearDown(() => library.close());

    test('does work on the database and returns the result', () async {
      expect(await library.run(_savePosition, ('http://a.test/a', 10)), 1);
      expect(await library.run(_savePosition, ('http://a.test/b', 20)), 2);
      expect(await library.run(_positions, null), [10, 20]);
      expect(library.replacedDamagedFile, isFalse);
    });

    test('does work that takes its time, several at once', () async {
      final results = await Future.wait([
        library.run(_slowEcho, 'one'),
        library.run(_slowEcho, 'two'),
        library.run(_positions, null),
      ]);

      expect(results, ['one', 'two', <int>[]]);
    });

    test('work that throws fails that call only', () async {
      await expectLater(
        library.run(_throwException, null),
        throwsA(
          isA<LibraryWorkException>().having(
            (e) => e.message,
            'message',
            contains('bad input'),
          ),
        ),
      );
      await expectLater(
        library.run(_throwError, null),
        throwsA(isA<LibraryWorkException>()),
      );
      await expectLater(
        library.run(_unsendable, null),
        throwsA(isA<LibraryWorkException>()),
      );

      expect(await library.run(_positions, null), isEmpty);
    });

    test('close waits for the work under way, then refuses more', () async {
      final slow = library.run(_slowEcho, 'done');

      await library.close();

      expect(await slow, 'done');
      await expectLater(
        library.run(_positions, null),
        throwsA(isA<LibraryWorkException>()),
      );
      // Closing twice is fine.
      await library.close();
    });
  });

  group('LibraryIsolate on a file', () {
    late Directory folder;
    late String path;

    setUp(() {
      folder = Directory.systemTemp.createTempSync('dhara_isolate_test');
      path = '${folder.path}${Platform.pathSeparator}library.db';
    });

    tearDown(() => folder.deleteSync(recursive: true));

    test('keeps the database between runs', () async {
      final first = await LibraryIsolate.spawn(path: path);
      await first.run(_savePosition, ('http://a.test/a', 10));
      await first.close();

      final second = await LibraryIsolate.spawn(path: path);
      addTearDown(second.close);

      expect(await second.run(_positions, null), [10]);
      expect(second.replacedDamagedFile, isFalse);
    });

    test('sets a damaged file aside and starts a new database', () async {
      File(path).writeAsStringSync('not a database ' * 500);

      final library = await LibraryIsolate.spawn(path: path);
      addTearDown(library.close);

      expect(library.replacedDamagedFile, isTrue);
      expect(await library.run(_positions, null), isEmpty);
      expect(File('$path.bad').readAsStringSync(), startsWith('not a data'));
    });

    test('refuses a file made by a newer app and leaves it alone', () async {
      final newer = sqlite3.open(path)
        ..userVersion = LibraryDb.schemaVersion + 1;
      newer.close();
      final before = File(path).readAsBytesSync();

      await expectLater(
        LibraryIsolate.spawn(path: path),
        throwsA(
          isA<LibraryDbException>().having(
            (e) => e.problem,
            'problem',
            LibraryDbProblem.newerVersion,
          ),
        ),
      );

      expect(File(path).readAsBytesSync(), before);
      expect(File('$path.bad').existsSync(), isFalse);
    });

    test(
      'says so when the file cannot be opened, and leaves it alone',
      () async {
        // A folder where the file should be: nothing SQLite can open.
        Directory(path).createSync();

        await expectLater(
          LibraryIsolate.spawn(path: path),
          throwsA(
            isA<LibraryDbException>().having(
              (e) => e.problem,
              'problem',
              LibraryDbProblem.unavailable,
            ),
          ),
        );

        // Not taken for a damaged database: nothing was moved out of the way.
        expect(Directory(path).existsSync(), isTrue);
        expect(
          FileSystemEntity.typeSync('$path.bad'),
          FileSystemEntityType.notFound,
        );
      },
    );
  });

  group('NoLibrary', () {
    test('fails every piece of work, and nothing else', () async {
      const library = NoLibrary();

      await expectLater(
        library.run(_positions, null),
        throwsA(isA<LibraryWorkException>()),
      );
      await library.close();
    });
  });

  group('LocalLibrary', () {
    test('does the same work without a second isolate', () async {
      final library = LocalLibrary(LibraryDb.inMemory());
      addTearDown(library.close);

      expect(await library.run(_savePosition, ('http://a.test/a', 10)), 1);
      expect(await library.run(_slowEcho, 'hi'), 'hi');
      await expectLater(
        library.run(_throwException, null),
        throwsA(isA<LibraryWorkException>()),
      );
    });
  });
}
