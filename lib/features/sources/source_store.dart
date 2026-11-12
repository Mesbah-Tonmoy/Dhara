import 'dart:convert';
import 'dart:io';

import 'package:dhara/features/sources/source.dart';
import 'package:dhara/features/sources/source_list.dart';
import 'package:flutter/foundation.dart';

/// The sources the app knows about: the starter list with the user's own
/// changes on top, and which of them are enabled on this PC.
///
/// Only the changes are saved (added or edited sources, removed starter
/// ids, enabled ids), so a starter entry the user never touched keeps
/// following the starter list when the app is updated.
///
/// Nothing is enabled until the user, or the BDIX Tester on their behalf,
/// enables it.
class SourceStore extends ChangeNotifier {
  SourceStore({required Iterable<Source> starter, required File file})
      : _starter = {for (final source in starter) source.id: source},
        _file = file {
    _rebuild();
  }

  final Map<String, Source> _starter;
  final File _file;

  // The user's changes. `_custom` holds added sources and edited starter
  // sources (same id as the starter entry they replace).
  final _custom = <String, Source>{};
  final _removed = <String>{};
  final _enabled = <String>{};

  List<Source> _sources = const [];
  bool _savedFileWasUnreadable = false;
  Future<void> _lastWrite = Future.value();

  /// Every known source: starter order first, then the user's additions.
  List<Source> get sources => _sources;

  bool isEnabled(String id) => _enabled.contains(id);

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
    _savedFileWasUnreadable = false;
    try {
      if (await _file.exists()) {
        // Everything is checked before any of it is applied.
        final root = decodeSourceListJson(await _file.readAsString());
        final custom = sourcesFromJson(root);
        final removed = _idList(root, 'removedIds');
        final enabled = _idList(root, 'enabledIds');
        _custom.addAll({for (final source in custom) source.id: source});
        _removed.addAll(removed);
        _enabled.addAll(enabled);
      }
    } on SourceFormatException {
      await _setBrokenFileAside();
    } on FileSystemException {
      // Unreadable, or not UTF-8.
      await _setBrokenFileAside();
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

  /// Replaces the source that has the same id. Throws a
  /// [SourceFormatException] if it is not valid or the id is unknown.
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

  bool _isKnown(String id) => _sources.any((source) => source.id == id);

  Future<void> _put(Source source) {
    _removed.remove(source.id);
    // An edit back to the starter values is no longer a change.
    if (_starter[source.id] == source) {
      _custom.remove(source.id);
    } else {
      _custom[source.id] = source;
    }
    return _changed();
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
  }

  /// Writes the current changes. Writes run one after another, each through
  /// a temporary file, so the saved file is always one complete state.
  ///
  /// Completes with a [FileSystemException] if the write fails; the change
  /// then still applies until the app closes.
  Future<void> _save() {
    final text = const JsonEncoder.withIndent('  ').convert({
      ...sourcesToJson(_custom.values),
      'removedIds': _removed.toList(),
      'enabledIds': _enabled.toList(),
    });
    final write = _lastWrite.then((_) async {
      await _file.parent.create(recursive: true);
      final temp = File('${_file.path}.tmp');
      await temp.writeAsString(text, flush: true);
      await temp.rename(_file.path);
    });
    // The next write must run even if this one fails.
    _lastWrite = write.then((_) {}, onError: (Object _) {});
    return write;
  }

  Future<void> _setBrokenFileAside() async {
    _savedFileWasUnreadable = true;
    try {
      await _file.rename('${_file.path}.bad');
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
