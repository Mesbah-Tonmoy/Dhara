import 'package:dhara/core/db/library_db.dart';
import 'package:dhara/features/home/home_store.dart';
import 'package:dhara/features/metadata/match_store.dart';
import 'package:dhara/features/metadata/metadata_store.dart';
import 'package:dhara/features/metadata/video_identity.dart';
import 'package:flutter/foundation.dart';
import 'package:sqlite3/sqlite3.dart';

/// An episode as TMDB describes it. A show the sources number another way
/// has none of these for its videos.
@immutable
class EpisodeInfo {
  const EpisodeInfo({
    required this.season,
    required this.episode,
    this.name,
    this.overview,
    this.stillPath,
    this.runtime,
  });

  final int season;
  final int episode;
  final String? name;
  final String? overview;
  final String? stillPath;

  /// Minutes.
  final int? runtime;
}

/// How far a video was watched, as the history has it.
@immutable
class Watched {
  const Watched({
    required this.position,
    required this.duration,
    required this.finished,
    required this.at,
  });

  final Duration position;
  final Duration duration;
  final bool finished;
  final DateTime at;

  /// 0 to 1; 1 once it was watched to the end.
  double get progress => finished || duration <= Duration.zero
      ? (finished ? 1 : 0)
      : (position.inMilliseconds / duration.inMilliseconds).clamp(0, 1);
}

/// Everything the page of one film or show is made of.
@immutable
class TitlePage {
  const TitlePage({
    required this.title,
    required this.copies,
    required this.matchState,
    this.originalName,
    this.language,
    this.votes,
    this.similar = const [],
    this.episodes = const [],
    this.seasonNames = const {},
    this.watched = const {},
  });

  /// The title, with its description; `videos` is 0 if no enabled source
  /// holds it any more.
  final TitleCard title;

  /// Its videos on the enabled sources, as `MetadataStore.copiesOf` orders
  /// them.
  final List<TitleCopy> copies;

  /// One of the states in [MatchState].
  final int matchState;
  final String? originalName;

  /// Code of the original language: "en", "bn".
  final String? language;
  final int? votes;

  /// "More like this".
  final List<TitleCard> similar;

  /// What TMDB knows of the show's episodes; empty for a film.
  final List<EpisodeInfo> episodes;

  /// The names TMDB gives the seasons, by number.
  final Map<int, String> seasonNames;

  /// How far each of [copies] was watched, by its address; only those that
  /// were.
  final Map<String, Watched> watched;

  /// TMDB named it, surely or not.
  bool get isMatched =>
      matchState == MatchState.matched ||
      matchState == MatchState.unsure ||
      matchState == MatchState.byHand;
}

/// Reads what the page of a title shows from the library database.
///
/// Every value goes into SQL as a parameter, never as text.
class DetailsStore {
  DetailsStore(this._library, {required Iterable<String> sourceIds})
    : _sourceIds = sourceIds.toList();

  final LibraryDb _library;
  final List<String> _sourceIds;

  Database get _db => _library.db;

  /// The page of the title with the id [title]; `null` if there is no such
  /// title (any more), or it was set aside.
  TitlePage? page(int title, {int similarTitles = 12}) {
    final home = HomeStore(_library, sourceIds: _sourceIds);
    final cards = home.cards(
      [title],
      whateverItsState: true,
      evenWithoutVideos: true,
      withOverview: true,
    );
    if (cards.isEmpty) return null;
    final card = cards.single;
    final more = _db.select(
      'SELECT match_state, original_name, language, votes FROM titles '
      'WHERE id = ?',
      [title],
    ).single;
    final copies = MetadataStore(
      _library,
    ).copiesOf(title, sourceIds: _sourceIds);
    return TitlePage(
      title: card,
      copies: copies,
      matchState: more['match_state'] as int,
      originalName: more['original_name'] as String?,
      language: more['language'] as String?,
      votes: more['votes'] as int?,
      similar: _similar(home, card, more['language'] as String?, similarTitles),
      episodes: _episodes(title),
      seasonNames: {
        for (final row in _db.select(
          'SELECT season, name FROM seasons WHERE title = ? '
          'AND name IS NOT NULL',
          [title],
        ))
          row['season'] as int: row['name'] as String,
      },
      watched: _watched(title),
    );
  }

  /// Titles of the same kind to offer next: ones that share the first
  /// genre, or, for a title without genres, ones of about the same year
  /// and language; those most people voted on first.
  List<TitleCard> _similar(
    HomeStore home,
    TitleCard title,
    String? language,
    int limit,
  ) {
    final kind = title.kind == TitleKind.series ? 1 : 0;
    const from =
        'SELECT ${HomeStore.cardColumns} FROM titles t '
        'WHERE t.kind = ? AND t.id != ? AND ${HomeStore.shownOnly} ';
    if (title.genres.isNotEmpty) {
      return home.fill(
        '${from}AND instr(ifnull(t.genres, \'\'), ?) > 0 '
        'ORDER BY t.votes DESC, t.id',
        [kind, title.id, title.genres.first],
        limit,
      );
    }
    final year = title.year;
    if (year == null) return const [];
    return home.fill(
      '${from}AND t.year BETWEEN ? AND ? '
      'AND (?5 IS NULL OR t.language = ?5) ORDER BY t.votes DESC, t.id',
      [kind, title.id, year - 2, year + 2, language],
      limit,
    );
  }

  List<EpisodeInfo> _episodes(int title) => [
    for (final row in _db.select(
      'SELECT season, episode, name, overview, still_path, runtime '
      'FROM episodes WHERE title = ? ORDER BY season, episode',
      [title],
    ))
      EpisodeInfo(
        season: row['season'] as int,
        episode: row['episode'] as int,
        name: row['name'] as String?,
        overview: row['overview'] as String?,
        stillPath: row['still_path'] as String?,
        runtime: row['runtime'] as int?,
      ),
  ];

  /// What the history says about the videos of [title], by address.
  Map<String, Watched> _watched(int title) => {
    for (final row in _db.select(
      'SELECT h.url, h.watched_at, h.finished, h.duration_ms, '
      // What can be resumed is where the player would go on.
      'ifnull(p.position_ms, h.position_ms) AS position_ms '
      'FROM file_meta m '
      'CROSS JOIN files f ON f.id = m.file '
      'CROSS JOIN watch_history h ON h.url = f.url '
      'LEFT JOIN playback p ON p.url = h.url '
      'WHERE m.title = ?',
      [title],
    ))
      row['url'] as String: Watched(
        position: Duration(milliseconds: row['position_ms'] as int),
        duration: Duration(milliseconds: row['duration_ms'] as int),
        finished: row['finished'] == 1,
        at: DateTime.fromMillisecondsSinceEpoch(row['watched_at'] as int),
      ),
  };
}
