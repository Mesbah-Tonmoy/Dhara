import 'dart:math';

import 'package:dhara/core/db/library_db.dart';
import 'package:dhara/features/metadata/video_identity.dart';
import 'package:flutter/foundation.dart';
import 'package:sqlite3/sqlite3.dart';

/// A film or show as a card on Home shows it. [name] is server-controlled
/// text until a provider has named the title: show it through a plain
/// `Text`.
@immutable
class TitleCard {
  const TitleCard({
    required this.id,
    required this.kind,
    required this.name,
    required this.videos,
    this.year,
    this.posterPath,
    this.backdropPath,
    this.rating,
    this.genres = const [],
    this.overview,
    this.runtime,
    this.isAnime = false,
    this.episodes = 0,
    this.height,
  });

  final int id;
  final TitleKind kind;
  final String name;
  final int? year;
  final String? posterPath;
  final String? backdropPath;

  /// Out of 10, as TMDB's users rate it.
  final double? rating;
  final List<String> genres;

  /// Only read for the banner; `null` on every other card.
  final String? overview;

  /// Minutes.
  final int? runtime;
  final bool isAnime;

  /// How many videos of it the enabled sources hold, trailers and samples
  /// left out: the copies of a film, every copy of every episode of a show.
  final int videos;

  /// How many different episodes those videos are; 0 for a film.
  final int episodes;

  /// The picture height of its sharpest video, if any name says.
  final int? height;
}

/// A video that was left unfinished, for the Continue Watching row.
@immutable
class ContinueItem {
  const ContinueItem({
    required this.url,
    required this.watchedAt,
    required this.position,
    required this.duration,
    this.title,
    this.fileName,
    this.season,
    this.episode,
    this.episodeName,
  });

  /// As it was played; server-controlled text. To be checked like any
  /// other address before it is played again.
  final String url;
  final DateTime watchedAt;
  final Duration position;
  final Duration duration;

  /// The film or show it is a copy of; `null` for a video that is not in
  /// the index (played from a pasted address) or is neither.
  final TitleCard? title;

  /// Its name in the index, if it is there. Server-controlled text.
  final String? fileName;
  final int? season;
  final int? episode;
  final String? episodeName;

  /// How much of it was watched, 0 to 1.
  double get progress => duration <= Duration.zero
      ? 0
      : (position.inMilliseconds / duration.inMilliseconds).clamp(0, 1);
}

/// Everything Home shows, as of one moment.
@immutable
class HomeContent {
  const HomeContent({
    this.featured = const [],
    this.continueWatching = const [],
    this.recentlyAdded = const [],
    this.movies = const [],
    this.series = const [],
    this.anime = const [],
    this.topRated = const [],
  });

  /// The titles the banner goes through.
  final List<TitleCard> featured;
  final List<ContinueItem> continueWatching;
  final List<TitleCard> recentlyAdded;
  final List<TitleCard> movies;
  final List<TitleCard> series;
  final List<TitleCard> anime;
  final List<TitleCard> topRated;

  /// The enabled sources hold no film or show to put on Home.
  bool get hasNoTitles =>
      recentlyAdded.isEmpty && movies.isEmpty && series.isEmpty;
}

/// Reads what Home shows from the library database: the rows of cards, the
/// banner and what was left unfinished.
///
/// - Only titles with a video on one of the sources in `sourceIds` (the
///   enabled ones) are returned.
/// - Titles TMDB was asked about and does not know are left to search and
///   browse; so is what the user set aside as not a film or show. Titles
///   not looked up yet are shown: without a TMDB key that is all of them.
/// - The rows walk an index in the order they are shown in and stop when
///   they are full, so a large library costs no more than a small one.
///
/// Every value goes into SQL as a parameter, never as text.
class HomeStore {
  HomeStore(this._library, {required Iterable<String> sourceIds}) {
    final ids = sourceIds.toList();
    _sources = ids.isEmpty
        ? const []
        : [
            for (final row in _db.select(
              'SELECT id FROM sources '
              'WHERE source_id IN (${_placeholders(ids.length)})',
              ids,
            ))
              row['id'] as int,
          ];
  }

  /// Top Rated only lists titles with at least this many votes, so that a
  /// 10.0 from one voter does not lead it.
  static const minVotesForTopRated = 300;

  /// The banner picks from the newest titles rated at least this, by at
  /// least this many voters.
  static const minRatingToFeature = 6.5;
  static const minVotesToFeature = 100;

  /// How many of the newest videos Recently Added looks at before it
  /// settles for a shorter row.
  static const maxRecentVideos = 20000;

  final LibraryDb _library;

  /// The enabled sources, by their row in the database.
  late final List<int> _sources;

  Database get _db => _library.db;

  /// The films, or the shows: the newest year first, within a year the
  /// ones most people voted on.
  List<TitleCard> newest(TitleKind kind, {int limit = 30}) => _fill(
    'SELECT $_columns FROM titles t INDEXED BY titles_newest '
    'WHERE t.kind = ? AND $_shown ORDER BY t.year DESC, t.votes DESC',
    [kind == TitleKind.series ? 1 : 0],
    limit,
  );

  /// The best rated titles of both kinds that enough people voted on.
  List<TitleCard> topRated({
    int limit = 30,
    int minVotes = minVotesForTopRated,
  }) => _fill(
    'SELECT $_columns FROM titles t INDEXED BY titles_rated '
    'WHERE t.rating IS NOT NULL AND t.votes >= ? AND $_shown '
    'ORDER BY t.rating DESC, t.votes DESC',
    [minVotes],
    limit,
  );

  /// Anime, films and shows: the newest first.
  List<TitleCard> anime({int limit = 30}) => _fill(
    'SELECT $_columns FROM titles t WHERE t.is_anime = 1 AND $_shown '
    'ORDER BY t.year DESC, t.votes DESC, t.id DESC',
    const [],
    limit,
  );

  /// The titles that got a video most recently, going by the date the
  /// server gives each video, or else by when the app first saw it.
  List<TitleCard> recentlyAdded({int limit = 30}) {
    if (_sources.isEmpty || limit <= 0) return const [];
    // Videos, newest first; the index is in that order already.
    final videos = _db.prepare(
      'SELECT m.title FROM files f INDEXED BY files_recent '
      'CROSS JOIN file_meta m ON m.file = f.id '
      'CROSS JOIN folders d ON d.id = f.folder '
      'WHERE m.title IS NOT NULL AND m.extra IS NULL '
      'AND d.source IN (${_placeholders(_sources.length)}) '
      'ORDER BY min(ifnull(f.modified, f.added_at), f.added_at) DESC '
      'LIMIT ?',
    );
    try {
      final cursor = videos.selectCursor([..._sources, maxRecentVideos]);
      final seen = <int>{};
      final cards = <TitleCard>[];
      var more = true;
      while (more && cards.length < limit) {
        final batch = <int>[];
        while (batch.length < limit && (more = cursor.moveNext())) {
          final title = cursor.current['title'] as int;
          if (seen.add(title)) batch.add(title);
        }
        cards.addAll(_cards(batch));
      }
      return cards.length > limit ? cards.sublist(0, limit) : cards;
    } finally {
      videos.close();
    }
  }

  /// Up to [count] titles for the banner: picked from the newest well
  /// rated films and shows that have a backdrop, the same ones for a whole
  /// [day] (any number that changes once a day).
  List<TitleCard> featured({required int day, int count = 5}) {
    const each = 15;
    List<TitleCard> pool(String rated, List<Object?> parameters) => [
      for (final kind in const [0, 1])
        ..._fill(
          'SELECT $_columns, t.overview FROM titles t '
          'INDEXED BY titles_newest WHERE t.kind = ? '
          'AND t.backdrop_path IS NOT NULL $rated AND $_shown '
          'ORDER BY t.year DESC, t.votes DESC',
          [kind, ...parameters],
          each,
        ),
    ];

    var candidates = pool('AND t.rating >= ? AND t.votes >= ?', const [
      minRatingToFeature,
      minVotesToFeature,
    ]);
    if (candidates.length < count) {
      // A library without much that is new and well rated: anything with
      // a backdrop will do.
      final ids = {for (final card in candidates) card.id};
      candidates = [
        ...candidates,
        for (final card in pool('', const []))
          if (ids.add(card.id)) card,
      ];
    }
    candidates.shuffle(Random(day));
    return candidates.length > count
        ? candidates.sublist(0, count)
        : candidates;
  }

  /// The videos that were left unfinished, the one watched last first. A
  /// film or show is in it once, with the video of it watched last, and
  /// not at all if that one was watched to the end.
  List<ContinueItem> continueWatching({int limit = 20}) {
    final rows = _db.select(
      'SELECT h.url, h.watched_at, h.finished, p.position_ms, '
      'p.duration_ms, f.name, d.source, m.title, m.season, m.episode, '
      'coalesce(e.name, m.episode_name) AS episode_name '
      'FROM (SELECT * FROM watch_history ORDER BY watched_at DESC LIMIT 400) h '
      // Only what the player would resume counts as unfinished.
      'LEFT JOIN playback p ON p.url = h.url '
      'LEFT JOIN files f ON f.id = (SELECT min(id) FROM files '
      'WHERE url = h.url) '
      'LEFT JOIN folders d ON d.id = f.folder '
      'LEFT JOIN file_meta m ON m.file = f.id '
      'LEFT JOIN episodes e ON e.title = m.title AND e.season = m.season '
      'AND e.episode = m.episode '
      'ORDER BY h.watched_at DESC, h.url',
    );
    final seen = <Object>{};
    final kept = <Row>[];
    for (final row in rows) {
      // A title is judged by its latest video alone.
      if (!seen.add((row['title'] ?? row['url']) as Object)) continue;
      if (row['finished'] == 1 || row['position_ms'] == null) continue;
      // In the index, but on a source that is switched off.
      final source = row['source'];
      if (source != null && !_sources.contains(source)) continue;
      kept.add(row);
      if (kept.length == limit) break;
    }
    final titles = {
      for (final card in _cards([
        for (final row in kept)
          if (row['title'] case final int title) title,
      ], whateverItsState: true))
        card.id: card,
    };
    return [
      for (final row in kept)
        ContinueItem(
          url: row['url'] as String,
          watchedAt: DateTime.fromMillisecondsSinceEpoch(
            row['watched_at'] as int,
          ),
          position: Duration(milliseconds: row['position_ms'] as int),
          duration: Duration(milliseconds: row['duration_ms'] as int),
          title: titles[row['title']],
          fileName: row['name'] as String?,
          season: row['season'] as int?,
          episode: row['episode'] as int?,
          episodeName: row['episode_name'] as String?,
        ),
    ];
  }

  /// All of Home. [today] decides which titles the banner shows.
  HomeContent content({required DateTime today, int rowLength = 30}) =>
      HomeContent(
        featured: featured(
          day:
              DateTime.utc(
                today.year,
                today.month,
                today.day,
              ).millisecondsSinceEpoch ~/
              Duration.millisecondsPerDay,
        ),
        continueWatching: continueWatching(),
        recentlyAdded: recentlyAdded(limit: rowLength),
        movies: newest(TitleKind.movie, limit: rowLength),
        series: newest(TitleKind.series, limit: rowLength),
        anime: anime(limit: rowLength),
        topRated: topRated(limit: rowLength),
      );

  /// The first [limit] titles [sql] lists that have a video on an enabled
  /// source. The query is read only as far as needed.
  List<TitleCard> _fill(String sql, List<Object?> parameters, int limit) {
    if (_sources.isEmpty || limit <= 0) return const [];
    final statement = _db.prepare(sql);
    try {
      final cursor = statement.selectCursor(parameters);
      final cards = <TitleCard>[];
      var more = true;
      while (more && cards.length < limit) {
        final batch = <Row>[];
        while (batch.length < limit && (more = cursor.moveNext())) {
          batch.add(cursor.current);
        }
        cards.addAll(_available(batch));
      }
      return cards.length > limit ? cards.sublist(0, limit) : cards;
    } finally {
      statement.close();
    }
  }

  /// The titles with these [ids], in that order, as far as they are shown
  /// on Home ([whateverItsState]: also what TMDB does not know) and have a
  /// video on an enabled source.
  List<TitleCard> _cards(List<int> ids, {bool whateverItsState = false}) {
    if (ids.isEmpty) return const [];
    final rows = {
      for (final row in _db.select(
        'SELECT $_columns FROM titles t '
        'WHERE t.id IN (${_placeholders(ids.length)}) '
        'AND ${whateverItsState ? 't.set_aside = 0' : _shown}',
        ids,
      ))
        row['id'] as int: row,
    };
    return _available([
      for (final id in ids)
        if (rows[id] case final row?) row,
    ]);
  }

  /// Cards for the titles in [rows] that have a video on an enabled
  /// source, in the same order.
  List<TitleCard> _available(List<Row> rows) {
    if (rows.isEmpty) return const [];
    final videos = {
      for (final row in _db.select(
        'SELECT m.title, count(*) AS videos, max(m.height) AS height, '
        'count(DISTINCT CASE WHEN m.episode IS NOT NULL '
        'THEN ifnull(m.season, 0) * 100000 + m.episode END) AS episodes '
        'FROM file_meta m '
        'CROSS JOIN files f ON f.id = m.file '
        'CROSS JOIN folders d ON d.id = f.folder '
        'WHERE m.title IN (${_placeholders(rows.length)}) '
        'AND m.extra IS NULL '
        'AND d.source IN (${_placeholders(_sources.length)}) '
        'GROUP BY m.title',
        [for (final row in rows) row['id'], ..._sources],
      ))
        row['title'] as int: row,
    };
    return [
      for (final row in rows)
        if (videos[row['id']] case final found?)
          TitleCard(
            id: row['id'] as int,
            kind: row['kind'] == 1 ? TitleKind.series : TitleKind.movie,
            name: row['name'] as String,
            year: row['year'] as int?,
            posterPath: row['poster_path'] as String?,
            backdropPath: row['backdrop_path'] as String?,
            rating: row['rating'] as double?,
            genres: switch (row['genres']) {
              final String joined => joined.split(', '),
              _ => const [],
            },
            overview: row.containsKey('overview')
                ? row['overview'] as String?
                : null,
            runtime: row['runtime'] as int?,
            isAnime: row['is_anime'] == 1,
            videos: found['videos'] as int,
            episodes: row['kind'] == 1 ? found['episodes'] as int : 0,
            height: found['height'] as int?,
          ),
    ];
  }
}

const _columns =
    't.id, t.kind, t.name, t.year, t.poster_path, t.backdrop_path, '
    't.rating, t.genres, t.runtime, t.is_anime';

/// What Home leaves out: titles TMDB does not know (state 3), and what was
/// set aside by hand.
const _shown = 't.match_state != 3 AND t.set_aside = 0';

/// "?, ?, ?" for [count] values.
String _placeholders(int count) => List.filled(count, '?').join(', ');
