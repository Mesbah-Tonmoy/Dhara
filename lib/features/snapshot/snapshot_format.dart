/// A library snapshot: what a development build has found and matched,
/// written out for a production build to start from.
///
/// It is a gzip file of JSON lines:
///
/// - the first line is an object that names the format ([snapshotFormat],
///   [snapshotVersion]) and says how many rows follow;
/// - an object with `"table"` and `"columns"` starts the rows of one table,
///   each of which is an array of values in the order of those columns;
/// - the last line is `{"end": true, "rows": n}`, so a file that was cut
///   short is told from a whole one.
///
/// What only this PC should know stays out of it: what was watched, My
/// List, the answers of the metadata providers and the errors of crawls.
library;

const snapshotFormat = 'dhara-library-snapshot';

/// Raised when a reader of the version before could no longer make sense
/// of the file. New tables and new columns do not need it: a reader takes
/// the ones it knows.
const snapshotVersion = 1;

/// What snapshot files are called.
const snapshotFileName = 'dhara-library.snapshot.gz';

/// One table of the library as a snapshot holds it.
class SnapshotTable {
  const SnapshotTable(
    this.name,
    this.columns, {
    required this.keys,
    required this.firstKey,
    required this.count,
    required this.page,
  });

  final String name;

  /// The columns of a row, in the order they are written. The first
  /// [keys] of them are the key the table is read along.
  final List<String> columns;
  final int keys;

  /// A key below every key the table can have.
  final List<Object> firstKey;

  /// Counts the rows.
  final String count;

  /// Selects the next rows after a key, in key order: its parameters are
  /// that key and how many rows to give.
  final String page;
}

// The smallest number a column holds.
const _lowest = -9223372036854775808;

/// The tables of a snapshot, in the order they are written: a row only
/// ever points at rows of tables before its own, or at an earlier row of
/// its own table.
const snapshotTables = [
  SnapshotTable(
    'sources',
    ['id', 'source_id', 'crawl_started_at', 'crawl_finished_at'],
    keys: 1,
    firstKey: [_lowest],
    count: 'SELECT count(*) FROM sources',
    page:
        'SELECT id, source_id, crawl_started_at, crawl_finished_at '
        'FROM sources WHERE id > ? ORDER BY id LIMIT ?',
  ),
  SnapshotTable(
    'folders',
    [
      'id',
      'source',
      'parent',
      'url',
      'path',
      'modified',
      'leaf',
      'state',
      'listed_at',
    ],
    keys: 1,
    firstKey: [_lowest],
    count: 'SELECT count(*) FROM folders',
    page:
        'SELECT id, source, parent, url, path, modified, leaf, state, '
        'listed_at FROM folders WHERE id > ? ORDER BY id LIMIT ?',
  ),
  SnapshotTable(
    'files',
    // The address as the library keeps it: what follows the address of
    // the folder, or a whole address.
    ['id', 'folder', 'name', 'url', 'size', 'modified', 'added_at'],
    keys: 1,
    firstKey: [_lowest],
    count: 'SELECT count(*) FROM files',
    page:
        'SELECT id, folder, name, url, size, modified, added_at '
        'FROM files WHERE id > ? ORDER BY id LIMIT ?',
  ),
  SnapshotTable(
    'subtitles',
    ['id', 'file', 'name', 'url'],
    keys: 1,
    firstKey: [_lowest],
    count: 'SELECT count(*) FROM subtitles',
    page:
        'SELECT id, file, name, url FROM subtitles '
        'WHERE id > ? ORDER BY id LIMIT ?',
  ),
  SnapshotTable(
    'titles',
    [
      'id',
      'kind',
      'name',
      'year',
      'original_name',
      'tmdb_id',
      'anilist_id',
      'match_state',
      'confidence',
      'overview',
      'rating',
      'votes',
      'genres',
      'language',
      'poster_path',
      'backdrop_path',
      'matched_at',
      'added_at',
      'runtime',
      'set_aside',
      'director',
      'actors',
      'details_at',
    ],
    keys: 1,
    firstKey: [_lowest],
    count: 'SELECT count(*) FROM titles',
    page:
        'SELECT id, kind, name, year, original_name, tmdb_id, anilist_id, '
        'match_state, confidence, overview, rating, votes, genres, language, '
        'poster_path, backdrop_path, matched_at, added_at, runtime, '
        'set_aside, director, actors, details_at '
        'FROM titles WHERE id > ? ORDER BY id LIMIT ?',
  ),
  SnapshotTable(
    'title_keys',
    ['key', 'title', 'name', 'alt_name', 'year', 'fixed'],
    keys: 1,
    firstKey: [''],
    count: 'SELECT count(*) FROM title_keys',
    page:
        'SELECT key, title, name, alt_name, year, fixed FROM title_keys '
        'WHERE key > ? ORDER BY key LIMIT ?',
  ),
  SnapshotTable(
    'seasons',
    [
      'title',
      'season',
      'name',
      'overview',
      'poster_path',
      'air_date',
      'episode_count',
    ],
    keys: 2,
    firstKey: [_lowest, _lowest],
    count: 'SELECT count(*) FROM seasons',
    page:
        'SELECT title, season, name, overview, poster_path, air_date, '
        'episode_count FROM seasons WHERE (title, season) > (?, ?) '
        'ORDER BY title, season LIMIT ?',
  ),
  SnapshotTable(
    'episodes',
    [
      'title',
      'season',
      'episode',
      'name',
      'overview',
      'still_path',
      'air_date',
      'runtime',
    ],
    keys: 3,
    firstKey: [_lowest, _lowest, _lowest],
    count: 'SELECT count(*) FROM episodes',
    page:
        'SELECT title, season, episode, name, overview, still_path, '
        'air_date, runtime FROM episodes '
        'WHERE (title, season, episode) > (?, ?, ?) '
        'ORDER BY title, season, episode LIMIT ?',
  ),
  SnapshotTable(
    'file_meta',
    [
      'file',
      'parser',
      'kind',
      'title',
      'season',
      'episode',
      'episode_end',
      'episode_name',
      'part',
      'extra',
      'height',
      'source',
      'codec',
      'audio',
      'languages',
      'is_3d',
      'release_group',
    ],
    keys: 1,
    firstKey: [_lowest],
    count: 'SELECT count(*) FROM file_meta',
    page:
        'SELECT file, parser, kind, title, season, episode, episode_end, '
        'episode_name, part, extra, height, source, codec, audio, languages, '
        'is_3d, release_group FROM file_meta '
        'WHERE file > ? ORDER BY file LIMIT ?',
  ),
];
