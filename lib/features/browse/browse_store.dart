import 'package:dhara/core/db/library_db.dart';
import 'package:dhara/features/home/home_store.dart';
import 'package:dhara/features/indexer/index_store.dart' show ftsQueryFor;
import 'package:flutter/foundation.dart';
import 'package:sqlite3/sqlite3.dart';

/// Which titles a search or a browse is over.
enum BrowseKind { all, movies, series, anime }

/// The order of the results.
enum BrowseSort {
  /// How well the name fits what was typed; without text, like [newest].
  relevance,

  /// By TMDB rating, the best first.
  rating,

  /// The newest year first; within a year, the ones most people voted on.
  newest,

  /// By name, A to Z.
  name,
}

/// What is searched for, and how the results are narrowed and ordered.
@immutable
class BrowseQuery {
  const BrowseQuery({
    this.text = '',
    this.kind = BrowseKind.all,
    this.sort = BrowseSort.relevance,
    this.minHeight,
    this.minRating,
    this.year,
    this.yearOrOlder = false,
    this.genres = const {},
  });

  /// Words of the title; the last may be unfinished.
  final String text;
  final BrowseKind kind;
  final BrowseSort sort;

  /// Only titles with a video at least this sharp (picture height).
  final int? minHeight;

  /// Only titles rated at least this, out of 10.
  final double? minRating;

  /// Only titles of this year; with [yearOrOlder], of this year or before.
  final int? year;
  final bool yearOrOlder;

  /// Only titles that have every one of these genres.
  final Set<String> genres;

  /// Nothing is narrowed (what is typed aside).
  bool get hasNoFilters =>
      kind == BrowseKind.all &&
      minHeight == null &&
      minRating == null &&
      year == null &&
      genres.isEmpty;

  /// How many filters narrow the results: the type, the quality, the
  /// rating and the year as one each, and every genre.
  int get filterCount =>
      (kind == BrowseKind.all ? 0 : 1) +
      (minHeight == null ? 0 : 1) +
      (minRating == null ? 0 : 1) +
      (year == null ? 0 : 1) +
      genres.length;

  BrowseQuery copyWith({
    String? text,
    BrowseKind? kind,
    BrowseSort? sort,
    int? Function()? minHeight,
    double? Function()? minRating,
    int? Function()? year,
    bool? yearOrOlder,
    Set<String>? genres,
  }) => BrowseQuery(
    text: text ?? this.text,
    kind: kind ?? this.kind,
    sort: sort ?? this.sort,
    minHeight: minHeight == null ? this.minHeight : minHeight(),
    minRating: minRating == null ? this.minRating : minRating(),
    year: year == null ? this.year : year(),
    yearOrOlder: yearOrOlder ?? this.yearOrOlder,
    genres: genres ?? this.genres,
  );

  @override
  bool operator ==(Object other) =>
      other is BrowseQuery &&
      other.text == text &&
      other.kind == kind &&
      other.sort == sort &&
      other.minHeight == minHeight &&
      other.minRating == minRating &&
      other.year == year &&
      other.yearOrOlder == yearOrOlder &&
      setEquals(other.genres, genres);

  @override
  int get hashCode => Object.hash(
    text,
    kind,
    sort,
    minHeight,
    minRating,
    year,
    yearOrOlder,
    Object.hashAllUnordered(genres),
  );
}

/// The answer to a [BrowseQuery]: which titles, in order, and how long
/// finding them took.
@immutable
class BrowseResult {
  const BrowseResult({
    required this.ids,
    required this.total,
    required this.took,
  });

  /// The ids of the titles that fit, in the order asked for.
  final List<int> ids;

  /// How many titles there are to search among.
  final int total;
  final Duration took;
}

/// Searches and browses the titles of the library.
///
/// - Every film and show with a video on one of the sources in `sourceIds`
///   is found, also the ones TMDB does not know; only what was set aside
///   by hand is left out.
/// - A query is answered with the ids of all the titles that fit, in
///   order: a few thousand numbers at most, so the grid knows its length
///   at once. The cards are then read a screenful at a time ([cards]).
///
/// Every value goes into SQL as a parameter, never as text.
class BrowseStore {
  BrowseStore(this._library, {required Iterable<String> sourceIds})
    : _home = HomeStore(_library, sourceIds: sourceIds) {
    final ids = sourceIds.toList();
    _sources = ids.isEmpty
        ? const []
        : [
            for (final row in _db.select(
              'SELECT id FROM sources '
              'WHERE source_id IN (${_placeholders(ids.length)})',
              ids,
            ))
              row['id'] as int,
          ];
  }

  final LibraryDb _library;
  final HomeStore _home;
  late final List<int> _sources;

  Database get _db => _library.db;

  /// The titles that fit [query], and how many there are in all.
  ///
  /// Counting them all takes many times longer than a search does, so a
  /// caller that knows the number, because the library has not changed
  /// since it last asked, passes it as [knownTotal].
  BrowseResult find(BrowseQuery query, {int? knownTotal}) {
    final watch = Stopwatch()..start();
    final ids = _ids(query);
    final total =
        knownTotal ??
        (query.text.trim().isEmpty && query.hasNoFilters
            ? ids.length
            : _ids(const BrowseQuery(), countOnly: true).first);
    watch.stop();
    return BrowseResult(ids: ids, total: total, took: watch.elapsed);
  }

  /// The cards of the titles with these [ids], in that order.
  List<TitleCard> cards(List<int> ids) =>
      _home.cards(ids, whateverItsState: true);

  /// Every genre a title of the library has, A to Z.
  List<String> genres() {
    final found = <String>{};
    for (final row in _db.select(
      'SELECT DISTINCT genres FROM titles '
      'WHERE genres IS NOT NULL AND set_aside = 0',
    )) {
      found.addAll((row['genres'] as String).split(', '));
    }
    return found.toList()..sort();
  }

  /// The ids that fit [query], in its order; with [countOnly], a list of
  /// one number: how many there are.
  List<int> _ids(BrowseQuery query, {bool countOnly = false}) {
    if (_sources.isEmpty) return countOnly ? const [0] : const [];
    final where = <String>['t.set_aside = 0'];
    final parameters = <Object?>[];
    var from = 'titles t';

    final words = ftsQueryFor(query.text);
    if (words != null) {
      from =
          '(SELECT rowid AS id, rank FROM titles_fts '
          'WHERE titles_fts MATCH ?) hit CROSS JOIN titles t ON t.id = hit.id';
      parameters.add(words);
    }
    switch (query.kind) {
      case BrowseKind.all:
        break;
      case BrowseKind.movies:
        where.add('t.kind = 0');
      case BrowseKind.series:
        where.add('t.kind = 1');
      case BrowseKind.anime:
        where.add('t.is_anime = 1');
    }
    if (query.minRating case final rating?) {
      where.add('t.rating >= ?');
      parameters.add(rating);
    }
    if (query.year case final year?) {
      where.add(query.yearOrOlder ? 't.year <= ?' : 't.year = ?');
      parameters.add(year);
    }
    for (final genre in query.genres) {
      // Between separators, so that "Action" does not find "Live Action".
      where.add("instr(', ' || ifnull(t.genres, '') || ', ', ?) > 0");
      parameters.add(', $genre, ');
    }
    // On an enabled source, and sharp enough if that was asked for.
    final minHeight = query.minHeight;
    where.add(
      'EXISTS (SELECT 1 FROM file_meta m '
      'CROSS JOIN files f ON f.id = m.file '
      'CROSS JOIN folders d ON d.id = f.folder '
      'WHERE m.title = t.id AND m.extra IS NULL '
      '${minHeight == null ? '' : 'AND m.height >= ? '}'
      'AND d.source IN (${_placeholders(_sources.length)}))',
    );
    parameters.addAll([?minHeight, ..._sources]);

    final order = switch (query.sort) {
      BrowseSort.relevance when words != null => 'hit.rank, t.votes DESC',
      BrowseSort.relevance ||
      BrowseSort.newest => 't.year DESC, t.votes DESC, t.id DESC',
      BrowseSort.rating => 't.rating DESC, t.votes DESC, t.id',
      BrowseSort.name => 't.name COLLATE NOCASE, t.year, t.id',
    };
    final rows = _db.select(
      'SELECT ${countOnly ? 'count(*) AS id' : 't.id'} FROM $from '
      'WHERE ${where.join(' AND ')}'
      '${countOnly ? '' : ' ORDER BY $order'}',
      parameters,
    );
    return [for (final row in rows) row['id'] as int];
  }
}

/// "?, ?, ?" for [count] values.
String _placeholders(int count) => List.filled(count, '?').join(', ');
