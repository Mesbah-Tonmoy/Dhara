import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:dhara/core/db/library_db.dart';
import 'package:dhara/core/net/media_url.dart';
import 'package:dhara/features/snapshot/snapshot_format.dart';
import 'package:dhara/features/sources/source.dart';
import 'package:sqlite3/sqlite3.dart';

/// Why a snapshot was not taken.
enum SnapshotProblem {
  /// The file cannot be opened or read.
  unreadable,

  /// It is not a snapshot, or not one that holds together: not gzip, no
  /// head, a line that is neither a table nor a row.
  notASnapshot,

  /// A later version of the app wrote it in a way this one does not read.
  newerVersion,

  /// It ends before its last line, or holds another number of rows than
  /// that line says.
  cutShort,

  /// The library holds something already. A snapshot only ever fills an
  /// empty one.
  libraryNotEmpty,

  /// The library could not be written (the disk is full, the file is held
  /// by another program).
  libraryFailed,
}

/// What [readSnapshot] did.
class SnapshotRead {
  const SnapshotRead({
    this.problem,
    this.rows = 0,
    this.skipped = 0,
    this.videos = 0,
    this.titles = 0,
    this.madeAt,
  });

  /// Why nothing was taken; `null` if the snapshot was read. With a
  /// problem the library is as empty as it was.
  final SnapshotProblem? problem;

  /// The rows that went into the library.
  final int rows;

  /// The rows that were left out: not well formed, of a server that is not
  /// in the source list, or pointing at a row that was left out.
  final int skipped;

  /// What the library holds now.
  final int videos;
  final int titles;

  /// When the snapshot was written, as it says itself.
  final DateTime? madeAt;

  bool get ok => problem == null;
}

/// Fills the empty library from the snapshot file at `path` (see
/// `snapshot_format.dart`) and returns what it did. Runs in the library
/// isolate. On `events`, if there is one, it says `(rows read, rows in
/// all)` as it goes.
///
/// A snapshot is untrusted input, like the answer of a server: it was
/// fetched from the internet, and whoever can change it could otherwise
/// point the player anywhere. So:
///
/// - only the tables and columns of [snapshotTables] are read, each value
///   is checked for its type, its size and its range, and the database's
///   own rules (strict types, checks, foreign keys) hold as for any other
///   writer. A row that fails is left out and counted;
/// - a source is only taken if the source list (`sources`) has it, a
///   folder only if it lies on a server of its source, and the folder a
///   crawl starts from only if it is a base URL of that source. A video
///   and a subtitle are taken only if they lie on a server of the source
///   their folder belongs to;
/// - the size of a line and of the whole are limited, and so is the
///   number of rows.
///
/// A file that does not hold together is refused as a whole, and what was
/// read of it up to there is taken out again.
///
/// Between two pieces of the file other work on the library gets its
/// turn.
Future<SnapshotRead> readSnapshot(
  LibraryDb db,
  (String, List<Source>, SendPort?) request,
) async {
  final (path, sources, events) = request;
  if (!_isEmpty(db)) {
    return const SnapshotRead(problem: SnapshotProblem.libraryNotEmpty);
  }
  final RandomAccessFile file;
  try {
    file = File(path).openSync();
  } on FileSystemException {
    return const SnapshotRead(problem: SnapshotProblem.unreadable);
  }

  // From here until the snapshot is in whole, the library says of itself
  // that it holds half of one (see [removeCutOffSnapshot]).
  db.db.execute('PRAGMA application_id = 1146310224');
  final reader = _Reader(db, sources);
  final lines = _Lines();
  final unpacked = gzip.decoder.startChunkedConversion(lines);
  final sinceReport = Stopwatch()..start();
  SnapshotProblem? problem;
  try {
    final buffer = Uint8List(_chunkBytes);
    while (true) {
      final count = file.readIntoSync(buffer);
      if (count == 0) break;
      unpacked.add(Uint8List.sublistView(buffer, 0, count));
      if (lines.waiting < _rowsAtOnce) continue;
      final batch = lines.take();
      db.transaction(() => batch.forEach(reader.line));
      if (events != null && sinceReport.elapsedMilliseconds >= 200) {
        events.send((reader.rowsSeen, reader.rowsExpected));
        sinceReport.reset();
      }
      // Lets other work on the library have its turn.
      await Future<void>.delayed(Duration.zero);
    }
    unpacked.close();
    final rest = lines.take();
    if (rest.isNotEmpty) db.transaction(() => rest.forEach(reader.line));
    if (lines.hasUnfinishedLine || !reader.ended) {
      problem = SnapshotProblem.cutShort;
    }
  } on _Refused catch (refused) {
    problem = refused.problem;
  } on FormatException {
    // Not gzip, or gzip that breaks off.
    problem = reader.started
        ? SnapshotProblem.cutShort
        : SnapshotProblem.notASnapshot;
  } on FileSystemException {
    problem = SnapshotProblem.unreadable;
  } on SqliteException {
    problem = SnapshotProblem.libraryFailed;
  } finally {
    file.closeSync();
    reader.close();
  }

  if (problem != null) {
    _empty(db);
    db.db.execute('PRAGMA application_id = 0');
    return SnapshotRead(problem: problem);
  }
  db.db.execute('PRAGMA application_id = 0');
  int count(String sql) => db.db.select(sql).single.values.single! as int;
  events?.send((reader.rowsSeen, reader.rowsSeen));
  return SnapshotRead(
    rows: reader.rowsTaken,
    skipped: reader.rowsSeen - reader.rowsTaken,
    videos: count('SELECT count(*) FROM files'),
    titles: count('SELECT count(*) FROM titles'),
    madeAt: reader.madeAt,
  );
}

/// Whether the library holds neither a server nor a title: what a
/// snapshot fills. Runs in the library isolate.
bool isLibraryEmpty(LibraryDb db, Object? _) => _isEmpty(db);

/// If the reading of a snapshot was cut off (the app was closed, the PC
/// went off), takes out what had been read, and returns whether that was
/// so. Runs in the library isolate, as the app starts, before anything
/// else uses the library.
///
/// While a snapshot is read the library carries a mark (the number in its
/// file that SQLite keeps for the application, 0 at all other times). It
/// was empty when the reading began, so with the mark everything in the
/// tables a snapshot fills is half of one. Every build looks for the mark
/// as it starts: nothing else can be added to a library that carries it.
bool removeCutOffSnapshot(LibraryDb db, Object? _) {
  final mark = db.db.select('PRAGMA application_id').single.values.single;
  if (mark != _readingMark) return false;
  _empty(db);
  db.db.execute('PRAGMA application_id = 0');
  return true;
}

/// "DSNP", as the number the statements above write out.
const _readingMark = 1146310224;

bool _isEmpty(LibraryDb db) =>
    db.db.select('SELECT 1 FROM sources LIMIT 1').isEmpty &&
    db.db.select('SELECT 1 FROM titles LIMIT 1').isEmpty;

/// The rows of every table a snapshot fills go with these two.
void _empty(LibraryDb db) {
  db.transaction(() {
    db.db
      ..execute('DELETE FROM sources')
      ..execute('DELETE FROM titles');
  });
  db.releaseFreeSpace();
}

/// How much of the file is read at a time.
const _chunkBytes = 64 * 1024;

/// About how many rows are written as one transaction. Many at once is
/// what makes it fast: the search index is written once per transaction,
/// and in small pieces it has to be put together again and again.
const _rowsAtOnce = 16000;

/// No line of a snapshot is longer than this. The longest hold the text
/// about a title, which is cut at 2,000 characters where it comes from.
const _maxLineBytes = 64 * 1024;

/// The most a snapshot may unpack to, and the most rows it may hold: ten
/// times what the library of 577,000 videos comes to.
const _maxBytes = 4 * 1024 * 1024 * 1024;
const _maxRows = 20 * 1000 * 1000;

/// The file does not hold together: nothing of it is taken.
class _Refused implements Exception {
  const _Refused(this.problem);

  final SnapshotProblem problem;
}

const _notASnapshot = _Refused(SnapshotProblem.notASnapshot);

/// Cuts what the file unpacks to into lines.
class _Lines implements Sink<List<int>> {
  final _whole = <Uint8List>[];
  final _open = BytesBuilder(copy: true);
  var _bytes = 0;

  /// The file does not end with the end of a line.
  bool get hasUnfinishedLine => _open.isNotEmpty;

  /// How many whole lines wait to be taken.
  int get waiting => _whole.length;

  /// The lines that are whole by now, each once.
  List<Uint8List> take() {
    final lines = [..._whole];
    _whole.clear();
    return lines;
  }

  @override
  void add(List<int> data) {
    _bytes += data.length;
    if (_bytes > _maxBytes) throw _notASnapshot;
    var start = 0;
    while (true) {
      final end = data.indexOf(0x0A, start);
      if (end < 0) break;
      if (_open.length + end - start > _maxLineBytes) throw _notASnapshot;
      if (_open.isEmpty) {
        _whole.add(Uint8List.fromList(data.sublist(start, end)));
      } else {
        _open.add(data.sublist(start, end));
        _whole.add(_open.takeBytes());
      }
      start = end + 1;
    }
    if (_open.length + data.length - start > _maxLineBytes) throw _notASnapshot;
    if (start < data.length) _open.add(data.sublist(start));
  }

  @override
  void close() {}
}

/// Reads the lines of a snapshot, one after the other, into the library.
class _Reader {
  _Reader(this._library, List<Source> sources)
    : _listed = {for (final source in sources) source.id: source};

  final LibraryDb _library;

  /// The source list, by id.
  final Map<String, Source> _listed;

  /// The sources of the snapshot that were taken, by their row: the
  /// addresses a crawl of each starts from, and the servers they lie on.
  final _baseUrls = <int, Set<String>>{};
  final _servers = <int, Set<String>>{};

  final _statements = <PreparedStatement>[];
  static final _json = utf8.decoder.fuse(json.decoder);

  _Table? _table;
  var _ended = false;

  bool started = false;
  DateTime? madeAt;

  /// How many rows the head of the file says there are.
  int rowsExpected = 0;
  int rowsSeen = 0;
  int rowsTaken = 0;

  /// The last line was the one that ends a snapshot, and it agrees with
  /// what was read.
  bool get ended => _ended;

  Database get _db => _library.db;

  void close() {
    for (final statement in _statements) {
      statement.close();
    }
  }

  void line(Uint8List bytes) {
    // Nothing follows the end.
    if (_ended) throw _notASnapshot;
    final Object? value;
    try {
      value = _json.convert(bytes);
    } on FormatException {
      throw _notASnapshot;
    }
    if (!started) return _head(value);
    switch (value) {
      case {'end': true, 'rows': final int rows}:
        if (rows != rowsSeen) throw const _Refused(SnapshotProblem.cutShort);
        _ended = true;
      case {'table': final String name, 'columns': final List<Object?> columns}:
        _table = _tableFor(name, columns);
      case final List<Object?> row:
        final table = _table;
        if (table == null) throw _notASnapshot;
        if (++rowsSeen > _maxRows) throw _notASnapshot;
        if (table.take(row)) rowsTaken++;
      default:
        throw _notASnapshot;
    }
  }

  void _head(Object? value) {
    if (value is! Map<String, Object?> || value['format'] != snapshotFormat) {
      throw _notASnapshot;
    }
    final version = value['version'];
    if (version is! int || version < 1) throw _notASnapshot;
    if (version > snapshotVersion) {
      throw const _Refused(SnapshotProblem.newerVersion);
    }
    started = true;
    if (value['madeAt'] case final int made when made > 0 && made < _maxTime) {
      madeAt = DateTime.fromMillisecondsSinceEpoch(made);
    }
    // Only for saying how far the reading is.
    if (value['rows'] case final Map<String, Object?> rows) {
      for (final count in rows.values) {
        if (count is int && count > 0 && count <= _maxRows) {
          rowsExpected += count;
        }
      }
    }
  }

  /// What reads the rows of the table [name], which come with [columns].
  /// A table this version does not know, or one without a column it
  /// needs, is passed over row by row.
  _Table _tableFor(String name, List<Object?> columns) {
    if (columns.length > 64 || columns.any((column) => column is! String)) {
      throw _notASnapshot;
    }
    final at = <String, int>{
      for (final (index, column) in columns.indexed) column! as String: index,
    };
    _Row row(List<Object?> values) => _Row(values, at);
    bool has(List<String> needed) => needed.every(at.containsKey);
    return switch (name) {
      'sources' when has(['id', 'source_id']) => _Table(
        columns.length,
        (values) => _source(row(values)),
      ),
      'folders' when has(['id', 'source', 'parent', 'url', 'path']) => _Table(
        columns.length,
        (values) => _folder(row(values)),
      ),
      'files' when has(['id', 'folder', 'name', 'url', 'added_at']) => _Table(
        columns.length,
        (values) => _file(row(values)),
      ),
      'subtitles' when has(['file', 'name', 'url']) => _Table(
        columns.length,
        (values) => _subtitle(row(values)),
      ),
      'titles' when has(['id', 'kind', 'name', 'added_at']) => _Table(
        columns.length,
        (values) => _title(row(values)),
      ),
      'title_keys' when has(['key', 'title', 'name']) => _Table(
        columns.length,
        (values) => _titleKey(row(values)),
      ),
      'seasons' when has(['title', 'season']) => _Table(
        columns.length,
        (values) => _season(row(values)),
      ),
      'episodes' when has(['title', 'season', 'episode']) => _Table(
        columns.length,
        (values) => _episode(row(values)),
      ),
      'file_meta' when has(['file', 'parser', 'kind']) => _Table(
        columns.length,
        (values) => _fileMeta(row(values)),
      ),
      _ => const _Table(-1, _pass),
    };
  }

  static bool _pass(List<Object?> values) => false;

  PreparedStatement _prepare(String sql) {
    final statement = _db.prepare(sql);
    _statements.add(statement);
    return statement;
  }

  /// Puts a row in. The database refuses what breaks its rules (a row it
  /// points at is missing, a value out of range, a key twice): that row
  /// is left out.
  bool _insert(PreparedStatement statement, List<Object?> values) {
    try {
      statement.execute(values);
      return true;
    } on SqliteException {
      return false;
    }
  }

  late final _insertSource = _prepare(
    'INSERT INTO sources (id, source_id, crawl_started_at, '
    'crawl_finished_at) VALUES (?, ?, ?, ?)',
  );

  bool _source(_Row row) {
    final id = row.id('id');
    final source = _listed[row.text('source_id', 64)];
    if (id == null || source == null) return false;
    if (!_insert(_insertSource, [
      id,
      source.id,
      row.time('crawl_started_at'),
      row.time('crawl_finished_at'),
    ])) {
      return false;
    }
    _baseUrls[id] = {for (final url in source.baseUrls) url.toString()};
    _servers[id] = {for (final url in source.baseUrls) _serverOf(url)};
    return true;
  }

  late final _insertFolder = _prepare(
    'INSERT INTO folders (id, source, parent, url, path, depth, modified, '
    'leaf, state, listed_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
  );
  late final _folderById = _prepare(
    'SELECT source, depth, url FROM folders WHERE id = ?',
  );

  // The folder looked up last: the rows of a folder follow each other.
  int? _lastFolder;
  (int, int, String)? _lastFolderRow;

  /// The source, the depth and the address of a folder that was taken.
  (int, int, String)? _folderRow(int id) {
    if (id == _lastFolder) return _lastFolderRow;
    final rows = _folderById.select([id]);
    _lastFolder = id;
    return _lastFolderRow = rows.isEmpty
        ? null
        : (
            rows.first['source'] as int,
            rows.first['depth'] as int,
            rows.first['url'] as String,
          );
  }

  bool _folder(_Row row) {
    final id = row.id('id');
    final address = row.text('url', _maxUrl);
    final path = row.text('path', _maxPath, orEmpty: true);
    final state = row.integer('state', 0, 2) ?? 0;
    if (id == null || address == null || path == null) return false;

    final int source;
    final int depth;
    final parent = row.id('parent');
    if (row.isNull('parent')) {
      // Where a crawl of a source starts: one of its base URLs, as the
      // source list has them.
      final listed = row.id('source');
      if (listed == null || !(_baseUrls[listed]?.contains(address) ?? false)) {
        return false;
      }
      source = listed;
      depth = 0;
    } else {
      // A folder below one that was taken, on a server of its source.
      final above = parent == null ? null : _folderRow(parent);
      if (above == null || above.$2 >= _maxDepth) return false;
      source = above.$1;
      depth = above.$2 + 1;
      if (!_isOnServer(address, source)) return false;
    }
    // The folder may be the one looked up last, when it was not there.
    if (id == _lastFolder) _lastFolder = null;
    return _insert(_insertFolder, [
      id,
      source,
      parent,
      address,
      path,
      depth,
      row.time('modified'),
      row.integer('leaf', 0, 1) ?? 0,
      state,
      row.time('listed_at'),
    ]);
  }

  late final _insertFile = _prepare(
    'INSERT INTO files (id, folder, name, url, size, modified, added_at) '
    'VALUES (?, ?, ?, ?, ?, ?, ?)',
  );

  bool _file(_Row row) {
    final id = row.id('id');
    final folderId = row.id('folder');
    final name = row.text('name', _maxName);
    final kept = row.text('url', _maxUrl);
    final added = row.time('added_at');
    if (id == null ||
        folderId == null ||
        name == null ||
        kept == null ||
        added == null) {
      return false;
    }
    final folder = _folderRow(folderId);
    if (folder == null) return false;
    // The library keeps what follows the address of the folder, or a
    // whole address; a row is put in with the whole one. Put together it
    // is checked like any other: what follows could change the host.
    final address = kept.contains('://') ? kept : '${folder.$3}$kept';
    if (address.length > _maxUrl || !_isOnServer(address, folder.$1)) {
      return false;
    }
    return _insert(_insertFile, [
      id,
      folderId,
      name,
      address,
      row.integer('size', 0, _maxSize),
      row.time('modified'),
      added,
    ]);
  }

  late final _insertSubtitle = _prepare(
    'INSERT INTO subtitles (file, name, url) VALUES (?, ?, ?)',
  );
  late final _sourceOfFile = _prepare(
    'SELECT d.source FROM files f JOIN folders d ON d.id = f.folder '
    'WHERE f.id = ?',
  );
  int? _lastFile;
  int? _lastFileSource;

  bool _subtitle(_Row row) {
    final file = row.id('file');
    final name = row.text('name', _maxName);
    final address = row.text('url', _maxUrl);
    if (file == null || name == null || address == null) return false;
    if (file != _lastFile) {
      final rows = _sourceOfFile.select([file]);
      _lastFile = file;
      _lastFileSource = rows.isEmpty ? null : rows.first['source'] as int;
    }
    final source = _lastFileSource;
    if (source == null || !_isOnServer(address, source)) return false;
    return _insert(_insertSubtitle, [file, name, address]);
  }

  late final _insertTitle = _prepare(
    'INSERT INTO titles (id, kind, name, year, original_name, tmdb_id, '
    'anilist_id, match_state, confidence, overview, rating, votes, genres, '
    'language, poster_path, backdrop_path, matched_at, added_at, runtime, '
    'set_aside, director, actors, details_at) '
    'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, '
    '?, ?)',
  );

  bool _title(_Row row) {
    final id = row.id('id');
    final kind = row.integer('kind', 0, 1);
    final name = row.text('name', _maxTitle);
    final added = row.time('added_at');
    if (id == null || kind == null || name == null || added == null) {
      return false;
    }
    return _insert(_insertTitle, [
      id,
      kind,
      name,
      row.integer('year', _minYear, _maxYear),
      row.text('original_name', _maxTitle),
      row.id('tmdb_id'),
      row.id('anilist_id'),
      row.integer('match_state', 0, 5) ?? 0,
      row.integer('confidence', 0, 100),
      row.text('overview', _maxOverview),
      row.number('rating', 0, 10),
      row.integer('votes', 0, _maxCount),
      row.text('genres', _maxList),
      row.text('language', 16),
      row.imagePath('poster_path'),
      row.imagePath('backdrop_path'),
      row.time('matched_at'),
      added,
      row.integer('runtime', 0, _maxMinutes),
      row.integer('set_aside', 0, 1) ?? 0,
      row.text('director', _maxList),
      row.text('actors', _maxList),
      row.time('details_at'),
    ]);
  }

  late final _insertTitleKey = _prepare(
    'INSERT INTO title_keys (key, title, name, alt_name, year, fixed) '
    'VALUES (?, ?, ?, ?, ?, ?)',
  );

  bool _titleKey(_Row row) {
    final key = row.text('key', _maxTitle + 16);
    final title = row.id('title');
    final name = row.text('name', _maxTitle);
    if (key == null || title == null || name == null) return false;
    return _insert(_insertTitleKey, [
      key,
      title,
      name,
      row.text('alt_name', _maxTitle),
      row.integer('year', _minYear, _maxYear),
      row.integer('fixed', 0, 1) ?? 0,
    ]);
  }

  late final _insertSeason = _prepare(
    'INSERT INTO seasons (title, season, name, overview, poster_path, '
    'air_date, episode_count) VALUES (?, ?, ?, ?, ?, ?, ?)',
  );

  bool _season(_Row row) {
    final title = row.id('title');
    final season = row.integer('season', 0, _maxNumber);
    if (title == null || season == null) return false;
    return _insert(_insertSeason, [
      title,
      season,
      row.text('name', _maxTitle),
      row.text('overview', _maxOverview),
      row.imagePath('poster_path'),
      row.date('air_date'),
      row.integer('episode_count', 0, _maxNumber),
    ]);
  }

  late final _insertEpisode = _prepare(
    'INSERT INTO episodes (title, season, episode, name, overview, '
    'still_path, air_date, runtime) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
  );

  bool _episode(_Row row) {
    final title = row.id('title');
    final season = row.integer('season', 0, _maxNumber);
    final episode = row.integer('episode', 0, _maxNumber);
    if (title == null || season == null || episode == null) return false;
    return _insert(_insertEpisode, [
      title,
      season,
      episode,
      row.text('name', _maxTitle),
      row.text('overview', _maxOverview),
      row.imagePath('still_path'),
      row.date('air_date'),
      row.integer('runtime', 0, _maxMinutes),
    ]);
  }

  late final _insertFileMeta = _prepare(
    'INSERT INTO file_meta (file, parser, kind, title, season, episode, '
    'episode_end, episode_name, part, extra, height, source, codec, audio, '
    'languages, is_3d, release_group) '
    'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
  );

  bool _fileMeta(_Row row) {
    final file = row.id('file');
    final parser = row.integer('parser', 0, _maxNumber);
    final kind = row.integer('kind', 0, 2);
    if (file == null || parser == null || kind == null) return false;
    return _insert(_insertFileMeta, [
      file,
      parser,
      kind,
      row.id('title'),
      row.integer('season', 0, _maxNumber),
      row.integer('episode', 0, _maxNumber),
      row.integer('episode_end', 0, _maxNumber),
      row.text('episode_name', _maxTitle),
      row.integer('part', 0, _maxNumber),
      row.integer('extra', 1, 2),
      row.integer('height', 0, _maxNumber),
      row.text('source', _maxTag),
      row.text('codec', _maxTag),
      row.text('audio', _maxTag),
      row.text('languages', _maxList),
      row.integer('is_3d', 0, 1) ?? 0,
      row.text('release_group', _maxTag),
    ]);
  }

  /// Whether [address] is a plain http(s) address on a server the source
  /// of the snapshot's row [source] has in the source list.
  bool _isOnServer(String address, int source) {
    final url = parseMediaUrl(address);
    // Written the one way an address is written: as the crawl kept it.
    if (url == null ||
        url.userInfo.isNotEmpty ||
        url.hasFragment ||
        url.toString() != address) {
      return false;
    }
    return _servers[source]?.contains(_serverOf(url)) ?? false;
  }
}

/// A server as the check for it sees one: scheme, host and port.
String _serverOf(Uri url) => '${url.scheme}://${url.host}:${url.port}';

/// The rows of one table: how many values each has, and what takes one.
class _Table {
  const _Table(this.width, this._take);

  /// -1: a table that is passed over.
  final int width;
  final bool Function(List<Object?> values) _take;

  bool take(List<Object?> values) =>
      (width < 0 || values.length == width) && _take(values);
}

/// One row, read by the names of its columns. Every reading checks what
/// it finds and gives `null` for what is missing or not as it should be;
/// the caller decides whether the row can do without.
class _Row {
  const _Row(this._values, this._at);

  final List<Object?> _values;
  final Map<String, int> _at;

  Object? _value(String column) {
    final index = _at[column];
    return index == null ? null : _values[index];
  }

  bool isNull(String column) => _value(column) == null;

  /// A whole number from [min] to [max].
  int? integer(String column, int min, int max) => switch (_value(column)) {
    final int value when value >= min && value <= max => value,
    _ => null,
  };

  /// The number of a row: above zero.
  int? id(String column) => integer(column, 1, _maxId);

  /// A point in time, in milliseconds.
  int? time(String column) => integer(column, 0, _maxTime);

  double? number(String column, num min, num max) => switch (_value(column)) {
    final num value when value >= min && value <= max => value.toDouble(),
    _ => null,
  };

  /// Text of one line, not longer than [max] and not empty (unless
  /// [orEmpty]). It is shown through plain `Text` widgets only, like every
  /// text of a server.
  String? text(String column, int max, {bool orEmpty = false}) =>
      switch (_value(column)) {
        final String value
            when value.length <= max &&
                (orEmpty || value.isNotEmpty) &&
                !value.contains(_controlChars) =>
          value,
        _ => null,
      };

  /// A path of TMDB's image server, in the one shape it has: it ends up
  /// in an address and in a file name.
  String? imagePath(String column) => switch (_value(column)) {
    final String value when _imageFile.hasMatch(value) => value,
    _ => null,
  };

  String? date(String column) => switch (_value(column)) {
    final String value when _isoDate.hasMatch(value) => value,
    _ => null,
  };
}

const _maxId = 0x7fffffffffff;
const _maxTime = 4102444800000 * 2; // far beyond the year 2100
const _maxSize = 0x7fffffffffff;
const _maxCount = 0x7fffffff;
const _maxNumber = 100000;
const _maxMinutes = 100000;
const _minYear = 1870;
const _maxYear = 2200;
const _maxDepth = 64;

const _maxUrl = 4096;
const _maxPath = 4096;
const _maxName = 1024;
const _maxTitle = 400;
const _maxOverview = 4000;
const _maxList = 1000;
const _maxTag = 100;

// Control characters, but for the tab and the line breaks that the text
// about a title may have.
final _controlChars = RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]');
final _imageFile = RegExp(r'^/[A-Za-z0-9_-]{1,64}\.(jpg|jpeg|png|webp)$');
final _isoDate = RegExp(r'^(18|19|20|21)\d{2}-\d{2}-\d{2}$');
