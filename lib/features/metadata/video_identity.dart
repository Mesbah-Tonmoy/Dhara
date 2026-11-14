import 'package:dhara/features/metadata/release_name.dart';
import 'package:flutter/foundation.dart';

/// Raise this whenever [identifyVideo] or `parseReleaseName` come to read
/// names differently: every file name in the library is then read again.
const identityVersion = 1;

/// What kind of thing a video is, for the library.
enum TitleKind {
  movie,
  series,

  /// Neither: music videos, clips, tutorials. Found by file name only.
  other,
}

/// Which film or episode a video file is, going by its name and the folders
/// it is in, and what its name says about the copy.
///
/// Every text in here comes from server-controlled names: show it only
/// through a plain `Text` widget and bind it as an SQL parameter.
@immutable
class VideoIdentity {
  const VideoIdentity({
    required this.kind,
    required this.title,
    this.key,
    this.year,
    this.altTitle,
    this.season,
    this.episode,
    this.episodeEnd,
    this.episodeTitle,
    this.part,
    this.extra,
    this.height,
    this.source,
    this.codec,
    this.audio,
    this.languages = const [],
    this.is3d = false,
    this.group,
  });

  final TitleKind kind;

  /// The name of the film or show, as the folder or the file writes it.
  final String title;

  /// The same for every copy of one film or show, whatever the spelling:
  /// `m|vivarium|2019`, `s|the bay`. `null` for [TitleKind.other].
  ///
  /// A show's key has no year: its season folders carry the year of the
  /// season, not of the show.
  final String? key;

  /// For a show this may be the year of the season the file belongs to.
  final int? year;

  /// The name the other one of folder and file gives it, if that differs:
  /// a second thing to look it up by.
  final String? altTitle;

  /// `null` with an [episode]: numbered straight through (anime).
  final int? season;
  final int? episode;
  final int? episodeEnd;
  final String? episodeTitle;

  /// "CD1", "CD2": one piece of a film that comes in several files.
  final int? part;

  /// A trailer or sample of [title], not the film itself.
  final ExtraKind? extra;

  final int? height;
  final VideoSource? source;
  final VideoCodec? codec;
  final MultiAudio? audio;
  final List<String> languages;
  final bool is3d;
  final String? group;

  @override
  String toString() =>
      'VideoIdentity(${kind.name}, "$title", $year, key: $key, '
      'alt: "$altTitle", S$season E$episode-$episodeEnd "$episodeTitle", '
      'part $part, ${extra?.name}, $height, ${source?.label}, '
      '${codec?.label}, ${audio?.label}, $languages, 3D: $is3d, $group)';
}

/// Works out which film or episode the video called [name] is.
///
/// [path] is the folder it is in, as the index keeps it: the folder names
/// below the source's base URL, joined by "/". [videosInFolder] is how many
/// videos that folder holds; a folder named like a film that holds one video
/// names that video, whatever the file is called.
///
/// Never throws.
VideoIdentity identifyVideo({
  required String path,
  required String name,
  int videosInFolder = 1,
  int? latestYear,
}) {
  ReleaseName read(String text) =>
      parseReleaseName(text, latestYear: latestYear);

  final file = read(name);
  final segments = [
    for (final segment in path.split('/'))
      if (segment.trim().isNotEmpty) segment.trim(),
  ];
  final parent = segments.isEmpty ? null : read(segments.last);
  final grand = segments.length < 2
      ? null
      : read(segments[segments.length - 2]);
  final parentIsBucket =
      parent == null ||
      _wholeBracket.hasMatch(segments.last) ||
      _bucketNames.contains(normalizeTitle(parent.title));
  // The folder the file is in, if it names something.
  final folder = parentIsBucket ? null : parent;
  final category = _categoryOf(segments);

  VideoIdentity build({
    required TitleKind kind,
    required String title,
    int? year,
    String? other,
    int? season,
    int? episode,
    String? episodeTitle,
  }) {
    final plain = normalizeTitle(title);
    final alt = other == null || normalizeTitle(other) == plain ? null : other;
    return VideoIdentity(
      kind: kind,
      title: title,
      key: switch (kind) {
        TitleKind.movie => 'm|$plain|${year ?? ''}',
        TitleKind.series => 's|$plain',
        TitleKind.other => null,
      },
      year: year,
      altTitle: alt == null || alt.isEmpty ? null : alt,
      season: season,
      episode: episode,
      episodeEnd: kind == TitleKind.series ? file.episodeEnd : null,
      episodeTitle: episodeTitle,
      part: file.part,
      extra: file.extra,
      // What the file does not say, its folder may: "Vivarium (2019) 720p
      // [Dual Audio]/necklace.mkv".
      height: file.height ?? parent?.height,
      source: file.source ?? parent?.source,
      codec: file.codec ?? parent?.codec,
      audio: file.audio ?? parent?.audio,
      languages: file.languages.isNotEmpty
          ? file.languages
          : parent?.languages ?? const [],
      is3d: file.is3d || (parent?.is3d ?? false),
      group: file.group,
    );
  }

  // An episode, by what the file says...
  var episode = file.episode;
  var episodeTitle = file.episodeTitle;
  var showTitle = file.title;
  if (episode != null &&
      file.season == null &&
      category == TitleKind.movie &&
      folder?.year != null) {
    // "Film - 10 720p.mkv" in the folder of a film: not episode 10.
    episode = null;
  }
  // ...or by where it is: "01 - Pilot.mkv" in "Season 1", "vober_hat96.wmv"
  // in "vober_hat".
  if (episode == null && file.year == null && parent != null) {
    final seasonFolder = parent.season != null && parent.episode == null;
    final counted = _leadingNumber.firstMatch(file.title);
    final parentPlain = normalizeTitle(parent.title);
    final filePlain = normalizeTitle(file.title);
    if (seasonFolder && counted != null) {
      episode = int.parse(counted.group(1)!);
      final words = counted.group(2)!.trim();
      episodeTitle = words.isEmpty ? null : words;
      showTitle = '';
    } else if (folder != null &&
        parentPlain.isNotEmpty &&
        filePlain.startsWith(parentPlain)) {
      final rest = filePlain.substring(parentPlain.length).trim();
      if (_twoOrThreeDigits.hasMatch(rest)) {
        episode = int.parse(rest);
        showTitle = parent.title;
      }
    }
  }

  if (episode != null) {
    // The file names the show; failing that the season folder, or the
    // show's folder above it.
    final named = [
      showTitle,
      if (folder != null) folder.title,
      if (grand != null && parent?.season != null) grand.title,
    ].where((title) => title.isNotEmpty).toList();
    if (named.isNotEmpty) {
      return build(
        kind: TitleKind.series,
        title: named.first,
        other: named.length > 1 ? named[1] : null,
        year: file.year ?? parent?.year ?? grand?.year,
        season: file.season ?? parent?.season ?? grand?.season,
        episode: episode,
        episodeTitle: episodeTitle,
      );
    }
  }

  // A folder named like a film ("Vivarium (2019) 720p") names what is in
  // it, as long as the file does not plainly say something else.
  var title = file.title;
  var year = file.year;
  String? other;
  final folderYear = folder?.year;
  final titleFolder = folder != null && folderYear != null;
  if (titleFolder) {
    final fileYear = file.year;
    final yearsAgree = fileYear == null || (fileYear - folderYear).abs() <= 1;
    final alone =
        videosInFolder <= 1 || file.part != null || file.extra != null;
    if (yearsAgree && (alone || _related(file.title, folder.title))) {
      title = folder.title;
      year = folderYear;
      other = file.title;
    } else {
      other = folder.title;
    }
  }

  // Under "Music Videos" and the like, only what is named like a film is one.
  final looksLikeFilm =
      (titleFolder && other == file.title) ||
      (file.year != null && (file.height != null || file.source != null));
  // "Baywatch S08 Extras.avi": of a season, but no episode.
  final seasonOnly = file.season != null;
  if (title.isEmpty ||
      seasonOnly ||
      (category == TitleKind.other && !looksLikeFilm)) {
    return build(
      kind: TitleKind.other,
      title: title.isEmpty ? name : title,
      year: year,
    );
  }
  return build(kind: TitleKind.movie, title: title, year: year, other: other);
}

/// [title] reduced to what two spellings of one name have in common: lower
/// case, no accents, no punctuation, "&" as "and", single letters run
/// together ("S.H.I.E.L.D." and "S H I E L D" are both "shield").
String normalizeTitle(String title) {
  final plain = StringBuffer();
  for (final rune in title.toLowerCase().runes) {
    final char = String.fromCharCode(rune);
    plain.write(_unaccented[char] ?? char);
  }
  final words = plain
      .toString()
      .replaceAll('&', ' and ')
      .replaceAll(_apostrophes, '')
      .replaceAll(_notLetterOrDigit, ' ')
      .trim()
      .split(_spaces);
  final joined = <String>[];
  var lastWasLetter = false;
  for (final word in words) {
    if (word.isEmpty) continue;
    final isLetter = _oneLetter.hasMatch(word);
    if (isLetter && lastWasLetter) {
      joined[joined.length - 1] += word;
    } else {
      joined.add(word);
    }
    lastWasLetter = isLetter;
  }
  return joined.join(' ');
}

/// Whether two titles are plausibly spellings of one name: one holds the
/// other ("TheUnborn-aXXo", "The Unborn"), or they share half their words
/// ("Transformers 2", "Transformers-Revenge of the Fallen").
bool _related(String a, String b) {
  final first = normalizeTitle(a);
  final second = normalizeTitle(b);
  if (first.isEmpty || second.isEmpty) return false;
  final packedFirst = first.replaceAll(' ', '');
  final packedSecond = second.replaceAll(' ', '');
  if (packedFirst.contains(packedSecond) ||
      packedSecond.contains(packedFirst)) {
    return true;
  }
  final firstWords = first.split(' ').toSet();
  final secondWords = second.split(' ').toSet();
  final shared = firstWords.intersection(secondWords).length;
  final fewer = firstWords.length < secondWords.length
      ? firstWords.length
      : secondWords.length;
  return shared * 2 >= fewer;
}

/// What the folders say the video is: the innermost folder with a word like
/// "Movies" or "TV Shows" decides. Folders named after a film (they carry a
/// year) are not asked: "Music and Lyrics (2007)" is not music.
TitleKind? _categoryOf(List<String> segments) {
  for (final segment in segments.reversed) {
    if (_yearInName.hasMatch(segment)) continue;
    final plain = normalizeTitle(segment);
    if (_seriesWords.hasMatch(plain)) return TitleKind.series;
    if (_movieWords.hasMatch(plain)) return TitleKind.movie;
    if (_otherWords.hasMatch(plain)) return TitleKind.other;
  }
  return null;
}

/// Folders that sort films, not name one: "Hindi-2021", "English 2014".
const _bucketNames = {
  'bangla',
  'bengali',
  'chinese',
  'dubbed',
  'english',
  'hindi',
  'japanese',
  'kannada',
  'korean',
  'latest',
  'malayalam',
  'movie',
  'movies',
  'new',
  'old',
  'other',
  'others',
  'punjabi',
  'tamil',
  'telugu',
  'urdu',
};

final _seriesWords = RegExp(
  r'\b(tv|tvshows?|tvseries|series|serials?|webseries)\b',
);
final _movieWords = RegExp(
  r'\b(movies?|films?|cinema|telefilms?|telifilms?|natok|dramas?|'
  r'documentar(y|ies)|documentry)\b',
);
final _otherWords = RegExp(
  r'\b(music|audio|songs?|mp3|mobile|fun|funny|tutorials?|software|'
  r'games?|e ?books?|wallpapers?|clips?)\b',
);

/// "(2019)", "(1960-1994)": a folder that is nothing but a bracket.
final _wholeBracket = RegExp(r'^\([^)]*\)$');
final _yearInName = RegExp(r'(19|20)\d{2}');

/// "01", "01 - Pilot", "12 The Name".
final _leadingNumber = RegExp(r'^(\d{1,3})(?:\s*-\s*|\s+|$)(.*)$');
final _twoOrThreeDigits = RegExp(r'^\d{2,3}$');
final _oneLetter = RegExp(r'^\p{L}$', unicode: true);
final _apostrophes = RegExp("['’`]");
final _notLetterOrDigit = RegExp(r'[^\p{L}\p{N}]+', unicode: true);
final _spaces = RegExp(r'\s+');

/// Accented Latin letters by the plain letter they stand for.
const _accents = {
  'a': 'àáâãäåāăą',
  'c': 'çćĉċč',
  'd': 'ďđ',
  'e': 'èéêëēĕėęě',
  'g': 'ĝğġģ',
  'h': 'ĥħ',
  'i': 'ìíîïĩīĭįı',
  'j': 'ĵ',
  'k': 'ķ',
  'l': 'ĺļľŀł',
  'n': 'ñńņň',
  'o': 'òóôõöøōŏő',
  'r': 'ŕŗř',
  's': 'śŝşš',
  't': 'ţťŧ',
  'u': 'ùúûüũūŭůűų',
  'w': 'ŵ',
  'y': 'ýÿŷ',
  'z': 'źżž',
  'ae': 'æ',
  'oe': 'œ',
  'ss': 'ß',
};

final _unaccented = {
  for (final MapEntry(key: plain, value: accented) in _accents.entries)
    for (final rune in accented.runes) String.fromCharCode(rune): plain,
};
