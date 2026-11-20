import 'dart:convert';
// For its compression only: the file itself is opened by SQLite.
import 'dart:io' show zlib;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:sqlite3/sqlite3.dart';

/// A short number made from the address of a video, to look the video up
/// by: 48 bits of FNV-1a over the address as UTF-8. Two addresses can
/// share one, so a lookup compares the address as well.
///
/// SQL knows it as `dhara_url_key(url)`; the column `files.url_key` and
/// its index are made with it, so it must never give another number for
/// an address than it did.
int urlKey(String url) {
  var hash = 0xcbf29ce484222325;
  for (final byte in utf8.encode(url)) {
    hash = (hash ^ byte) * 0x100000001b3;
  }
  return hash & 0xffffffffffff;
}

/// How an answer of a metadata provider is kept: its text, deflated. SQL
/// knows the two as `dhara_pack(text)` and `dhara_unpack(blob)`.
Uint8List packAnswer(String text) =>
    Uint8List.fromList(zlib.encode(utf8.encode(text)));

String unpackAnswer(Uint8List packed) => utf8.decode(zlib.decode(packed));

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
/// left, the films and shows those videos are copies of, and what the user
/// watched and put on My List.
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
  factory LibraryDb.open(String path) =>
      LibraryDb._prepare(sqlite3.open(path), onDisk: true);

  /// A database that lives in memory only, for tests.
  factory LibraryDb.inMemory() =>
      LibraryDb._prepare(sqlite3.openInMemory(), onDisk: false);

  /// Opens the database at [path] as an older version of the app would have
  /// left it, with the schema at [version], to test upgrades.
  @visibleForTesting
  factory LibraryDb.openAt(String path, int version) =>
      LibraryDb._prepare(sqlite3.open(path), onDisk: true, upTo: version);

  /// How much of the file SQLite may keep in memory, in KB.
  static const pageCacheKb = 16000;

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
      _addFunctions(db);
      if (onDisk && version == 0) {
        // A new file: what is deleted later can be given back to the disk
        // a page at a time ([releaseFreeSpace]). It has to be said before
        // the first table is made.
        db.execute('PRAGMA auto_vacuum = INCREMENTAL');
      }
      if (onDisk) {
        // Readers and the writer do not block each other, and a commit does
        // not wait for the disk. A crash can lose the last few commits but
        // never damages the file; the index can be crawled again.
        db.execute('PRAGMA journal_mode = WAL');
        db.execute('PRAGMA synchronous = NORMAL');
        // SQLite keeps 2 MB of the file in memory by default, less than
        // the titles alone take, so every browse read them from the disk
        // cache again. With up to 16 MB, Home and a title page take half
        // the time on a library of 20,000 titles.
        db.execute('PRAGMA cache_size = -$pageCacheKb');
      }
      final library = LibraryDb._(db);
      for (var next = version; next < upTo; next++) {
        library.transaction(() {
          db.execute(_migrations[next]);
          db.userVersion = next + 1;
        });
      }
      if (onDisk && version > 0 && version < 5 && upTo >= 5) {
        // Version 5 threw away two large indexes and packed the cache.
        // Written anew, the file is as small as what it holds, and from
        // now on it can give free space back by itself. Done once: it
        // takes as long as copying the file.
        db
          ..execute('PRAGMA auto_vacuum = INCREMENTAL')
          ..execute('VACUUM')
          ..execute('PRAGMA wal_checkpoint(TRUNCATE)');
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
  static const schemaVersion = 5;

  final Database db;

  /// Gives the pages that deleting left empty back to the disk. Cheap when
  /// there are none; worth calling after a source was removed or a crawl
  /// dropped what a server no longer has.
  void releaseFreeSpace() => db.execute('PRAGMA incremental_vacuum');

  /// The functions the schema and the queries use; see [urlKey] and
  /// [packAnswer]. `dhara_url_key` is part of the schema (a column is made
  /// with it), so it may be called from there; the other two only from the
  /// app's own statements.
  static void _addFunctions(Database db) {
    db
      ..createFunction(
        functionName: 'dhara_url_key',
        argumentCount: const AllowedArgumentCount(1),
        deterministic: true,
        directOnly: false,
        function: (arguments) => switch (arguments[0]) {
          final String url => urlKey(url),
          _ => null,
        },
      )
      ..createFunction(
        functionName: 'dhara_pack',
        argumentCount: const AllowedArgumentCount(1),
        deterministic: true,
        function: (arguments) => switch (arguments[0]) {
          final String text => packAnswer(text),
          _ => null,
        },
      )
      ..createFunction(
        functionName: 'dhara_unpack',
        argumentCount: const AllowedArgumentCount(1),
        deterministic: true,
        function: (arguments) => switch (arguments[0]) {
          final Uint8List packed => unpackAnswer(packed),
          _ => null,
        },
      );
  }

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
const _migrations = [_schemaV1, _schemaV2, _schemaV3, _schemaV4, _schemaV5];

/// The same library in less room. Measured on 577,000 videos: 768 MB before,
/// see docs/DEVELOPMENT.md for after.
const _schemaV5 = '''
-- Finding a video by its address took an index over every address, a
-- second copy of them all (120 MB). A short number made from the address
-- finds it as well; the query then compares the address itself.
DROP INDEX files_url;
ALTER TABLE files ADD COLUMN url_key INTEGER
  GENERATED ALWAYS AS (dhara_url_key(url)) VIRTUAL;
CREATE INDEX files_url_key ON files (url_key);

-- The search index over file names kept where in a name each word stands
-- (137 MB). Which words a name has is all the search asks: a quarter of
-- the size. It cannot look for words in a row any more, so the query
-- names every word by itself.
DROP TABLE files_fts;
CREATE VIRTUAL TABLE files_fts USING fts5 (
  name,
  path,
  content = '',
  contentless_delete = 1,
  tokenize = 'unicode61 remove_diacritics 2',
  prefix = '2 3',
  detail = none
);
INSERT INTO files_fts (rowid, name, path)
SELECT f.id, f.name, d.path FROM files f JOIN folders d ON d.id = f.folder;

-- The providers' answers, deflated, and in a table of the ordinary kind:
-- as rows of an index, answers of a kilobyte each left half of every page
-- empty.
CREATE TABLE metadata_answers (
  id INTEGER PRIMARY KEY,
  provider TEXT NOT NULL,           -- 'tmdb', 'anilist'
  key TEXT NOT NULL,                -- what was asked
  body BLOB NOT NULL,               -- JSON, as dhara_pack leaves it
  fetched_at INTEGER NOT NULL,
  UNIQUE (provider, key)
) STRICT;
INSERT INTO metadata_answers (provider, key, body, fetched_at)
SELECT provider, key, dhara_pack(body), fetched_at FROM metadata_cache;
DROP TABLE metadata_cache;
ALTER TABLE metadata_answers RENAME TO metadata_cache;
''';

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

/// Who made a title, and when TMDB's details of it were read.
const _schemaV4 = '''
-- Of a film, who directed it; of a show, who created it. Names joined by
-- ", ", like genres.
ALTER TABLE titles ADD COLUMN director TEXT;
-- The first few of the cast, joined by ", ".
ALTER TABLE titles ADD COLUMN actors TEXT;
-- When TMDB's page of the title (genres, length, people) was last read;
-- NULL: never. A match alone does not bring these.
ALTER TABLE titles ADD COLUMN details_at INTEGER;
''';

/// My List, the watch history, and what Home sorts and filters by.
const _schemaV3 = '''
-- The films and shows the user put on My List.
CREATE TABLE my_list (
  title INTEGER PRIMARY KEY REFERENCES titles (id) ON DELETE CASCADE,
  added_at INTEGER NOT NULL
) STRICT;

-- What was watched: one row per video, by URL like playback, for the last
-- time it was watched. playback holds only what can be resumed; this also
-- keeps what was watched to the end.
CREATE TABLE watch_history (
  url TEXT PRIMARY KEY,
  watched_at INTEGER NOT NULL,
  position_ms INTEGER NOT NULL,     -- where it was left that time
  duration_ms INTEGER NOT NULL,
  finished INTEGER NOT NULL DEFAULT 0 CHECK (finished IN (0, 1))
) STRICT, WITHOUT ROWID;
CREATE INDEX watch_history_recent ON watch_history (watched_at);

-- What was left unfinished before there was a history.
INSERT INTO watch_history (url, watched_at, position_ms, duration_ms)
SELECT url, updated_at, position_ms, duration_ms FROM playback;

-- From a watched URL to its video, and so to its title.
CREATE INDEX files_url ON files (url);

-- Newest videos first: by the date the server gives, or else by when the
-- app first saw the file. A date later than that is a server's mistake.
CREATE INDEX files_recent
  ON files (min(ifnull(modified, added_at), added_at));

ALTER TABLE titles ADD COLUMN runtime INTEGER;   -- minutes
-- Set by hand: not a film or a show after all. Left out everywhere.
ALTER TABLE titles ADD COLUMN set_aside INTEGER NOT NULL DEFAULT 0
  CHECK (set_aside IN (0, 1));
-- Anime: AniList knows it, or it is animation from Japan.
ALTER TABLE titles ADD COLUMN is_anime INTEGER GENERATED ALWAYS AS (
  anilist_id IS NOT NULL
  OR (ifnull(language, '') = 'ja' AND instr(ifnull(genres, ''), 'Animation') > 0)
) VIRTUAL;

-- The rows of Home: the newest films or shows, and the best rated titles.
CREATE INDEX titles_newest ON titles (kind, year, votes);
CREATE INDEX titles_rated ON titles (rating, votes);
''';
