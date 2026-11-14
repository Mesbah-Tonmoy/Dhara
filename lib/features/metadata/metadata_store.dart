import 'package:dhara/core/db/library_db.dart';
import 'package:dhara/features/indexer/index_store.dart' show ftsQueryFor;
import 'package:dhara/features/metadata/release_name.dart';
import 'package:dhara/features/metadata/video_identity.dart';
import 'package:flutter/foundation.dart';
import 'package:sqlite3/sqlite3.dart';

/// A video in the index whose name has not been read yet.
@immutable
class UnreadFile {
  const UnreadFile({
    required this.id,
    required this.name,
    required this.path,
    required this.videosInFolder,
  });

  final int id;
  final String name;

  /// The folders it is in, below the source's base URL.
  final String path;
  final int videosInFolder;
}

/// How much the library holds.
@immutable
class TitleCounts {
  const TitleCounts({
    required this.movies,
    required this.shows,
    required this.otherVideos,
    required this.unreadFiles,
  });

  final int movies;
  final int shows;

  /// Videos that are neither a film nor an episode.
  final int otherVideos;

  /// Videos whose names are still to be read.
  final int unreadFiles;
}

/// A film or show found by a search. [name] is server-controlled text
/// until a provider has named the title: show it through a plain `Text`.
@immutable
class TitleHit {
  const TitleHit({
    required this.id,
    required this.kind,
    required this.name,
    required this.copies,
    this.year,
    this.posterPath,
  });

  final int id;
  final TitleKind kind;
  final String name;
  final int? year;
  final String? posterPath;

  /// How many videos of it the enabled sources hold, trailers and samples
  /// left out.
  final int copies;
}

/// One video of a title: a copy of the film, or of one of its episodes.
/// Names and paths are server-controlled text.
@immutable
class TitleCopy {
  const TitleCopy({
    required this.fileId,
    required this.sourceId,
    required this.name,
    required this.path,
    required this.url,
    this.size,
    this.season,
    this.episode,
    this.episodeEnd,
    this.episodeName,
    this.part,
    this.extra,
    this.height,
    this.source,
    this.codec,
    this.audio,
    this.languages = const [],
    this.is3d = false,
    this.group,
  });

  final int fileId;
  final String sourceId;
  final String name;
  final String path;
  final Uri url;
  final int? size;
  final int? season;
  final int? episode;
  final int? episodeEnd;
  final String? episodeName;
  final int? part;
  final ExtraKind? extra;
  final int? height;
  final VideoSource? source;
  final VideoCodec? codec;
  final MultiAudio? audio;
  final List<String> languages;
  final bool is3d;
  final String? group;
}

/// Reads and writes the part of the library database that says what the
/// indexed videos are: the titles (films and shows), which title each video
/// is a copy of, and the search over titles.
///
/// Reading the names of the files goes: [unreadFiles], `identifyVideo` for
/// each, [saveIdentities], until none are left; then
/// [removeTitlesWithoutFiles].
///
/// Every value goes into SQL as a parameter, never as text.
class MetadataStore {
  MetadataStore(
    this._library, {
    this.parserVersion = identityVersion,
    DateTime Function() now = DateTime.now,
  }) : _clock = now;

  final LibraryDb _library;
  final DateTime Function() _clock;

  /// Names read by an older version than this are read again.
  final int parserVersion;

  Database get _db => _library.db;

  late final _titleOfKey = _db.prepare(
    'SELECT title, alt_name FROM title_keys WHERE key = ?',
  );
  late final _insertTitle = _db.prepare(
    'INSERT INTO titles (kind, name, year, added_at) VALUES (?, ?, ?, ?)',
  );
  late final _insertKey = _db.prepare(
    'INSERT INTO title_keys (key, title, name, alt_name, year) '
    'VALUES (?, ?, ?, ?, ?)',
  );
  late final _setAltName = _db.prepare(
    'UPDATE title_keys SET alt_name = ? WHERE key = ?',
  );
  late final _earlierYear = _db.prepare(
    'UPDATE titles SET year = ?2 WHERE id = ?1 AND kind = 1 '
    'AND match_state = 0 AND (year IS NULL OR year > ?2)',
  );
  late final _saveMeta = _db.prepare(
    'INSERT OR REPLACE INTO file_meta (file, parser, kind, title, season, '
    'episode, episode_end, episode_name, part, extra, height, source, codec, '
    'audio, languages, is_3d, release_group) '
    'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
  );

  /// Up to [limit] videos whose names this version of the parser has not
  /// read, or whose title is gone, oldest first.
  List<UnreadFile> unreadFiles({int limit = 500}) => [
    for (final row in _db.select(
      'SELECT f.id, f.name, d.path, '
      '(SELECT count(*) FROM files g WHERE g.folder = f.folder) AS videos '
      'FROM files f JOIN folders d ON d.id = f.folder '
      'LEFT JOIN file_meta m ON m.file = f.id '
      'WHERE m.file IS NULL OR m.parser < ?1 '
      'OR (m.kind < 2 AND m.title IS NULL) '
      'ORDER BY f.id LIMIT ?2',
      [parserVersion, limit],
    ))
      UnreadFile(
        id: row['id'] as int,
        name: row['name'] as String,
        path: row['path'] as String,
        videosInFolder: row['videos'] as int,
      ),
  ];

  /// Keeps what the names of these files (by file id) say, as one
  /// transaction. Films and shows are tied to their title, which is made
  /// if this is the first copy of it. A file that is gone meanwhile is
  /// skipped.
  void saveIdentities(Map<int, VideoIdentity> identities) =>
      _library.transaction(() {
        for (final MapEntry(key: file, value: identity) in identities.entries) {
          final exists = _db.select('SELECT 1 FROM files WHERE id = ?', [file]);
          if (exists.isNotEmpty) _save(file, identity);
        }
      });

  void _save(int file, VideoIdentity identity) {
    _saveMeta.execute([
      file,
      parserVersion,
      _kindCode(identity.kind),
      _titleFor(identity),
      identity.season,
      identity.episode,
      identity.episodeEnd,
      identity.episodeTitle,
      identity.part,
      switch (identity.extra) {
        null => null,
        ExtraKind.trailer => 1,
        ExtraKind.sample => 2,
      },
      identity.height,
      identity.source?.name,
      identity.codec?.name,
      identity.audio?.name,
      identity.languages.isEmpty ? null : identity.languages.join(','),
      identity.is3d ? 1 : 0,
      identity.group,
    ]);
  }

  /// The title a film or an episode belongs to, made if need be; `null`
  /// for a video that is neither.
  int? _titleFor(VideoIdentity identity) {
    final key = identity.key;
    if (key == null) return null;
    final year = identity.year;
    final known = _titleOfKey.select([key]);
    if (known.isNotEmpty) {
      final title = known.first['title'] as int;
      if (known.first['alt_name'] == null && identity.altTitle != null) {
        _setAltName.execute([identity.altTitle, key]);
      }
      // Season folders carry the year of the season; the earliest one is
      // the best guess for the show.
      if (year != null) _earlierYear.execute([title, year]);
      return title;
    }
    _insertTitle.execute([
      _kindCode(identity.kind),
      identity.title,
      year,
      _clock().millisecondsSinceEpoch,
    ]);
    final title = _db.lastInsertRowId;
    _insertKey.execute([key, title, identity.title, identity.altTitle, year]);
    return title;
  }

  /// The answer of [provider] kept under [key], unless it is older than
  /// [maxAge].
  String? cachedAnswer(
    String provider,
    String key, {
    required Duration maxAge,
  }) {
    final rows = _db.select(
      'SELECT body, fetched_at FROM metadata_cache '
      'WHERE provider = ? AND key = ?',
      [provider, key],
    );
    if (rows.isEmpty) return null;
    final age =
        _clock().millisecondsSinceEpoch - (rows.first['fetched_at'] as int);
    // An answer from the future (the clock was set back) is not trusted
    // either.
    if (age < 0 || age > maxAge.inMilliseconds) return null;
    return rows.first['body'] as String;
  }

  /// Keeps [body] as the answer of [provider] to [key], replacing an older
  /// one.
  void cacheAnswer(String provider, String key, String body) => _db.execute(
    'INSERT OR REPLACE INTO metadata_cache '
    '(provider, key, body, fetched_at) VALUES (?, ?, ?, ?)',
    [provider, key, body, _clock().millisecondsSinceEpoch],
  );

  /// Drops the kept answers of [provider] that are older than [maxAge] and
  /// returns how many.
  int forgetAnswers(String provider, {required Duration maxAge}) {
    _db.execute(
      'DELETE FROM metadata_cache WHERE provider = ? AND fetched_at < ?',
      [provider, _clock().millisecondsSinceEpoch - maxAge.inMilliseconds],
    );
    return _db.updatedRows;
  }

  /// Removes the titles no video belongs to any more and returns how many.
  /// A title tied to its name by hand stays: its files may come back.
  int removeTitlesWithoutFiles() {
    _db.execute(
      'DELETE FROM titles WHERE '
      'NOT EXISTS (SELECT 1 FROM file_meta m WHERE m.title = titles.id) '
      'AND NOT EXISTS (SELECT 1 FROM title_keys k '
      'WHERE k.title = titles.id AND k.fixed = 1)',
    );
    return _db.updatedRows;
  }

  TitleCounts counts() {
    final row = _db.select(
      'SELECT '
      '(SELECT count(*) FROM titles WHERE kind = 0) AS movies, '
      '(SELECT count(*) FROM titles WHERE kind = 1) AS shows, '
      '(SELECT count(*) FROM file_meta WHERE kind = 2) AS other, '
      '(SELECT count(*) FROM files f LEFT JOIN file_meta m ON m.file = f.id '
      'WHERE m.file IS NULL OR m.parser < ?1 '
      'OR (m.kind < 2 AND m.title IS NULL)) AS unread',
      [parserVersion],
    ).single;
    return TitleCounts(
      movies: row['movies'] as int,
      shows: row['shows'] as int,
      otherVideos: row['other'] as int,
      unreadFiles: row['unread'] as int,
    );
  }

  /// The titles whose name contains every word of [text], best match
  /// first; the last word may be unfinished. Only titles with a video on
  /// one of the sources in [sourceIds] are returned.
  List<TitleHit> searchTitles(
    String text, {
    required Iterable<String> sourceIds,
    int limit = 50,
  }) {
    final query = ftsQueryFor(text);
    final ids = sourceIds.toList();
    if (query == null || ids.isEmpty) return const [];
    // The videos of a title on the sources asked for.
    final onSources =
        'FROM file_meta m '
        'JOIN files f ON f.id = m.file '
        'JOIN folders d ON d.id = f.folder '
        'JOIN sources s ON s.id = d.source '
        'WHERE s.source_id IN (${_placeholders(ids.length)}) AND m.title = ';
    return [
      // Copies are counted for the titles returned only, not for every
      // title that matches.
      for (final row in _db.select(
        'SELECT t.id, t.kind, t.name, t.year, t.poster_path, '
        '(SELECT count(*) ${onSources}t.id AND m.extra IS NULL) AS copies '
        'FROM (SELECT rowid AS id, rank FROM titles_fts '
        'WHERE titles_fts MATCH ? '
        'AND EXISTS (SELECT 1 ${onSources}titles_fts.rowid) '
        'ORDER BY rank LIMIT ?) hit '
        'JOIN titles t ON t.id = hit.id ORDER BY hit.rank',
        [...ids, query, ...ids, limit],
      ))
        TitleHit(
          id: row['id'] as int,
          kind: _kindOf(row['kind'] as int),
          name: row['name'] as String,
          year: row['year'] as int?,
          posterPath: row['poster_path'] as String?,
          copies: row['copies'] as int,
        ),
    ];
  }

  /// Every video of [title] on the sources in [sourceIds]: by season and
  /// episode, then by part, the sharpest picture first.
  List<TitleCopy> copiesOf(int title, {required Iterable<String> sourceIds}) {
    final ids = sourceIds.toList();
    if (ids.isEmpty) return const [];
    return [
      for (final row in _db.select(
        'SELECT f.id, f.name, f.url, f.size, d.path, s.source_id, m.season, '
        'm.episode, m.episode_end, m.episode_name, m.part, m.extra, '
        'm.height, m.source, m.codec, m.audio, m.languages, m.is_3d, '
        'm.release_group '
        'FROM file_meta m '
        'JOIN files f ON f.id = m.file '
        'JOIN folders d ON d.id = f.folder '
        'JOIN sources s ON s.id = d.source '
        'WHERE m.title = ? AND s.source_id IN (${_placeholders(ids.length)}) '
        'ORDER BY m.extra IS NOT NULL, m.season IS NULL, m.season, '
        'm.episode, m.part, m.height DESC, f.id',
        [title, ...ids],
      ))
        TitleCopy(
          fileId: row['id'] as int,
          sourceId: row['source_id'] as String,
          name: row['name'] as String,
          path: row['path'] as String,
          url: Uri.parse(row['url'] as String),
          size: row['size'] as int?,
          season: row['season'] as int?,
          episode: row['episode'] as int?,
          episodeEnd: row['episode_end'] as int?,
          episodeName: row['episode_name'] as String?,
          part: row['part'] as int?,
          extra: switch (row['extra']) {
            1 => ExtraKind.trailer,
            2 => ExtraKind.sample,
            _ => null,
          },
          height: row['height'] as int?,
          source: _byName(VideoSource.values, row['source']),
          codec: _byName(VideoCodec.values, row['codec']),
          audio: _byName(MultiAudio.values, row['audio']),
          languages: switch (row['languages']) {
            final String joined => joined.split(','),
            _ => const [],
          },
          is3d: row['is_3d'] == 1,
          group: row['release_group'] as String?,
        ),
    ];
  }
}

// The numbers the database keeps for a kind; not the order of the enum,
// which may change.
int _kindCode(TitleKind kind) => switch (kind) {
  TitleKind.movie => 0,
  TitleKind.series => 1,
  TitleKind.other => 2,
};

TitleKind _kindOf(int code) => switch (code) {
  0 => TitleKind.movie,
  1 => TitleKind.series,
  _ => TitleKind.other,
};

/// The value called [name], or `null` for a name this version of the app
/// does not know.
T? _byName<T extends Enum>(List<T> values, Object? name) {
  for (final value in values) {
    if (value.name == name) return value;
  }
  return null;
}

/// "?, ?, ?" for [count] values.
String _placeholders(int count) => List.filled(count, '?').join(', ');
