import 'dart:convert';
import 'dart:io';

import 'package:dhara/core/db/library_db.dart';
import 'package:dhara/features/indexer/index_store.dart';
import 'package:dhara/features/sources/adapters/source_adapter.dart';
import 'package:dhara/features/sources/source.dart';

/// The two servers the library of [fillSnapshotLibrary] was read from.
final snapshotSources = [
  Source(
    id: 'alpha',
    name: 'Alpha',
    type: SourceType.h5ai,
    category: SourceCategory.movies,
    baseUrls: [Uri.parse('http://10.0.0.1/alpha/')],
  ),
  Source(
    id: 'beta',
    name: 'Beta',
    type: SourceType.directoryListing,
    category: SourceCategory.series,
    baseUrls: [Uri.parse('http://beta.test:8080/')],
  ),
];

/// A small library as a development build would have it: two servers
/// crawled to the end, a film with two copies and a subtitle, a show with
/// a season of two episodes, all matched; and what a snapshot must leave
/// out (something watched, My List, an answer of TMDB).
void fillSnapshotLibrary(LibraryDb library) {
  final store = IndexStore(library, now: () => DateTime.utc(2026, 11, 20));
  final [alpha, beta] = snapshotSources;

  final a = store.beginCrawl(alpha.id, alpha.baseUrls);
  final aBase = alpha.baseUrls.single;
  store.saveListing(
    store.pendingFolders(a).single,
    FolderListing(
      folders: [
        RemoteEntry(
          name: 'Films',
          url: aBase.resolve('Films/'),
          isFolder: true,
          modified: DateTime.utc(2026, 11, 1),
        ),
      ],
    ),
    maxDepth: 12,
    folderBudget: 100,
  );
  store.saveListing(
    store.pendingFolders(a).single,
    FolderListing(
      videos: [
        IndexedVideo(
          RemoteEntry(
            name: 'Vivarium.2019.1080p.mkv',
            url: aBase.resolve('Films/Vivarium.2019.1080p.mkv'),
            isFolder: false,
            size: 2147483648,
            modified: DateTime.utc(2026, 10, 2),
          ),
          [
            RemoteEntry(
              name: 'Vivarium.2019.1080p.srt',
              url: aBase.resolve('Films/Vivarium.2019.1080p.srt'),
              isFolder: false,
            ),
          ],
        ),
      ],
    ),
    maxDepth: 12,
    folderBudget: 100,
  );
  store.finishCrawl(a);

  final b = store.beginCrawl(beta.id, beta.baseUrls);
  final bBase = beta.baseUrls.single;
  store.saveListing(
    store.pendingFolders(b).single,
    FolderListing(
      videos: [
        for (final name in const [
          'Vivarium (2019) 720p.mp4',
          'The.Bay.S01E01.mkv',
          'The.Bay.S01E02.mkv',
        ])
          IndexedVideo(
            RemoteEntry(
              name: name,
              url: bBase.resolve(Uri.encodeComponent(name)),
              isFolder: false,
              size: 1000,
            ),
          ),
      ],
    ),
    maxDepth: 12,
    folderBudget: 100,
  );
  store.finishCrawl(b);

  int file(String name) =>
      library.db.select('SELECT id FROM files WHERE name = ?', [
            name,
          ]).single['id']
          as int;

  library.db
    ..execute(
      'INSERT INTO titles (id, kind, name, year, tmdb_id, match_state, '
      'confidence, overview, rating, votes, genres, language, poster_path, '
      'backdrop_path, matched_at, added_at, runtime, director, actors, '
      'details_at) VALUES '
      "(1, 0, 'Vivarium', 2019, 458305, 1, 96, 'A couple looks for a home.', "
      "5.9, 2100, 'Science Fiction, Thriller', 'en', '/viva.jpg', "
      "'/viva-back.jpg', 1700000000000, 1690000000000, 98, 'Lorcan Finnegan', "
      "'Imogen Poots, Jesse Eisenberg', 1700000001000), "
      "(2, 1, 'The Bay', 2019, 86430, 1, 90, 'A family liaison officer.', "
      "7.2, 150, 'Crime, Drama', 'en', '/bay.jpg', NULL, 1700000000000, "
      '1690000000000, NULL, NULL, NULL, NULL)',
    )
    ..execute(
      'INSERT INTO title_keys (key, title, name, year, fixed) VALUES '
      "('m|vivarium|2019', 1, 'Vivarium', 2019, 0), "
      "('s|the bay', 2, 'The Bay', NULL, 1)",
    )
    ..execute(
      'INSERT INTO seasons (title, season, name, episode_count) '
      "VALUES (2, 1, 'Series 1', 6)",
    )
    ..execute(
      'INSERT INTO episodes (title, season, episode, name, runtime) VALUES '
      "(2, 1, 1, 'Episode 1', 47), (2, 1, 2, 'Episode 2', 46)",
    )
    ..execute(
      'INSERT INTO file_meta (file, parser, kind, title, season, episode, '
      'height, codec) VALUES '
      "(?, 7, 0, 1, NULL, NULL, 1080, 'x264'), "
      '(?, 7, 0, 1, NULL, NULL, 720, NULL), '
      '(?, 7, 1, 2, 1, 1, NULL, NULL), '
      '(?, 7, 1, 2, 1, 2, NULL, NULL)',
      [
        file('Vivarium.2019.1080p.mkv'),
        file('Vivarium (2019) 720p.mp4'),
        file('The.Bay.S01E01.mkv'),
        file('The.Bay.S01E02.mkv'),
      ],
    )
    // What stays on this PC.
    ..execute(
      'INSERT INTO playback (url, position_ms, duration_ms, updated_at) '
      "VALUES ('http://private.test/watched.mkv', 5, 10, 1)",
    )
    ..execute(
      'INSERT INTO watch_history (url, watched_at, position_ms, duration_ms) '
      "VALUES ('http://private.test/watched.mkv', 1, 5, 10)",
    )
    ..execute('INSERT INTO my_list (title, added_at) VALUES (2, 1)')
    ..execute(
      'INSERT INTO metadata_cache (provider, key, body, fetched_at) '
      "VALUES ('tmdb', 'movie/458305', dhara_pack('private-answer'), 1)",
    )
    ..execute("UPDATE sources SET last_error = 'private-error'");
}

/// The lines of the snapshot at [path], each as JSON gave it.
List<Object?> readSnapshotLines(String path) => [
  for (final line in const LineSplitter().convert(
    utf8.decode(gzip.decode(File(path).readAsBytesSync())),
  ))
    jsonDecode(line),
];
