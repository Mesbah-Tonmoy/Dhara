import 'package:dhara/core/db/library_db.dart';
import 'package:flutter/foundation.dart';
import 'package:sqlite3/sqlite3.dart';

/// A video that was watched, as the history keeps it: the last time only.
@immutable
class WatchedVideo {
  const WatchedVideo({
    required this.url,
    required this.watchedAt,
    required this.position,
    required this.duration,
    required this.finished,
  });

  /// As it was played; server-controlled text.
  final String url;
  final DateTime watchedAt;

  /// Where it was left that time; the whole [duration] if it was watched
  /// to the end.
  final Duration position;
  final Duration duration;
  final bool finished;
}

/// Reads and writes the watch history in the library database: which
/// videos were watched, when, and how far.
///
/// The player writes it together with the resume positions (see
/// `ResumeStore`). A video is known by its URL, so one played from a
/// pasted address is kept too.
///
/// Every value goes into SQL as a parameter, never as text.
class HistoryStore {
  HistoryStore(this._library, {DateTime Function() now = DateTime.now})
    : _clock = now;

  /// How many videos the history keeps; older ones are dropped by [trim].
  static const maxEntries = 5000;

  final LibraryDb _library;
  final DateTime Function() _clock;

  Database get _db => _library.db;

  /// Notes that [url] was watched just now (or [at]) up to [positionMs];
  /// replaces what was known about it.
  void record(
    String url, {
    required int positionMs,
    required int durationMs,
    required bool finished,
    int? at,
  }) => _db.execute(
    'INSERT INTO watch_history '
    '(url, watched_at, position_ms, duration_ms, finished) '
    'VALUES (?1, ?2, ?3, ?4, ?5) ON CONFLICT (url) DO UPDATE SET '
    'watched_at = excluded.watched_at, position_ms = excluded.position_ms, '
    'duration_ms = excluded.duration_ms, finished = excluded.finished',
    [
      url,
      at ?? _clock().millisecondsSinceEpoch,
      // Watched to the end: nothing is left of it.
      if (finished) durationMs else positionMs,
      durationMs,
      if (finished) 1 else 0,
    ],
  );

  /// What was watched, the latest first.
  List<WatchedVideo> entries({int limit = 100, int offset = 0}) => [
    for (final row in _db.select(
      'SELECT url, watched_at, position_ms, duration_ms, finished '
      'FROM watch_history ORDER BY watched_at DESC, url LIMIT ? OFFSET ?',
      [limit, offset],
    ))
      WatchedVideo(
        url: row['url'] as String,
        watchedAt: DateTime.fromMillisecondsSinceEpoch(
          row['watched_at'] as int,
        ),
        position: Duration(milliseconds: row['position_ms'] as int),
        duration: Duration(milliseconds: row['duration_ms'] as int),
        finished: row['finished'] == 1,
      ),
  ];

  int count() =>
      _db.select('SELECT count(*) AS n FROM watch_history').single['n'] as int;

  /// Takes [url] out of the history. Its resume position is not touched.
  void remove(String url) =>
      _db.execute('DELETE FROM watch_history WHERE url = ?', [url]);

  /// Empties the history. Resume positions are not touched.
  void clear() => _db.execute('DELETE FROM watch_history');

  /// Drops all but the [keep] most recently watched videos and returns
  /// how many were dropped.
  int trim({int keep = maxEntries}) {
    _db.execute(
      'DELETE FROM watch_history WHERE url NOT IN '
      '(SELECT url FROM watch_history ORDER BY watched_at DESC LIMIT ?)',
      [keep],
    );
    return _db.updatedRows;
  }
}
