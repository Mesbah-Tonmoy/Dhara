import 'package:flutter/foundation.dart' show visibleForTesting;
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
/// subtitles, how far each source has been crawled, where each video was
/// left, and the films and shows those videos are copies of.
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

  /// Opens the database at [path] as an older version of the app would have
  /// left it, with the schema at [version], to test upgrades.
  @visibleForTesting
  factory LibraryDb.openAt(String path, int version) => LibraryDb._prepare(
        sqlite3.open(path),
        onDisk: true,
        upTo: version,
      );

  factory LibraryDb._prepare(
    Database db, {
    required bool onDisk,
    int upTo = schemaVersion,
  }) {
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
      for (var next = version; next < upTo; next++) {
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
  static const schemaVersion = 2;

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
const _migrations = [_schemaV1, _schemaV2];

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

/// Films and shows: what the videos of version 1 are copies of.
const _schemaV2 = '''
-- One film or one show, however many copies of it the sources hold.
CREATE TABLE titles (
  id INTEGER PRIMARY KEY,
  kind INTEGER NOT NULL CHECK (kind IN (0, 1)),   -- 0 film, 1 show
  name TEXT NOT NULL,               -- as the files spell it, until a provider names it
  year INTEGER,                     -- of a show: the earliest its files mention
  original_name TEXT,
  tmdb_id INTEGER,
  anilist_id INTEGER,
  -- 0 not looked up yet, 1 matched, 2 matched but unsure, 3 not found,
  -- 4 matched by hand, 5 left as it is by hand
  match_state INTEGER NOT NULL DEFAULT 0 CHECK (match_state BETWEEN 0 AND 5),
  confidence INTEGER CHECK (confidence BETWEEN 0 AND 100),
  overview TEXT,
  rating REAL,
  votes INTEGER,
  genres TEXT,                      -- names, joined by ", "
  language TEXT,                    -- code of the original language
  poster_path TEXT,
  backdrop_path TEXT,
  matched_at INTEGER,
  added_at INTEGER NOT NULL
) STRICT;
-- Two spellings that turn out to be one film are merged into one title.
CREATE UNIQUE INDEX titles_tmdb ON titles (kind, tmdb_id)
  WHERE tmdb_id IS NOT NULL;
CREATE INDEX titles_match ON titles (match_state);

-- The names files give a title: 'm|vivarium|2019', 's|the bay'. Several
-- spellings can lead to one title.
CREATE TABLE title_keys (
  key TEXT PRIMARY KEY,
  title INTEGER NOT NULL REFERENCES titles (id) ON DELETE CASCADE,
  name TEXT NOT NULL,               -- as written, to look it up by
  alt_name TEXT,                    -- what the file says when its folder says otherwise
  year INTEGER,
  fixed INTEGER NOT NULL DEFAULT 0 CHECK (fixed IN (0, 1))  -- tied to its title by hand
) STRICT, WITHOUT ROWID;
CREATE INDEX title_keys_title ON title_keys (title);

-- Seasons and episodes as a provider lists them. What the sources hold of
-- them is in file_meta.
CREATE TABLE seasons (
  title INTEGER NOT NULL REFERENCES titles (id) ON DELETE CASCADE,
  season INTEGER NOT NULL,
  name TEXT,
  overview TEXT,
  poster_path TEXT,
  air_date TEXT,
  episode_count INTEGER,
  PRIMARY KEY (title, season)
) STRICT, WITHOUT ROWID;

CREATE TABLE episodes (
  title INTEGER NOT NULL REFERENCES titles (id) ON DELETE CASCADE,
  season INTEGER NOT NULL,
  episode INTEGER NOT NULL,
  name TEXT,
  overview TEXT,
  still_path TEXT,
  air_date TEXT,
  runtime INTEGER,                  -- minutes
  PRIMARY KEY (title, season, episode)
) STRICT, WITHOUT ROWID;

-- What the name of each video says: which title it is a copy of, which
-- episode, and how good a copy. Made again when the parser changes.
CREATE TABLE file_meta (
  file INTEGER PRIMARY KEY REFERENCES files (id) ON DELETE CASCADE,
  parser INTEGER NOT NULL,          -- version of the parser that read the name
  kind INTEGER NOT NULL CHECK (kind IN (0, 1, 2)),  -- 0 film, 1 show, 2 neither
  title INTEGER REFERENCES titles (id) ON DELETE SET NULL,
  season INTEGER,                   -- NULL with an episode: numbered straight through
  episode INTEGER,
  episode_end INTEGER,
  episode_name TEXT,
  part INTEGER,                     -- CD 1, CD 2
  extra INTEGER CHECK (extra IN (1, 2)),  -- 1 trailer, 2 sample
  height INTEGER,
  source TEXT,
  codec TEXT,
  audio TEXT,
  languages TEXT,                   -- joined by ","
  is_3d INTEGER NOT NULL DEFAULT 0 CHECK (is_3d IN (0, 1)),
  release_group TEXT
) STRICT;
CREATE INDEX file_meta_title ON file_meta (title, season, episode);

-- Answers of the metadata providers, cut down to what the app uses.
CREATE TABLE metadata_cache (
  provider TEXT NOT NULL,           -- 'tmdb', 'anilist'
  key TEXT NOT NULL,                -- what was asked
  body TEXT NOT NULL,               -- JSON
  fetched_at INTEGER NOT NULL,
  PRIMARY KEY (provider, key)
) STRICT, WITHOUT ROWID;

-- Search index over title names; rowid = titles.id. Like files_fts it keeps
-- no copy of the text, but a title can be renamed.
CREATE VIRTUAL TABLE titles_fts USING fts5 (
  name,
  original_name,
  content = '',
  contentless_delete = 1,
  tokenize = 'unicode61 remove_diacritics 2',
  prefix = '2 3'
);
CREATE TRIGGER titles_fts_insert AFTER INSERT ON titles BEGIN
  INSERT INTO titles_fts (rowid, name, original_name)
  VALUES (new.id, new.name, new.original_name);
END;
CREATE TRIGGER titles_fts_delete AFTER DELETE ON titles BEGIN
  DELETE FROM titles_fts WHERE rowid = old.id;
END;
CREATE TRIGGER titles_fts_update AFTER UPDATE OF name, original_name ON titles
BEGIN
  DELETE FROM titles_fts WHERE rowid = old.id;
  INSERT INTO titles_fts (rowid, name, original_name)
  VALUES (new.id, new.name, new.original_name);
END;
''';
