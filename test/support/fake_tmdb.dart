import 'dart:convert';
import 'dart:io';

import 'package:dhara/features/metadata/video_identity.dart';

import 'local_server.dart';

/// A stand-in for TMDB on a [LocalServer]: knows the films and shows it is
/// told about and answers searches and details in TMDB's format.
///
/// A search finds every film or show whose title (or original title) has
/// all the words asked for, and, if a year is asked for, is of that year.
class FakeTmdb {
  FakeTmdb(this._server) {
    _server.routes['/3/search/movie'] = (request) => _search(request, _films);
    _server.routes['/3/search/tv'] = (request) => _search(request, _shows);
    _server.routes['/3/authentication'] = (request) =>
        _answer(request, {'success': true, 'status_code': 1});
  }

  final LocalServer _server;
  final _films = <Map<String, Object?>>[];
  final _shows = <Map<String, Object?>>[];

  /// Every request so far: "movie|the glass harbor|2019", "tv/70001",
  /// "tv/70001/season/1".
  final asked = <String>[];

  /// Answer every request with this status instead: 401, 500.
  int? failWith;

  /// Where a client finds this server.
  Uri get url => _server.url('/3');

  void addFilm(
    int id,
    String title,
    int? year, {
    int votes = 100,
    String? originalTitle,
    String? poster,
  }) => _films.add({
    'id': id,
    'title': title,
    'original_title': originalTitle ?? title,
    'release_date': year == null ? '' : '$year-06-01',
    'overview': 'About $title.',
    'popularity': votes / 10,
    'vote_average': 7.5,
    'vote_count': votes,
    'original_language': 'en',
    'poster_path': poster ?? '/poster$id.jpg',
    'backdrop_path': '/backdrop$id.jpg',
  });

  /// [seasons] gives the episode names of each season by its number.
  void addShow(
    int id,
    String name,
    int? year, {
    int votes = 100,
    Map<int, List<String>> seasons = const {},
  }) {
    final show = {
      'id': id,
      'name': name,
      'original_name': name,
      'first_air_date': year == null ? '' : '$year-09-01',
      'overview': 'About $name.',
      'popularity': votes / 10,
      'vote_average': 8.0,
      'vote_count': votes,
      'original_language': 'en',
      'poster_path': '/poster$id.jpg',
      'backdrop_path': '/backdrop$id.jpg',
    };
    _shows.add(show);
    _server.routes['/3/tv/$id'] = (request) {
      asked.add('tv/$id');
      return _answer(request, {
        ...show,
        'genres': [
          {'id': 18, 'name': 'Drama'},
          {'id': 9648, 'name': 'Mystery'},
        ],
        'seasons': [
          for (final MapEntry(key: number, value: episodes) in seasons.entries)
            {
              'season_number': number,
              'name': number == 0 ? 'Specials' : 'Season $number',
              'episode_count': episodes.length,
              'air_date': '${(year ?? 2000) + number}-09-01',
              'poster_path': '/season$id-$number.jpg',
            },
        ],
      });
    };
    for (final MapEntry(key: number, value: episodes) in seasons.entries) {
      _server.routes['/3/tv/$id/season/$number'] = (request) {
        asked.add('tv/$id/season/$number');
        return _answer(request, {
          'season_number': number,
          'name': 'Season $number',
          'overview': 'Season $number of $name.',
          'air_date': '${(year ?? 2000) + number}-09-01',
          'poster_path': '/season$id-$number.jpg',
          'episodes': [
            for (final (index, title) in episodes.indexed)
              {
                'episode_number': index + 1,
                'name': title,
                'overview': 'In which $title happens.',
                'air_date': '${(year ?? 2000) + number}-09-0${index % 9 + 1}',
                'runtime': 45,
                'still_path': '/still$id-$number-${index + 1}.jpg',
              },
          ],
        });
      };
    }
  }

  Future<void> _search(HttpRequest request, List<Map<String, Object?>> known) {
    final isShow = identical(known, _shows);
    final query = normalizeTitle(request.uri.queryParameters['query'] ?? '');
    final year = request.uri.queryParameters['year'];
    asked.add('${isShow ? 'tv' : 'movie'}|$query|${year ?? ''}');
    final words = query.split(' ').toSet();
    bool has(Object? title) =>
        normalizeTitle('$title').split(' ').toSet().containsAll(words);
    return _answer(request, {
      'page': 1,
      'results': [
        for (final entry in known)
          if (has(entry[isShow ? 'name' : 'title']) ||
              has(entry[isShow ? 'original_name' : 'original_title']))
            if (year == null ||
                '${entry[isShow ? 'first_air_date' : 'release_date']}'
                    .startsWith(year))
              entry,
      ],
    });
  }

  Future<void> _answer(HttpRequest request, Map<String, Object?> body) async {
    final status = failWith;
    request.response
      ..statusCode = status ?? HttpStatus.ok
      ..headers.set(
        HttpHeaders.contentTypeHeader,
        'application/json; charset=utf-8',
      )
      ..write(
        jsonEncode(
          status == null ? body : {'success': false, 'status_code': 7},
        ),
      );
    await request.response.close();
  }
}
