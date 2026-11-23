import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:dhara/core/app_info.dart';
import 'package:dhara/core/db/library_db.dart';
import 'package:dhara/features/snapshot/snapshot_format.dart';

/// What [writeSnapshot] wrote.
class SnapshotWritten {
  const SnapshotWritten({
    required this.path,
    required this.rows,
    required this.bytes,
    required this.videos,
    required this.titles,
  });

  /// The file, where the user asked for it.
  final String path;

  /// The rows of every table together.
  final int rows;

  /// The size of the file.
  final int bytes;
  final int videos;
  final int titles;
}

/// Writes the library to the file at `path` as a snapshot (see
/// `snapshot_format.dart`) and returns what it wrote. Runs in the library
/// isolate.
///
/// The file is written under another name and only gets its own once it is
/// whole, so what lies at `path` is never half a snapshot. On `events`, if
/// there is one, it says `(rows written, rows in all)` as it goes.
///
/// Between two pages of rows other work on the library gets its turn, so
/// the app goes on answering. A crawl or a run of matching at the same
/// time would leave rows in the file that no longer fit each other (a
/// reader drops those): the caller sees that none is under way.
///
/// Throws a [FileSystemException] if the file cannot be written.
Future<SnapshotWritten> writeSnapshot(
  LibraryDb db,
  (String, SendPort?) request,
) async {
  final (path, events) = request;
  final counts = {
    for (final table in snapshotTables)
      table.name: db.db.select(table.count).single.values.single! as int,
  };
  final total = counts.values.fold(0, (sum, count) => sum + count);

  final part = File('$path.part');
  final file = part.openSync(mode: FileMode.write);
  var open = true;
  try {
    final packed = gzip.encoder.startChunkedConversion(_FileSink(file));
    void line(Object? json) => packed.add(utf8.encode('${jsonEncode(json)}\n'));

    line({
      'format': snapshotFormat,
      'version': snapshotVersion,
      'schema': LibraryDb.schemaVersion,
      'app': dharaVersion,
      'madeAt': DateTime.now().millisecondsSinceEpoch,
      'rows': counts,
    });

    var written = 0;
    final sinceReport = Stopwatch()..start();
    for (final table in snapshotTables) {
      line({'table': table.name, 'columns': table.columns});
      final page = db.db.prepare(table.page);
      try {
        var key = table.firstKey;
        while (true) {
          final rows = page.select([...key, _pageSize]);
          if (rows.isEmpty) break;
          final text = StringBuffer();
          for (final row in rows) {
            text
              ..write(
                jsonEncode([for (final value in row.values) _plain(value)]),
              )
              ..write('\n');
          }
          packed.add(utf8.encode(text.toString()));
          written += rows.length;
          key = [
            for (var column = 0; column < table.keys; column++)
              rows.last.values[column]!,
          ];
          if (events != null && sinceReport.elapsedMilliseconds >= 200) {
            events.send((written, total));
            sinceReport.reset();
          }
          // Lets other work on the library have its turn.
          await Future<void>.delayed(Duration.zero);
        }
      } finally {
        page.close();
      }
    }
    line({'end': true, 'rows': written});
    packed.close();
    file
      ..flushSync()
      ..closeSync();
    open = false;
    part.renameSync(path);
    events?.send((written, written));
    return SnapshotWritten(
      path: path,
      rows: written,
      bytes: File(path).lengthSync(),
      videos: counts['files'] ?? 0,
      titles: counts['titles'] ?? 0,
    );
  } on Object {
    if (open) file.closeSync();
    try {
      if (part.existsSync()) part.deleteSync();
    } on FileSystemException {
      // It stays behind under its other name; the next try replaces it.
    }
    rethrow;
  }
}

const _pageSize = 2000;

/// A value as JSON can carry it. The tables of a snapshot hold numbers and
/// text only; a number that is none (the library has no such rating, but
/// SQLite would keep one) is left out.
Object? _plain(Object? value) => switch (value) {
  final double number when !number.isFinite => null,
  int() || double() || String() || null => value,
  _ => null,
};

/// Writes what it is given to an open file, as it comes.
class _FileSink implements Sink<List<int>> {
  _FileSink(this._file);

  final RandomAccessFile _file;

  @override
  void add(List<int> data) => _file.writeFromSync(data);

  @override
  void close() {}
}
