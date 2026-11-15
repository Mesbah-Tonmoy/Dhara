import 'dart:async';

import 'package:dhara/core/db/library_db.dart';
import 'package:dhara/core/db/library_isolate.dart';
import 'package:dhara/features/history/history_store.dart';
import 'package:dhara/features/home/home_controller.dart';
import 'package:dhara/features/metadata/titles_controller.dart';
import 'package:dhara/features/player/resume_store.dart';
import 'package:flutter/widgets.dart';

/// The watch history as the History page shows it, and the two things the
/// page can do to it: take one video out, or empty it.
///
/// Taking a video out also forgets where it was left, here and in the
/// [ResumeStore], so that it does not come back under Continue Watching.
class HistoryController extends ChangeNotifier {
  HistoryController({
    required LibraryWorker library,
    required TitlesController titles,
    required ResumeStore resume,
    HomeController? home,
  }) : _library = library,
       _titles = titles,
       _resume = resume,
       _home = home;

  final LibraryWorker _library;
  final TitlesController _titles;
  final ResumeStore _resume;
  final HomeController? _home;

  List<HistoryItem>? _items;
  var _asked = 0;
  var _failed = false;
  var _disposed = false;

  /// What was watched, the latest first; `null` until it was read.
  List<HistoryItem>? get items => _items;

  /// The library did not answer the last time it was asked.
  bool get failed => _failed;

  /// Reads the history again. Never throws.
  Future<void> load() async {
    final number = ++_asked;
    List<HistoryItem>? items;
    try {
      items = await _library.run(_read, _enabledIds());
    } on LibraryWorkException {
      // Dealt with below.
    }
    if (_disposed || number != _asked) return;
    _failed = items == null;
    _items = items ?? _items;
    notifyListeners();
  }

  /// Takes [item] out of the history and forgets where it was left.
  Future<void> remove(HistoryItem item) async {
    final url = item.video.url;
    _items = [
      for (final other in _items ?? const <HistoryItem>[])
        if (other.video.url != url) other,
    ];
    notifyListeners();
    final address = Uri.tryParse(url);
    if (address != null) _resume.clear(address);
    await _change(_forget, url);
  }

  /// Empties the history and forgets every position.
  Future<void> clear() async {
    _items = const [];
    notifyListeners();
    _resume.clearAll();
    await _change(_forgetAll, null);
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  Future<void> _change<A>(LibraryWork<A, void> change, A argument) async {
    try {
      await _library.run(change, argument);
    } on LibraryWorkException {
      // What the page shows is right until the app closes.
    }
    // Continue Watching follows.
    unawaited(_home?.refreshContinueWatching());
  }

  List<String> _enabledIds() {
    final sources = _titles.index.sources;
    return [
      for (final source in sources.sources)
        if (sources.isEnabled(source.id)) source.id,
    ];
  }
}

/// Makes the [HistoryController] available to the widget tree.
class HistoryScope extends InheritedNotifier<HistoryController> {
  const HistoryScope({
    super.key,
    required HistoryController controller,
    required super.child,
  }) : super(notifier: controller);

  /// The controller; the calling widget rebuilds whenever it changes.
  static HistoryController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<HistoryScope>();
    assert(scope != null, 'No HistoryScope above this widget');
    return scope!.notifier!;
  }

  /// The controller, without rebuilding on changes (for event handlers).
  static HistoryController read(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<HistoryScope>();
    assert(scope != null, 'No HistoryScope above this widget');
    return scope!.notifier!;
  }
}

// What follows runs in the library isolate.

List<HistoryItem> _read(LibraryDb db, List<String> sourceIds) =>
    HistoryStore(db).items(sourceIds: sourceIds);

void _forget(LibraryDb db, String url) => HistoryStore(db).forget(url);

void _forgetAll(LibraryDb db, Object? _) => HistoryStore(db).forgetAll();
