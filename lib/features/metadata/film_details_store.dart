import 'package:dhara/core/db/library_db.dart';
import 'package:dhara/features/metadata/tmdb_client.dart';
import 'package:flutter/foundation.dart';
import 'package:sqlite3/sqlite3.dart';

/// A matched film whose page on TMDB has not been read yet.
@immutable
class FilmToFetch {
  const FilmToFetch({required this.title, required this.tmdbId});

  /// The id of the title in the library.
  final int title;
  final int tmdbId;
}

/// Reads and writes what TMDB's page of a film adds to a match: its
/// genres, its length, who directed it and who is in it.
///
/// A match (a search answer) does not carry these, so every matched film
/// is asked about once more, by id. That is one request per film; the
/// answer is kept for good and marked with the time it was read.
///
/// Every value goes into SQL as a parameter, never as text.
class FilmDetailsStore {
  FilmDetailsStore(this._library, {DateTime Function() now = DateTime.now})
    : _clock = now;

  final LibraryDb _library;
  final DateTime Function() _clock;

  Database get _db => _library.db;

  /// Up to [limit] matched films (with a video) whose page was never read,
  /// with an id above [after], lowest id first.
  List<FilmToFetch> filmsToFetch({int after = 0, int limit = 100}) => [
    for (final row in _db.select(
      'SELECT t.id, t.tmdb_id FROM titles t '
      'WHERE t.kind = 0 AND t.tmdb_id IS NOT NULL AND t.details_at IS NULL '
      'AND t.id > ? '
      'AND EXISTS (SELECT 1 FROM file_meta m WHERE m.title = t.id) '
      'ORDER BY t.id LIMIT ?',
      [after, limit],
    ))
      FilmToFetch(title: row['id'] as int, tmdbId: row['tmdb_id'] as int),
  ];

  /// How many films [filmsToFetch] would list in all.
  int countToFetch() =>
      _db
              .select(
                'SELECT count(*) AS n FROM titles t '
                'WHERE t.kind = 0 AND t.tmdb_id IS NOT NULL '
                'AND t.details_at IS NULL '
                'AND EXISTS (SELECT 1 FROM file_meta m WHERE m.title = t.id)',
              )
              .single['n']
          as int;

  /// Keeps what TMDB's page says about [film] and notes that it was read.
  /// With `null` for [details] (TMDB no longer has the film) only the note
  /// is made, so it is not asked for every time.
  ///
  /// A film that was matched to something else meanwhile is left alone:
  /// the details belong to the id they were asked by.
  void saveFilm(FilmToFetch film, TmdbDetails? details) => _db.execute(
    details == null
        ? 'UPDATE titles SET details_at = ?1 WHERE id = ?2 AND tmdb_id = ?3'
        : 'UPDATE titles SET details_at = ?1, genres = ?4, runtime = ?5, '
              'director = ?6, actors = ?7 WHERE id = ?2 AND tmdb_id = ?3',
    [
      _clock().millisecondsSinceEpoch,
      film.title,
      film.tmdbId,
      if (details != null) ...[
        details.genres.isEmpty ? null : details.genres.join(', '),
        details.runtime,
        details.makers.isEmpty ? null : details.makers.join(', '),
        details.cast.isEmpty ? null : details.cast.join(', '),
      ],
    ],
  );
}
