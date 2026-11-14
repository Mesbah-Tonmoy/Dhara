import 'dart:convert';

import 'package:dhara/core/db/library_db.dart';
import 'package:dhara/features/metadata/tmdb_client.dart';
import 'package:flutter/foundation.dart';
import 'package:sqlite3/sqlite3.dart';

/// A matched show whose seasons and episodes are to be asked for.
@immutable
class ShowToFetch {
  const ShowToFetch({
    required this.title,
    required this.tmdbId,
    required this.seasons,
  });

  /// The id of the title in the library.
  final int title;
  final int tmdbId;

  /// The seasons the library has videos of, in order.
  final List<int> seasons;
}

/// Reads and writes the part of the library database that holds what TMDB
/// says about the seasons and episodes of matched shows.
///
/// Every value goes into SQL as a parameter, never as text.
class EpisodeStore {
  EpisodeStore(this._library, {DateTime Function() now = DateTime.now})
    : _clock = now;

  /// After this long a show is asked about again: episodes are added and
  /// their names filled in as a season airs.
  static const refreshAfter = Duration(days: 14);

  static const _provider = 'tmdb';

  final LibraryDb _library;
  final DateTime Function() _clock;

  Database get _db => _library.db;
  int get _now => _clock().millisecondsSinceEpoch;

  /// The matched shows (with a video) that were not asked about lately, or
  /// of which the library now has a season that was not asked for.
  List<ShowToFetch> showsToFetch() {
    final oldest = _now - refreshAfter.inMilliseconds;
    final shows = <ShowToFetch>[];
    for (final row in _db.select(
      'SELECT t.id, t.tmdb_id, c.body, c.fetched_at FROM titles t '
      'LEFT JOIN metadata_cache c ON c.provider = ? '
      "AND c.key = 'show|' || t.tmdb_id "
      'WHERE t.kind = 1 AND t.tmdb_id IS NOT NULL '
      'AND EXISTS (SELECT 1 FROM file_meta m WHERE m.title = t.id) '
      'ORDER BY t.id',
      [_provider],
    )) {
      final title = row['id'] as int;
      final seasons = [
        for (final season in _db.select(
          'SELECT DISTINCT season FROM file_meta '
          'WHERE title = ? AND season IS NOT NULL ORDER BY season',
          [title],
        ))
          season['season'] as int,
      ];
      final fetchedAt = row['fetched_at'] as int?;
      final fresh =
          fetchedAt != null && fetchedAt > oldest && fetchedAt <= _now;
      if (fresh && _fetched(row['body']).containsAll(seasons)) continue;
      shows.add(
        ShowToFetch(
          title: title,
          tmdbId: row['tmdb_id'] as int,
          seasons: seasons,
        ),
      );
    }
    return shows;
  }

  /// Keeps what TMDB says about the show [title]: its genres and seasons
  /// from [details], and the episodes of [seasons] (those that were asked
  /// for). Replaces what was kept before, and notes that the show was
  /// asked about now, also if TMDB knew none of the seasons.
  void saveShow(
    ShowToFetch show,
    TmdbDetails? details,
    List<TmdbSeason> seasons,
  ) => _library.transaction(() {
    final title = show.title;
    final exists = _db.select('SELECT 1 FROM titles WHERE id = ?', [title]);
    if (exists.isEmpty) return;
    if (details != null) {
      _db
        ..execute('UPDATE titles SET genres = ? WHERE id = ?', [
          details.genres.isEmpty ? null : details.genres.join(', '),
          title,
        ])
        ..execute('DELETE FROM seasons WHERE title = ?', [title])
        ..execute('DELETE FROM episodes WHERE title = ?', [title]);
      final overviews = {
        for (final season in seasons) season.number: season.overview,
      };
      for (final season in details.seasons) {
        _db.execute(
          'INSERT OR REPLACE INTO seasons (title, season, name, overview, '
          'poster_path, air_date, episode_count) VALUES (?, ?, ?, ?, ?, ?, ?)',
          [
            title,
            season.number,
            season.name,
            overviews[season.number],
            season.posterPath,
            season.airDate,
            season.episodeCount,
          ],
        );
      }
      for (final season in seasons) {
        for (final episode in season.episodes) {
          _db.execute(
            'INSERT OR REPLACE INTO episodes (title, season, episode, name, '
            'overview, still_path, air_date, runtime) '
            'VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
            [
              title,
              season.number,
              episode.number,
              episode.name,
              episode.overview,
              episode.stillPath,
              episode.airDate,
              episode.runtime,
            ],
          );
        }
      }
    }
    _db.execute(
      'INSERT OR REPLACE INTO metadata_cache '
      '(provider, key, body, fetched_at) VALUES (?, ?, ?, ?)',
      [_provider, 'show|${show.tmdbId}', jsonEncode(show.seasons), _now],
    );
  });

  /// The season numbers a note of an earlier fetch lists.
  static Set<int> _fetched(Object? body) {
    if (body is! String) return const {};
    try {
      final json = jsonDecode(body);
      if (json is List<Object?>) return json.whereType<int>().toSet();
    } on FormatException {
      // Counts as not fetched.
    }
    return const {};
  }
}
