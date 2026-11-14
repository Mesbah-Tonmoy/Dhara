import 'package:dhara/features/metadata/title_matcher.dart';
import 'package:dhara/features/metadata/tmdb_client.dart';
import 'package:dhara/features/metadata/video_identity.dart';
import 'package:flutter_test/flutter_test.dart';

TmdbCandidate _film(
  int id,
  String title,
  int? year, {
  int votes = 100,
  String? original,
}) => TmdbCandidate(
  id: id,
  kind: TitleKind.movie,
  title: title,
  originalTitle: original,
  year: year,
  votes: votes,
);

TmdbCandidate _show(int id, String title, int? year, {int votes = 100}) =>
    TmdbCandidate(
      id: id,
      kind: TitleKind.series,
      title: title,
      year: year,
      votes: votes,
    );

void main() {
  /// The best candidate for a film called [name], with its confidence.
  (int, int)? best(
    String name,
    int? year,
    List<TmdbCandidate> candidates, {
    String? alt,
    TitleKind kind = TitleKind.movie,
  }) {
    final ranked = rankCandidates(
      TitleQuery(kind: kind, name: name, altName: alt, year: year),
      candidates,
    );
    return ranked.isEmpty
        ? null
        : (ranked.first.candidate.id, ranked.first.confidence);
  }

  group('titleSimilarity', () {
    test('is 1 for one name in different spellings', () {
      for (final (a, b) in [
        ('Godzilla vs. Kong', 'godzilla.vs..kong'),
        ('The Dark Knight', 'Dark Knight'),
        ('Return of the Living Dead III', 'Return of the Living Dead 3'),
        ('Les Misérables', 'Les Miserables'),
        ('S.H.I.E.L.D.', 'S H I E L D'),
        ('Fast & Furious', 'Fast and Furious'),
        ("Don't Be a Menace", 'Dont Be A Menace'),
      ]) {
        expect(titleSimilarity(a, b), 1, reason: '$a / $b');
      }
    });

    test('is high for a slip of the pen, low for another name', () {
      expect(titleSimilarity('Silent Hills', 'Silent Hill'), greaterThan(.9));
      expect(titleSimilarity('Spacewalker', 'Spacewalk'), greaterThan(.8));
      expect(titleSimilarity('Alien', 'Aliens vs. Predator'), lessThan(.5));
      expect(titleSimilarity('The Ring', 'The Raid'), lessThan(.8));
      expect(titleSimilarity('', 'Anything'), 0);
      expect(titleSimilarity('!!!', '???'), 0);
    });

    test('counts a name without its subtitle as close', () {
      expect(
        titleSimilarity(
          'Nameless Gangster',
          'Nameless Gangster: Rules of the Time',
        ),
        .85,
      );
      // One short word is not a title cut short.
      expect(titleSimilarity('It', 'It Chapter Two'), lessThan(.5));
    });
  });

  group('rankCandidates', () {
    test('is sure of the one film with that name and year', () {
      expect(best('Vivarium', 2019, [_film(1, 'Vivarium', 2019)]), (1, 100));
    });

    test('tells films of one name apart by the year', () {
      final ring = [_film(1, 'The Ring', 2002), _film(2, 'The Ring', 1998)];
      expect(best('The Ring', 2002, ring), (1, 100));
      expect(best('The Ring', 1998, ring), (2, 100));
    });

    test('takes a year one off, less sure', () {
      final (id, confidence) = best('Calcutta 71', 1971, [
        _film(1, 'Calcutta 71', 1972),
      ])!;
      expect(id, 1);
      expect(confidence, inInclusiveRange(sureConfidence, 95));
    });

    test('never trusts a film from a plainly different year', () {
      final (_, confidence) = best('Hell', 2011, [_film(1, 'Hell', 2005)])!;
      expect(confidence, lessThan(unsureConfidence));
    });

    test('without a year is sure only if the name stands alone', () {
      final (_, alone) = best('Alangkar', null, [_film(1, 'Alangkar', 1978)])!;
      expect(alone, greaterThanOrEqualTo(sureConfidence));

      final (_, among) = best('Hell', null, [
        _film(1, 'Hell', 2011),
        _film(2, 'Hell', 2005),
      ])!;
      expect(among, inInclusiveRange(unsureConfidence, sureConfidence - 1));
    });

    test('two that fit equally well are never a sure match', () {
      final twins = [
        _film(1, 'Twins', 2019, votes: 40),
        _film(2, 'Twins', 2019, votes: 900),
      ];
      final (id, confidence) = best('Twins', 2019, twins)!;
      expect(id, 2, reason: 'the better known one');
      expect(confidence, lessThan(sureConfidence));
      expect(confidence, greaterThanOrEqualTo(unsureConfidence));
    });

    test('matches on the original title and on the other name', () {
      expect(
        best('Die Welle', 2008, [
          _film(1, 'The Wave', 2008, original: 'Die Welle'),
        ]),
        (1, 100),
      );
      expect(
        best('Shall We Kiss', 2007, [
          _film(1, "Un baiser s'il vous plaît", 2007),
        ], alt: "Un baiser s'il vous plait"),
        (1, 100),
      );
    });

    test('takes a slip in the name if the year fits and nothing else does', () {
      final (id, confidence) = best('Silent Hills', 2006, [
        _film(1, 'Silent Hill', 2006),
        _film(2, 'Silent Night', 2012),
      ])!;
      expect(id, 1);
      expect(confidence, greaterThanOrEqualTo(sureConfidence));
    });

    test('an unrelated name is no match, whatever the year', () {
      final (_, confidence) = best('Parlor', 2015, [
        _film(1, 'Something Else Entirely', 2015),
      ])!;
      expect(confidence, lessThanOrEqualTo(40));
    });

    test('a name cut short needs the year and no rival', () {
      final full = _film(1, 'Nameless Gangster: Rules of the Time', 2012);
      final (_, alone) = best('Nameless Gangster', 2012, [full])!;
      expect(alone, greaterThanOrEqualTo(sureConfidence));

      final (_, noYear) = best('Nameless Gangster', null, [
        full,
        _film(2, 'Nameless Gangster 2', 2015),
      ])!;
      expect(noYear, lessThan(sureConfidence));
    });

    test('for a show, a later year fits: it is a season', () {
      final signal = [_show(1, 'The Quiet Signal', 2017)];
      const kind = TitleKind.series;
      expect(best('The Quiet Signal', 2017, signal, kind: kind), (1, 100));
      final (_, later) = best('The Quiet Signal', 2019, signal, kind: kind)!;
      expect(later, greaterThanOrEqualTo(sureConfidence));
      final (_, earlier) = best('The Quiet Signal', 2010, signal, kind: kind)!;
      expect(earlier, lessThan(unsureConfidence));
    });

    test('leaves out the other kind and repeated candidates', () {
      final ranked = rankCandidates(
        const TitleQuery(kind: TitleKind.movie, name: 'Twins', year: 2019),
        [
          _show(9, 'Twins', 2019),
          _film(1, 'Twins', 2019),
          _film(1, 'Twins', 2019),
        ],
      );
      expect([for (final entry in ranked) entry.candidate.id], [1]);
      expect(ranked.single.confidence, 100);
    });

    test('orders the rest too, each with a confidence of its own', () {
      final ranked = rankCandidates(
        const TitleQuery(kind: TitleKind.movie, name: 'The Ring', year: 2002),
        [
          _film(3, 'Rings', 2017),
          _film(2, 'The Ring', 1998),
          _film(1, 'The Ring', 2002),
        ],
      );
      expect([for (final entry in ranked) entry.candidate.id], [1, 2, 3]);
      expect(ranked[1].confidence, lessThan(unsureConfidence));
      expect(ranked[2].confidence, lessThan(ranked[1].confidence));
      expect(
        rankCandidates(
          const TitleQuery(kind: TitleKind.movie, name: 'x'),
          const [],
        ),
        isEmpty,
      );
    });
  });
}
