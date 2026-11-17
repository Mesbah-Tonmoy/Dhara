import 'dart:async';

import 'package:dhara/core/db/library_db.dart';
import 'package:dhara/core/db/library_isolate.dart';
import 'package:dhara/core/secrets/secret_store.dart';
import 'package:dhara/features/browse/ui/browse_screen.dart';
import 'package:dhara/features/details/ui/details_screen.dart';
import 'package:dhara/features/home/home_controller.dart';
import 'package:dhara/features/home/home_store.dart';
import 'package:dhara/features/home/ui/card_row.dart';
import 'package:dhara/features/home/ui/hero_banner.dart';
import 'package:dhara/features/home/ui/home_screen.dart';
import 'package:dhara/features/home/ui/poster_card.dart';
import 'package:dhara/features/home/ui/wide_card.dart';
import 'package:dhara/features/indexer/index_controller.dart';
import 'package:dhara/features/indexer/ui/index_screen.dart';
import 'package:dhara/features/metadata/match_controller.dart';
import 'package:dhara/features/metadata/titles_controller.dart';
import 'package:dhara/features/metadata/tmdb_key.dart';
import 'package:dhara/features/metadata/ui/titles_screen.dart';
import 'package:dhara/features/sources/source_store.dart';
import 'package:dhara/features/sources/ui/server_discovery_screen.dart';
import 'package:dhara/shell/shell_controller.dart';
import 'package:dhara/theme/tokens.dart';
import 'package:dhara/widgets/placeholder_art.dart';
import 'package:dhara/widgets/surfaces.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/test_app.dart';
import '../../../widgets/support.dart';

/// Films and one show on the source "a", as a crawl and a match on TMDB
/// would have left them. Film [n] is of the year 2000 + n.
LibraryDb _library({
  int films = 3,
  bool rated = true,
  bool backdrops = false,
  String scheme = 'http',
}) {
  final library = LibraryDb.inMemory();
  final db = library.db
    ..execute("INSERT INTO sources (id, source_id) VALUES (1, 'a')")
    ..execute(
      'INSERT INTO folders (id, source, url, path, depth) '
      "VALUES (1, 1, 'http://10.0.0.1/a/', 'All', 0)",
    );
  void add(int id, int kind, String name, int year, {int? episode}) {
    db
      ..execute(
        'INSERT OR IGNORE INTO titles (id, kind, name, year, tmdb_id, '
        'match_state, rating, votes, genres, backdrop_path, overview, '
        'added_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0)',
        [
          id,
          kind,
          name,
          year,
          if (rated) id else null,
          if (rated) 1 else 0,
          if (rated) 6 + id / 10 else null,
          if (rated) 1000 + id else null,
          if (rated) 'Drama, Mystery' else null,
          if (backdrops) '/b$id.jpg' else null,
          if (backdrops) 'About $name.' else null,
        ],
      )
      ..execute(
        'INSERT INTO files (folder, name, url, modified, added_at) '
        'VALUES (1, ?, ?, ?, 99999)',
        [
          '$name ${episode ?? ''}.mkv',
          '$scheme://10.0.0.1/a/$id-${episode ?? 0}.mkv',
          id * 10 + (episode ?? 0),
        ],
      )
      ..execute(
        'INSERT INTO file_meta (file, parser, kind, title, season, episode, '
        'height) VALUES (last_insert_rowid(), 1, ?, ?, ?, ?, 1080)',
        [kind, id, if (episode != null) 1 else null, episode],
      );
  }

  for (var n = 1; n <= films; n++) {
    add(n, 0, 'Film $n', 2000 + n);
  }
  add(900, 1, 'The Bay', 2019, episode: 1);
  add(900, 1, 'The Bay', 2019, episode: 2);
  return library;
}

/// The app on [db], with the source "a" switched on if [enabled].
Future<SourceStore> _boot(
  WidgetTester tester, {
  LibraryDb? db,
  bool enabled = true,
  bool withSource = true,
  bool settle = true,
}) async {
  tester.view
    ..physicalSize = const Size(1280, 720)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final (:app, :sources) = testApp(
    db: db,
    sources: [if (withSource) testSource('a')],
  );
  if (enabled && withSource) {
    await sources.setEnabled(['a'], enabled: true);
  }
  await tester.pumpWidget(app);
  await (settle ? tester.pumpAndSettle() : _run(tester));
  return sources;
}

/// Lets a second pass, for pages on which something keeps moving (the
/// banner) and so never settle.
Future<void> _run(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Finder _row(String key) => find.byKey(Key('home-row-$key'));

List<String> _cards(WidgetTester tester, String row) => [
  for (final card in tester.widgetList<PosterCard>(
    find.descendant(of: _row(row), matching: find.byType(PosterCard)),
  ))
    card.title.name,
];

void main() {
  group('rows', () {
    testWidgets('shows the library as rows of posters', (tester) async {
      await _boot(tester, db: _library());

      expect(find.byKey(const Key('home')), findsOneWidget);
      expect(_cards(tester, 'recent'), [
        'The Bay',
        'Film 3',
        'Film 2',
        'Film 1',
      ]);
      expect(_cards(tester, 'movies'), ['Film 3', 'Film 2', 'Film 1']);
      expect(_cards(tester, 'series'), ['The Bay']);
      expect(
        tester.getTopLeft(_row('recent')).dy,
        lessThan(tester.getTopLeft(_row('movies')).dy),
      );
    });

    testWidgets('a row with nothing in it is left out', (tester) async {
      await _boot(tester, db: _library(rated: false));

      expect(_row('movies'), findsOneWidget);
      expect(_row('anime'), findsNothing);
      expect(_row('top'), findsNothing, reason: 'nothing is rated');
    });

    testWidgets('every row is built once Home is up, also those far below '
        'the window', (tester) async {
      await _boot(tester, db: _library());

      // A list by itself builds what is in the window and 250 pixels
      // beyond it; the last row starts further down than that.
      final last = find.byKey(const Key('home-row-top'), skipOffstage: false);
      expect(last, findsOneWidget);
      expect(tester.getTopLeft(last).dy, greaterThan(720 + 250));
      expect(
        find.descendant(
          of: last,
          matching: find.byType(PosterCard, skipOffstage: false),
          skipOffstage: false,
        ),
        findsNWidgets(4),
      );
    });

    testWidgets('Top Rated numbers its cards', (tester) async {
      await _boot(tester, db: _library());
      await tester.scrollUntilVisible(
        _row('top'),
        300,
        scrollable: find.byType(Scrollable).first,
      );

      final ranks = [
        for (final card in tester.widgetList<PosterCard>(
          find.descendant(of: _row('top'), matching: find.byType(PosterCard)),
        ))
          card.rank,
      ];
      expect(ranks, [1, 2, 3, 4]);
      expect(_cards(tester, 'top'), ['The Bay', 'Film 3', 'Film 2', 'Film 1']);
      expect(
        tester
            .widget<PosterCard>(
              find
                  .descendant(
                    of: _row('movies'),
                    matching: find.byType(PosterCard),
                    skipOffstage: false,
                  )
                  .first,
            )
            .rank,
        isNull,
      );
    });

    testWidgets('Movies and Series lead on to all of them', (tester) async {
      await _boot(tester, db: _library());

      final seeAll = find.descendant(
        of: _row('movies'),
        matching: find.text('See all'),
      );
      expect(seeAll, findsOneWidget);
      expect(
        find.descendant(of: _row('recent'), matching: find.text('See all')),
        findsNothing,
      );

      await tester.tap(seeAll);
      await tester.pumpAndSettle();
      expect(find.byType(BrowseScreen), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const Key('browse-heading'))).data,
        'Movies',
      );
      expect(
        tester.widget<Text>(find.byKey(const Key('browse-info'))).data,
        startsWith('3 of 4 titles'),
      );
    });

    testWidgets('only builds the cards in view of a long row', (tester) async {
      await _boot(tester, db: _library(films: 200));

      final row = tester.widget<CardRow>(_row('movies'));
      expect(row.itemCount, 30, reason: 'a row holds thirty at most');
      expect(_cards(tester, 'movies').length, lessThan(12));
    });

    testWidgets('a card opens its title', (tester) async {
      await _boot(tester, db: _library());

      await tester.tap(
        find.descendant(
          of: _row('movies'),
          matching: find.byWidgetPredicate(
            (widget) => widget is PosterCard && widget.title.name == 'Film 2',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(DetailsScreen), findsOneWidget);
      expect(
        tester.widget<DetailsScreen>(find.byType(DetailsScreen)).titleId,
        2,
      );
      expect(
        tester.widget<Text>(find.byKey(const Key('details-title'))).data,
        'Film 2',
      );
      // And Back leads to Home again.
      await tester.tap(find.byKey(const Key('shell-back')));
      await tester.pumpAndSettle();
      expect(_row('movies'), findsOneWidget);
    });

    testWidgets('Tab reaches the cards after the title bar and the rail', (
      tester,
    ) async {
      useKeyboardHighlight();
      await _boot(tester, db: _library());

      // Nothing is lit before the keyboard is used.
      PosterCard? focused() => FocusManager.instance.primaryFocus?.context
          ?.findAncestorWidgetOfExactType<PosterCard>();
      expect(focused(), isNull);

      for (var i = 0; i < 12 && focused() == null; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
      }
      expect(focused()?.title.name, 'The Bay');

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(focused()?.title.name, 'Film 3');
    });

    testWidgets('follows the sources: a server switched off takes its '
        'titles along', (tester) async {
      final sources = await _boot(tester, db: _library());
      expect(_row('movies'), findsOneWidget);

      await sources.setEnabled(['a'], enabled: false);
      await tester.pumpAndSettle();

      expect(_row('movies'), findsNothing);
      expect(find.byKey(const Key('home-start')), findsOneWidget);
    });
  });

  group('banner', () {
    BoxDecoration ground(WidgetTester tester) =>
        tester
                .widget<AnimatedContainer>(
                  find.byKey(const Key('shell-bar-ground')),
                )
                .decoration!
            as BoxDecoration;

    testWidgets('leads Home when titles have backdrops, under a clear '
        'title bar', (tester) async {
      await _boot(tester, db: _library(backdrops: true), settle: false);

      expect(find.byType(HeroBanner), findsOneWidget);
      expect(find.byKey(const Key('hero-title')), findsOneWidget);
      // The artwork starts at the window's top-left corner.
      final art = tester.getRect(
        find
            .descendant(
              of: find.byType(HeroBanner),
              matching: find.byType(PlaceholderArt),
            )
            .first,
      );
      expect(art.topLeft, Offset.zero);
      expect(art.right, 1280);
      expect(ground(tester).color!.a, 0);
      // The first row moves up over its foot.
      expect(
        tester.getTopLeft(_row('recent')).dy,
        lessThan(HeroBanner.heightFor(720)),
      );
    });

    testWidgets('once it is scrolled away the title bar is glass', (
      tester,
    ) async {
      await _boot(
        tester,
        db: _library(backdrops: true, films: 12),
        settle: false,
      );

      await tester.drag(find.byType(HeroBanner), const Offset(0, -300));
      await _run(tester);
      expect(ground(tester).color, DharaColors.glass);

      await tester.drag(_row('recent'), const Offset(0, 600));
      await _run(tester);
      expect(ground(tester).color!.a, 0);
    });

    testWidgets('is left out when nothing has a backdrop, and the bar is '
        'glass', (tester) async {
      await _boot(tester, db: _library(), settle: false);

      expect(find.byType(HeroBanner), findsNothing);
      expect(ground(tester).color, DharaColors.glass);
    });

    testWidgets('on another page the bar is glass, and clear again on the '
        'way back', (tester) async {
      await _boot(tester, db: _library(backdrops: true), settle: false);

      await tester.tap(find.byKey(const Key('rail-discovery')));
      await _run(tester);
      expect(find.byType(HeroBanner), findsNothing);
      expect(ground(tester).color, DharaColors.glass);

      await tester.tap(find.byKey(const Key('shell-back')));
      await _run(tester);
      expect(ground(tester).color!.a, 0);

      // The page of a title has artwork under the bar as well.
      await tester.tap(find.byKey(const Key('hero-more')));
      await _run(tester);
      expect(find.byType(DetailsScreen), findsOneWidget);
      expect(ground(tester).color!.a, 0);
    });

    testWidgets('My List on the banner is kept in the library', (tester) async {
      final db = _library(backdrops: true);
      await _boot(tester, db: db, settle: false);
      final shown = tester
          .widget<Text>(find.byKey(const Key('hero-title')))
          .data!;

      await tester.tap(find.byKey(const Key('my-list-button')));
      await _run(tester);

      expect(find.text('In My List'), findsOneWidget);
      expect(
        db.db
            .select(
              'SELECT t.name FROM my_list l JOIN titles t ON t.id = l.title',
            )
            .single
            .values,
        [shown],
      );
    });

    testWidgets('Play says so when no copy can be played', (tester) async {
      await _boot(
        tester,
        db: _library(backdrops: true, scheme: 'ftp'),
        settle: false,
      );

      await tester.tap(find.byKey(const Key('hero-play')));
      await tester.pump();
      await tester.pump();

      expect(
        find.textContaining('has no copy that can be played from here.'),
        findsOneWidget,
      );
      await tester.pump(const Duration(seconds: 4));
    });
  });

  group('Continue Watching', () {
    void watched(LibraryDb db, String url, {required int at}) => db.db
      ..execute(
        'INSERT INTO watch_history '
        '(url, watched_at, position_ms, duration_ms) '
        'VALUES (?, ?, 600000, 2400000)',
        [url, at],
      )
      ..execute(
        'INSERT INTO playback (url, position_ms, duration_ms, updated_at) '
        'VALUES (?, 600000, 2400000, ?)',
        [url, at],
      );

    testWidgets('lists what was left unfinished, before the other rows', (
      tester,
    ) async {
      final db = _library();
      watched(db, 'http://10.0.0.1/a/2-0.mkv', at: 5);
      watched(db, 'http://10.0.0.1/a/900-2.mkv', at: 9);
      await _boot(tester, db: db);

      final cards = tester
          .widgetList<WideCard>(
            find.descendant(
              of: _row('continue'),
              matching: find.byType(WideCard),
            ),
          )
          .toList();
      expect(
        [for (final card in cards) card.item.title?.name],
        ['The Bay', 'Film 2'],
      );
      expect(find.text('S1 · E2 · 30 min left'), findsOneWidget);
      expect(
        tester.getTopLeft(_row('continue')).dy,
        lessThan(tester.getTopLeft(_row('recent')).dy),
      );
    });

    testWidgets('is left out when nothing is unfinished', (tester) async {
      await _boot(tester, db: _library());

      expect(_row('continue'), findsNothing);
    });

    testWidgets('an address that is no longer allowed is not played', (
      tester,
    ) async {
      final db = _library();
      watched(db, 'ftp://elsewhere.test/clip.mkv', at: 5);
      await _boot(tester, db: db);

      await tester.tap(find.byType(WideCard));
      await tester.pump();

      expect(
        find.text('This address cannot be played any more.'),
        findsOneWidget,
      );
      await tester.pump(const Duration(seconds: 4));
    });
  });

  group('without a TMDB key', () {
    testWidgets('says where posters come from, with the way to add a key', (
      tester,
    ) async {
      await _boot(tester, db: _library(rated: false));
      // The key is looked for as the app starts.
      final tmdbKey = TmdbKeyScope.read(
        tester.element(find.byType(HomeScreen)),
      );
      await tester.runAsync(tmdbKey.load);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('home-key-notice')), findsOneWidget);
      // Titles are still listed, drawn from their names.
      expect(_cards(tester, 'movies'), ['Film 3', 'Film 2', 'Film 1']);

      await tester.tap(find.byKey(const Key('home-add-key')));
      await tester.pumpAndSettle();
      expect(find.byType(TitlesScreen), findsOneWidget);
    });

    testWidgets('says nothing before it knows whether there is a key', (
      tester,
    ) async {
      await _boot(tester, db: _library());

      expect(find.byKey(const Key('home-key-notice')), findsNothing);
    });
  });

  group('with nothing to show', () {
    Finder done(int step) => find.byKey(Key('home-step-$step-done'));

    testWidgets('says what to do first: find servers', (tester) async {
      await _boot(tester, enabled: false);

      expect(find.byKey(const Key('home-start')), findsOneWidget);
      expect(find.text('Welcome to Dhara'), findsOneWidget);
      expect(done(1), findsNothing);
      expect(done(2), findsNothing);
      expect(done(3), findsNothing);

      await tester.tap(find.byKey(const Key('home-step-servers')));
      await tester.pumpAndSettle();
      expect(find.byType(ServerDiscoveryScreen), findsOneWidget);
    });

    testWidgets('the index waits for a server', (tester) async {
      await _boot(tester, enabled: false);

      await tester.tap(find.byKey(const Key('home-step-index')));
      await tester.pumpAndSettle();

      expect(find.byType(IndexScreen), findsNothing);
    });

    testWidgets('with a server on, the index is next', (tester) async {
      await _boot(tester);

      expect(done(1), findsOneWidget);
      expect(find.text('1 server is switched on.'), findsOneWidget);
      expect(done(2), findsNothing);

      await tester.tap(find.byKey(const Key('home-step-index')));
      await tester.pumpAndSettle();
      expect(find.byType(IndexScreen), findsOneWidget);
    });

    testWidgets('playing a URL is still at hand', (tester) async {
      await _boot(tester, withSource: false);

      await tester.tap(find.byKey(const Key('home-open-url')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('url-field')), findsOneWidget);
    });
  });

  group('while the library is read', () {
    /// Home alone over a library that answers when [answer] completes.
    Future<void> pump(WidgetTester tester, _SlowLibrary library) async {
      final sources = SourceStore(starter: [testSource('a')]);
      final index = IndexController(
        library: library,
        sources: sources,
        deviceId: 'dhara-test',
      );
      final titles = TitlesController(library: library, index: index);
      final tmdbKey = TmdbKeyController(MemorySecretStore());
      final match = MatchController(
        library: library,
        titles: titles,
        tmdbKey: tmdbKey,
      );
      final home = HomeController(
        library: library,
        titles: titles,
        match: match,
      );
      addTearDown(() {
        home.dispose();
        match.dispose();
        titles.dispose();
        index.dispose();
      });
      await tester.pumpWidget(
        IndexScope(
          controller: index,
          child: TitlesScope(
            controller: titles,
            child: TmdbKeyScope(
              controller: tmdbKey,
              child: HomeScope(
                controller: home,
                child: ShellScope(
                  controller: ShellController(
                    pageFor: (_, _) => const SizedBox(),
                  ),
                  child: host(const HomeScreen(), disableAnimations: true),
                ),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('shows grey rows, but only if it takes long', (tester) async {
      final library = _SlowLibrary();
      await pump(tester, library);

      expect(find.byType(Skeleton), findsNothing);
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byType(Skeleton), findsNothing);

      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const Key('home-loading')), findsOneWidget);
      expect(find.byType(CardRowSkeleton), findsWidgets);

      library.answer.complete(const HomeContent());
      await tester.pump();
      await tester.pump();
      expect(find.byType(Skeleton), findsNothing);
      expect(find.byKey(const Key('home-start')), findsOneWidget);
    });

    testWidgets('a quick answer shows no grey at all', (tester) async {
      final library = _SlowLibrary();
      await pump(tester, library);

      library.answer.complete(const HomeContent());
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(Skeleton), findsNothing);
      expect(find.byKey(const Key('home-start')), findsOneWidget);
    });

    testWidgets('says so if the library cannot be read', (tester) async {
      final library = _SlowLibrary();
      await pump(tester, library);

      library.answer.completeError(const LibraryWorkException('broken'));
      await tester.pump();
      await tester.pump();

      expect(find.byKey(const Key('home-failed')), findsOneWidget);
      expect(find.text('The library could not be read'), findsOneWidget);
      expect(find.byKey(const Key('home-open-url')), findsOneWidget);
    });
  });
}

/// A library whose answer to Home's question comes when the test says.
class _SlowLibrary implements LibraryWorker {
  final answer = Completer<HomeContent>();

  @override
  Future<R> run<A, R>(LibraryWork<A, R> work, A argument) async =>
      await answer.future as R;

  @override
  Future<void> close() async {}
}
