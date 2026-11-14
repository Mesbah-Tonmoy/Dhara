import 'dart:async';

import 'package:dhara/core/db/library_db.dart';
import 'package:dhara/core/db/library_isolate.dart';
import 'package:dhara/features/metadata/match_controller.dart';
import 'package:dhara/features/metadata/match_store.dart';
import 'package:dhara/features/metadata/metadata_store.dart';
import 'package:dhara/features/metadata/review_store.dart';
import 'package:dhara/features/metadata/title_matcher.dart';
import 'package:dhara/features/metadata/titles_controller.dart';
import 'package:dhara/features/metadata/tmdb_cache.dart';
import 'package:dhara/features/metadata/tmdb_client.dart';
import 'package:dhara/features/metadata/tmdb_key.dart';
import 'package:dhara/features/metadata/video_identity.dart';
import 'package:flutter/widgets.dart';

/// What a search on TMDB by hand came back with.
@immutable
class ReviewSearch {
  const ReviewSearch(this.candidates, {this.failure});

  /// Best fit first.
  final List<ScoredCandidate> candidates;

  /// Why TMDB gave no answer, in plain English; `null` if it did.
  final String? failure;
}

/// The titles that need a look by the user, and what the user can do
/// about each: take one of TMDB's candidates, search TMDB by another name,
/// or leave the title as the files name it.
class ReviewController extends ChangeNotifier {
  ReviewController({
    required LibraryWorker library,
    required TitlesController titles,
    required MatchController match,
    required TmdbKeyController tmdbKey,
    Uri? tmdbUrl,
    int tmdbRetries = 1,
  }) : _library = library,
       _titles = titles,
       _match = match,
       _tmdbKey = tmdbKey,
       _tmdbUrl = tmdbUrl,
       _tmdbRetries = tmdbRetries;

  final LibraryWorker _library;
  final TitlesController _titles;
  final MatchController _match;
  final TmdbKeyController _tmdbKey;

  /// Where TMDB is asked; only tests point this elsewhere.
  final Uri? _tmdbUrl;
  final int _tmdbRetries;

  List<ReviewItem>? _items;
  var _disposed = false;

  /// The titles to review, as of the last [load]; `null` before the first.
  List<ReviewItem>? get items => _items;

  /// Reads the list again. Never throws.
  Future<void> load() async {
    final ids = [
      for (final source in _titles.index.sources.sources)
        if (_titles.index.sources.isEnabled(source.id)) source.id,
    ];
    try {
      _items = await _library.run(_readItems, ids);
    } on LibraryWorkException {
      _items ??= const [];
    }
    _notify();
  }

  /// The title with the id [title] as something to review, whatever its
  /// state: to put right a match from its own page. `null` if it is gone
  /// or has no video on an enabled source.
  Future<ReviewItem?> itemFor(int title) async {
    final ids = [
      for (final source in _titles.index.sources.sources)
        if (_titles.index.sources.isEnabled(source.id)) source.id,
    ];
    try {
      final found = await _library.run(_readItem, (ids, title));
      return found.isEmpty ? null : found.single;
    } on LibraryWorkException {
      return null;
    }
  }

  /// What TMDB said about [item] when it was last asked, best fit first.
  /// Makes no request.
  Future<List<ScoredCandidate>> candidatesOf(ReviewItem item) async {
    try {
      final kept = await _library.run(_keptCandidates, item);
      return rankCandidates(
        _query(item, item.spelledName, item.spelledYear),
        kept,
      );
    } on LibraryWorkException {
      return const [];
    }
  }

  /// Asks TMDB for films or shows (whichever [item] is) called [name],
  /// of [year] if one is given.
  Future<ReviewSearch> search(ReviewItem item, String name, int? year) async {
    final key = await _tmdbKey.key();
    final kind = _tmdbKey.kind;
    if (key == null || kind == null) {
      return const ReviewSearch([], failure: 'Add a TMDB key first.');
    }
    if (name.trim().isEmpty) return const ReviewSearch([]);
    try {
      final (failure, found) = await _library.run(_search, (
        key,
        kind.index,
        _tmdbUrl,
        _tmdbRetries,
        item.kind == TitleKind.series,
        name.trim(),
        year,
      ));
      return ReviewSearch(
        rankCandidates(_query(item, name, year), found),
        failure: failure,
      );
    } on LibraryWorkException {
      return const ReviewSearch([], failure: 'The search failed in the app.');
    }
  }

  /// Makes [item] the film or show [candidate], for good. If another title
  /// is that one already, the two become one.
  Future<void> choose(ReviewItem item, TmdbCandidate candidate) =>
      _settle(item, () => _library.run(_choose, (item.id, candidate)));

  /// Leaves [item] as the files name it and takes it off the list.
  Future<void> leaveAsIs(ReviewItem item) =>
      _settle(item, () => _library.run(_leaveAsIs, item.id));

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  Future<void> _settle(ReviewItem item, Future<void> Function() work) async {
    try {
      await work();
    } on LibraryWorkException {
      return;
    }
    _items = [
      for (final other in _items ?? const <ReviewItem>[])
        if (other.id != item.id) other,
    ];
    _notify();
    // The numbers on the Films and shows screen follow.
    await _match.load();
  }

  /// What to compare candidates with: the name asked by, and the name the
  /// files give the title.
  static TitleQuery _query(ReviewItem item, String name, int? year) =>
      TitleQuery(
        kind: item.kind,
        name: name,
        altName: item.altName ?? item.spelledName,
        year: year,
      );

  void _notify() {
    if (!_disposed) notifyListeners();
  }
}

/// Makes the [ReviewController] available to the widget tree.
class ReviewScope extends InheritedNotifier<ReviewController> {
  const ReviewScope({
    super.key,
    required ReviewController controller,
    required super.child,
  }) : super(notifier: controller);

  /// The controller; the calling widget rebuilds whenever it changes.
  static ReviewController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<ReviewScope>();
    assert(scope != null, 'No ReviewScope above this widget');
    return scope!.notifier!;
  }

  /// The controller, without rebuilding on changes (for event handlers).
  static ReviewController read(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<ReviewScope>();
    assert(scope != null, 'No ReviewScope above this widget');
    return scope!.notifier!;
  }
}

// What follows runs in the library isolate.

List<ReviewItem> _readItems(LibraryDb db, List<String> sourceIds) =>
    ReviewStore(db).items(sourceIds: sourceIds);

List<ReviewItem> _readItem(LibraryDb db, (List<String>, int) request) =>
    ReviewStore(db).items(sourceIds: request.$1, only: request.$2);

List<TmdbCandidate> _keptCandidates(LibraryDb db, ReviewItem item) =>
    ReviewStore(db).keptCandidates(item);

void _choose(LibraryDb db, (int, TmdbCandidate) request) {
  final (title, candidate) = request;
  MatchStore(db).apply(title, candidate, confidence: 100, byHand: true);
}

void _leaveAsIs(LibraryDb db, int title) => ReviewStore(db).leaveAsIs(title);

/// Asks TMDB and returns why it gave no answer (or `null`) and what it
/// found. The answer is kept like any other.
Future<(String?, List<TmdbCandidate>)> _search(
  LibraryDb db,
  (String, int, Uri?, int, bool, String, int?) request,
) async {
  final (key, kind, tmdbUrl, retries, isShow, name, year) = request;
  final client = TmdbClient(
    key: key,
    kind: TmdbKeyKind.values[kind],
    baseUrl: tmdbUrl,
    retries: retries,
  );
  try {
    final found = await CachedTmdb(
      client,
      MetadataStore(db),
    ).candidates(isShow ? TitleKind.series : TitleKind.movie, name, year: year);
    return (null, found);
  } on TmdbException catch (error) {
    return (error.message, const <TmdbCandidate>[]);
  } finally {
    client.close();
  }
}
