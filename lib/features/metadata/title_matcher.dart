import 'package:dhara/features/metadata/tmdb_client.dart';
import 'package:dhara/features/metadata/video_identity.dart';
import 'package:flutter/foundation.dart';

/// From this confidence on, a match is taken without asking.
const sureConfidence = 85;

/// From this confidence on, a match is taken but put up for review; below
/// it, the title counts as not found.
const unsureConfidence = 60;

/// What the files say about a title, to compare candidates with.
@immutable
class TitleQuery {
  const TitleQuery({
    required this.kind,
    required this.name,
    this.altName,
    this.year,
  });

  final TitleKind kind;
  final String name;

  /// The name the file gives it when its folder says otherwise.
  final String? altName;

  /// Of a show this may be the year of a season.
  final int? year;
}

/// A candidate with how sure it is to be the title meant, 0 to 100.
@immutable
class ScoredCandidate {
  const ScoredCandidate(this.candidate, this.confidence);

  final TmdbCandidate candidate;
  final int confidence;
}

/// Orders [candidates] by how well they fit [query], best first, each with
/// its confidence.
///
/// The confidence is made of up to 70 points for the name (how alike the
/// spellings are, against the title and the original title), up to 20 for
/// the year, and, for the best one only, up to 10 for standing clear of
/// the second best.
///
/// - A candidate whose year is plainly wrong never gets past 59; a film
///   two years off never past 79.
/// - Of two that fit equally well, the one far better known is taken (the
///   other is a short film or a fan cut of the same name); if neither is,
///   the match never gets past 84.
List<ScoredCandidate> rankCandidates(
  TitleQuery query,
  List<TmdbCandidate> candidates,
) {
  final seen = <int>{};
  final scored = [
    for (final candidate in candidates)
      if (candidate.kind == query.kind && seen.add(candidate.id))
        _score(query, candidate),
  ];
  scored.sort((a, b) {
    final byBase = b.base.compareTo(a.base);
    return byBase != 0
        ? byBase
        : b.candidate.votes.compareTo(a.candidate.votes);
  });
  return [
    for (final (index, entry) in scored.indexed)
      ScoredCandidate(
        entry.candidate,
        index == 0
            ? _confidenceOfBest(entry, scored.length > 1 ? scored[1] : null)
            : entry.capped(entry.base, 84),
      ),
  ];
}

/// The confidence of a match that rests on TMDB's word alone.
const aliasConfidence = 70;

/// The best match for [query] in what TMDB answered, or `null` if it
/// answered nothing of use.
///
/// [byNameAndYear] is the answer to the search by name and year; [others]
/// are the answers to any further searches (without the year, by the other
/// name).
///
/// If no name fits, but the search by name and year came back with exactly
/// one film or show of that year, that one is taken as an unsure match:
/// TMDB also searches the other titles a film goes by ("Formula 51" finds
/// "The 51st State", a Hindi dub's title finds the original), and those
/// names are not in its answer.
ScoredCandidate? bestMatch(
  TitleQuery query, {
  required List<TmdbCandidate> byNameAndYear,
  List<TmdbCandidate> others = const [],
}) {
  final best = rankCandidates(query, [...byNameAndYear, ...others]).firstOrNull;
  if (best != null && best.confidence >= unsureConfidence) return best;

  final asked = query.year;
  final sameKind = {
    for (final candidate in byNameAndYear)
      if (candidate.kind == query.kind) candidate.id: candidate,
  };
  if (asked != null && sameKind.length == 1) {
    final only = sameKind.values.single;
    final year = only.year;
    final fits =
        year != null &&
        (query.kind == TitleKind.series ? year <= asked : year == asked);
    if (fits) return ScoredCandidate(only, aliasConfidence);
  }
  return best;
}

/// How alike two titles are, 0 to 1: 1 for the same name in any spelling
/// ("Godzilla Vs. Kong", "godzilla vs kong"; "Part III", "Part 3"; "4
/// Assassins", "Four Assassins"; with or without "The").
double titleSimilarity(String a, String b) {
  final first = _forms(a);
  final second = _forms(b);
  var best = 0.0;
  for (final x in first) {
    for (final y in second) {
      final similarity = _similarity(x, y);
      if (similarity > best) best = similarity;
    }
  }
  return best;
}

class _Scored {
  const _Scored(this.candidate, this.name, this.year, this.most);

  final TmdbCandidate candidate;

  /// Points for the name, 0 to 70; 0 means the names are unrelated.
  final int name;

  /// Points for the year, 0 to 20.
  final int year;

  /// What the year allows the confidence to be at most.
  final int most;

  int get base => name + year;

  /// [points], held down to what this candidate can be trusted with at
  /// most, and to [limit].
  int capped(int points, int limit) {
    var top = limit < most ? limit : most;
    if (name == 0 && top > 40) top = 40;
    return points < top ? points : top;
  }
}

_Scored _score(TitleQuery query, TmdbCandidate candidate) {
  var similarity = 0.0;
  for (final name in [query.name, query.altName]) {
    if (name == null || name.isEmpty) continue;
    for (final other in [candidate.title, candidate.originalTitle]) {
      if (other == null) continue;
      final value = titleSimilarity(name, other);
      if (value > similarity) similarity = value;
    }
  }
  // Half alike is as good as unrelated: "Alien", "Aliens vs. Predator".
  final name = similarity < .5 ? 0 : (similarity * 70).round();

  final asked = query.year;
  final actual = candidate.year;
  if (asked == null || actual == null) return _Scored(candidate, name, 8, 100);
  final later = asked - actual;
  if (query.kind == TitleKind.series) {
    // A season folder carries the year of the season: the same year or any
    // later one fits a show.
    return switch (later) {
      0 => _Scored(candidate, name, 20, 100),
      > 0 => _Scored(candidate, name, 14, 100),
      -1 => _Scored(candidate, name, 8, 100),
      _ => _Scored(candidate, name, 0, 59),
    };
  }
  // Servers and TMDB often differ by a year (festival or home release),
  // now and then by two.
  return switch (later.abs()) {
    0 => _Scored(candidate, name, 20, 100),
    1 => _Scored(candidate, name, 12, 100),
    2 => _Scored(candidate, name, 4, 79),
    _ => _Scored(candidate, name, 0, 59),
  };
}

int _confidenceOfBest(_Scored best, _Scored? next) {
  if (next == null) return best.capped(best.base + 10, 100);
  final gap = best.base - next.base;
  if (gap > 0) {
    final clear = gap >= 15 ? 10 : (gap * 10 / 15).round();
    return best.capped(best.base + clear, 100);
  }
  // Two that fit equally well. If one is far better known, the other is a
  // short film or a fan cut of the same name and year.
  final known = best.candidate.votes;
  final other = next.candidate.votes < 1 ? 1 : next.candidate.votes;
  if (known >= 20 && known >= 10 * other) {
    return best.capped(best.base + 5, 100);
  }
  return best.capped(best.base, 84);
}

/// The spellings of [title] to compare: plain, and without "the", "a" or
/// "an" in front. Roman numerals and number words count as numbers.
List<String> _forms(String title) {
  final words = [
    for (final word in normalizeTitle(title).split(' '))
      if (word.isNotEmpty) _numbers[word] ?? word,
  ];
  if (words.isEmpty) return const [];
  final plain = words.join(' ');
  if (words.length > 1 && _articles.contains(words.first)) {
    return [plain, words.skip(1).join(' ')];
  }
  return [plain];
}

double _similarity(String a, String b) {
  if (a == b) return 1;
  final longer = a.length > b.length ? a : b;
  final shorter = a.length > b.length ? b : a;
  var alike = 1 - _distance(a, b) / longer.length;
  // The same words in another order: "Jason Lives: Friday the 13th Part
  // VI", "Friday the 13th Part VI-Jason Lives".
  if (alike < .95 && _sorted(a) == _sorted(b)) alike = .95;
  // A name without its subtitle: "Nameless Gangster", "Nameless Gangster
  // Rules of the Time". Not for one short word ("It", "It Chapter Two").
  final isStart =
      longer.startsWith('$shorter ') &&
      (shorter.contains(' ') || shorter.length >= 6);
  if (isStart && alike < .85) return .85;
  // What stands in front may be another film altogether ("The Dead",
  // "Survival of the Dead"): close enough for a match, never for a sure
  // one.
  final isEnd = longer.endsWith(' $shorter') && shorter.contains(' ');
  return isEnd && alike < .75 ? .75 : alike;
}

String _sorted(String words) => (words.split(' ')..sort()).join(' ');

/// How many letters have to be added, dropped or changed to turn [a] into
/// [b] (Levenshtein distance).
int _distance(String a, String b) {
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;
  var previous = List<int>.generate(b.length + 1, (i) => i);
  var current = List<int>.filled(b.length + 1, 0);
  for (var i = 1; i <= a.length; i++) {
    current[0] = i;
    for (var j = 1; j <= b.length; j++) {
      final change = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
      var least = previous[j - 1] + change;
      if (previous[j] + 1 < least) least = previous[j] + 1;
      if (current[j - 1] + 1 < least) least = current[j - 1] + 1;
      current[j] = least;
    }
    final swap = previous;
    previous = current;
    current = swap;
  }
  return previous[b.length];
}

const _articles = {'the', 'a', 'an'};

/// Roman numerals and number words by the number they stand for.
const _numbers = {
  'ii': '2',
  'iii': '3',
  'iv': '4',
  'v': '5',
  'vi': '6',
  'vii': '7',
  'viii': '8',
  'ix': '9',
  'x': '10',
  'xi': '11',
  'xii': '12',
  'xiii': '13',
  'zero': '0',
  'one': '1',
  'two': '2',
  'three': '3',
  'four': '4',
  'five': '5',
  'six': '6',
  'seven': '7',
  'eight': '8',
  'nine': '9',
  'ten': '10',
  'eleven': '11',
  'twelve': '12',
  'thirteen': '13',
};
