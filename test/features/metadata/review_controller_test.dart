import 'package:dhara/core/db/library_db.dart';
import 'package:dhara/core/db/library_isolate.dart';
import 'package:dhara/core/secrets/secret_store.dart';
import 'package:dhara/features/indexer/index_controller.dart';
import 'package:dhara/features/metadata/match_controller.dart';
import 'package:dhara/features/metadata/match_store.dart';
import 'package:dhara/features/metadata/review_controller.dart';
import 'package:dhara/features/metadata/review_store.dart';
import 'package:dhara/features/metadata/title_matcher.dart';
import 'package:dhara/features/metadata/titles_controller.dart';
import 'package:dhara/features/metadata/tmdb_key.dart';
import 'package:dhara/features/metadata/video_identity.dart';
import 'package:dhara/features/sources/source.dart';
import 'package:dhara/features/sources/source_store.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_tmdb.dart';
import '../../support/local_server.dart';

const _apiKey = '0123456789abcdef0123456789abcdef';

var _urls = 0;

/// Puts videos into the index, in the folder [path] of [source].
void _put(LibraryDb library, String source, String path, List<String> names) {
  final db = library.db;
  db.execute(
    'INSERT INTO sources (source_id, crawl_started_at, crawl_finished_at) '
    'VALUES (?, 1, 2) ON CONFLICT (source_id) DO NOTHING',
    [source],
  );
  db.execute(
    'INSERT INTO folders (source, url, path, depth, state) '
    'SELECT id, ?, ?, 1, 1 FROM sources WHERE source_id = ?',
    ['http://$source.test/${_urls++}/', path, source],
  );
  final folder = db.lastInsertRowId;
  for (final name in names) {
    db.execute(
      'INSERT INTO files (folder, name, url, added_at) VALUES (?, ?, ?, 0)',
      [folder, name, 'http://$source.test/${_urls++}/$name'],
    );
  }
}

void main() {
  late LocalServer server;
  late FakeTmdb tmdb;
  late LibraryDb db;
  late SourceStore sources;
  late TitlesController titles;
  late TmdbKeyController tmdbKey;
  late MatchController match;
  late ReviewController review;

  /// Opens the controllers, reads the names and looks every title up.
  Future<void> open({String? key = _apiKey}) async {
    sources = SourceStore(
      starter: [
        for (final id in ['icc', 'flix'])
          Source(
            id: id,
            name: id,
            type: SourceType.directoryListing,
            category: SourceCategory.mixed,
            baseUrls: [Uri.parse('http://10.0.0.1/$id/')],
          ),
      ],
    );
    await sources.setEnabled(['icc', 'flix'], enabled: true);
    final library = LocalLibrary(db);
    final index = IndexController(
      library: library,
      sources: sources,
      deviceId: 'dhara-test',
    );
    titles = TitlesController(library: library, index: index);
    final secrets = MemorySecretStore();
    if (key != null) await secrets.write('tmdb', key);
    tmdbKey = TmdbKeyController(secrets);
    await tmdbKey.load();
    match = MatchController(
      library: library,
      titles: titles,
      tmdbKey: tmdbKey,
      tmdbUrl: tmdb.url,
      tmdbRetries: 0,
    );
    review = ReviewController(
      library: library,
      titles: titles,
      match: match,
      tmdbKey: tmdbKey,
      tmdbUrl: tmdb.url,
      tmdbRetries: 0,
    );
    addTearDown(() {
      review.dispose();
      match.dispose();
      titles.dispose();
      index.dispose();
    });
    await index.load();
    await titles.refresh();
    await pumpEventQueue();
    await match.start();
  }

  ReviewItem item(String name) =>
      review.items!.singleWhere((entry) => entry.spelledName == name);

  Map<String, Object?> row(String name) =>
      db.db.select('SELECT * FROM titles WHERE name = ?', [name]).single;

  setUp(() async {
    server = await LocalServer.start();
    tmdb = FakeTmdb(server)
      ..addFilm(1, 'Stillwater', 2018)
      ..addFilm(2, 'Hell', 2011, votes: 500)
      ..addFilm(3, 'Hell', 2005)
      ..addFilm(4, 'The Real Name', 1999);
    db = LibraryDb.inMemory();
    addTearDown(db.close);
    _put(db, 'icc', 'Movies/English', [
      'Stillwater (2018) 1080p WEBDL.mkv',
      'Hell.mkv',
      'A Wrong Name (1999) 720p.mkv',
    ]);
  });

  tearDown(() => server.close());

  test('lists what is unsure and what was not found', () async {
    await open();
    expect(review.items, isNull);

    await review.load();

    final items = review.items!;
    expect(
      [for (final entry in items) entry.spelledName],
      ['Hell', 'A Wrong Name'],
    );
    expect(items.first.notFound, isFalse);
    expect(items.first.confidence, 78);
    expect(items.first.kind, TitleKind.movie);
    expect(items.first.posterPath, isNotNull);
    expect(items.first.copies, 1);
    expect(items.first.sampleName, 'Hell.mkv');
    expect(items.first.samplePath, 'Movies/English');
    expect(items.last.notFound, isTrue);
    expect(items.last.spelledYear, 1999);
  });

  test('leaves out titles on sources that are switched off', () async {
    _put(db, 'flix', 'Movies', ['Only On Flix (2001).mkv']);
    await open();
    await sources.setEnabled(['flix'], enabled: false);

    await review.load();

    expect([
      for (final entry in review.items!) entry.spelledName,
    ], isNot(contains('Only On Flix')));
  });

  test(
    'offers what TMDB said before, best fit first, without asking',
    () async {
      await open();
      await review.load();
      final asked = tmdb.asked.length;

      final candidates = await review.candidatesOf(item('Hell'));

      expect([for (final entry in candidates) entry.candidate.id], [2, 3]);
      expect(candidates.first.confidence, lessThan(sureConfidence));
      expect(await review.candidatesOf(item('A Wrong Name')), isEmpty);
      expect(tmdb.asked, hasLength(asked));
    },
  );

  test('searches TMDB by another name', () async {
    await open();
    await review.load();
    final wrong = item('A Wrong Name');

    final found = await review.search(wrong, ' The Real Name ', 1999);

    expect(found.failure, isNull);
    expect(found.candidates.single.candidate.id, 4);
    expect(found.candidates.single.confidence, 100);
    expect(tmdb.asked.last, 'movie|the real name|1999');

    final none = await review.search(wrong, 'Zzzz', null);
    expect(none.failure, isNull);
    expect(none.candidates, isEmpty);
    final empty = await review.search(wrong, '   ', null);
    expect(empty.failure, isNull);
    expect(empty.candidates, isEmpty);
  });

  test('says why a search gave no answer', () async {
    await open();
    await review.load();
    final wrong = item('A Wrong Name');

    tmdb.failWith = 401;
    final refused = await review.search(wrong, 'The Real Name', null);
    expect(refused.failure, 'TMDB does not accept the key.');
    expect(refused.candidates, isEmpty);

    tmdb.failWith = 500;
    final down = await review.search(wrong, 'Another Name', null);
    expect(down.failure, startsWith('TMDB'));

    await tmdbKey.remove();
    final keyless = await review.search(wrong, 'The Real Name', null);
    expect(keyless.failure, 'Add a TMDB key first.');
  });

  test('a choice is final and takes the title off the list', () async {
    await open();
    await review.load();
    final hell = item('Hell');
    final older = (await review.candidatesOf(hell)).last.candidate;
    expect(older.id, 3);
    var told = 0;
    review.addListener(() => told++);

    await review.choose(hell, older);

    expect(
      [for (final entry in review.items!) entry.spelledName],
      ['A Wrong Name'],
    );
    expect(told, 1);
    final chosen = row('Hell');
    expect(chosen['tmdb_id'], 3);
    expect(chosen['year'], 2005);
    expect(chosen['match_state'], MatchState.byHand);
    expect(chosen['confidence'], 100);
    expect(
      db.db
          .select('SELECT fixed FROM title_keys WHERE title = ?', [
            chosen['id'],
          ])
          .single
          .values,
      [1],
    );
    final counts = match.counts!;
    expect((counts.unsure, counts.byHand), (0, 1));

    // No later run changes it.
    await match.start();
    expect(row('Hell')['tmdb_id'], 3);
  });

  test('a choice that is another title already makes them one', () async {
    await open();
    await review.load();
    final wrong = item('A Wrong Name');
    final found = await review.search(wrong, 'Stillwater', null);

    await review.choose(wrong, found.candidates.single.candidate);

    expect(
      db.db.select('SELECT count(*) AS n FROM titles').single['n'],
      2,
      reason: 'Stillwater and Hell',
    );
    final hit = (await titles.search('stillwater')).single;
    expect(hit.copies, 2);
    expect(row('Stillwater')['match_state'], MatchState.byHand);
  });

  test('left as it is, a title is off the list and never looked up', () async {
    await open();
    await review.load();

    await review.leaveAsIs(item('A Wrong Name'));

    expect([for (final entry in review.items!) entry.spelledName], ['Hell']);
    final left = row('A Wrong Name');
    expect(left['match_state'], MatchState.leftAlone);
    expect(left['tmdb_id'], isNull);
    final asked = tmdb.asked.length;
    await match.start();
    expect(tmdb.asked, hasLength(asked));
    expect(match.counts!.notFound, 0);
    expect((await titles.search('wrong name')).single.name, 'A Wrong Name');
  });

  test('without a library the list is empty and nothing breaks', () async {
    final index = IndexController(
      library: const NoLibrary(),
      sources: SourceStore(starter: const []),
      deviceId: 'dhara-test',
    );
    final none = TitlesController(library: const NoLibrary(), index: index);
    final keys = TmdbKeyController(MemorySecretStore());
    final matching = MatchController(
      library: const NoLibrary(),
      titles: none,
      tmdbKey: keys,
    );
    final lost = ReviewController(
      library: const NoLibrary(),
      titles: none,
      match: matching,
      tmdbKey: keys,
    );
    addTearDown(() {
      lost.dispose();
      matching.dispose();
      none.dispose();
      index.dispose();
    });

    await lost.load();

    expect(lost.items, isEmpty);
  });
}
