import 'dart:convert';
import 'dart:io';

import 'package:dhara/features/sources/source.dart';
import 'package:dhara/features/sources/source_list.dart';
import 'package:flutter/foundation.dart';

/// What the last test of a source found from this connection.
@immutable
class SourceHealth {
  const SourceHealth({
    required this.checkedAt,
    required this.reachable,
    required this.readable,
    this.ping,
  });

  final DateTime checkedAt;

  /// The server answered.
  final bool reachable;

  /// The app could also read its content (see `SourceTestResult.readable`).
  final bool readable;
  final Duration? ping;

  Map<String, Object?> toJson() => {
        'checkedAt': checkedAt.toUtc().toIso8601String(),
        'reachable': reachable,
        'readable': readable,
        'pingMs': ping?.inMilliseconds,
      };

  /// Reads a saved entry, or returns `null` if it is not well formed.
  static SourceHealth? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final checkedAt = json['checkedAt'];
    final reachable = json['reachable'];
    final readable = json['readable'];
    final pingMs = json['pingMs'];
    final time = checkedAt is String ? DateTime.tryParse(checkedAt) : null;
    if (time == null || reachable is! bool || readable is! bool) return null;
    return SourceHealth(
      checkedAt: time.toLocal(),
      reachable: reachable,
      readable: readable && reachable,
      ping:
          pingMs is int && pingMs >= 0 ? Duration(milliseconds: pingMs) : null,
    );
  }
}

/// What importing a source list would change.
class SourceImportPreview {
  const SourceImportPreview({
    required this.added,
    required this.changed,
    required this.unchanged,
  });

  /// Sources with an id the app does not know yet.
  final List<Source> added;

  /// Sources that would replace a known one with the same id.
  final List<Source> changed;

  /// How many are already known exactly as they are.
  final int unchanged;

  bool get changesNothing => added.isEmpty && changed.isEmpty;
}

/// The sources the app knows about: the starter list with the user's own
/// changes on top, which of them are enabled on this PC, and what the last
/// test of each found.
///
/// Only the changes are saved (added or edited sources, removed starter
/// ids, enabled ids), so a starter entry the user never touched keeps
/// following the starter list when the app is updated.
///
/// Nothing is enabled until the user, or the BDIX Tester on their behalf,
/// enables it.
///
/// Without a [File] the changes are kept in memory only, for this run: the
/// fallback when the app's data folder is not available.
class SourceStore extends ChangeNotifier {
  SourceStore({required Iterable<Source> starter, File? file})
      : _starter = {for (final source in starter) source.id: source},
        _file = file {
    _rebuild();
  }

  final Map<String, Source> _starter;
  final File? _file;

  // The user's changes. `_custom` holds added sources and edited starter
  // sources (same id as the starter entry they replace).
  final _custom = <String, Source>{};
  final _removed = <String>{};
  final _enabled = <String>{};
  final _health = <String, SourceHealth>{};

  List<Source> _sources = const [];
  bool _savedFileWasUnreadable = false;
  Future<void> _lastWrite = Future.value();

  /// Every known source: starter order first, then the user's additions.
  List<Source> get sources => _sources;

  bool isEnabled(String id) => _enabled.contains(id);

  /// What the last test of this source found, if it was ever tested.
  SourceHealth? healthOf(String id) => _health[id];

  /// Every known source as a source list, ready to be saved to a file.
  /// Which sources are enabled is not part of it: that depends on the
  /// connection.
  String exportJson() =>
      const JsonEncoder.withIndent('  ').convert(sourcesToJson(_sources));

  /// True when the saved file could not be used by the last [load]. The
  /// file was set aside as `<name>.bad` and the starter list is in effect.
  bool get savedFileWasUnreadable => _savedFileWasUnreadable;

  /// Reads the user's saved changes. Call once at start-up.
  ///
  /// Never throws: a missing file means "no changes yet", and a damaged one
  /// is set aside (see [savedFileWasUnreadable]).
  Future<void> load() async {
    _custom.clear();
    _removed.clear();
    _enabled.clear();
    _health.clear();
    _savedFileWasUnreadable = false;
    final file = _file;
    try {
      if (file != null && await file.exists()) {
        // Everything is checked before any of it is applied.
        final root = decodeSourceListJson(await file.readAsString());
        final custom = sourcesFromJson(root);
        final removed = _idList(root, 'removedIds');
        final enabled = _idList(root, 'enabledIds');
        _custom.addAll({for (final source in custom) source.id: source});
        _removed.addAll(removed);
        _enabled.addAll(enabled);
        // Test results are only a convenience: bad entries are skipped
        // instead of rejecting the user's sources with them.
        final health = root['health'];
        if (health is Map<String, dynamic>) {
          for (final MapEntry(:key, :value) in health.entries) {
            final entry = SourceHealth.fromJson(value);
            if (entry != null) _health[key] = entry;
          }
        }
      }
    } on SourceFormatException {
      await _setBrokenFileAside(file!);
    } on FileSystemException {
      // Unreadable, or not UTF-8.
      await _setBrokenFileAside(file!);
    }
    _rebuild();
    notifyListeners();
  }

  /// Adds a new source (not enabled). Throws a [SourceFormatException] if
  /// it is not valid or its id is taken.
  Future<void> add(Source source) async {
    final checked = sourceFromJson(source.toJson());
    if (_isKnown(checked.id)) {
      throw const SourceFormatException(
        'source.id: another source already uses this id.',
      );
    }
    await _put(checked);
  }

  /// Replaces the source that has the same id; it stays enabled if it was.
  /// Throws a [SourceFormatException] if it is not valid or the id is
  /// unknown.
  Future<void> update(Source source) async {
    final checked = sourceFromJson(source.toJson());
    if (!_isKnown(checked.id)) {
      throw const SourceFormatException('source.id: no source has this id.');
    }
    await _put(checked);
  }

  /// Removes a source. An unknown [id] is ignored.
  Future<void> remove(String id) {
    if (!_isKnown(id)) return Future.value();
    _custom.remove(id);
    // A starter source would come back on the next load, so remember it.
    if (_starter.containsKey(id)) _removed.add(id);
    _enabled.remove(id);
    return _changed();
  }

  /// Enables or disables the sources with these [ids]; unknown ids are
  /// ignored.
  Future<void> setEnabled(Iterable<String> ids, {required bool enabled}) {
    var changed = false;
    for (final id in ids) {
      if (!_isKnown(id)) continue;
      changed |= enabled ? _enabled.add(id) : _enabled.remove(id);
    }
    return changed ? _changed() : Future.value();
  }

  /// What [importSources] would do with [incoming], without doing it.
  SourceImportPreview previewImport(Iterable<Source> incoming) {
    final known = {for (final source in _sources) source.id: source};
    final added = <Source>[];
    final changed = <Source>[];
    var unchanged = 0;
    for (final source in incoming) {
      final current = known[source.id];
      if (current == null) {
        added.add(source);
      } else if (current != source) {
        changed.add(source);
      } else {
        unchanged++;
      }
    }
    return SourceImportPreview(
      added: added,
      changed: changed,
      unchanged: unchanged,
    );
  }

  /// Takes over a source list (as read by `parseSourceList`): new ids are
  /// added, known ids are replaced. Nothing gets enabled by an import, and
  /// a replaced source is switched off until it has been tested again, so
  /// a list from elsewhere cannot point an enabled source somewhere new.
  Future<void> importSources(Iterable<Source> incoming) {
    final preview = previewImport(incoming);
    if (preview.changesNothing) return Future.value();
    for (final source in preview.changed) {
      _enabled.remove(source.id);
    }
    for (final source in [...preview.added, ...preview.changed]) {
      _apply(source);
    }
    return _changed();
  }

  /// Remembers test results, keyed by source id; unknown ids are ignored.
  Future<void> recordHealth(Map<String, SourceHealth> results) {
    if (results.isEmpty) return Future.value();
    _health.addAll(results);
    return _changed();
  }

  bool _isKnown(String id) => _sources.any((source) => source.id == id);

  Future<void> _put(Source source) {
    _apply(source);
    return _changed();
  }

  void _apply(Source source) {
    _removed.remove(source.id);
    // After a change, the last test was of the old addresses.
    final current = _custom[source.id] ?? _starter[source.id];
    if (current != source) _health.remove(source.id);
    // An edit back to the starter values is no longer a change.
    if (_starter[source.id] == source) {
      _custom.remove(source.id);
    } else {
      _custom[source.id] = source;
    }
  }

  Future<void> _changed() {
    _rebuild();
    notifyListeners();
    return _save();
  }

  /// Recomputes [sources], dropping saved changes that no longer apply
  /// (for example after the starter list itself changed).
  void _rebuild() {
    _custom.removeWhere((id, source) => _starter[id] == source);
    _removed.removeWhere(
      (id) => !_starter.containsKey(id) || _custom.containsKey(id),
    );
    _sources = List.unmodifiable([
      for (final source in _starter.values)
        if (!_removed.contains(source.id)) _custom[source.id] ?? source,
      for (final source in _custom.values)
        if (!_starter.containsKey(source.id)) source,
    ]);
    final known = {for (final source in _sources) source.id};
    _enabled.removeWhere((id) => !known.contains(id));
    _health.removeWhere((id, _) => !known.contains(id));
  }

  /// Writes the current changes. Writes run one after another, each through
  /// a temporary file, so the saved file is always one complete state.
  ///
  /// Completes with a [FileSystemException] if the write fails; the change
  /// then still applies until the app closes.
  Future<void> _save() {
    final file = _file;
    if (file == null) return Future.value();
    final text = const JsonEncoder.withIndent('  ').convert({
      ...sourcesToJson(_custom.values),
      'removedIds': _removed.toList(),
      'enabledIds': _enabled.toList(),
      'health': {
        for (final MapEntry(:key, :value) in _health.entries)
          key: value.toJson(),
      },
    });
    final write = _lastWrite.then((_) async {
      await file.parent.create(recursive: true);
      final temp = File('${file.path}.tmp');
      await temp.writeAsString(text, flush: true);
      await temp.rename(file.path);
    });
    // The next write must run even if this one fails.
    _lastWrite = write.then((_) {}, onError: (Object _) {});
    return write;
  }

  Future<void> _setBrokenFileAside(File file) async {
    _savedFileWasUnreadable = true;
    try {
      await file.rename('${file.path}.bad');
    } on FileSystemException {
      // Best effort: the next save replaces the file either way.
    }
  }
}

List<String> _idList(Map<String, dynamic> root, String key) {
  final value = root[key];
  if (value == null) return const [];
  if (value is! List || value.any((id) => id is! String)) {
    throw SourceFormatException('"$key" must be a list of ids.');
  }
  return value.cast<String>();
}
