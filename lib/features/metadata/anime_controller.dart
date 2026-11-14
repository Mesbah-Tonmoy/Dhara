import 'dart:async';

import 'package:dhara/core/db/library_db.dart';
import 'package:dhara/core/db/library_isolate.dart';
import 'package:dhara/features/metadata/anilist_client.dart';
import 'package:dhara/features/metadata/anime_store.dart';
import 'package:flutter/widgets.dart';

/// AniList's lists of anime (trending now, and this season's), with which
/// of them the library has.
///
/// The lists are fetched in the library isolate, twice a day at most, and
/// kept in the library database in between; what the library has of them
/// is worked out anew every time they are shown.
class AnimeController extends ChangeNotifier {
  AnimeController({
    required LibraryWorker library,
    Uri? aniListUrl,
    DateTime Function() clock = DateTime.now,
  }) : _library = library,
       _aniListUrl = aniListUrl,
       _clock = clock;

  final LibraryWorker _library;

  /// Where AniList is asked; only tests point this elsewhere.
  final Uri? _aniListUrl;
  final DateTime Function() _clock;

  List<AnimeRow>? _trending;
  List<AnimeRow>? _seasonal;
  String? _failure;
  Future<void>? _loading;
  var _disposed = false;

  /// The anime most talked about right now; `null` before the first load.
  List<AnimeRow>? get trending => _trending;

  /// The anime of the season under way.
  List<AnimeRow>? get seasonal => _seasonal;

  /// The season [seasonal] is about, and its year.
  AnimeSeason get season => AnimeSeason.of(_clock());
  int get seasonYear => _clock().year;

  bool get isLoading => _loading != null;

  /// Why AniList gave no answer the last time, in plain English; `null` if
  /// it did.
  String? get failure => _failure;

  /// Reads the lists, from the database if they are fresh, from AniList
  /// otherwise (or if [fresh] is asked for). Never throws.
  Future<void> load({bool fresh = false}) => _loading ??= _load(fresh);

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  Future<void> _load(bool fresh) async {
    scheduleMicrotask(_notify);
    try {
      final (trending, seasonal, failure) = await _library.run(_readLists, (
        _aniListUrl,
        fresh,
        season.index,
        seasonYear,
        _clock().millisecondsSinceEpoch,
      ));
      _trending = trending ?? _trending;
      _seasonal = seasonal ?? _seasonal;
      _failure = failure;
    } on LibraryWorkException {
      _failure = 'The lists could not be read because of an error in the app.';
    }
    _loading = null;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }
}

/// Makes the [AnimeController] available to the widget tree.
class AnimeScope extends InheritedNotifier<AnimeController> {
  const AnimeScope({
    super.key,
    required AnimeController controller,
    required super.child,
  }) : super(notifier: controller);

  /// The controller; the calling widget rebuilds whenever it changes.
  static AnimeController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AnimeScope>();
    assert(scope != null, 'No AnimeScope above this widget');
    return scope!.notifier!;
  }
}

// What follows runs in the library isolate.

/// Both lists matched against the library, and why AniList gave no answer
/// if it had to be asked and did not. A list is `null` if there is nothing
/// to show for it, not even an old one.
Future<(List<AnimeRow>?, List<AnimeRow>?, String?)> _readLists(
  LibraryDb db,
  (Uri?, bool, int, int, int) request,
) async {
  final (url, fresh, seasonIndex, year, now) = request;
  final season = AnimeSeason.values[seasonIndex];
  // The time as the controller sees it, so both agree on what is fresh.
  final store = AnimeStore(
    db,
    now: () => DateTime.fromMillisecondsSinceEpoch(now),
  );
  const trendingKey = 'trending';
  final seasonKey = 'season|${season.name}|$year';

  var trending = fresh ? null : store.keptList(trendingKey);
  var seasonal = fresh ? null : store.keptList(seasonKey);
  String? failure;
  if (trending == null || seasonal == null) {
    final client = AniListClient(url: url);
    try {
      if (trending == null) {
        trending = await client.trending();
        store.keepList(trendingKey, trending);
      }
      if (seasonal == null) {
        seasonal = await client.season(season, year);
        store.keepList(seasonKey, seasonal);
      }
    } on AniListException catch (error) {
      failure = error.message;
    } finally {
      client.close();
    }
  }
  return (
    trending == null ? null : store.match(trending),
    seasonal == null ? null : store.match(seasonal),
    failure,
  );
}
