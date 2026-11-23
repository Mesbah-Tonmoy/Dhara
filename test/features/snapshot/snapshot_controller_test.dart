import 'dart:io';

import 'package:dhara/core/db/library_db.dart';
import 'package:dhara/core/db/library_isolate.dart';
import 'package:dhara/core/secrets/secret_store.dart';
import 'package:dhara/features/indexer/index_controller.dart';
import 'package:dhara/features/metadata/match_controller.dart';
import 'package:dhara/features/metadata/titles_controller.dart';
import 'package:dhara/features/metadata/tmdb_key.dart';
import 'package:dhara/features/snapshot/snapshot_controller.dart';
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
    expect(snapshots.canWrite, isTrue);

    final run = snapshots.write(at('library.gz'));
    expect(snapshots.isWriting, isTrue);
    expect(snapshots.canWrite, isFalse);
    // Asked again meanwhile, it is the same run.
    expect(snapshots.write(at('another.gz')), same(run));
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
    expect(snapshots.canWrite, isTrue);

    await snapshots.write(at('library.gz'));

    expect(snapshots.failed, isFalse);
    expect(snapshots.written, isNotNull);
  });
}
