import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dhara/core/net/safe_http_client.dart';
import 'package:dhara/features/metadata/video_identity.dart';
import 'package:flutter/foundation.dart';

/// How a TMDB account signs its requests.
enum TmdbKeyKind {
  /// "API Read Access Token": sent as a header, so it never sits in an
  /// address. The one to prefer.
  accessToken('API Read Access Token'),

  /// "API Key" (v3): 32 hex digits, sent as part of the address.
  apiKey('API key');

  const TmdbKeyKind(this.label);

  final String label;
}

/// What TMDB says about a key.
enum TmdbKeyCheck {
  accepted,
  refused,

  /// TMDB did not answer, or not in a way that says anything about the key.
  unreachable,
}

/// Why a request to TMDB gave no result.
enum TmdbFailure {
  /// TMDB does not accept the key.
  invalidKey,

  /// There is no film, show or season with that id.
  notFound,

  /// Still told to slow down after waiting as long as it asked.
  rateLimited,

  /// No connection, a timeout, or TMDB is out of order.
  unreachable,

  /// The answer is not what the documentation describes.
  badAnswer,
}

class TmdbException implements Exception {
  const TmdbException(this.failure, this.message);

  final TmdbFailure failure;

  /// Plain English, safe to show and to log: never an address or the key.
  final String message;

  @override
  String toString() => 'TmdbException(${failure.name}): $message';
}

/// A film or show a search found: what is needed to tell whether it is the
/// one a file name means, and to show it.
///
/// Text in here was written by TMDB's users: show it only through a plain
/// `Text` widget.
@immutable
class TmdbCandidate {
  const TmdbCandidate({
    required this.id,
    required this.kind,
    required this.title,
    this.originalTitle,
    this.year,
    this.overview,
    this.popularity = 0,
    this.votes = 0,
    this.rating,
    this.language,
    this.posterPath,
    this.backdropPath,
  });

  final int id;

  /// [TitleKind.movie] or [TitleKind.series].
  final TitleKind kind;
  final String title;
  final String? originalTitle;

  /// Of the release, or of the first episode.
  final int? year;
  final String? overview;
  final double popularity;
  final int votes;

  /// 0 to 10; `null` while nobody has voted.
  final double? rating;

  /// Code of the original language: "en", "bn".
  final String? language;

  /// "/abc.jpg": to be put behind TMDB's image address and a size.
  final String? posterPath;
  final String? backdropPath;

  Map<String, Object?> toJson() => {
    'id': id,
    'kind': kind == TitleKind.series ? 'tv' : 'movie',
    'title': title,
    'original_title': originalTitle,
    'year': year,
    'overview': overview,
    'popularity': popularity,
    'votes': votes,
    'rating': rating,
    'language': language,
    'poster_path': posterPath,
    'backdrop_path': backdropPath,
  };

  /// Reads what [toJson] wrote; `null` for anything else.
  static TmdbCandidate? fromJson(Object? json) {
    if (json is! Map<String, Object?>) return null;
    final id = _id(json['id']);
    final title = _text(json['title'], _maxTitle);
    if (id == null || title == null) return null;
    return TmdbCandidate(
      id: id,
      kind: json['kind'] == 'tv' ? TitleKind.series : TitleKind.movie,
      title: title,
      originalTitle: _text(json['original_title'], _maxTitle),
      year: _year(json['year']),
      overview: _text(json['overview'], _maxOverview),
      popularity: _number(json['popularity']) ?? 0,
      votes: _count(json['votes']),
      rating: _number(json['rating']),
      language: _text(json['language'], 12),
      posterPath: _imagePath(json['poster_path']),
      backdropPath: _imagePath(json['backdrop_path']),
    );
  }
}

/// A season as the page of its show lists it.
@immutable
class TmdbSeasonSummary {
  const TmdbSeasonSummary({
    required this.number,
    this.name,
    this.episodeCount,
    this.airDate,
    this.posterPath,
  });

  /// 0 is the "Specials" season.
  final int number;
  final String? name;
  final int? episodeCount;

  /// "2019-04-09".
  final String? airDate;
  final String? posterPath;
}

/// Everything TMDB says about one film or show.
@immutable
class TmdbDetails {
  const TmdbDetails({
    required this.summary,
    this.genres = const [],
    this.runtime,
    this.seasons = const [],
    this.makers = const [],
    this.cast = const [],
  });

  /// How many of the cast, and of the directors or creators, are kept.
  static const maxCast = 8;
  static const maxMakers = 3;

  final TmdbCandidate summary;

  /// Who directed the film, or created the show.
  final List<String> makers;

  /// The first of the cast, in TMDB's order (the leads first).
  final List<String> cast;

  /// Genre names, in English.
  final List<String> genres;

  /// Of a film, in minutes.
  final int? runtime;

  /// Of a show; empty for a film.
  final List<TmdbSeasonSummary> seasons;
}

@immutable
class TmdbEpisode {
  const TmdbEpisode({
    required this.number,
    this.name,
    this.overview,
    this.airDate,
    this.runtime,
    this.stillPath,
  });

  final int number;
  final String? name;
  final String? overview;
  final String? airDate;

  /// In minutes.
  final int? runtime;
  final String? stillPath;
}

@immutable
class TmdbSeason {
  const TmdbSeason({
    required this.number,
    this.name,
    this.overview,
    this.airDate,
    this.posterPath,
    this.episodes = const [],
  });

  final int number;
  final String? name;
  final String? overview;
  final String? airDate;
  final String? posterPath;
  final List<TmdbEpisode> episodes;
}

/// Asks The Movie Database (version 3 of its API) about films and shows.
///
/// - Talks to `api.themoviedb.org` over https only, through a
///   [SafeHttpClient]; every request has a time limit and a size limit.
/// - Polite: requests are spaced out ([spacing]), at most [maxInFlight] run
///   at a time, and when TMDB says to slow down (429) everything waits as
///   long as it asks.
/// - A timeout, a lost connection or a server error is tried again, at most
///   [retries] times.
/// - The key goes out as a header (token) or in the address (API key) and
///   nowhere else: not into errors, not into logs.
///
/// Only titles and years are sent; nothing about the user or their files.
class TmdbClient {
  TmdbClient({
    required String key,
    required TmdbKeyKind kind,
    SafeHttpClient? http,
    Uri? baseUrl,
    this.spacing = const Duration(milliseconds: 125),
    this.maxInFlight = 4,
    this.retries = 3,
    Future<void> Function(Duration)? wait,
    DateTime Function() now = DateTime.now,
  }) : _key = key,
       _kind = kind,
       _ownsHttp = http == null,
       _http =
           http ??
           // TMDB itself, or the stand-in a test points [baseUrl] at: this
           // client goes nowhere else, also not when it is redirected.
           SafeHttpClient(
             isAllowedHost: (host) => host == (baseUrl?.host ?? apiHost),
           ),
       _base = baseUrl ?? Uri.https(apiHost, '/3'),
       _wait = wait ?? Future<void>.delayed,
       _now = now;

  static const apiHost = 'api.themoviedb.org';

  /// How many results of a search are kept, best first.
  static const maxCandidates = 5;

  /// The least time between the start of two requests.
  final Duration spacing;
  final int maxInFlight;
  final int retries;

  final String _key;
  final TmdbKeyKind _kind;
  final SafeHttpClient _http;
  final bool _ownsHttp;
  final Uri _base;
  final Future<void> Function(Duration) _wait;
  final DateTime Function() _now;

  DateTime? _nextStart;
  var _inFlight = 0;
  final _queue = <Completer<void>>[];
  var _closed = false;

  /// Drops the connections, if this client made them itself. Requests
  /// still under way fail.
  void close() {
    _closed = true;
    if (_ownsHttp) _http.close();
  }

  /// Asks TMDB whether it accepts the key. Never throws.
  Future<TmdbKeyCheck> checkKey() async {
    try {
      await _get('authentication', retry: false);
      return TmdbKeyCheck.accepted;
    } on TmdbException catch (error) {
      return error.failure == TmdbFailure.invalidKey
          ? TmdbKeyCheck.refused
          : TmdbKeyCheck.unreachable;
    }
  }

  /// The films called something like [title], best match first; with
  /// [year], those released that year only.
  Future<List<TmdbCandidate>> searchMovies(String title, {int? year}) =>
      _search(TitleKind.movie, title, year);

  /// The shows called something like [title]; with [year], those that
  /// had an episode that year (a season's year will do).
  Future<List<TmdbCandidate>> searchShows(String title, {int? year}) =>
      _search(TitleKind.series, title, year);

  /// The page of a film: genres, length, director and cast (the credits
  /// come along in the same request).
  Future<TmdbDetails> movie(int id) async {
    final json = await _get('movie/$id', query: _withCredits);
    final summary = _candidate(json, TitleKind.movie);
    if (summary == null) throw _badAnswer();
    final credits = json['credits'];
    return TmdbDetails(
      summary: summary,
      genres: _genres(json['genres']),
      runtime: _minutes(json['runtime']),
      makers: _names(
        [
          for (final member in _list(_field(credits, 'crew')))
            if (_field(member, 'job') == 'Director') member,
        ],
        TmdbDetails.maxMakers,
      ),
      cast: _names(_list(_field(credits, 'cast')), TmdbDetails.maxCast),
    );
  }

  /// The page of a show: genres, seasons, who created it and its cast.
  Future<TmdbDetails> show(int id) async {
    final json = await _get('tv/$id', query: _withCredits);
    final summary = _candidate(json, TitleKind.series);
    if (summary == null) throw _badAnswer();
    return TmdbDetails(
      summary: summary,
      makers: _names(_list(json['created_by']), TmdbDetails.maxMakers),
      cast: _names(
        _list(_field(json['credits'], 'cast')),
        TmdbDetails.maxCast,
      ),
      genres: _genres(json['genres']),
      seasons: [
        for (final season in _list(json['seasons']))
          if (season is Map<String, Object?>)
            if (_seasonNumber(season['season_number']) case final number?)
              TmdbSeasonSummary(
                number: number,
                name: _text(season['name'], _maxTitle),
                episodeCount: _seasonNumber(season['episode_count']),
                airDate: _date(season['air_date']),
                posterPath: _imagePath(season['poster_path']),
              ),
      ],
    );
  }

  /// Season [number] of the show [id], with its episodes.
  Future<TmdbSeason> season(int id, int number) async {
    final json = await _get('tv/$id/season/$number');
    return TmdbSeason(
      number: _seasonNumber(json['season_number']) ?? number,
      name: _text(json['name'], _maxTitle),
      overview: _text(json['overview'], _maxOverview),
      airDate: _date(json['air_date']),
      posterPath: _imagePath(json['poster_path']),
      episodes: [
        for (final episode in _list(json['episodes']))
          if (episode is Map<String, Object?>)
            if (_seasonNumber(episode['episode_number']) case final episodeNo?)
              TmdbEpisode(
                number: episodeNo,
                name: _text(episode['name'], _maxTitle),
                overview: _text(episode['overview'], _maxOverview),
                airDate: _date(episode['air_date']),
                runtime: _minutes(episode['runtime']),
                stillPath: _imagePath(episode['still_path']),
              ),
      ],
    );
  }

  Future<List<TmdbCandidate>> _search(
    TitleKind kind,
    String title,
    int? year,
  ) async {
    final query = title.trim();
    if (query.isEmpty) return const [];
    final json = await _get(
      kind == TitleKind.series ? 'search/tv' : 'search/movie',
      query: {
        // Long enough for any title.
        'query': query.length > 200 ? query.substring(0, 200) : query,
        'include_adult': 'false',
        'language': 'en-US',
        'page': '1',
        if (year != null) 'year': '$year',
      },
    );
    final found = <TmdbCandidate>[];
    for (final result in _list(json['results'])) {
      final candidate = _candidate(result, kind);
      if (candidate == null) continue;
      found.add(candidate);
      if (found.length == maxCandidates) break;
    }
    return found;
  }

  /// One GET to [path] below the base address; returns the JSON object of
  /// the answer or throws a [TmdbException].
  Future<Map<String, Object?>> _get(
    String path, {
    Map<String, String> query = const {},
    bool retry = true,
  }) async {
    final parameters = {
      ...query,
      if (_kind == TmdbKeyKind.apiKey) 'api_key': _key,
    };
    final url = _base.replace(
      path: '${_base.path}/$path',
      queryParameters: parameters.isEmpty ? null : parameters,
    );
    final headers = {
      HttpHeaders.acceptHeader: 'application/json',
      if (_kind == TmdbKeyKind.accessToken)
        HttpHeaders.authorizationHeader: 'Bearer $_key',
    };

    for (var attempt = 0; ; attempt++) {
      final last = !retry || attempt >= retries;
      SafeHttpResponse? response;
      SafeHttpException? failure;
      await _takeTurn();
      try {
        // Closed while it waited for its turn.
        if (_closed) {
          throw const SafeHttpException(SafeHttpFailure.network, 'closed');
        }
        response = await _http.get(
          url,
          headers: headers,
          timeout: const Duration(seconds: 15),
          maxBytes: _maxAnswerBytes,
        );
      } on SafeHttpException catch (error) {
        failure = error;
      } finally {
        // Before any waiting: a request that waits holds nobody up.
        _giveTurn();
      }
      if (response == null) {
        final transient =
            failure?.failure == SafeHttpFailure.timeout ||
            failure?.failure == SafeHttpFailure.network;
        if (!transient || last || _closed) {
          throw const TmdbException(
            TmdbFailure.unreachable,
            'TMDB could not be reached.',
          );
        }
        await _wait(_backoff(attempt));
        continue;
      }

      final status = response.statusCode;
      if (status == HttpStatus.tooManyRequests) {
        if (last) {
          throw const TmdbException(
            TmdbFailure.rateLimited,
            'TMDB keeps asking to slow down.',
          );
        }
        // Nothing else starts either until TMDB is ready again.
        final pause = _retryAfter(response);
        _nextStart = _now().add(pause);
        continue;
      }
      if (status >= 500) {
        if (last) {
          throw const TmdbException(
            TmdbFailure.unreachable,
            'TMDB is out of order at the moment.',
          );
        }
        await _wait(_backoff(attempt));
        continue;
      }
      if (status == HttpStatus.unauthorized) {
        throw const TmdbException(
          TmdbFailure.invalidKey,
          'TMDB does not accept the key.',
        );
      }
      if (status == HttpStatus.notFound) {
        throw const TmdbException(
          TmdbFailure.notFound,
          'TMDB has nothing under that id.',
        );
      }
      if (!response.isOk) throw _badAnswer();
      try {
        final json = jsonDecode(response.body);
        if (json is Map<String, Object?>) return json;
      } on FormatException {
        // Reported below.
      }
      throw _badAnswer();
    }
  }

  /// Waits until this request may start: its place in the queue, then the
  /// spacing from the request before (or the pause TMDB asked for).
  Future<void> _takeTurn() async {
    if (_inFlight >= maxInFlight) {
      final turn = Completer<void>();
      _queue.add(turn);
      await turn.future;
    } else {
      _inFlight++;
    }
    final now = _now();
    final next = _nextStart;
    final start = next != null && next.isAfter(now) ? next : now;
    _nextStart = start.add(spacing);
    if (start.isAfter(now)) await _wait(start.difference(now));
  }

  void _giveTurn() {
    // The place goes straight to whoever waits longest.
    if (_queue.isNotEmpty) {
      _queue.removeAt(0).complete();
    } else {
      _inFlight--;
    }
  }

  /// How long TMDB asks to wait, within reason.
  Duration _retryAfter(SafeHttpResponse response) {
    final seconds = int.tryParse(response.header('retry-after') ?? '');
    return Duration(seconds: (seconds ?? 2).clamp(1, 30));
  }

  /// 1 s, 3 s, 9 s.
  static Duration _backoff(int attempt) {
    var seconds = 1;
    for (var i = 0; i < attempt && seconds < 9; i++) {
      seconds *= 3;
    }
    return Duration(seconds: seconds);
  }

  static TmdbException _badAnswer() => const TmdbException(
    TmdbFailure.badAnswer,
    'TMDB sent an answer the app does not understand.',
  );
}

/// Asks TMDB whether it accepts [key]. Never throws.
Future<TmdbKeyCheck> checkTmdbKey(String key, TmdbKeyKind kind) async {
  final client = TmdbClient(key: key, kind: kind);
  try {
    return await client.checkKey();
  } finally {
    client.close();
  }
}

/// The film or show in one entry of a search, or in a details page; `null`
/// if it has no id or no name.
TmdbCandidate? _candidate(Object? json, TitleKind kind) {
  if (json is! Map<String, Object?>) return null;
  final isShow = kind == TitleKind.series;
  final id = _id(json['id']);
  final title = _text(json[isShow ? 'name' : 'title'], _maxTitle);
  if (id == null || title == null) return null;
  final original = _text(
    json[isShow ? 'original_name' : 'original_title'],
    _maxTitle,
  );
  final date = _date(json[isShow ? 'first_air_date' : 'release_date']);
  final votes = _count(json['vote_count']);
  return TmdbCandidate(
    id: id,
    kind: kind,
    title: title,
    originalTitle: original == title ? null : original,
    year: date == null ? null : int.parse(date.substring(0, 4)),
    overview: _text(json['overview'], _maxOverview),
    popularity: _number(json['popularity']) ?? 0,
    votes: votes,
    // TMDB says 0 while nobody has voted.
    rating: votes == 0 ? null : _number(json['vote_average']),
    language: _text(json['original_language'], 12),
    posterPath: _imagePath(json['poster_path']),
    backdropPath: _imagePath(json['backdrop_path']),
  );
}

/// Asks for the cast and crew along with a film's or show's page.
const _withCredits = {'append_to_response': 'credits'};

Object? _field(Object? json, String name) =>
    json is Map<String, Object?> ? json[name] : null;

/// The names of the first [most] people in [people], each once.
List<String> _names(List<Object?> people, int most) {
  final names = <String>[];
  for (final person in people) {
    // A comma would split one name in two where the names are kept.
    final name = _text(_field(person, 'name'), 80)?.replaceAll(',', ' ');
    if (name == null || names.contains(name)) continue;
    names.add(name);
    if (names.length == most) break;
  }
  return names;
}

List<String> _genres(Object? json) => [
  for (final genre in _list(json))
    if (genre is Map<String, Object?>)
      if (_text(genre['name'], 60) case final name?) name,
];

List<Object?> _list(Object? json) => json is List<Object?> ? json : const [];

int? _id(Object? value) => value is int && value > 0 ? value : null;

int _count(Object? value) => value is int && value > 0 ? value : 0;

double? _number(Object? value) =>
    value is num && value.isFinite ? value.toDouble() : null;

int? _year(Object? value) =>
    value is int && value >= 1870 && value <= 2200 ? value : null;

int? _seasonNumber(Object? value) =>
    value is int && value >= 0 && value <= 100000 ? value : null;

int? _minutes(Object? value) =>
    value is int && value > 0 && value < 100000 ? value : null;

/// Trimmed, cut to [max] characters; `null` if nothing is left.
String? _text(Object? value, int max) {
  if (value is! String) return null;
  final text = value.trim();
  if (text.isEmpty) return null;
  return text.length > max ? text.substring(0, max) : text;
}

/// "2019-04-09", or `null` for anything that is not a date like it.
String? _date(Object? value) =>
    value is String && _isoDate.hasMatch(value) ? value : null;

/// A path of TMDB's image server, or `null`. Only the shape TMDB uses is
/// let through: the path ends up in an address and in a file name.
String? _imagePath(Object? value) =>
    value is String && _imageFile.hasMatch(value) ? value : null;

const _maxTitle = 300;
const _maxOverview = 2000;

/// A season of a long-running show, with guest stars for every episode,
/// runs to about a megabyte.
const _maxAnswerBytes = 6 * 1024 * 1024;

final _isoDate = RegExp(r'^(18|19|20|21)\d{2}-\d{2}-\d{2}$');
final _imageFile = RegExp(r'^/[A-Za-z0-9_-]{1,64}\.(jpg|jpeg|png|webp)$');
