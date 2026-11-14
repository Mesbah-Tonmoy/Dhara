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
/// the second best. A candidate whose year is plainly wrong never gets
/// past 59; two that cannot be told apart never past 84.
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
            : entry.confidenceAlone,
      ),
  ];
}

/// How alike two titles are, 0 to 1: 1 for the same name in any spelling
/// ("Godzilla Vs. Kong", "godzilla vs kong"; "Part III", "Part 3"; with or
/// without "The").
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
  const _Scored(
    this.candidate,
    this.name,
    this.year, {
    required this.wrongYear,
  });

  final TmdbCandidate candidate;

  /// Points for the name, 0 to 70; 0 means the names are unrelated.
  final int name;

  /// Points for the year, 0 to 20.
  final int year;
  final bool wrongYear;

  int get base => name + year;

  /// The confidence without the points for standing clear of the others.
  int get confidenceAlone => _capped(base, 84);

  int _capped(int points, int most) {
    if (name == 0) return points < 40 ? points : 40;
    if (wrongYear) return points < 59 ? points : 59;
    return points < most ? points : most;
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
  var year = 8;
  var wrongYear = false;
  if (asked != null && actual != null) {
    final later = asked - actual;
    if (query.kind == TitleKind.series) {
      // A season folder carries the year of the season: the same year or
      // any later one fits a show.
      year = later == 0
          ? 20
          : later > 0
          ? 14
          : later == -1
          ? 8
          : 0;
      wrongYear = later < -1;
    } else {
      year = later == 0
          ? 20
          : later.abs() == 1
          ? 12
          : 0;
      wrongYear = later.abs() > 1;
    }
  }
  return _Scored(candidate, name, year, wrongYear: wrongYear);
}

int _confidenceOfBest(_Scored best, _Scored? next) {
  if (next == null) return best._capped(best.base + 10, 100);
  final gap = best.base - next.base;
  if (gap > 0) {
    final clear = gap >= 15 ? 10 : (gap * 10 / 15).round();
    return best._capped(best.base + clear, 100);
  }
  // Two that fit equally well: only being far better known tells them
  // apart, and not for certain.
  final known = best.candidate.votes;
  final other = next.candidate.votes < 1 ? 1 : next.candidate.votes;
  return best._capped(best.base + (known >= 10 * other ? 5 : 0), 84);
}

/// The spellings of [title] to compare: plain, and without "the", "a" or
/// "an" in front. Roman numerals count as numbers.
List<String> _forms(String title) {
  final words = [
    for (final word in normalizeTitle(title).split(' '))
      if (word.isNotEmpty) _romanNumerals[word] ?? word,
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
  final alike = 1 - _distance(a, b) / longer.length;
  // A name without its subtitle: "Nameless Gangster", "Nameless Gangster
  // Rules of the Time". Not for one short word ("It", "It Chapter Two").
  final isStart =
      longer.startsWith('$shorter ') &&
      (shorter.contains(' ') || shorter.length >= 6);
  return isStart && alike < .85 ? .85 : alike;
}

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

const _romanNumerals = {
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
};
