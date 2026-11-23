import 'dart:io';

import 'package:dhara/core/db/library_db.dart';
import 'package:dhara/core/db/library_isolate.dart';
import 'package:dhara/core/secrets/secret_store.dart';
import 'package:dhara/features/indexer/index_controller.dart';
import 'package:dhara/features/metadata/match_controller.dart';
import 'package:dhara/features/metadata/titles_controller.dart';
import 'package:dhara/features/metadata/tmdb_key.dart';
import 'package:dhara/features/snapshot/snapshot_controller.dart';
import 'package:dhara/features/snapshot/snapshot_reader.dart';
import 'package:dhara/features/sources/source_store.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/snapshot_library.dart';

void main() {
  late Directory folder;
  late LibraryDb db;
  late LibrarySnapshotController snapshots;

  setUp(() {
    folder = Directory.systemTemp.createTempSync('dhara-snapshot-');
    db = LibraryDb.inMemory();
    fillSnapshotLibrary(db);
    final library = LocalLibrary(db);
    final index = IndexController(
      library: library,
      sources: SourceStore(starter: snapshotSources),
      deviceId: 'dhara-test',
    );
    final titles = TitlesController(library: library, index: index);
    snapshots = LibrarySnapshotController(
      library: library,
      index: index,
      titles: titles,
      match: MatchController(
        library: library,
        titles: titles,
        tmdbKey: TmdbKeyController(MemorySecretStore()),
      ),
    );
  });

  tearDown(() {
    snapshots.dispose();
    db.close();
    folder.deleteSync(recursive: true);
  });

  String at(String name) => '${folder.path}${Platform.pathSeparator}$name';

  test('writes a snapshot and says what it wrote', () async {
    final seen = <(bool, int)>[];
    snapshots.addListener(
      () => seen.add((snapshots.isWriting, snapshots.rowsDone)),
    );
    expect(snapshots.isFree, isTrue);

    final run = snapshots.write(at('library.gz'));
    expect(snapshots.isWriting, isTrue);
    expect(snapshots.isFree, isFalse);
    // Asked for another meanwhile, or to read one, it does neither.
    await snapshots.write(at('another.gz'));
    expect(await snapshots.read(at('library.gz')), isNull);
    await run;

    expect(snapshots.isWriting, isFalse);
    expect(snapshots.failed, isFalse);
    expect(snapshots.written!.path, at('library.gz'));
    expect(snapshots.written!.videos, 4);
    expect(snapshots.written!.titles, 2);
    expect(readSnapshotLines(at('library.gz')).last, {'end': true, 'rows': 21});
    expect(File(at('another.gz')).existsSync(), isFalse);
    expect(seen.first.$1, isTrue);
    expect(seen.last.$1, isFalse);
    expect(snapshots.rowsDone, 21);
    expect(snapshots.rowsTotal, 21);
  });

  test('says so when the file cannot be written, and can try again', () async {
    await snapshots.write(at('missing${Platform.pathSeparator}library.gz'));

    expect(snapshots.failed, isTrue);
    expect(snapshots.written, isNull);
    expect(snapshots.isFree, isTrue);

    await snapshots.write(at('library.gz'));

    expect(snapshots.failed, isFalse);
    expect(snapshots.written, isNotNull);
  });

  group('reading', () {
    late LibraryDb empty;
    late IndexController index;
    late LibrarySnapshotController reader;

    setUp(() async {
      await snapshots.write(at('library.gz'));
      empty = LibraryDb.inMemory();
      final library = LocalLibrary(empty);
      index = IndexController(
        library: library,
        sources: SourceStore(starter: snapshotSources),
        deviceId: 'dhara-test',
      );
      final titles = TitlesController(library: library, index: index);
      reader = LibrarySnapshotController(
        library: library,
        index: index,
        titles: titles,
        match: MatchController(
          library: library,
          titles: titles,
          tmdbKey: TmdbKeyController(MemorySecretStore()),
        ),
      );
    });

    tearDown(() {
      reader.dispose();
      empty.close();
    });

    test('fills the empty library, and the index knows it', () async {
      expect(index.statsOf('alpha'), isNull);

      final run = reader.read(at('library.gz'));
      expect(reader.isReading, isTrue);
      expect(reader.isWriting, isFalse);
      expect(reader.isFree, isFalse);
      final read = await run;

      expect(read!.ok, isTrue);
      expect(read.videos, 4);
      expect(read.titles, 2);
      expect(reader.lastRead, same(read));
      expect(reader.isReading, isFalse);
      // Told to the index, which the names of the videos and Home follow.
      expect(index.statsOf('alpha')!.files, 1);
      expect(index.statsOf('beta')!.files, 3);
    });

    test('says why a file was not taken, and leaves a library that holds '
        'something alone', () async {
      File(at('other.gz')).writeAsStringSync('not a snapshot');

      final refused = await reader.read(at('other.gz'));

      expect(refused!.problem, SnapshotProblem.notASnapshot);
      expect(reader.lastRead!.problem, SnapshotProblem.notASnapshot);
      expect(index.statsOf('alpha'), isNull);

      // The library the snapshot was written from is not empty.
      final again = await snapshots.read(at('library.gz'));

      expect(again!.problem, SnapshotProblem.libraryNotEmpty);
      expect(snapshotProblemText(again.problem!), contains('not empty'));
    });
  });
}
