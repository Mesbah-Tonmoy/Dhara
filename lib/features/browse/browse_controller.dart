import 'dart:async';

import 'package:dhara/core/db/library_db.dart';
import 'package:dhara/core/db/library_isolate.dart';
import 'package:dhara/features/browse/browse_store.dart';
import 'package:dhara/features/home/home_controller.dart';
import 'package:dhara/features/home/home_store.dart';
import 'package:dhara/features/metadata/titles_controller.dart';
import 'package:flutter/widgets.dart';

/// Search and browse: holds what is asked for ([query]), the titles that
/// fit, and their cards as far as the grid has needed them.
///
/// It lives as long as the app, so the search field in the title bar can
/// write to it from any page and the browse page finds its filters as it
/// left them. The library is asked in its isolate: typing waits a moment
/// for the next key ([typingPause]) before it asks, a filter asks at once,
/// and only the latest answer counts. Cards are read a screenful at a time
/// as the grid scrolls ([cardAt]).
///
/// When the library changes (Home is read again), the results are too.
class BrowseController extends ChangeNotifier {
  BrowseController({
    required LibraryWorker library,
    required TitlesController titles,
    HomeController? home,
    this.typingPause = const Duration(milliseconds: 120),
  }) : _library = library,
       _titles = titles,
       _home = home {
    _home?.addListener(_onLibraryChanged);
  }

  /// How many cards are read at a time.
  static const pageSize = 60;

  final Duration typingPause;

  final LibraryWorker _library;
  final TitlesController _titles;
  final HomeController? _home;

  var _query = const BrowseQuery();
  BrowseResult? _result;
  var _genres = const <String>[];
  final _cards = <int, TitleCard>{};
  final _pagesAsked = <int>{};
  Timer? _typing;
  Object? _seenLibrary;
  var _asked = 0;
  var _started = false;
  var _loading = false;
  var _failed = false;
  var _disposed = false;

  BrowseQuery get query => _query;

  /// The answer to [query]; `null` until the first one has come.
  BrowseResult? get result => _result;

  /// How many titles fit; 0 until the first answer.
  int get count => _result?.ids.length ?? 0;

  /// Every genre there is to filter by.
  List<String> get genres => _genres;

  /// An answer is on its way.
  bool get isLoading => _loading;

  /// The library did not answer the last time it was asked.
  bool get failed => _failed;

  /// Asks for the first time, if that has not happened yet: the browse
  /// page calls it when it opens.
  void ensureLoaded() {
    if (_started) return;
    _started = true;
    _ask();
  }

  /// What was typed into the search field. Asks once typing pauses.
  void setText(String text) {
    if (text == _query.text) return;
    _query = _query.copyWith(text: text);
    _started = true;
    _typing?.cancel();
    _typing = Timer(typingPause, _ask);
    _notify();
  }

  /// Changes the filters or the order, and asks at once.
  void change(BrowseQuery Function(BrowseQuery query) change) {
    final next = change(_query);
    if (next == _query) return;
    _query = next;
    _started = true;
    _typing?.cancel();
    _ask();
  }

  /// Takes every filter off; what was typed stays.
  void resetFilters() =>
      change((query) => BrowseQuery(text: query.text, sort: query.sort));

  /// The card at place [index] of the results, or `null` while it is
  /// being read (the page it is on is asked for then).
  TitleCard? cardAt(int index) {
    final ids = _result?.ids;
    if (ids == null || index < 0 || index >= ids.length) return null;
    final card = _cards[ids[index]];
    if (card == null) _askPage(index ~/ pageSize);
    return card;
  }

  @override
  void dispose() {
    _disposed = true;
    _typing?.cancel();
    _home?.removeListener(_onLibraryChanged);
    super.dispose();
  }

  /// Home was read again: the library may hold other titles now.
  void _onLibraryChanged() {
    final home = _home;
    if (home == null || home.isLoading || !_started) return;
    final rows = home.content?.movies;
    if (identical(rows, _seenLibrary)) return;
    _seenLibrary = rows;
    _ask();
  }

  Future<void> _ask() async {
    final number = ++_asked;
    final query = _query;
    _loading = true;
    // Not at once: the page may be asking while it is being built.
    scheduleMicrotask(_notify);
    BrowseResult? result;
    List<String>? genres;
    try {
      (result, genres) = await _library.run(_find, (query, _enabledIds()));
    } on LibraryWorkException {
      // Dealt with below.
    }
    // A later question was asked meanwhile: its answer is the one.
    if (_disposed || number != _asked) return;
    _loading = false;
    _failed = result == null;
    if (result != null) {
      _result = result;
      _genres = genres ?? _genres;
      // Cards may have changed with the library; they are read again.
      _cards.clear();
      _pagesAsked.clear();
    }
    _notify();
  }

  Future<void> _askPage(int page) async {
    if (!_pagesAsked.add(page)) return;
    final number = _asked;
    final ids = _result!.ids;
    final start = page * pageSize;
    final wanted = ids.sublist(start, (start + pageSize).clamp(0, ids.length));
    try {
      final cards = await _library.run(_readCards, (wanted, _enabledIds()));
      // For an answer that has been replaced meanwhile.
      if (_disposed || number != _asked) return;
      for (final card in cards) {
        _cards[card.id] = card;
      }
      // A title that is gone meanwhile leaves its place empty for good:
      // marked, so that it is not asked for with every frame.
      _notify();
    } on LibraryWorkException {
      if (number == _asked) _pagesAsked.remove(page);
    }
  }

  List<String> _enabledIds() {
    final sources = _titles.index.sources;
    return [
      for (final source in sources.sources)
        if (sources.isEnabled(source.id)) source.id,
    ];
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }
}

/// Makes the [BrowseController] available to the widget tree.
class BrowseScope extends InheritedNotifier<BrowseController> {
  const BrowseScope({
    super.key,
    required BrowseController controller,
    required super.child,
  }) : super(notifier: controller);

  /// The controller; the calling widget rebuilds whenever it changes.
  static BrowseController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<BrowseScope>();
    assert(scope != null, 'No BrowseScope above this widget');
    return scope!.notifier!;
  }

  /// The controller, without rebuilding on changes (for event handlers).
  static BrowseController read(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<BrowseScope>();
    assert(scope != null, 'No BrowseScope above this widget');
    return scope!.notifier!;
  }
}

// What follows runs in the library isolate.

(BrowseResult, List<String>) _find(
  LibraryDb db,
  (BrowseQuery, List<String>) request,
) {
  final (query, sourceIds) = request;
  final store = BrowseStore(db, sourceIds: sourceIds);
  return (store.find(query), store.genres());
}

List<TitleCard> _readCards(LibraryDb db, (List<int>, List<String>) request) {
  final (ids, sourceIds) = request;
  return BrowseStore(db, sourceIds: sourceIds).cards(ids);
}
