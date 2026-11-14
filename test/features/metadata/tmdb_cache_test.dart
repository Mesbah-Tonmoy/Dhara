import 'dart:io';

import 'package:dhara/core/db/library_db.dart';
import 'package:dhara/features/metadata/metadata_store.dart';
import 'package:dhara/features/metadata/tmdb_cache.dart';
import 'package:dhara/features/metadata/tmdb_client.dart';
import 'package:dhara/features/metadata/video_identity.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/local_server.dart';

void main() {
  late LocalServer server;
  late LibraryDb library;
  late MetadataStore store;
  late CachedTmdb tmdb;
  late DateTime clock;

  void json(String path, String body, {int status = HttpStatus.ok}) =>
      server.serve(
        path,
        body,
        status: status,
        contentType: 'application/json; charset=utf-8',
      );

  int asked(String path) =>
      server.requests.where((request) => request.uri.path == path).length;

  int kept() =>
      library.db.select('SELECT count(*) AS n FROM metadata_cache').single['n']
          as int;

  setUp(() async {
    server = await LocalServer.start();
    json('/3/search/movie', fixture('tmdb/search_movie.json'));
    json('/3/search/tv', fixture('tmdb/search_tv.json'));
    library = LibraryDb.inMemory();
    clock = DateTime(2026, 11, 14, 12);
    store = MetadataStore(library, now: () => clock);
    final client = TmdbClient(
      key: '0123456789abcdef0123456789abcdef',
      kind: TmdbKeyKind.apiKey,
      http: server.client(),
      baseUrl: server.url('/3'),
      retries: 0,
      wait: (_) async {},
    );
    addTearDown(client.close);
    tmdb = CachedTmdb(client, store);
  });

  tearDown(() async {
    library.close();
    await server.close();
  });

  test('asks TMDB once and answers from the database after that', () async {
    final first = await tmdb.candidates(
      TitleKind.movie,
      'The Glass Harbor',
      year: 2019,
    );
    final again = await tmdb.candidates(
      TitleKind.movie,
      'The Glass Harbor',
      year: 2019,
    );

    expect(asked('/3/search/movie'), 1);
    expect([for (final film in again) film.id], [for (final f in first) f.id]);
    expect(again.first.toJson(), first.first.toJson());
    expect(again.first.posterPath, '/pGlassHarbor01.jpg');
    expect(kept(), 1);
  });

  test('another spelling of the title is the same question', () async {
    await tmdb.candidates(TitleKind.movie, 'The Glass Harbor', year: 2019);
    await tmdb.candidates(TitleKind.movie, 'the.glass-HARBOR!', year: 2019);

    expect(asked('/3/search/movie'), 1);
    expect(
      CachedTmdb.searchKey(TitleKind.movie, 'The Glass Harbor', 2019),
      'search|movie|the glass harbor|2019',
    );
    expect(
      CachedTmdb.searchKey(TitleKind.series, 'S.H.I.E.L.D.', null),
      'search|tv|shield|',
    );
    expect(
      CachedTmdb.searchKey(TitleKind.movie, ' !!! ', null),
      'search|movie|!!!|',
    );
  });

  test('another year, or a show of that name, is another question', () async {
    await tmdb.candidates(TitleKind.movie, 'The Quiet Signal', year: 2019);
    await tmdb.candidates(TitleKind.movie, 'The Quiet Signal', year: 2018);
    await tmdb.candidates(TitleKind.movie, 'The Quiet Signal');
    final shows = await tmdb.candidates(TitleKind.series, 'The Quiet Signal');

    expect(asked('/3/search/movie'), 3);
    expect(asked('/3/search/tv'), 1);
    expect(shows.first.kind, TitleKind.series);
    expect(kept(), 4);

    // A show comes back from the database as a show.
    final again = await tmdb.candidates(TitleKind.series, 'The Quiet Signal');
    expect(again.first.kind, TitleKind.series);
    expect(asked('/3/search/tv'), 1);
  });

  test('remembers that nothing was found, too', () async {
    json('/3/search/movie', '{"page":1,"results":[]}');

    expect(await tmdb.candidates(TitleKind.movie, 'Zzzz'), isEmpty);
    expect(await tmdb.candidates(TitleKind.movie, 'Zzzz'), isEmpty);

    expect(asked('/3/search/movie'), 1);
  });

  test('asks again once the answer is a month old', () async {
    await tmdb.candidates(TitleKind.movie, 'The Glass Harbor');

    clock = clock.add(const Duration(days: 29));
    await tmdb.candidates(TitleKind.movie, 'The Glass Harbor');
    expect(asked('/3/search/movie'), 1);

    clock = clock.add(const Duration(days: 2));
    await tmdb.candidates(TitleKind.movie, 'The Glass Harbor');
    expect(asked('/3/search/movie'), 2);
    expect(kept(), 1, reason: 'the new answer replaces the old one');
  });

  test('does not trust an answer from the future', () async {
    await tmdb.candidates(TitleKind.movie, 'The Glass Harbor');

    clock = clock.subtract(const Duration(days: 3));
    await tmdb.candidates(TitleKind.movie, 'The Glass Harbor');

    expect(asked('/3/search/movie'), 2);
  });

  test('keeps nothing when TMDB gives no answer', () async {
    json('/3/search/movie', '{}', status: HttpStatus.internalServerError);

    await expectLater(
      tmdb.candidates(TitleKind.movie, 'The Glass Harbor'),
      throwsA(isA<TmdbException>()),
    );
    expect(kept(), 0);

    json('/3/search/movie', fixture('tmdb/search_movie.json'));
    expect(
      await tmdb.candidates(TitleKind.movie, 'The Glass Harbor'),
      isNotEmpty,
    );
  });

  test('asks again if what was kept cannot be read', () async {
    await tmdb.candidates(TitleKind.movie, 'The Glass Harbor');
    library.db.execute("UPDATE metadata_cache SET body = 'not json'");
    expect(
      await tmdb.candidates(TitleKind.movie, 'The Glass Harbor'),
      hasLength(5),
    );
    expect(asked('/3/search/movie'), 2);

    library.db.execute("UPDATE metadata_cache SET body = '{\"a\":1}'");
    await tmdb.candidates(TitleKind.movie, 'The Glass Harbor');
    expect(asked('/3/search/movie'), 3);

    // Entries that are not candidates are left out; the rest counts.
    library.db.execute(
      'UPDATE metadata_cache SET body = '
      "'[{\"id\":7,\"title\":\"Kept\"},{\"id\":0},42]'",
    );
    final kept = await tmdb.candidates(TitleKind.movie, 'The Glass Harbor');
    expect([for (final film in kept) film.title], ['Kept']);
    expect(asked('/3/search/movie'), 3);
  });

  test('forgets answers that no longer count', () async {
    await tmdb.candidates(TitleKind.movie, 'Old One');
    clock = clock.add(const Duration(days: 20));
    await tmdb.candidates(TitleKind.movie, 'Newer One');
    store.cacheAnswer('anilist', 'trending', '[]');
    clock = clock.add(const Duration(days: 15));

    expect(tmdb.forgetOldAnswers(), 1);

    expect(
      [
        for (final row in library.db.select(
          'SELECT provider, key FROM metadata_cache ORDER BY key',
        ))
          '${row['provider']} ${row['key']}',
      ],
      ['tmdb search|movie|newer one|', 'anilist trending'],
    );
  });
}
