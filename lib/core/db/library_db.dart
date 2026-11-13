import 'package:sqlite3/sqlite3.dart';

/// Why [LibraryDb.open] refused a database file.
enum LibraryDbProblem {
  /// A newer version of the app made the file. It is left as it is.
  newerVersion,

  /// The file is not a usable SQLite database.
  damaged,

  /// No database could be opened: the file cannot be reached, or SQLite
  /// itself is missing. Reported by `LibraryIsolate`; says nothing about
  /// the content of the file.
  unavailable,
}

class LibraryDbException implements Exception {
  const LibraryDbException(this.problem);

  final LibraryDbProblem problem;

  @override
  String toString() => 'LibraryDbException(${problem.name})';
}

/// The app's one SQLite database: every video found on the sources, their
/// subtitles, how far each source has been crawled, and where each video
/// was left.
///
/// `package:sqlite3` is synchronous, so outside tests this is used from the
/// library isolate only, never from the UI.
///
/// Times are stored as milliseconds since the epoch (UTC). Names, paths and
/// URLs are server-controlled text: bind them as parameters, never build
/// SQL from them.
class LibraryDb {
  LibraryDb._(this.db);

  /// Opens the database at [path], creating or upgrading it as needed.
  ///
  /// Throws a [LibraryDbException] if the file cannot be used.
  factory LibraryDb.open(String path) => LibraryDb._prepare(
        sqlite3.open(path),
        onDisk: true,
      );

  /// A database that lives in memory only, for tests.
  factory LibraryDb.inMemory() => LibraryDb._prepare(
        sqlite3.openInMemory(),
        onDisk: false,
      );

  factory LibraryDb._prepare(Database db, {required bool onDisk}) {
    try {
      // Waits instead of failing if a second copy of the app has the file.
      db.execute('PRAGMA busy_timeout = 3000');
      db.execute('PRAGMA foreign_keys = ON');

      // Checked before anything is written: a newer app's file is not to
      // be touched, not even its journal mode.
      final version = db.userVersion;
      if (version > schemaVersion) {
        throw const LibraryDbException(LibraryDbProblem.newerVersion);
      }
      if (onDisk) {
        // Readers and the writer do not block each other, and a commit does
        // not wait for the disk. A crash can lose the last few commits but
        // never damages the file; the index can be crawled again.
        db.execute('PRAGMA journal_mode = WAL');
        db.execute('PRAGMA synchronous = NORMAL');
      }
      final library = LibraryDb._(db);
      for (var next = version; next < schemaVersion; next++) {
        library.transaction(() {
          db.execute(_migrations[next]);
          db.userVersion = next + 1;
        });
      }
      return library;
    } on SqliteException catch (error) {
      db.close();
      if (_damagedCodes.contains(error.resultCode)) {
        throw const LibraryDbException(LibraryDbProblem.damaged);
      }
      rethrow;
    } on LibraryDbException {
      db.close();
      rethrow;
    }
  }

  /// The schema this version of the app reads and writes. Raise it together
  /// with a new entry in [_migrations].
  static const schemaVersion = 1;

  final Database db;

  /// Runs [body] as one transaction: all of its changes are kept, or, if it
  /// throws, none.
  T transaction<T>(T Function() body) {
    db.execute('BEGIN IMMEDIATE');
    try {
      final result = body();
      db.execute('COMMIT');
      return result;
    } on Object {
      // Some errors make SQLite roll back by itself.
      if (!db.autocommit) db.execute('ROLLBACK');
      rethrow;
    }
  }

  void close() => db.close();
}

// SQLITE_CORRUPT and SQLITE_NOTADB.
const _damagedCodes = {11, 26};

/// One script per schema version, in order: `_migrations[n]` takes a
/// database from version n to n + 1. Never edit a script that has shipped;
/// add a new one.
const _migrations = [_schemaV1];

const _schemaV1 = '''
-- Crawl state of one source. The source itself (name, URLs, type) lives in
-- the source list; this row exists once the source has been crawled.
CREATE TABLE sources (
  id INTEGER PRIMARY KEY,
  source_id TEXT NOT NULL UNIQUE,   -- the id in the source list
  crawl_started_at INTEGER,
  crawl_finished_at INTEGER,        -- the last crawl that reached the end
  last_error TEXT
) STRICT;

-- Every folder found, which is also the crawl queue (state = 0).
CREATE TABLE folders (
  id INTEGER PRIMARY KEY,
  source INTEGER NOT NULL REFERENCES sources (id) ON DELETE CASCADE,
  parent INTEGER REFERENCES folders (id) ON DELETE CASCADE,  -- NULL: a base URL
  url TEXT NOT NULL UNIQUE,
  path TEXT NOT NULL,               -- folder names below the base URL, for search
  depth INTEGER NOT NULL,
  modified INTEGER,                 -- as the parent folder's page says
  leaf INTEGER NOT NULL DEFAULT 0 CHECK (leaf IN (0, 1)),  -- held no folders when last read
  state INTEGER NOT NULL DEFAULT 0 CHECK (state IN (0, 1, 2)),  -- 0 to read, 1 read, 2 failed
  listed_at INTEGER
) STRICT;
CREATE INDEX folders_parent ON folders (parent);
CREATE INDEX folders_queue ON folders (source, state);

-- Video files only.
CREATE TABLE files (
  id INTEGER PRIMARY KEY,
  folder INTEGER NOT NULL REFERENCES folders (id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  url TEXT NOT NULL,
  size INTEGER,
  modified INTEGER,
  added_at INTEGER NOT NULL         -- when the app first saw it
) STRICT;
CREATE INDEX files_folder ON files (folder);

-- Subtitle files that belong to a video.
CREATE TABLE subtitles (
  id INTEGER PRIMARY KEY,
  file INTEGER NOT NULL REFERENCES files (id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  url TEXT NOT NULL
) STRICT;
CREATE INDEX subtitles_file ON subtitles (file);

-- Search index over file names and folder paths; rowid = files.id. It
-- keeps no copy of the text. A file's name and folder never change (a
-- renamed file is a new row), so insert and delete are all it needs.
CREATE VIRTUAL TABLE files_fts USING fts5 (
  name,
  path,
  content = '',
  contentless_delete = 1,
  tokenize = 'unicode61 remove_diacritics 2',
  prefix = '2 3'
);
CREATE TRIGGER files_fts_insert AFTER INSERT ON files BEGIN
  INSERT INTO files_fts (rowid, name, path)
  VALUES (new.id, new.name, (SELECT path FROM folders WHERE id = new.folder));
END;
CREATE TRIGGER files_fts_delete AFTER DELETE ON files BEGIN
  DELETE FROM files_fts WHERE rowid = old.id;
END;

-- Where each video was left, by URL (also for videos not in the index).
CREATE TABLE playback (
  url TEXT PRIMARY KEY,
  position_ms INTEGER NOT NULL,
  duration_ms INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
) STRICT, WITHOUT ROWID;
''';
