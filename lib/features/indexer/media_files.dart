import 'package:dhara/features/player/subtitle_file.dart';

/// The only file types the index keeps. Everything else a server lists is
/// ignored: never stored, never fetched.
enum MediaKind { video, subtitle }

/// Video containers the bundled player opens.
const videoFileExtensions = <String>{
  'mkv',
  'mp4',
  'm4v',
  'avi',
  'mov',
  'webm',
  'ts',
  'm2ts',
  'mpg',
  'mpeg',
  'wmv',
  'flv',
};

/// What the file called [name] is, going by its extension alone, or `null`
/// if the index has no use for it.
MediaKind? mediaKindOf(String name) {
  final dot = name.lastIndexOf('.');
  // No extension, or nothing in front of it (".mkv").
  if (dot <= 0) return null;
  final extension = name.substring(dot + 1).toLowerCase();
  if (videoFileExtensions.contains(extension)) return MediaKind.video;
  if (subtitleFileExtensions.contains(extension)) return MediaKind.subtitle;
  return null;
}

/// Whether a folder called [name] is one that holds the subtitles of the
/// video next to it ("Subs", "Subtitles").
bool isSubtitleFolder(String name) =>
    const {'sub', 'subs', 'subtitle', 'subtitles'}.contains(name.toLowerCase());

/// Decides which video each subtitle file belongs to, by file name.
///
/// Returns one entry per name in [subtitles]: the index in [videos] of its
/// video, or `null` if it belongs to none (such a subtitle is not kept).
///
/// A subtitle belongs to, in this order:
/// 1. the video with the same name, or whose name it continues
///    (`Movie.2020.mkv`: `Movie.2020.srt`, `Movie.2020.en.forced.srt`);
///    the longest such video name wins;
/// 2. the only video whose name continues the subtitle's
///    (`Show.S01E02.srt`: `Show.S01E02.720p.WEB.mkv`);
/// 3. the only video there is (`English.srt` next to one movie).
List<int?> matchSubtitles(List<String> videos, List<String> subtitles) {
  if (videos.isEmpty) return List.filled(subtitles.length, null);

  final indexOf = <String, int>{};
  for (final (index, name) in videos.indexed) {
    // Two videos with one name ("a.mkv", "a.mp4"): the first one gets it.
    indexOf.putIfAbsent(_stem(name), () => index);
  }
  final stems = indexOf.keys.toList()..sort();

  return [
    for (final name in subtitles)
      _videoFor(_stem(name), indexOf, stems) ??
          (videos.length == 1 ? 0 : null),
  ];
}

int? _videoFor(String subtitle, Map<String, int> indexOf, List<String> stems) {
  // Rule 1: cut the subtitle's name back, one part at a time.
  var end = subtitle.length;
  while (end > 0) {
    final video = indexOf[subtitle.substring(0, end)];
    if (video != null) return video;
    end = subtitle.lastIndexOf(_separator, end - 1);
  }

  // Rule 2: the names that start with the subtitle's sort right after it.
  String? only;
  for (var i = _firstAtOrAfter(stems, subtitle); i < stems.length; i++) {
    final stem = stems[i];
    if (!stem.startsWith(subtitle)) break;
    if (!_separator.hasMatch(stem[subtitle.length])) continue;
    if (only != null) return null;
    only = stem;
  }
  return only == null ? null : indexOf[only];
}

/// The position of the first of the sorted [stems] that is not before
/// [text].
int _firstAtOrAfter(List<String> stems, String text) {
  var low = 0;
  var high = stems.length;
  while (low < high) {
    final middle = (low + high) ~/ 2;
    if (stems[middle].compareTo(text) < 0) {
      low = middle + 1;
    } else {
      high = middle;
    }
  }
  return low;
}

/// The name without its extension, in lower case.
String _stem(String name) {
  final dot = name.lastIndexOf('.');
  return (dot <= 0 ? name : name.substring(0, dot)).toLowerCase();
}

/// What separates the parts of a file name.
final _separator = RegExp(r'[._\- (\[]');
