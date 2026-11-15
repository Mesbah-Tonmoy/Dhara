import 'dart:convert';

import 'package:dhara/core/db/library_db.dart';
import 'package:dhara/features/metadata/match_store.dart';
import 'package:dhara/features/metadata/tmdb_cache.dart';
import 'package:dhara/features/metadata/tmdb_client.dart';
import 'package:dhara/features/metadata/video_identity.dart';
import 'package:flutter/foundation.dart';
import 'package:sqlite3/sqlite3.dart';

/// A title TMDB was asked about without a sure answer: matched but put up
/// for review, or not found. Names and paths are server-controlled text.
@immutable
class ReviewItem {
  const ReviewItem({
    required this.id,
    required this.kind,
    required this.name,
    required this.spelledName,
    required this.notFound,
    required this.copies,
    this.year,
    this.spelledYear,
    this.altName,
    this.confidence,
    this.posterPath,
    this.sampleName,
    this.samplePath,
  });

  final int id;
  final TitleKind kind;

  /// What the title is called now: TMDB's name if it was matched.
  final String name;
  final int? year;

  /// The name and year the folder or file gives it, to ask TMDB by.
  final String spelledName;
  final int? spelledYear;

  /// The name the file gives it when its folder says otherwise.
  final String? altName;

  /// TMDB has nothing that fits; otherwise it is matched, but not surely.
  final bool notFound;

  /// How sure the best candidate was, 0 to 100, if there was one.
  final int? confidence;
  final String? posterPath;

  /// How many videos of it there are, trailers and samples left out.
  final int copies;

  /// One of its videos, and the folders that one is in.
  final String? sampleName;
  final String? samplePath;
}

/// Reads and writes the part of the library database that the Needs review
/// screen works on.
///
/// Every value goes into SQL as a parameter, never as text.
class ReviewStore {
  ReviewStore(this._library, {DateTime Function() now = DateTime.now})
    : _clock = now;

  final LibraryDb _library;
  final DateTime Function() _clock;

  Database get _db => _library.db;

  /// The titles to review that have a video on one of the sources in
  /// [sourceIds]: the unsure matches first, then what was not found, each
  /// by name.
  ///
  /// With [only], the title with that id alone, whatever its state: to put
  /// right a match nobody doubted.
  ///
  /// At most [limit] of them, after the first [offset]: the list is read a
  /// part at a time. [count] says how many there are in all.
  List<ReviewItem> items({
    required Iterable<String> sourceIds,
    int limit = 500,
    int offset = 0,
    int? only,
  }) {
    final ids = sourceIds.toList();
    if (ids.isEmpty) return const [];
    return [
      for (final row in _db.select(
        'SELECT t.id, t.kind, t.name, t.year, t.match_state, t.confidence, '
        't.poster_path, k.name AS spelled, k.year AS spelled_year, '
        'k.alt_name, '
        '(SELECT count(*) FROM file_meta m WHERE m.title = t.id '
        'AND m.extra IS NULL) AS copies, '
        '(SELECT f.name FROM file_meta m JOIN files f ON f.id = m.file '
        'WHERE m.title = t.id ORDER BY f.id LIMIT 1) AS sample, '
        '(SELECT d.path FROM file_meta m JOIN files f ON f.id = m.file '
        'JOIN folders d ON d.id = f.folder '
        'WHERE m.title = t.id ORDER BY f.id LIMIT 1) AS path '
        'FROM titles t '
        // The first of its spellings stands for the title.
        'LEFT JOIN title_keys k ON k.key = (SELECT min(key) FROM title_keys '
        'WHERE title = t.id) '
        'WHERE ${only == null ? 't.match_state IN (2, 3)' : 't.id = ?'} '
        'AND EXISTS ('
        'SELECT 1 FROM file_meta m JOIN files f ON f.id = m.file '
        'JOIN folders d ON d.id = f.folder JOIN sources s ON s.id = d.source '
        'WHERE m.title = t.id '
        'AND s.source_id IN (${List.filled(ids.length, '?').join(', ')})) '
        'ORDER BY t.match_state, t.name COLLATE NOCASE, t.id '
        'LIMIT ? OFFSET ?',
        [?only, ...ids, limit, offset],
      ))
        ReviewItem(
          id: row['id'] as int,
          kind: row['kind'] == 1 ? TitleKind.series : TitleKind.movie,
          name: row['name'] as String,
          year: row['year'] as int?,
          spelledName: (row['spelled'] ?? row['name']) as String,
          spelledYear: row['spelled_year'] as int?,
          altName: row['alt_name'] as String?,
          notFound: row['match_state'] == MatchState.notFound,
          confidence: row['confidence'] as int?,
          posterPath: row['poster_path'] as String?,
          copies: row['copies'] as int,
          sampleName: row['sample'] as String?,
          samplePath: row['path'] as String?,
        ),
    ];
  }

  /// How many titles there are to review with a video on one of the
  /// sources in [sourceIds]: what [items] lists, without its limit.
  int count({required Iterable<String> sourceIds}) {
    final ids = sourceIds.toList();
    if (ids.isEmpty) return 0;
    return _db
            .select(
              'SELECT count(*) AS titles FROM titles t '
              'WHERE t.match_state IN (2, 3) AND EXISTS ('
              'SELECT 1 FROM file_meta m JOIN files f ON f.id = m.file '
              'JOIN folders d ON d.id = f.folder '
              'JOIN sources s ON s.id = d.source WHERE m.title = t.id '
              'AND s.source_id IN (${List.filled(ids.length, '?').join(', ')}))',
              ids,
            )
            .single['titles']
        as int;
  }

  /// What TMDB answered when it was asked about [item] before, as far as
  /// the answers are still kept: no request is made. Every film or show
  /// once.
  List<TmdbCandidate> keptCandidates(ReviewItem item) {
    final alt = item.altName;
    final keys = {
      CachedTmdb.searchKey(item.kind, item.spelledName, item.spelledYear),
      CachedTmdb.searchKey(item.kind, item.spelledName, null),
      if (alt != null) CachedTmdb.searchKey(item.kind, alt, item.spelledYear),
    };
    final seen = <int>{};
    final candidates = <TmdbCandidate>[];
    for (final key in keys) {
      final rows = _db.select(
        'SELECT body FROM metadata_cache WHERE provider = ? AND key = ?',
        [CachedTmdb.provider, key],
      );
      if (rows.isEmpty) continue;
      final Object? json;
      try {
        json = jsonDecode(rows.first['body'] as String);
      } on FormatException {
        continue;
      }
      if (json is! List<Object?>) continue;
      for (final entry in json) {
        final candidate = TmdbCandidate.fromJson(entry);
        if (candidate != null && seen.add(candidate.id)) {
          candidates.add(candidate);
        }
      }
    }
    return candidates;
  }

  /// Notes that the user wants the title [title] left as the files name
  /// it: it leaves the review list and no later run looks it up again.
  void leaveAsIs(int title) => _library.transaction(() {
    _db
      ..execute(
        'UPDATE titles SET match_state = 5, matched_at = ? WHERE id = ?',
        [_clock().millisecondsSinceEpoch, title],
      )
      ..execute('UPDATE title_keys SET fixed = 1 WHERE title = ?', [title]);
  });
}
