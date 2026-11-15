import 'package:dhara/core/db/library_db.dart';
import 'package:dhara/features/metadata/title_matcher.dart';
import 'package:dhara/features/metadata/tmdb_client.dart';
import 'package:dhara/features/metadata/video_identity.dart';
import 'package:flutter/foundation.dart';
import 'package:sqlite3/sqlite3.dart';

/// A title TMDB has not been asked about yet.
@immutable
class PendingTitle {
  const PendingTitle({
    required this.id,
    required this.kind,
    required this.name,
    this.altName,
    this.year,
  });

  final int id;
  final TitleKind kind;

  /// As the folder or file spells it.
  final String name;
  final String? altName;
  final int? year;

  TitleQuery get query =>
      TitleQuery(kind: kind, name: name, altName: altName, year: year);
}

/// How many titles are in which state of being matched.
@immutable
class MatchCounts {
  const MatchCounts({
    this.pending = 0,
    this.matched = 0,
    this.unsure = 0,
    this.notFound = 0,
    this.byHand = 0,
  });

  /// Not looked up yet.
  final int pending;
  final int matched;

  /// Matched, but put up for review.
  final int unsure;
  final int notFound;

  /// Matched, or left as they are, by the user.
  final int byHand;

  /// TMDB has been asked about these before.
  int get lookedUp => matched + unsure + notFound;

  /// What the Needs review screen lists.
  int get toReview => unsure + notFound;
}

/// What became of a title that was matched.
enum MatchOutcome {
  /// It carries the film's or show's data now.
  matched,

  /// Another title is that film or show already: the two are one now.
  merged,

  /// Matched, with data, but put up for review.
  unsure,

  /// Would be another title's film, and not sure enough to make them one.
  unsureNotApplied,

  /// The title is gone, or of the other kind.
  skipped,
}

/// The states `titles.match_state` takes.
abstract final class MatchState {
  static const pending = 0;
  static const matched = 1;
  static const unsure = 2;
  static const notFound = 3;
  static const byHand = 4;
  static const leftAlone = 5;
}

/// Reads and writes the part of the library database that ties titles to
/// what TMDB knows as films and shows.
///
/// Every value goes into SQL as a parameter, never as text.
class MatchStore {
  MatchStore(this._library, {DateTime Function() now = DateTime.now})
    : _clock = now;

  final LibraryDb _library;
  final DateTime Function() _clock;

  Database get _db => _library.db;
  int get _now => _clock().millisecondsSinceEpoch;

  /// Up to [limit] titles that have not been looked up, with an id above
  /// [after], lowest id first. Titles without a video are left out.
  List<PendingTitle> pendingTitles({int after = 0, int limit = 40}) => [
    for (final row in _db.select(
      'SELECT t.id, t.kind, t.name, t.year, '
      '(SELECT k.alt_name FROM title_keys k WHERE k.title = t.id '
      'AND k.alt_name IS NOT NULL ORDER BY k.key LIMIT 1) AS alt '
      'FROM titles t WHERE t.match_state = 0 AND t.id > ? '
      'AND EXISTS (SELECT 1 FROM file_meta m WHERE m.title = t.id) '
      'ORDER BY t.id LIMIT ?',
      [after, limit],
    ))
      PendingTitle(
        id: row['id'] as int,
        kind: row['kind'] == 1 ? TitleKind.series : TitleKind.movie,
        name: row['name'] as String,
        altName: row['alt'] as String?,
        year: row['year'] as int?,
      ),
  ];

  /// Up to [limit] titles that are unsure or were not found, with an id
  /// above [after], lowest id first: by the name and year their files give
  /// them, which is what TMDB was asked by.
  List<PendingTitle> reviewableTitles({int after = 0, int limit = 200}) => [
    for (final row in _db.select(
      'SELECT t.id, t.kind, k.name, k.year, k.alt_name FROM titles t '
      // The first of its spellings stands for the title.
      'JOIN title_keys k ON k.key = (SELECT min(key) FROM title_keys '
      'WHERE title = t.id) '
      'WHERE t.match_state IN (2, 3) AND t.id > ? '
      'AND EXISTS (SELECT 1 FROM file_meta m WHERE m.title = t.id) '
      'ORDER BY t.id LIMIT ?',
      [after, limit],
    ))
      PendingTitle(
        id: row['id'] as int,
        kind: row['kind'] == 1 ? TitleKind.series : TitleKind.movie,
        name: row['name'] as String,
        altName: row['alt_name'] as String?,
        year: row['year'] as int?,
      ),
  ];

  /// Lets titles that were not found more than [after] ago be looked up
  /// again: films appear on TMDB later than on the servers. Returns how
  /// many.
  int retryNotFound({Duration after = const Duration(days: 30)}) {
    _db.execute(
      'UPDATE titles SET match_state = 0 '
      'WHERE match_state = 3 AND matched_at < ?',
      [_now - after.inMilliseconds],
    );
    return _db.updatedRows;
  }

  /// Notes that TMDB has nothing that fits [title]. [confidence] is that
  /// of the best candidate, if there was one.
  void markNotFound(int title, {int? confidence}) => _db.execute(
    'UPDATE titles SET match_state = 3, confidence = ?, matched_at = ? '
    'WHERE id = ? AND match_state = 0',
    [confidence, _now, title],
  );

  /// Makes [title] the film or show [candidate]. Returns what became of
  /// it, and the id it has now (another one after a merge).
  ///
  /// At [sureConfidence] or above, or [byHand], the match is final: if
  /// another title is that film already, the two become one (the videos
  /// and the spellings of [title] move over). Below, the title gets the
  /// data but is put up for review, and is never merged.
  ///
  /// [byHand] also ties the spellings of the title to it for good, so no
  /// later pass changes it.
  (MatchOutcome, int) apply(
    int title,
    TmdbCandidate candidate, {
    required int confidence,
    bool byHand = false,
  }) => _library.transaction(() {
    final kind = candidate.kind == TitleKind.series ? 1 : 0;
    final own = _db.select('SELECT kind FROM titles WHERE id = ?', [title]);
    if (own.isEmpty || own.single['kind'] != kind) {
      return (MatchOutcome.skipped, title);
    }
    final sure = byHand || confidence >= sureConfidence;
    final same = _db.select(
      'SELECT id, match_state FROM titles '
      'WHERE kind = ? AND tmdb_id = ? AND id != ?',
      [kind, candidate.id, title],
    );

    if (same.isNotEmpty) {
      if (!sure) {
        _db.execute(
          'UPDATE titles SET match_state = 2, confidence = ?, '
          'matched_at = ? WHERE id = ?',
          [confidence, _now, title],
        );
        return (MatchOutcome.unsureNotApplied, title);
      }
      final other = same.single['id'] as int;
      _db
        ..execute('UPDATE file_meta SET title = ? WHERE title = ?', [
          other,
          title,
        ])
        ..execute('UPDATE title_keys SET title = ? WHERE title = ?', [
          other,
          title,
        ])
        // On My List under either name: the film stays on it.
        ..execute(
          'INSERT OR IGNORE INTO my_list (title, added_at) '
          'SELECT ?, added_at FROM my_list WHERE title = ?',
          [other, title],
        )
        ..execute('DELETE FROM titles WHERE id = ?', [title]);
      if (byHand) {
        _db
          ..execute(
            'UPDATE titles SET match_state = 4, confidence = 100 '
            'WHERE id = ?',
            [other],
          )
          ..execute('UPDATE title_keys SET fixed = 1 WHERE title = ?', [other]);
      } else if (same.single['match_state'] == MatchState.unsure) {
        // What was unsure about the other one is settled by this one.
        _db.execute(
          'UPDATE titles SET match_state = 1, confidence = ? WHERE id = ?',
          [confidence, other],
        );
      }
      return (MatchOutcome.merged, other);
    }

    _db.execute(
      'UPDATE titles SET name = ?, original_name = ?, year = ?, '
      'tmdb_id = ?, match_state = ?, confidence = ?, overview = ?, '
      'rating = ?, votes = ?, language = ?, poster_path = ?, '
      'backdrop_path = ?, matched_at = ?, '
      // Another film or show than before: its page is to be read again.
      'details_at = CASE WHEN tmdb_id IS ?4 THEN details_at END '
      'WHERE id = ?',
      [
        candidate.title,
        candidate.originalTitle,
        candidate.year,
        candidate.id,
        if (byHand)
          MatchState.byHand
        else
          sure ? MatchState.matched : MatchState.unsure,
        byHand ? 100 : confidence,
        candidate.overview,
        candidate.rating,
        candidate.votes,
        candidate.language,
        candidate.posterPath,
        candidate.backdropPath,
        _now,
        title,
      ],
    );
    if (byHand) {
      _db.execute('UPDATE title_keys SET fixed = 1 WHERE title = ?', [title]);
    }
    return (sure ? MatchOutcome.matched : MatchOutcome.unsure, title);
  });

  /// How many titles (with a video) are in which state.
  MatchCounts counts() {
    final byState = {
      for (final row in _db.select(
        'SELECT t.match_state, count(*) AS n FROM titles t '
        'WHERE EXISTS (SELECT 1 FROM file_meta m WHERE m.title = t.id) '
        'GROUP BY t.match_state',
      ))
        row['match_state'] as int: row['n'] as int,
    };
    return MatchCounts(
      pending: byState[MatchState.pending] ?? 0,
      matched: byState[MatchState.matched] ?? 0,
      unsure: byState[MatchState.unsure] ?? 0,
      notFound: byState[MatchState.notFound] ?? 0,
      byHand:
          (byState[MatchState.byHand] ?? 0) +
          (byState[MatchState.leftAlone] ?? 0),
    );
  }
}
