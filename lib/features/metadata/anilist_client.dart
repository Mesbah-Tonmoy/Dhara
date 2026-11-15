import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dhara/core/images/image_store.dart'
    show anilistCoverFile, anilistImageHost;
import 'package:dhara/core/net/safe_http_client.dart';
import 'package:flutter/foundation.dart';

/// The four seasons anime is released in.
enum AnimeSeason {
  winter('Winter'),
  spring('Spring'),
  summer('Summer'),
  fall('Fall');

  const AnimeSeason(this.label);

  final String label;

  /// The season [date] is in: winter is January to March, and so on.
  static AnimeSeason of(DateTime date) => values[(date.month - 1) ~/ 3];
}

/// An anime as AniList lists it.
///
/// Text in here was written by AniList's users: show it only through a
/// plain `Text` widget.
@immutable
class AnimeEntry {
  const AnimeEntry({
    required this.id,
    this.english,
    this.romaji,
    this.native,
    this.synonyms = const [],
    this.format,
    this.episodes,
    this.year,
    this.score,
    this.coverPath,
  });

  final int id;

  /// Its cover on AniList's picture server, as [anilistCoverPath] lets it
  /// through; `null` if there is none, or the lists were kept before
  /// covers were.
  final String? coverPath;

  /// The title in English, in Latin letters, and in its own script.
  final String? english;
  final String? romaji;
  final String? native;

  /// Other names it goes by.
  final List<String> synonyms;

  /// "TV", "MOVIE", "OVA", "ONA", "SPECIAL", "TV_SHORT".
  final String? format;
  final int? episodes;

  /// The year it started.
  final int? year;

  /// 0 to 100; `null` while too few have rated it.
  final int? score;

  /// What to call it: the English title if there is one.
  String get name => english ?? romaji ?? native ?? 'Anime $id';

  bool get isFilm => format == 'MOVIE';

  /// Every name it goes by, the best known first.
  List<String> get names => [?english, ?romaji, ...synonyms, ?native];

  Map<String, Object?> toJson() => {
    'id': id,
    'english': english,
    'romaji': romaji,
    'native': native,
    'synonyms': synonyms,
    'format': format,
    'episodes': episodes,
    'year': year,
    'score': score,
    'cover': coverPath,
  };

  /// Reads what [toJson] wrote; `null` for anything else.
  static AnimeEntry? fromJson(Object? json) {
    if (json is! Map<String, Object?>) return null;
    final id = json['id'];
    if (id is! int || id <= 0) return null;
    final synonyms = json['synonyms'];
    return AnimeEntry(
      id: id,
      english: _text(json['english']),
      romaji: _text(json['romaji']),
      native: _text(json['native']),
      synonyms: [
        if (synonyms is List<Object?>)
          for (final synonym in synonyms.take(_maxSynonyms))
            if (_text(synonym) case final name?) name,
      ],
      format: _text(json['format']),
      episodes: _count(json['episodes']),
      year: _count(json['year']),
      score: _count(json['score']),
      coverPath: switch (json['cover']) {
        final String path when anilistCoverFile.hasMatch(path) => path,
        _ => null,
      },
    );
  }
}

/// The path of the cover AniList gives as [url], or `null` unless it is
/// an `https` address on AniList's picture server of the usual shape.
String? anilistCoverPath(Object? url) {
  if (url is! String) return null;
  final address = Uri.tryParse(url);
  if (address == null ||
      address.scheme != 'https' ||
      address.host != anilistImageHost ||
      address.hasPort ||
      address.hasQuery ||
      address.hasFragment ||
      address.userInfo.isNotEmpty) {
    return null;
  }
  return anilistCoverFile.hasMatch(address.path) ? address.path : null;
}

/// Why AniList gave no answer.
enum AniListFailure { rateLimited, unreachable, badAnswer }

class AniListException implements Exception {
  const AniListException(this.failure, this.message);

  final AniListFailure failure;

  /// Plain English, safe to show and to log.
  final String message;

  @override
  String toString() => 'AniListException(${failure.name}): $message';
}

/// Asks AniList which anime are trending and which air in a season.
///
/// - Talks to `graphql.anilist.co` over https only, through a
///   [SafeHttpClient], with a time limit and a size limit. No key is
///   needed and nothing about the user or the library is sent: the two
///   questions are the same for everyone.
/// - AniList allows few requests a minute. The app asks twice a day at
///   most; when told to slow down (429) it waits as long as AniList asks,
///   once.
class AniListClient {
  AniListClient({
    SafeHttpClient? http,
    Uri? url,
    Future<void> Function(Duration)? wait,
  }) : _ownsHttp = http == null,
       _http =
           http ??
           SafeHttpClient(isAllowedHost: (name) => name == (url?.host ?? host)),
       _url = url ?? Uri.https(host, '/'),
       _wait = wait ?? Future<void>.delayed;

  static const host = 'graphql.anilist.co';

  /// How many anime a list holds at most.
  static const listLength = 50;

  final SafeHttpClient _http;
  final bool _ownsHttp;
  final Uri _url;
  final Future<void> Function(Duration) _wait;

  /// Drops the connections, if this client made them itself.
  void close() {
    if (_ownsHttp) _http.close();
  }

  /// The anime most talked about right now, the most first.
  Future<List<AnimeEntry>> trending() => _list({
    'sort': ['TRENDING_DESC', 'POPULARITY_DESC'],
  });

  /// The anime that started in [season] of [year], the most popular first.
  Future<List<AnimeEntry>> season(AnimeSeason season, int year) => _list({
    'sort': ['POPULARITY_DESC'],
    'season': season.name.toUpperCase(),
    'year': year,
  });

  Future<List<AnimeEntry>> _list(Map<String, Object?> variables) async {
    final json = await _post({
      'query': _listQuery,
      'variables': {...variables, 'perPage': listLength},
    });
    final page = json['data'];
    final media = page is Map<String, Object?> ? page['Page'] : null;
    final entries = media is Map<String, Object?> ? media['media'] : null;
    if (entries is! List<Object?>) throw _badAnswer();
    return [
      for (final entry in entries.take(listLength))
        if (_entry(entry) case final anime?) anime,
    ];
  }

  Future<Map<String, Object?>> _post(Map<String, Object?> body) async {
    for (var attempt = 0; ; attempt++) {
      final SafeHttpResponse response;
      try {
        response = await _http.postJson(
          _url,
          body,
          headers: {HttpHeaders.acceptHeader: 'application/json'},
          timeout: const Duration(seconds: 20),
          maxBytes: 2 * 1024 * 1024,
        );
      } on SafeHttpException {
        throw const AniListException(
          AniListFailure.unreachable,
          'AniList could not be reached.',
        );
      }
      if (response.statusCode == HttpStatus.tooManyRequests) {
        if (attempt > 0) {
          throw const AniListException(
            AniListFailure.rateLimited,
            'AniList asks to slow down. Try again in a minute.',
          );
        }
        final seconds = int.tryParse(response.header('retry-after') ?? '');
        await _wait(Duration(seconds: (seconds ?? 60).clamp(1, 90)));
        continue;
      }
      if (response.statusCode >= 500) {
        throw const AniListException(
          AniListFailure.unreachable,
          'AniList is out of order at the moment.',
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

  static AniListException _badAnswer() => const AniListException(
    AniListFailure.badAnswer,
    'AniList sent an answer the app does not understand.',
  );
}

/// One anime of AniList's answer, or `null` if it has no id.
AnimeEntry? _entry(Object? json) {
  if (json is! Map<String, Object?>) return null;
  final title = json['title'];
  final start = json['startDate'];
  final titles = title is Map<String, Object?>
      ? title
      : const <String, Object?>{};
  return AnimeEntry.fromJson({
    'id': json['id'],
    'english': titles['english'],
    'romaji': titles['romaji'],
    'native': titles['native'],
    'synonyms': json['synonyms'],
    'format': json['format'],
    'episodes': json['episodes'],
    'year': start is Map<String, Object?> ? start['year'] : null,
    'score': json['averageScore'],
    'cover': anilistCoverPath(switch (json['coverImage']) {
      final Map<String, Object?> cover => cover['large'],
      _ => null,
    }),
  });
}

/// Trimmed, cut to a sensible length; `null` if nothing is left.
String? _text(Object? value) {
  if (value is! String) return null;
  final text = value.trim();
  if (text.isEmpty) return null;
  return text.length > 300 ? text.substring(0, 300) : text;
}

int? _count(Object? value) =>
    value is int && value > 0 && value < 100000 ? value : null;

const _maxSynonyms = 12;

/// One page of anime, in the order asked for. Adult titles are left out.
const _listQuery = r'''
query ($perPage: Int, $sort: [MediaSort], $season: MediaSeason, $year: Int) {
  Page(page: 1, perPage: $perPage) {
    media(type: ANIME, sort: $sort, season: $season, seasonYear: $year,
        isAdult: false) {
      id
      title { romaji english native }
      synonyms
      format
      episodes
      averageScore
      startDate { year }
      coverImage { large }
    }
  }
}
''';
