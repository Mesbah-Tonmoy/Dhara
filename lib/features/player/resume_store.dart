import 'dart:async';
import 'dart:convert';

import 'package:dhara/core/db/library_db.dart';
import 'package:dhara/core/db/library_isolate.dart';
import 'package:dhara/core/settings/key_value_store.dart';
import 'package:dhara/features/history/history_store.dart';
import 'package:dhara/features/player/playback_progress.dart';
import 'package:flutter/widgets.dart';

/// Remembers where each video was left, so it can be resumed, and notes
/// what was watched in the watch history.
///
/// The positions live in the library database (table `playback`), for the
/// [maxEntries] most recently watched videos. They are also held in
/// memory, so asking for one never waits; changes are written behind.
///
/// The history (table `watch_history`, read through [HistoryStore]) is
/// written along with them: a video is in it once it was watched far
/// enough to be resumed, or to the end.
///
/// Without a library the positions last for this run only, and there is no
/// history.
class ResumeStore {
  ResumeStore([this._library, this._clock = DateTime.now]);

  static const maxEntries = 2000;

  /// Where the positions lived before the library database existed.
  static const legacyKey = 'player.resumePositions';

  final LibraryWorker? _library;
  final DateTime Function() _clock;

  // url -> (positionMs, durationMs); insertion order = least recent first.
  final _entries = <String, (int, int)>{};

  /// Reads the saved positions. Call once at start-up. Never throws.
  ///
  /// Positions still in the settings file ([legacy]) are moved to the
  /// database and then taken out of the settings. They stay there if the
  /// database cannot take them, so nothing is lost.
  Future<void> load({KeyValueStore? legacy}) async {
    final library = _library;
    final old = legacy == null ? const <_Row>[] : _legacyRows(legacy);
    var saved = const <_Row>[];
    var readable = false;
    if (library != null) {
      try {
        saved = await library.run(_readPositions, maxEntries);
        readable = true;
      } on LibraryWorkException {
        // This run starts without saved positions.
      }
    }

    // Whatever the database holds was watched after the move.
    for (final (url, position, duration) in [...old, ...saved]) {
      _entries
        ..remove(url)
        ..[url] = (position, duration);
    }
    while (_entries.length > maxEntries) {
      _entries.remove(_entries.keys.first);
    }

    if (old.isEmpty || library == null || !readable) return;
    try {
      // Their real dates are not known: just before now, in their order.
      final first = _clock().millisecondsSinceEpoch - old.length * 1000;
      await library.run(_importPositions, [
        for (final (index, (url, position, duration)) in old.indexed)
          (url, position, duration, first + index * 1000),
      ]);
      await legacy!.remove(legacyKey);
    } on LibraryWorkException {
      // Tried again at the next start.
    }
  }

  /// The position to resume [url] from, or `null` to start at the beginning.
  Duration? positionFor(Uri url) {
    final entry = _entries[_keyFor(url)];
    return entry == null ? null : Duration(milliseconds: entry.$1);
  }

  /// Records the current [position] of [url]. Positions not worth resuming
  /// (see [isResumable]) remove the entry instead; one in the credits also
  /// counts as watched to the end (see [finish]).
  void save(Uri url, {required Duration position, required Duration duration}) {
    // Unknown duration: nothing can be judged yet.
    if (duration <= Duration.zero) return;
    final key = _keyFor(url);
    if (!isResumable(position, duration)) {
      if (isWatched(position, duration)) {
        finish(url, duration: duration);
      } else if (_entries.remove(key) != null) {
        // Back in the first moments: the history keeps the last time it
        // was really watched.
        _write(_deletePosition, key);
      }
      return;
    }
    final entry = (position.inMilliseconds, duration.inMilliseconds);
    _entries
      ..remove(key)
      ..[key] = entry;
    _write(_writePosition, (
      key,
      entry.$1,
      entry.$2,
      _clock().millisecondsSinceEpoch,
    ));
    while (_entries.length > maxEntries) {
      final oldest = _entries.keys.first;
      _entries.remove(oldest);
      _write(_deletePosition, oldest);
    }
  }

  /// Notes that [url] was watched to the end: next time it starts from the
  /// beginning, and the history shows it as watched. Without a known
  /// [duration] only the position is forgotten.
  void finish(Uri url, {required Duration duration}) {
    final key = _keyFor(url);
    _entries.remove(key);
    _write(_finishVideo, (
      key,
      duration.inMilliseconds,
      _clock().millisecondsSinceEpoch,
    ));
  }

  /// Forgets where [url] was left. The history is not touched.
  void clear(Uri url) {
    final key = _keyFor(url);
    if (_entries.remove(key) != null) _write(_deletePosition, key);
  }

  /// Forgets every position, for this run: the History page empties the
  /// database itself when it clears the history.
  void clearAll() => _entries.clear();

  // The fragment never reaches the server, so it is not part of the identity.
  static String _keyFor(Uri url) => url.removeFragment().toString();

  /// Sends a change to the database without waiting for it. If it fails,
  /// the position is still right until the app closes.
  void _write<A>(LibraryWork<A, void> change, A argument) {
    final library = _library;
    if (library == null) return;
    unawaited(library.run(change, argument).then((_) {}, onError: (_) {}));
  }

  /// Reads the list that used to be kept in the settings, skipping anything
  /// that is not a well-formed row, so a damaged or hand-edited file cannot
  /// break playback.
  static List<_Row> _legacyRows(KeyValueStore store) {
    final raw = store.getString(legacyKey);
    if (raw == null) return const [];
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return const [];
    }
    if (decoded is! List) return const [];
    final rows = <_Row>[];
    for (final row in decoded) {
      if (row is! List || row.length != 3) continue;
      final [url, position, duration] = row;
      if (url is! String || position is! int || duration is! int) continue;
      if (position < 0 || duration <= 0 || position > duration) continue;
      rows.add((url, position, duration));
    }
    return rows;
  }
}

/// A saved position: URL, position and duration in milliseconds.
typedef _Row = (String, int, int);

// What follows runs in the library isolate.

/// The saved positions, least recently watched first. Rows beyond the
/// [keep] most recent ones are dropped for good, and so is the far end of
/// the history.
List<_Row> _readPositions(LibraryDb db, int keep) {
  db.db.execute(
    'DELETE FROM playback WHERE url NOT IN '
    '(SELECT url FROM playback ORDER BY updated_at DESC LIMIT ?)',
    [keep],
  );
  HistoryStore(db).trim();
  return [
    for (final row in db.db.select(
      'SELECT url, position_ms, duration_ms FROM playback ORDER BY updated_at',
    ))
      (
        row['url'] as String,
        row['position_ms'] as int,
        row['duration_ms'] as int,
      ),
  ];
}

/// Keeps a position, and the same in the history.
void _writePosition(LibraryDb db, (String, int, int, int) row) {
  final (url, position, duration, at) = row;
  db.transaction(() {
    db.db.execute(
      'INSERT INTO playback (url, position_ms, duration_ms, updated_at) '
      'VALUES (?, ?, ?, ?) ON CONFLICT (url) DO UPDATE SET '
      'position_ms = excluded.position_ms, '
      'duration_ms = excluded.duration_ms, updated_at = excluded.updated_at',
      [url, position, duration, at],
    );
    HistoryStore(db).record(
      url,
      positionMs: position,
      durationMs: duration,
      finished: false,
      at: at,
    );
  });
}

/// Forgets the position of a video (URL, duration, time) that was watched
/// to the end and notes it in the history as watched.
void _finishVideo(LibraryDb db, (String, int, int) row) {
  final (url, duration, at) = row;
  db.transaction(() {
    db.db.execute('DELETE FROM playback WHERE url = ?', [url]);
    // A video whose length never became known is not worth a row.
    if (duration <= 0) return;
    HistoryStore(db).record(
      url,
      positionMs: duration,
      durationMs: duration,
      finished: true,
      at: at,
    );
  });
}

void _deletePosition(LibraryDb db, String url) =>
    db.db.execute('DELETE FROM playback WHERE url = ?', [url]);

/// Adds positions from before the database, to the history as well; a
/// video the database already knows keeps what it has.
void _importPositions(LibraryDb db, List<(String, int, int, int)> rows) =>
    db.transaction(() {
      for (final (url, position, duration, updatedAt) in rows) {
        db.db
          ..execute(
            'INSERT OR IGNORE INTO playback '
            '(url, position_ms, duration_ms, updated_at) VALUES (?, ?, ?, ?)',
            [url, position, duration, updatedAt],
          )
          ..execute(
            'INSERT OR IGNORE INTO watch_history '
            '(url, watched_at, position_ms, duration_ms) VALUES (?, ?, ?, ?)',
            [url, updatedAt, position, duration],
          );
      }
    });

/// Makes the [ResumeStore] available to the widget tree.
class ResumeStoreScope extends InheritedWidget {
  const ResumeStoreScope({
    super.key,
    required this.store,
    required super.child,
  });

  final ResumeStore store;

  static ResumeStore of(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<ResumeStoreScope>();
    assert(scope != null, 'No ResumeStoreScope above this widget');
    return scope!.store;
  }

  @override
  bool updateShouldNotify(ResumeStoreScope oldWidget) =>
      store != oldWidget.store;
}
