import 'dart:async';

import 'package:dhara/core/db/library_db.dart';
import 'package:dhara/core/db/library_isolate.dart';
import 'package:dhara/features/home/home_store.dart';
import 'package:dhara/features/metadata/match_controller.dart';
import 'package:dhara/features/metadata/titles_controller.dart';
import 'package:dhara/features/sources/source_store.dart';
import 'package:flutter/widgets.dart';

/// Holds what Home shows, read from the library database in its isolate.
///
/// It lives as long as the app, so Home opens with what was read last and
/// never waits. It reads again by itself whenever what it shows may have
/// changed: sources were switched on or off, the names of new videos were
/// read, or titles were matched. While titles are being matched (which
/// takes minutes and changes something every moment) it reads at most once
/// every [pause].
class HomeController extends ChangeNotifier {
  HomeController({
    required LibraryWorker library,
    required TitlesController titles,
    required MatchController match,
    this.pause = const Duration(seconds: 12),
    DateTime Function() now = DateTime.now,
  }) : _library = library,
       _titles = titles,
       _match = match,
       _clock = now {
    _sources.addListener(_onChange);
    _titles.addListener(_onChange);
    _match.addListener(_onChange);
  }

  /// The shortest time between two reads that nobody asked for.
  final Duration pause;

  final LibraryWorker _library;
  final TitlesController _titles;
  final MatchController _match;
  final DateTime Function() _clock;

  HomeContent? _content;
  Future<void>? _load;
  String? _loadedFor;
  DateTime? _loadedAt;
  Timer? _later;
  var _failed = false;
  var _disposed = false;

  SourceStore get _sources => _titles.index.sources;

  /// What Home shows; `null` until it was read for the first time.
  HomeContent? get content => _content;

  /// It is being read right now.
  bool get isLoading => _load != null;

  /// The last read failed: the library database did not answer.
  bool get failed => _failed;

  /// Reads everything again and completes when that is done; while a read
  /// is under way this only waits for it. Never throws.
  Future<void> refresh() => _load ??= _read();

  /// Reads the Continue Watching row again, after something was played.
  /// Never throws.
  Future<void> refreshContinueWatching() async {
    // A full read under way may have looked before the video was played.
    await _load;
    final content = _content;
    if (content == null) return refresh();
    try {
      final items = await _library.run(_readContinue, _enabledIds());
      if (_disposed) return;
      _content = HomeContent(
        featured: content.featured,
        continueWatching: items,
        recentlyAdded: content.recentlyAdded,
        movies: content.movies,
        series: content.series,
        anime: content.anime,
        topRated: content.topRated,
      );
      notifyListeners();
    } on LibraryWorkException {
      // The row stays as it was.
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _later?.cancel();
    _sources.removeListener(_onChange);
    _titles.removeListener(_onChange);
    _match.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (_disposed || isLoading || _state() == _loadedFor) return;
    // While names are being read every batch changes the counts; the end
    // of the pass is what counts.
    if (_titles.isReading) return;
    final last = _loadedAt;
    final wait = last == null || !_match.isRunning
        ? Duration.zero
        : pause - _clock().difference(last);
    _later?.cancel();
    if (wait <= Duration.zero) {
      unawaited(refresh());
    } else {
      _later = Timer(wait, _onChange);
    }
  }

  Future<void> _read() async {
    final state = _state();
    // Lets the caller's `_load` be set before anyone is told.
    scheduleMicrotask(_notify);
    try {
      _content = await _library.run(_readHome, (
        _enabledIds(),
        _clock().millisecondsSinceEpoch,
      ));
      _failed = false;
    } on LibraryWorkException {
      _failed = true;
    } finally {
      // Also after a failure: the next change tries again, not every
      // notification in between.
      _loadedFor = state;
      _loadedAt = _clock();
      _load = null;
      _notify();
    }
    // Something changed while it was being read.
    if (!_disposed) _onChange();
  }

  /// What Home depends on, as far as this can tell without asking the
  /// database: a change means it may show something else.
  String _state() {
    final counts = _titles.counts;
    final matched = _match.counts;
    return [
      _enabledIds().join(','),
      counts?.movies,
      counts?.shows,
      matched?.matched,
      matched?.unsure,
      matched?.notFound,
      matched?.byHand,
    ].join('|');
  }

  List<String> _enabledIds() => [
    for (final source in _sources.sources)
      if (_sources.isEnabled(source.id)) source.id,
  ];

  void _notify() {
    if (!_disposed) notifyListeners();
  }
}

/// Makes the [HomeController] available to the widget tree.
class HomeScope extends InheritedNotifier<HomeController> {
  const HomeScope({
    super.key,
    required HomeController controller,
    required super.child,
  }) : super(notifier: controller);

  /// The controller; the calling widget rebuilds whenever it changes.
  static HomeController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<HomeScope>();
    assert(scope != null, 'No HomeScope above this widget');
    return scope!.notifier!;
  }

  /// The controller, without rebuilding on changes (for event handlers).
  static HomeController read(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<HomeScope>();
    assert(scope != null, 'No HomeScope above this widget');
    return scope!.notifier!;
  }
}

// What follows runs in the library isolate.

HomeContent _readHome(LibraryDb db, (List<String>, int) request) {
  final (sourceIds, now) = request;
  return HomeStore(
    db,
    sourceIds: sourceIds,
  ).content(today: DateTime.fromMillisecondsSinceEpoch(now));
}

List<ContinueItem> _readContinue(LibraryDb db, List<String> sourceIds) =>
    HomeStore(db, sourceIds: sourceIds).continueWatching();
