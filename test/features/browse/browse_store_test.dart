import 'package:dhara/core/db/library_db.dart';
import 'package:dhara/core/db/library_isolate.dart';
import 'package:dhara/features/browse/browse_controller.dart';
import 'package:dhara/features/browse/browse_store.dart';
import 'package:dhara/features/indexer/index_controller.dart';
import 'package:dhara/features/metadata/metadata_store.dart';
import 'package:dhara/features/metadata/titles_controller.dart';
import 'package:dhara/features/metadata/video_identity.dart';
import 'package:dhara/features/sources/source.dart';
import 'package:dhara/features/sources/source_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  late LibraryDb library;
  late Database db;
  var urls = 0;

  setUp(() {
    library = LibraryDb.inMemory();
    db = library.db;
  });

  tearDown(() => library.close());

  BrowseStore store([List<String> sources = const ['flix', 'icc']]) =>
      BrowseStore(library, sourceIds: sources);

  /// Puts a video into the index, reads its name, and returns its title.
  int add(String path, String name, {String source = 'icc'}) {
    db.execute(
      'INSERT INTO sources (source_id) VALUES (?) '
      'ON CONFLICT (source_id) DO NOTHING',
      [source],
    );
    db.execute(
      'INSERT INTO folders (source, url, path, depth) '
      'SELECT id, ?, ?, 1 FROM sources WHERE source_id = ?',
      ['http://$source.test/${urls++}/', path, source],
    );
    db.execute(
      'INSERT INTO files (folder, name, url, added_at) VALUES (?, ?, ?, 0)',
      [db.lastInsertRowId, name, 'http://$source.test/${urls++}/$name'],
    );
    final file = db.lastInsertRowId;
    MetadataStore(library).saveIdentities({
      file: identifyVideo(path: path, name: name, latestYear: 2027),
    });
    return db.select('SELECT title FROM file_meta WHERE file = ?', [
          file,
        ]).single['title']
        as int;
  }

  int film(
    String name,
    int year, {
    String quality = '1080p',
    String source = 'icc',
    double? rating,
    int? votes,
    String? genres,
    String? language,
    int state = 1,
  }) {
    final id = add('Movies', '$name ($year) $quality.mkv', source: source);
    db.execute(
      'UPDATE titles SET match_state = ?, rating = ?, votes = ?, genres = ?, '
      'language = ? WHERE id = ?',
      [state, rating, votes, genres, language, id],
    );
    return id;
  }

  int show(String name, {String? genres, String? language, double? rating}) {
    final id = add('Tv/$name/Season 1', '$name S01E01 720p.mkv');
    db.execute(
      'UPDATE titles SET match_state = 1, year = 2019, genres = ?, '
      'language = ?, rating = ? WHERE id = ?',
      [genres, language, rating, id],
    );
    return id;
  }

  List<String> names(BrowseQuery query, [BrowseStore? from]) {
    final found = (from ?? store()).find(query);
    return [for (final card in (from ?? store()).cards(found.ids)) card.name];
  }

  void seed() {
    film(
      'The Glass Harbor',
      2019,
      rating: 7.4,
      votes: 900,
      genres: 'Drama, Mystery',
    );
    film(
      'Harbor Lights',
      2024,
      quality: '2160p',
      rating: 8.3,
      votes: 100,
      genres: 'Drama',
    );
    film(
      'Ashfall',
      2021,
      quality: '720p',
      rating: 6.1,
      votes: 5000,
      genres: 'Action, Drama',
    );
    film('Home Video', 2020, quality: '480p', state: 3);
    show('The Bay', genres: 'Crime, Drama', rating: 7.9);
    show('Mushishi', genres: 'Animation, Mystery', language: 'ja', rating: 8.6);
  }

  group('find', () {
    test('without anything asked, lists every title, the newest first', () {
      seed();

      final result = store().find(const BrowseQuery());

      expect(result.total, 6);
      expect(result.ids, hasLength(6));
      expect(names(const BrowseQuery()).first, 'Harbor Lights');
      expect(
        names(const BrowseQuery()),
        contains('Home Video'),
        reason: 'also what TMDB does not know',
      );
    });

    test('finds titles by the words of their name, the last unfinished', () {
      seed();

      expect(names(const BrowseQuery(text: 'harbor')).toSet(), {
        'The Glass Harbor',
        'Harbor Lights',
      });
      expect(names(const BrowseQuery(text: 'glass harb')), [
        'The Glass Harbor',
      ]);
      expect(names(const BrowseQuery(text: 'nothing like it')), isEmpty);
      final result = store().find(const BrowseQuery(text: 'harbor'));
      expect((result.ids.length, result.total), (2, 6));
    });

    test('what is typed cannot act as query syntax', () {
      seed();

      for (final text in ['"', 'harbor OR ashfall', "x' OR 1=1 --", '* NOT']) {
        expect(
          () => store().find(BrowseQuery(text: text)),
          returnsNormally,
          reason: text,
        );
      }
      expect(names(const BrowseQuery(text: 'harbor OR ashfall')), isEmpty);
    });

    test('narrows by kind', () {
      seed();

      expect(names(const BrowseQuery(kind: BrowseKind.series)).toSet(), {
        'The Bay',
        'Mushishi',
      });
      expect(names(const BrowseQuery(kind: BrowseKind.movies)), hasLength(4));
      expect(names(const BrowseQuery(kind: BrowseKind.anime)), ['Mushishi']);
    });

    test('narrows by quality, rating, year and genres', () {
      seed();

      expect(names(const BrowseQuery(minHeight: 2160)), ['Harbor Lights']);
      expect(names(const BrowseQuery(minHeight: 1080)).toSet(), {
        'Harbor Lights',
        'The Glass Harbor',
      });
      expect(names(const BrowseQuery(minRating: 8)).toSet(), {
        'Harbor Lights',
        'Mushishi',
      });
      expect(names(const BrowseQuery(year: 2021)), ['Ashfall']);
      expect(names(const BrowseQuery(year: 2020, yearOrOlder: true)).toSet(), {
        'Home Video',
        'The Glass Harbor',
        'The Bay',
        'Mushishi',
      });
      expect(names(const BrowseQuery(genres: {'Drama', 'Mystery'})), [
        'The Glass Harbor',
      ]);
      // All of it together, with a search.
      expect(
        names(
          const BrowseQuery(
            text: 'har',
            kind: BrowseKind.movies,
            minRating: 7,
            genres: {'Drama'},
            minHeight: 1080,
          ),
        ).toSet(),
        {'Harbor Lights', 'The Glass Harbor'},
      );
    });

    test('a genre is matched whole', () {
      film('Stage Play', 2020, genres: 'Live Action, Drama');
      film('Car Chase', 2021, genres: 'Action');

      expect(names(const BrowseQuery(genres: {'Action'})), ['Car Chase']);
    });

    test('orders by rating, by year, or by name', () {
      seed();

      expect(names(const BrowseQuery(sort: BrowseSort.rating)).take(3), [
        'Mushishi',
        'Harbor Lights',
        'The Bay',
      ]);
      expect(names(const BrowseQuery(sort: BrowseSort.newest)).take(2), [
        'Harbor Lights',
        'Ashfall',
      ]);
      expect(names(const BrowseQuery(sort: BrowseSort.name)), [
        'Ashfall',
        'Harbor Lights',
        'Home Video',
        'Mushishi',
        'The Bay',
        'The Glass Harbor',
      ]);
      // With a search, relevance is the order unless another is asked for.
      expect(names(const BrowseQuery(text: 'harbor', sort: BrowseSort.name)), [
        'Harbor Lights',
        'The Glass Harbor',
      ]);
    });

    test('only finds what an enabled source holds, at the quality it '
        'holds there', () {
      film('Both', 2020, quality: '720p');
      add('Movies', 'Both (2020) 2160p.mkv', source: 'flix');
      film('Elsewhere', 2021, source: 'flix');

      final here = store(['icc']);
      expect(names(const BrowseQuery(), here), ['Both']);
      expect(here.find(const BrowseQuery()).total, 1);
      expect(names(const BrowseQuery(minHeight: 2160), here), isEmpty);
      expect(names(const BrowseQuery(minHeight: 2160)), ['Both']);
      // A total that the caller knows is not counted again.
      final told = here.find(const BrowseQuery(text: 'both'), knownTotal: 42);
      expect(told.total, 42);
      expect(told.ids, here.find(const BrowseQuery(text: 'both')).ids);

      expect(store([]).find(const BrowseQuery()).ids, isEmpty);
      expect(store([]).find(const BrowseQuery(text: 'both')).total, 0);
    });

    test('leaves out what was set aside, and titles with trailers only', () {
      final aside = film('Set Aside', 2020);
      db.execute('UPDATE titles SET set_aside = 1 WHERE id = ?', [aside]);
      add('Movies', 'Coming Soon (2027) Trailer.mkv');
      film('Here', 2021);

      expect(names(const BrowseQuery()), ['Here']);
    });

    test('lists the genres there are, A to Z', () {
      seed();

      expect(store().genres(), [
        'Action',
        'Animation',
        'Crime',
        'Drama',
        'Mystery',
      ]);
    });
  });

  test('searches and filters a large library quickly', () {
    library.transaction(() {
      db
        ..execute("INSERT INTO sources (id, source_id) VALUES (1, 'icc')")
        ..execute(
          'INSERT INTO folders (id, source, url, path, depth) '
          "VALUES (1, 1, 'http://icc.test/', 'All', 0)",
        );
      final addTitle = db.prepare(
        'INSERT INTO titles (id, kind, name, year, match_state, rating, '
        'votes, genres, language, added_at) '
        'VALUES (?, ?, ?, ?, 1, ?, ?, ?, ?, 0)',
      );
      final addFile = db.prepare(
        'INSERT INTO files (id, folder, name, url, added_at) '
        'VALUES (?, 1, ?, ?, 0)',
      );
      final addMeta = db.prepare(
        'INSERT INTO file_meta (file, parser, kind, title, height) '
        'VALUES (?, 1, 0, ?, ?)',
      );
      var file = 0;
      const words = ['Harbor', 'Glass', 'Ashfall', 'Lantern', 'Signal', 'Tide'];
      for (var id = 1; id <= 20000; id++) {
        addTitle.execute([
          id,
          if (id % 5 == 0) 1 else 0,
          '${words[id % 6]} ${words[id * 7 % 6]} Number $id',
          1960 + id % 67,
          4 + (id % 55) / 10,
          id * 7 % 5000,
          id % 3 == 0 ? 'Drama, Mystery' : 'Action, Drama',
          id % 9 == 0 ? 'ja' : 'en',
        ]);
        for (var copy = 0; copy < 5; copy++) {
          file++;
          addFile.execute([file, 'f$file.mkv', 'http://icc.test/$file.mkv']);
          addMeta.execute([
            file,
            id,
            const [480, 720, 1080, 2160][file % 4],
          ]);
        }
      }
      for (final statement in [addTitle, addFile, addMeta]) {
        statement.close();
      }
    });
    final big = store(['icc']);

    Duration time(BrowseQuery query) {
      var best = const Duration(days: 1);
      for (var i = 0; i < 3; i++) {
        final watch = Stopwatch()..start();
        big.find(query);
        watch.stop();
        if (watch.elapsed < best) best = watch.elapsed;
      }
      return best;
    }

    final everything = time(const BrowseQuery());
    final typed = time(const BrowseQuery(text: 'harbor glass num'));
    final filtered = time(
      const BrowseQuery(
        kind: BrowseKind.movies,
        minHeight: 2160,
        minRating: 7,
        genres: {'Mystery'},
        sort: BrowseSort.name,
      ),
    );
    final ids = big.find(const BrowseQuery()).ids;
    var page = const Duration(days: 1);
    var cards = big.cards(ids.sublist(0, 60));
    for (var i = 1; i <= 3; i++) {
      final watch = Stopwatch()..start();
      cards = big.cards(ids.sublist(i * 60, i * 60 + 60));
      watch.stop();
      if (watch.elapsed < page) page = watch.elapsed;
    }
    // ignore: avoid_print
    print(
      'Browse 20,000 titles (100,000 videos): everything '
      '${everything.inMicroseconds / 1000} ms, a search '
      '${typed.inMicroseconds / 1000} ms, filters '
      '${filtered.inMicroseconds / 1000} ms, a page of 60 cards '
      '${page.inMicroseconds / 1000} ms',
    );

    expect(big.find(const BrowseQuery()).ids, hasLength(20000));
    expect(cards, hasLength(60));
    // The aims: a search under 100 ms, a page of the grid under 20 ms. The
    // limits only catch a blow-up on a slow machine.
    expect(typed, lessThan(const Duration(milliseconds: 500)));
    expect(everything, lessThan(const Duration(milliseconds: 1500)));
    expect(filtered, lessThan(const Duration(milliseconds: 1500)));
    expect(page, lessThan(const Duration(milliseconds: 300)));
  });

  group('BrowseController', () {
    late BrowseController browse;
    late SourceStore sources;

    Future<void> open() async {
      sources = SourceStore(
        starter: [
          for (final id in ['icc', 'flix'])
            Source(
              id: id,
              name: id,
              type: SourceType.h5ai,
              category: SourceCategory.mixed,
              baseUrls: [Uri.parse('http://$id.test/')],
            ),
        ],
      );
      await sources.setEnabled(['icc', 'flix'], enabled: true);
      final worker = LocalLibrary(library);
      final index = IndexController(
        library: worker,
        sources: sources,
        deviceId: 'dhara-test',
      );
      final titles = TitlesController(library: worker, index: index);
      browse = BrowseController(
        library: worker,
        titles: titles,
        typingPause: const Duration(milliseconds: 20),
      );
      addTearDown(() {
        browse.dispose();
        titles.dispose();
        index.dispose();
      });
    }

    Future<void> settle() async {
      await Future<void>.delayed(const Duration(milliseconds: 40));
      await pumpEventQueue();
    }

    test('asks nothing until it is used, then answers the query', () async {
      seed();
      await open();
      expect(browse.result, isNull);

      browse.ensureLoaded();
      await settle();

      expect(browse.count, 6);
      expect(browse.result!.total, 6);
      expect(browse.genres, contains('Mystery'));
      expect(browse.failed, isFalse);
    });

    test(
      'typing asks once it pauses, and only the last answer counts',
      () async {
        seed();
        await open();
        var told = 0;
        browse.addListener(() => told++);

        browse
          ..setText('h')
          ..setText('ha')
          ..setText('harbor');
        expect(browse.query.text, 'harbor');
        expect(browse.result, isNull, reason: 'not asked yet');
        await settle();

        expect(browse.count, 2);
        expect(told, lessThan(8));
      },
    );

    test('a filter asks at once; reset takes them all off', () async {
      seed();
      await open();
      browse.setText('harbor');
      browse.change((query) => query.copyWith(minHeight: () => 2160));
      await pumpEventQueue();

      expect(browse.count, 1);
      expect(browse.query.hasNoFilters, isFalse);

      browse.resetFilters();
      await pumpEventQueue();
      expect(browse.count, 2);
      expect(browse.query.text, 'harbor', reason: 'what was typed stays');
      expect(browse.query.hasNoFilters, isTrue);
    });

    test('reads the cards a page at a time, as they are asked for', () async {
      for (var i = 0; i < 150; i++) {
        film('Film $i', 2000);
      }
      await open();
      browse.ensureLoaded();
      await settle();
      expect(browse.count, 150);

      expect(browse.cardAt(0), isNull, reason: 'being read');
      await pumpEventQueue();
      expect(browse.cardAt(0), isNotNull);
      expect(browse.cardAt(59), isNotNull);
      expect(browse.cardAt(60), isNull, reason: 'the next page');
      await pumpEventQueue();
      expect(browse.cardAt(119), isNotNull);
      expect(browse.cardAt(500), isNull);
    });

    test('says so when the library does not answer', () async {
      await open();
      final broken = BrowseController(
        library: const NoLibrary(),
        titles: TitlesController(
          library: const NoLibrary(),
          index: IndexController(
            library: const NoLibrary(),
            sources: sources,
            deviceId: 'dhara-test',
          ),
        ),
      );
      addTearDown(broken.dispose);

      broken.ensureLoaded();
      await pumpEventQueue();

      expect(broken.failed, isTrue);
      expect(broken.result, isNull);
    });
  });
}
