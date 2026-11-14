import 'dart:convert';

import 'package:dhara/features/metadata/metadata_store.dart';
import 'package:dhara/features/metadata/tmdb_client.dart';
import 'package:dhara/features/metadata/video_identity.dart';

/// TMDB with a memory: what a search found is kept in the library database,
/// so the same title is asked about once a month at most, also when it was
/// not found. Lives in the library isolate, next to the database.
class CachedTmdb {
  CachedTmdb(this._client, this._store);

  /// The name the answers are kept under.
  static const provider = 'tmdb';

  /// How long an answer counts. New films appear on TMDB and its data is
  /// corrected, so nothing is kept for ever.
  static const keepFor = Duration(days: 30);

  final TmdbClient _client;
  final MetadataStore _store;

  /// The films or shows TMDB knows by [title], best match first: from the
  /// database if they were asked for lately, from TMDB otherwise.
  ///
  /// Throws a [TmdbException] if TMDB had to be asked and gave no answer;
  /// nothing is kept then.
  Future<List<TmdbCandidate>> candidates(
    TitleKind kind,
    String title, {
    int? year,
  }) async {
    final key = searchKey(kind, title, year);
    final kept = _store.cachedAnswer(provider, key, maxAge: keepFor);
    if (kept != null) {
      final candidates = _decode(kept);
      if (candidates != null) return candidates;
    }
    final found = kind == TitleKind.series
        ? await _client.searchShows(title, year: year)
        : await _client.searchMovies(title, year: year);
    _store.cacheAnswer(
      provider,
      key,
      jsonEncode([for (final candidate in found) candidate.toJson()]),
    );
    return found;
  }

  /// What TMDB answered to this search, if the answer is still kept; no
  /// request is made. `null` if it was never asked or the answer is too
  /// old.
  List<TmdbCandidate>? kept(TitleKind kind, String title, {int? year}) {
    final body = _store.cachedAnswer(
      provider,
      searchKey(kind, title, year),
      maxAge: keepFor,
    );
    return body == null ? null : _decode(body);
  }

  /// Drops the answers that no longer count.
  int forgetOldAnswers() => _store.forgetAnswers(provider, maxAge: keepFor);

  /// What a search is kept under: spellings of one title share an answer.
  static String searchKey(TitleKind kind, String title, int? year) {
    final plain = normalizeTitle(title);
    return 'search|${kind == TitleKind.series ? 'tv' : 'movie'}|'
        '${plain.isEmpty ? title.trim().toLowerCase() : plain}|${year ?? ''}';
  }

  /// `null` if [body] is not what this class wrote.
  static List<TmdbCandidate>? _decode(String body) {
    final Object? json;
    try {
      json = jsonDecode(body);
    } on FormatException {
      return null;
    }
    if (json is! List<Object?>) return null;
    return [
      for (final entry in json)
        if (TmdbCandidate.fromJson(entry) case final candidate?) candidate,
    ];
  }
}
