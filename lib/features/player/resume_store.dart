import 'dart:async';
import 'dart:convert';

import 'package:dhara/core/settings/key_value_store.dart';
import 'package:dhara/features/player/playback_progress.dart';
import 'package:flutter/widgets.dart';

/// Remembers where each video was left, so it can be resumed.
///
/// Interim storage: one JSON value in the settings file, capped at
/// [maxEntries] (least recently watched dropped first). It moves into the
/// SQLite library database when that arrives with the indexer.
class ResumeStore {
  ResumeStore(this._store) {
    _load();
  }

  static const maxEntries = 200;
  static const _key = 'player.resumePositions';

  final KeyValueStore _store;

  // url -> [positionMs, durationMs]; insertion order = least recent first.
  final _entries = <String, (int, int)>{};

  /// The position to resume [url] from, or `null` to start at the beginning.
  Duration? positionFor(Uri url) {
    final entry = _entries[_keyFor(url)];
    return entry == null ? null : Duration(milliseconds: entry.$1);
  }

  /// Records the current [position] of [url]. Positions not worth resuming
  /// (see [isResumable]) remove the entry instead.
  void save(Uri url, {required Duration position, required Duration duration}) {
    // Unknown duration: nothing can be judged yet.
    if (duration <= Duration.zero) return;
    final key = _keyFor(url);
    if (!isResumable(position, duration)) {
      if (_entries.remove(key) != null) _persist();
      return;
    }
    _entries
      ..remove(key)
      ..[key] = (position.inMilliseconds, duration.inMilliseconds);
    while (_entries.length > maxEntries) {
      _entries.remove(_entries.keys.first);
    }
    _persist();
  }

  /// Forgets [url], e.g. after it was watched to the end.
  void clear(Uri url) {
    if (_entries.remove(_keyFor(url)) != null) _persist();
  }

  // The fragment never reaches the server, so it is not part of the identity.
  static String _keyFor(Uri url) => url.removeFragment().toString();

  void _persist() {
    final rows = [
      for (final entry in _entries.entries)
        [entry.key, entry.value.$1, entry.value.$2],
    ];
    unawaited(_store.setString(_key, jsonEncode(rows)));
  }

  /// Reads the saved list, skipping anything that is not a well-formed row,
  /// so a damaged or hand-edited file cannot break playback.
  void _load() {
    final raw = _store.getString(_key);
    if (raw == null) return;
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return;
    }
    if (decoded is! List) return;
    for (final row in decoded) {
      if (row is! List || row.length != 3) continue;
      final [url, position, duration] = row;
      if (url is! String || position is! int || duration is! int) continue;
      if (position < 0 || duration <= 0 || position > duration) continue;
      _entries[url] = (position, duration);
    }
    while (_entries.length > maxEntries) {
      _entries.remove(_entries.keys.first);
    }
  }
}

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
