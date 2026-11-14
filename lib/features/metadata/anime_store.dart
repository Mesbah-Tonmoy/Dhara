import 'dart:convert';

import 'package:dhara/core/db/library_db.dart';
import 'package:dhara/features/indexer/index_store.dart' show ftsQueryFor;
import 'package:dhara/features/metadata/anilist_client.dart';
import 'package:dhara/features/metadata/metadata_store.dart';
import 'package:dhara/features/metadata/video_identity.dart';
import 'package:flutter/foundation.dart';
import 'package:sqlite3/sqlite3.dart';

/// An anime of one of AniList's lists, and the title of the library it is,
/// if the library has it.
@immutable
class AnimeRow {
  const AnimeRow(this.anime, {this.titleId, this.titleKind});

  final AnimeEntry anime;

  /// The title in the library; `null` if the library does not have it.
  final int? titleId;
  final TitleKind? titleKind;

  bool get inLibrary => titleId != null;
}

/// Reads and writes the part of the library database that has to do with
/// AniList: its lists as they were last fetched, and which titles of the
/// library the anime on them are.
///
/// Every value goes into SQL as a parameter, never as text.
class AnimeStore {
  AnimeStore(this._library, {DateTime Function() now = DateTime.now})
    : _answers = MetadataStore(_library, now: now);

  /// The name the lists are kept under.
  static const provider = 'anilist';

  /// How long a list counts: what is trending changes by the day.
  static const keepFor = Duration(hours: 12);

  final LibraryDb _library;
  final MetadataStore _answers;

  Database get _db => _library.db;

  /// The list kept under [key], if it is not older than [keepFor].
  List<AnimeEntry>? keptList(String key) {
    final body = _answers.cachedAnswer(provider, key, maxAge: keepFor);
    if (body == null) return null;
    try {
      final json = jsonDecode(body);
      if (json is! List<Object?>) return null;
      return [
        for (final entry in json)
          if (AnimeEntry.fromJson(entry) case final anime?) anime,
      ];
    } on FormatException {
      return null;
    }
  }

  /// Keeps [list] under [key].
  void keepList(String key, List<AnimeEntry> list) => _answers.cacheAnswer(
    provider,
    key,
    jsonEncode([for (final anime in list) anime.toJson()]),
  );

  /// Finds the title of the library each anime of [list] is, going by its
  /// names, and notes AniList's id on the titles found.
  ///
  /// AniList lists every season of a show as an anime of its own ("The
  /// Apothecary Diaries Season 3"); the library has one title per show, so
  /// a season finds its show.
  List<AnimeRow> match(List<AnimeEntry> list) => _library.transaction(
    () => [
      for (final anime in list)
        switch (_titleOf(anime)) {
          null => AnimeRow(anime),
          (final id, final kind) => AnimeRow(
            anime,
            titleId: id,
            titleKind: kind,
          ),
        },
    ],
  );

  (int, TitleKind)? _titleOf(AnimeEntry anime) {
    final names = <String>{};
    for (final name in anime.names) {
      final plain = normalizeTitle(name);
      if (plain.isNotEmpty) names.add(plain);
      final show = normalizeTitle(name.replaceFirst(_seasonSuffix, ''));
      if (show.isNotEmpty) names.add(show);
    }
    for (final name in names) {
      // A film is looked for among the films first, anything else among
      // the shows; a library may have filed it the other way.
      for (final isShow in anime.isFilm ? [false, true] : [true, false]) {
        final found = isShow ? _show(name) : _film(name, anime.year);
        if (found == null) continue;
        _db.execute(
          'UPDATE titles SET anilist_id = ? WHERE id = ? '
          'AND anilist_id IS NULL',
          [anime.id, found],
        );
        return (found, isShow ? TitleKind.series : TitleKind.movie);
      }
    }
    return null;
  }

  /// The show whose files, or TMDB, call it [name] (already normalised).
  int? _show(String name) {
    final byKey = _db.select('SELECT title FROM title_keys WHERE key = ?', [
      's|$name',
    ]);
    if (byKey.isNotEmpty) return byKey.first['title'] as int;
    return _byTitleName(name, kind: 1, year: null);
  }

  /// The film called [name], of [year] if there are several.
  int? _film(String name, int? year) {
    final prefix = 'm|$name|';
    final byKey = _db.select(
      'SELECT title, year FROM title_keys '
      'WHERE substr(key, 1, ?) = ? ORDER BY year = ? DESC, year',
      [prefix.length, prefix, year],
    );
    if (byKey.isNotEmpty) return byKey.first['title'] as int;
    return _byTitleName(name, kind: 0, year: year);
  }

  /// A matched title that TMDB calls [name]: its files may spell it
  /// another way.
  int? _byTitleName(String name, {required int kind, required int? year}) {
    final query = ftsQueryFor(name);
    if (query == null) return null;
    // The search index narrows it down; the names are compared after.
    for (final row in _db.select(
      'SELECT t.id, t.name, t.original_name FROM titles_fts '
      'JOIN titles t ON t.id = titles_fts.rowid '
      'WHERE titles_fts MATCH ? AND t.kind = ? '
      'ORDER BY t.year = ? DESC, titles_fts.rank LIMIT 20',
      [query, kind, year],
    )) {
      if (normalizeTitle(row['name'] as String) == name ||
          normalizeTitle('${row['original_name'] ?? ''}') == name) {
        return row['id'] as int;
      }
    }
    return null;
  }
}

/// "Season 3", "3rd Season", "Part 2", "Cour 2", "Final Season" at the end
/// of a name.
final _seasonSuffix = RegExp(
  r'[\s:\-–]*\b(season\s*\d+|\d+(st|nd|rd|th)\s+season|part\s*\d+|'
  r'cour\s*\d+|the\s+final\s+season|final\s+season)\s*$',
  caseSensitive: false,
);
