import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:dhara/core/app_info.dart';
import 'package:dhara/core/db/library_db.dart';
import 'package:dhara/features/snapshot/snapshot_format.dart';
import 'package:dhara/features/snapshot/snapshot_writer.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/snapshot_library.dart';

void main() {
  late Directory folder;
  late LibraryDb library;

  setUp(() {
    folder = Directory.systemTemp.createTempSync('dhara-snapshot-');
    library = LibraryDb.inMemory();
  });

  tearDown(() {
    library.close();
    folder.deleteSync(recursive: true);
  });

  String at(String name) => '${folder.path}${Platform.pathSeparator}$name';

  /// The rows of each table in [lines], as maps by column.
  Map<String, List<Map<String, Object?>>> tablesOf(List<Object?> lines) {
    final tables = <String, List<Map<String, Object?>>>{};
    late List<String> columns;
    late List<Map<String, Object?>> rows;
    for (final line in lines.sublist(1, lines.length - 1)) {
      if (line is Map) {
        columns = (line['columns'] as List).cast();
        rows = tables[line['table'] as String] = [];
      } else {
        rows.add(Map.fromIterables(columns, line! as List));
      }
    }
    return tables;
  }

  group('the table list', () {
    test('names columns the library has, the keys first', () {
      for (final table in snapshotTables) {
        final rows = library.db.select(table.page, [...table.firstKey, 1]);
        expect(rows.columnNames, table.columns, reason: table.name);
        expect(table.firstKey, hasLength(table.keys), reason: table.name);
        expect(library.db.select(table.count).single.values.single, 0);
      }
    });

    test('leaves out what only this PC should know', () {
      expect(
        {for (final table in snapshotTables) table.name},
        isNot(
          anyOf(
            contains('playback'),
            contains('watch_history'),
            contains('my_list'),
            contains('metadata_cache'),
          ),
        ),
      );
      final sources = snapshotTables.firstWhere((t) => t.name == 'sources');
      expect(sources.columns, isNot(contains('last_error')));
    });
  });

  test('writes every table as gzip JSON lines, from head to end', () async {
    fillSnapshotLibrary(library);
    final path = at(snapshotFileName);

    final written = await writeSnapshot(library, (path, null));

    final lines = readSnapshotLines(path);
    final head = lines.first! as Map;
    expect(head['format'], snapshotFormat);
    expect(head['version'], snapshotVersion);
    expect(head['schema'], LibraryDb.schemaVersion);
    expect(head['app'], dharaVersion);
    expect(head['madeAt'], isA<int>());
    expect(head['rows'], {
      'sources': 2,
      'folders': 3,
      'files': 4,
      'subtitles': 1,
      'titles': 2,
      'title_keys': 2,
      'seasons': 1,
      'episodes': 2,
      'file_meta': 4,
    });
    expect(lines.last, {'end': true, 'rows': 21});

    final tables = tablesOf(lines);
    expect(tables.keys, [for (final table in snapshotTables) table.name]);
    expect(
      [for (final row in tables['sources']!) row['source_id']],
      ['alpha', 'beta'],
    );
    expect(tables['folders']![1], {
      'id': 2,
      'source': 1,
      'parent': 1,
      'url': 'http://10.0.0.1/alpha/Films/',
      'path': 'Films',
      'modified': DateTime.utc(2026, 11, 1).millisecondsSinceEpoch,
      'leaf': 1,
      'state': 1,
      'listed_at': DateTime.utc(2026, 11, 20).millisecondsSinceEpoch,
    });
    // The address as the library keeps it: what follows the folder's.
    expect(tables['files']!.first, {
      'id': 1,
      'folder': 2,
      'name': 'Vivarium.2019.1080p.mkv',
      'url': 'Vivarium.2019.1080p.mkv',
      'size': 2147483648,
      'modified': DateTime.utc(2026, 10, 2).millisecondsSinceEpoch,
      'added_at': DateTime.utc(2026, 11, 20).millisecondsSinceEpoch,
    });
    expect(tables['subtitles']!.single['url'], endsWith('1080p.srt'));
    expect(tables['titles']!.first, containsPair('name', 'Vivarium'));
    expect(tables['titles']!.first, containsPair('rating', 5.9));
    expect(
      tables['titles']!.first,
      containsPair('director', 'Lorcan Finnegan'),
    );
    expect(tables['title_keys']!.last, containsPair('fixed', 1));
    expect(tables['seasons']!.single, containsPair('episode_count', 6));
    expect([for (final row in tables['episodes']!) row['episode']], [1, 2]);
    expect(tables['file_meta']!.first, containsPair('height', 1080));

    expect(written.path, path);
    expect(written.rows, 21);
    expect(written.videos, 4);
    expect(written.titles, 2);
    expect(written.bytes, File(path).lengthSync());
    expect(File('$path.part').existsSync(), isFalse);
  });

  test('holds nothing of what was watched, My List, TMDB or errors', () async {
    fillSnapshotLibrary(library);
    final path = at(snapshotFileName);

    await writeSnapshot(library, (path, null));

    final text = utf8.decode(gzip.decode(File(path).readAsBytesSync()));
    expect(text, isNot(contains('private')));
    expect(text, isNot(contains('my_list')));
  });

  test('reads tables of many rows a page at a time, losing none', () async {
    library.db
      ..execute("INSERT INTO sources (source_id) VALUES ('alpha')")
      ..execute(
        'INSERT INTO folders (source, url, path, depth) '
        "VALUES (1, 'http://10.0.0.1/alpha/', '', 0)",
      )
      ..execute('BEGIN');
    for (var i = 0; i < 4500; i++) {
      library.db.execute(
        'INSERT INTO files (folder, name, url, added_at) VALUES (1, ?, ?, 0)',
        ['$i.mkv', 'http://10.0.0.1/alpha/$i.mkv'],
      );
    }
    // A key of three parts: episodes of several shows and seasons.
    for (var title = 1; title <= 3; title++) {
      library.db.execute(
        'INSERT INTO titles (id, kind, name, added_at) VALUES (?, 1, ?, 0)',
        [title, 'Show $title'],
      );
      for (var season = 0; season < 3; season++) {
        for (var episode = 1; episode <= 300; episode++) {
          library.db.execute(
            'INSERT INTO episodes (title, season, episode) VALUES (?, ?, ?)',
            [title, season, episode],
          );
        }
      }
    }
    library.db.execute('COMMIT');
    final path = at(snapshotFileName);
    final events = ReceivePort();
    final progress = <Object?>[];
    events.listen(progress.add);

    final written = await writeSnapshot(library, (path, events.sendPort));
    await pumpEventQueue();
    events.close();

    final tables = tablesOf(readSnapshotLines(path));
    expect(
      [for (final row in tables['files']!) row['id']],
      [for (var id = 1; id <= 4500; id++) id],
    );
    expect(
      [
        for (final row in tables['episodes']!)
          (row['title'], row['season'], row['episode']),
      ],
      [
        for (var title = 1; title <= 3; title++)
          for (var season = 0; season < 3; season++)
            for (var episode = 1; episode <= 300; episode++)
              (title, season, episode),
      ],
    );
    expect(written.rows, 1 + 1 + 4500 + 3 + 2700);
    // It ends by saying that all of it is written.
    expect(progress.last, (written.rows, written.rows));
  });

  test('leaves nothing behind where it cannot write', () async {
    fillSnapshotLibrary(library);
    final path = at('no-such-folder${Platform.pathSeparator}snapshot.gz');

    await expectLater(
      writeSnapshot(library, (path, null)),
      throwsA(isA<FileSystemException>()),
    );

    expect(folder.listSync(), isEmpty);
  });

  test('replaces a snapshot that lies there already', () async {
    final path = at(snapshotFileName);
    File(path).writeAsStringSync('an older one');

    await writeSnapshot(library, (path, null));

    expect(readSnapshotLines(path).last, {'end': true, 'rows': 0});
    expect(folder.listSync(), hasLength(1));
  });
}
