import 'package:dhara/core/db/library_db.dart';
import 'package:dhara/features/browse/browse_controller.dart';
import 'package:dhara/features/browse/browse_store.dart';
import 'package:dhara/features/browse/ui/browse_screen.dart';
import 'package:dhara/features/details/ui/details_screen.dart';
import 'package:dhara/features/home/ui/poster_card.dart';
import 'package:dhara/theme/tokens.dart';
import 'package:dhara/widgets/chips.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/test_app.dart';

/// [films] films ("Film 1" is of 2001, rated 6.1, and so on) and the show
/// "The Bay", on the source "a".
LibraryDb _library({int films = 4}) {
  final library = LibraryDb.inMemory();
  final db = library.db
    ..execute("INSERT INTO sources (id, source_id) VALUES (1, 'a')")
    ..execute(
      'INSERT INTO folders (id, source, url, path, depth) '
      "VALUES (1, 1, 'http://10.0.0.1/a/', 'All', 0)",
    );
  void add(int id, int kind, String name, int year, String genres) {
    db
      ..execute(
        'INSERT INTO titles (id, kind, name, year, tmdb_id, match_state, '
        'rating, votes, genres, added_at) '
        'VALUES (?, ?, ?, ?, ?, 1, ?, ?, ?, 0)',
        [id, kind, name, year, id, 6 + id % 30 / 10, 100 + id, genres],
      )
      ..execute(
        'INSERT INTO files (folder, name, url, added_at) VALUES (1, ?, ?, 0)',
        ['$name.mkv', 'http://10.0.0.1/a/$id.mkv'],
      )
      ..execute(
        'INSERT INTO file_meta (file, parser, kind, title, season, episode, '
        'height) VALUES (last_insert_rowid(), 1, ?, ?, ?, ?, ?)',
        [
          kind,
          id,
          if (kind == 1) 1 else null,
          if (kind == 1) 1 else null,
          id.isEven ? 2160 : 720,
        ],
      );
  }

  for (var n = 1; n <= films; n++) {
    add(n, 0, 'Film $n', 2000 + n, n.isEven ? 'Drama, Mystery' : 'Action');
  }
  add(9000, 1, 'The Bay', 2019, 'Crime, Drama');
  return library;
}

final _search = find.byKey(const Key('shell-search'));

/// The app on [db], with Search open.
Future<BrowseController> _open(
  WidgetTester tester,
  LibraryDb db, {
  Size window = const Size(1280, 900),
}) async {
  tester.view
    ..physicalSize = window
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final (:app, :sources) = testApp(db: db, sources: [testSource('a')]);
  await sources.setEnabled(['a'], enabled: true);
  await tester.pumpWidget(app);
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('rail-search')));
  await tester.pumpAndSettle();
  return BrowseScope.read(tester.element(find.byType(BrowseScreen)));
}

/// Lets a search that waits for typing to pause be asked and answered.
Future<void> _typed(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 200));
  await tester.pumpAndSettle();
}

String _text(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(Key(key))).data!;

List<String> _shown(WidgetTester tester) => [
  for (final card in tester.widgetList<PosterCard>(find.byType(PosterCard)))
    card.title.name,
];

void main() {
  testWidgets('lists every title as a grid of posters, the newest first', (
    tester,
  ) async {
    await _open(tester, _library());

    expect(_text(tester, 'browse-heading'), 'Browse everything');
    expect(
      _text(tester, 'browse-info'),
      startsWith('5 of 5 titles · found in'),
    );
    expect(_shown(tester), ['The Bay', 'Film 4', 'Film 3', 'Film 2', 'Film 1']);
    expect(find.byKey(const Key('browse-reset')), findsNothing);

    // Posters in rows, no narrower than those on Home.
    final first = tester.getRect(find.byType(PosterCard).first);
    final second = tester.getRect(find.byType(PosterCard).at(1));
    expect(first.width, greaterThanOrEqualTo(DharaLayout.posterWidth));
    expect(first.width, lessThan(DharaLayout.posterWidth * 1.4));
    expect(first.height, moreOrLessEquals(first.width * 1.5, epsilon: .01));
    expect(second.top, first.top);
    expect(second.left - first.right, DharaLayout.cardGap);
  });

  testWidgets('the results follow what is typed in the title bar', (
    tester,
  ) async {
    await _open(tester, _library());

    await tester.enterText(_search, 'film');
    await _typed(tester);
    expect(_text(tester, 'browse-heading'), 'Results for “film”');
    expect(_text(tester, 'browse-info'), startsWith('4 of 5 titles'));
    expect(_shown(tester), isNot(contains('The Bay')));

    await tester.enterText(_search, 'film 3');
    await _typed(tester);
    expect(_shown(tester), ['Film 3']);

    await tester.enterText(_search, 'zzz');
    await _typed(tester);
    expect(find.byKey(const Key('browse-empty')), findsOneWidget);
    expect(find.text('Nothing matches'), findsOneWidget);
    expect(find.byType(PosterCard), findsNothing);

    await tester.enterText(_search, '');
    await _typed(tester);
    expect(_shown(tester), hasLength(5));
  });

  testWidgets('the filters narrow the grid at once, and can be reset', (
    tester,
  ) async {
    final browse = await _open(tester, _library());

    await tester.tap(find.text('Series'));
    await tester.pumpAndSettle();
    expect(_text(tester, 'browse-heading'), 'Series');
    expect(_shown(tester), ['The Bay']);
    expect(browse.query.kind, BrowseKind.series);

    await tester.tap(find.text('Movies'));
    await tester.tap(find.byKey(const Key('filter-quality-2160')));
    await tester.pumpAndSettle();
    expect(_shown(tester), ['Film 4', 'Film 2']);

    await tester.tap(find.byKey(const Key('filter-genre-Mystery')));
    await tester.tap(find.byKey(const Key('filter-sort-name')));
    await tester.pumpAndSettle();
    expect(_shown(tester), ['Film 2', 'Film 4']);
    expect(
      tester
          .widget<PillChip>(find.byKey(const Key('filter-genre-Mystery')))
          .selected,
      isTrue,
    );
    expect(_text(tester, 'browse-info'), startsWith('2 of 5 titles'));

    await tester.tap(find.byKey(const Key('browse-reset')));
    await tester.pumpAndSettle();
    expect(_shown(tester), hasLength(5));
    expect(browse.query.hasNoFilters, isTrue);
    expect(find.byKey(const Key('browse-reset')), findsNothing);
  });

  testWidgets('offers the years counting back from this one', (tester) async {
    final browse = await _open(tester, _library());
    final year = DateTime.now().year;

    expect(find.text('$year'), findsOneWidget);
    expect(find.text('${year - 3} & older'), findsOneWidget);

    await tester.tap(find.byKey(const Key('filter-year-older')));
    await tester.pumpAndSettle();
    expect((browse.query.year, browse.query.yearOrOlder), (year - 3, true));
    expect(_shown(tester), hasLength(5));

    await tester.tap(find.byKey(Key('filter-year-$year')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('browse-empty')), findsOneWidget);
  });

  testWidgets('lists the genres the library has', (tester) async {
    await _open(tester, _library());

    for (final genre in ['Action', 'Crime', 'Drama', 'Mystery']) {
      expect(find.byKey(Key('filter-genre-$genre')), findsOneWidget);
    }
  });

  testWidgets('only builds the cards in view of a large library', (
    tester,
  ) async {
    final browse = await _open(tester, _library(films: 3000));

    expect(browse.count, 3001);
    expect(_text(tester, 'browse-info'), startsWith('3001 of 3001 titles'));
    expect(find.byType(PosterCard).evaluate().length, lessThan(40));

    // Far down the grid the cards are read as they come into view.
    final grid = find
        .descendant(
          of: find.byType(BrowseScreen),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.drag(grid, const Offset(0, -30000));
    await tester.pumpAndSettle();
    final shown = _shown(tester);
    expect(shown, isNotEmpty);
    expect(shown, isNot(contains('Film 3000')));
    expect(find.byType(PosterCard).evaluate().length, lessThan(60));
  });

  testWidgets('a card opens the page of its title, and Back returns to '
      'the results', (tester) async {
    await _open(tester, _library());
    await tester.enterText(_search, 'film');
    await _typed(tester);

    await tester.tap(find.byType(PosterCard).at(1));
    await tester.pumpAndSettle();
    expect(find.byType(DetailsScreen), findsOneWidget);

    await tester.tap(find.byKey(const Key('shell-back')));
    await tester.pumpAndSettle();
    expect(_text(tester, 'browse-heading'), 'Results for “film”');
    expect(_shown(tester), hasLength(4));
  });

  testWidgets('fits a narrow window', (tester) async {
    await _open(tester, _library(), window: const Size(940, 600));

    expect(tester.takeException(), isNull);
    expect(find.byType(PosterCard), findsWidgets);
  });

  test('how long a search took is told shortly', () {
    expect(tookLabel(const Duration(microseconds: 40)), 'under 0.1');
    expect(tookLabel(const Duration(microseconds: 3400)), '3.4');
    expect(tookLabel(const Duration(milliseconds: 27)), '27');
  });
}
