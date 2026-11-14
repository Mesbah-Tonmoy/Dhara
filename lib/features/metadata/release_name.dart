import 'package:dhara/features/indexer/media_files.dart';
import 'package:flutter/foundation.dart';

/// Where a copy of a video was taken from.
enum VideoSource {
  bluRay('BluRay'),
  webDl('WEB-DL'),
  webRip('WEBRip'),
  hdRip('HDRip'),
  hdtv('HDTV'),
  dvd('DVD'),
  cam('CAM');

  const VideoSource(this.label);

  final String label;
}

enum VideoCodec {
  h264('H.264'),
  hevc('HEVC'),
  av1('AV1'),
  xvid('XviD'),
  divx('DivX');

  const VideoCodec(this.label);

  final String label;
}

/// More than one audio track, as release names announce it.
enum MultiAudio {
  dual('Dual Audio'),
  triple('Triple Audio'),
  multi('Multi Audio');

  const MultiAudio(this.label);

  final String label;
}

/// What the name of a video file or of its folder says about it.
///
/// Every text in here comes from a server-controlled name: show it only
/// through a plain `Text` widget and bind it as an SQL parameter.
@immutable
class ReleaseName {
  const ReleaseName({
    required this.title,
    this.year,
    this.height,
    this.source,
    this.codec,
    this.audio,
    this.languages = const [],
    this.is3d = false,
    this.group,
  });

  /// The name of the film or show, as written, without the release tags.
  final String title;
  final int? year;

  /// Picture height in lines: 720, 1080, 2160.
  final int? height;
  final VideoSource? source;
  final VideoCodec? codec;
  final MultiAudio? audio;

  /// The languages the name lists, in English, in the order written.
  final List<String> languages;
  final bool is3d;

  /// Who made this copy ("YIFY"); says nothing about the film.
  final String? group;

  @override
  String toString() =>
      'ReleaseName("$title", $year, $height, ${source?.label}, '
      '${codec?.label}, ${audio?.label}, $languages, 3D: $is3d, $group)';
}

/// Reads a release-style [name]: of a video file (the extension is dropped)
/// or of a folder.
///
/// The title ends at the year, or else at the first tag that cannot be part
/// of a title (`720p`, `BluRay`, `x264`, a `[tag]`). A year is a number from
/// 1900 to [latestYear] (next year by default) with something in front of
/// it, so `1917.2019.1080p` is the film "1917" from 2019.
///
/// Never throws, whatever the name looks like.
ReleaseName parseReleaseName(String name, {int? latestYear}) {
  final stem = _stemOf(name);
  final dotted = _dotsSeparate(stem);
  final tokens = _scan(stem, dotted: dotted);
  final tags = _classify([for (final token in tokens) token.key]);
  final maxYear = latestYear ?? DateTime.now().year + 1;

  int? yearAt(int index) {
    final token = tokens[index];
    final text = token.kind == _Kind.word ? token.key : token.text;
    if (!_fourDigits.hasMatch(text)) return null;
    final year = int.parse(text);
    return year >= 1900 && year <= maxYear ? year : null;
  }

  // The title starts after any "[group]" tags in front.
  var start = 0;
  while (start < tokens.length && tokens[start].kind == _Kind.bracket) {
    start++;
  }

  // "(1973) Ashani Sanket": the year comes first and the title follows.
  // After a tag in front ("[REC] (2007)"), or alone, it leaves no title.
  int? year;
  var titleless = false;
  if (start < tokens.length && tokens[start].kind == _Kind.paren) {
    year = yearAt(start);
    if (year != null) {
      if (start == 0 && tokens.length > 1) {
        start++;
      } else {
        titleless = true;
      }
    }
  }

  // What ends the title for certain: a tag no title contains, or a "[tag]".
  // The first word is never one ("Cam.2018.1080p").
  var marker = tokens.length;
  for (var i = start + 1; i < tokens.length; i++) {
    if (tokens[i].kind == _Kind.bracket || (tags[i]?.strong ?? false)) {
      marker = i;
      break;
    }
  }

  var end = titleless ? start : marker;
  if (year == null) {
    int? position;
    // "(2019)" beats a bare number.
    for (var i = start + 1; i < tokens.length && position == null; i++) {
      if (tokens[i].kind != _Kind.word && yearAt(i) != null) position = i;
    }
    // Otherwise the last number before the tags: "Blade.Runner.2049.2017".
    for (var i = marker - 1; i > start && position == null; i--) {
      if (tokens[i].kind == _Kind.word && yearAt(i) != null) position = i;
    }
    // Or, failing that, the first one among the tags.
    for (var i = marker + 1; i < tokens.length && position == null; i++) {
      if (tokens[i].kind == _Kind.word && yearAt(i) != null) position = i;
    }
    // Or a "[2014]" in front of the title.
    for (var i = 0; i < start && position == null; i++) {
      if (yearAt(i) != null) position = i;
    }
    if (position != null) {
      year = yearAt(position);
      if (position > start && position < end) end = position;
    }
  }

  // A closing "(Drama)" or "(France)" is a remark, not the title.
  while (end > start && tokens[end - 1].kind == _Kind.paren) {
    end--;
  }
  // "Movie.DUBBED.720p": loose tags right before the certain ones.
  if (year == null && marker < tokens.length) {
    while (end - start > 1 && (tags[end - 1]?.trailing ?? false)) {
      end--;
    }
  }
  // "Reindeer Games Directors Cut (2000)".
  while (end - start > 1) {
    final last = tokens[end - 1].key;
    if (_editionWords.contains(last)) {
      end--;
    } else if (end - start > 2 &&
        _editionNouns.contains(last) &&
        _editionKinds.contains(tokens[end - 2].key)) {
      end -= 2;
    } else {
      break;
    }
  }

  var title = _titleOf(tokens.sublist(start, end), dotted: dotted);
  if (title.isEmpty) {
    // "[REC] (2007)": the tag in front was the title after all.
    final fallback = tokens.isNotEmpty && tokens.first.kind == _Kind.bracket
        ? tokens.first.text
        : stem;
    title = fallback.replaceAll(_spaces, ' ').trim();
  }

  // Everything outside the title is searched for tags.
  final found = _Found();
  for (var i = 0; i < tokens.length; i++) {
    if (i >= start && i < end) continue;
    final token = tokens[i];
    if (token.kind == _Kind.word) {
      final tag = tags[i];
      if (tag != null) found.add(tag);
    } else if (yearAt(i) == null) {
      final keys = [
        for (final part in token.text.split(_innerSeparators)) _keyOf(part),
      ];
      _classify(keys).nonNulls.forEach(found.add);
    }
  }

  return ReleaseName(
    title: title,
    year: year,
    height: found.height ?? found.looseHeight,
    source: found.source ?? found.looseSource,
    codec: found.codec,
    audio: found.audio,
    languages: List.unmodifiable(found.languages),
    is3d: found.is3d,
    group: found.any ? _groupOf(tokens, tags, end) : null,
  );
}

/// The name without invisible characters and without a video extension.
String _stemOf(String name) {
  final clean = name.replaceAll(_invisible, '').trim();
  final dot = clean.lastIndexOf('.');
  if (dot > 0 &&
      videoFileExtensions.contains(clean.substring(dot + 1).toLowerCase())) {
    return clean.substring(0, dot);
  }
  return clean;
}

/// Whether the dots of [stem] stand for spaces ("The.Movie.2019") instead of
/// belonging to the words ("Dr. Bird's Advice", "3.10 to Yuma").
bool _dotsSeparate(String stem) {
  // What is in brackets does not count: "Satan's.Little.Helper[2004]DvDrip".
  final plain = stem.replaceAll(_enclosed, '').trim();
  final dots = '.'.allMatches(plain).length;
  return dots > 0 && dots > _spaces.allMatches(plain).length;
}

enum _Kind { word, paren, bracket }

class _Token {
  _Token(this.text, this.kind, {this.dash = false, this.attached = ''});

  /// A word as written, or what is inside the brackets.
  final String text;
  final _Kind kind;

  /// A "-" stands in front of it.
  final bool dash;

  /// "-" or "+" if that ties it to the word before, with no space between.
  final String attached;

  /// What tags are looked up by; empty for anything but a word.
  late final String key = kind == _Kind.word ? _keyOf(text) : '';
}

/// Lower case, without punctuation around it: "Inc." is "inc".
String _keyOf(String text) => text.toLowerCase().replaceAll(_edges, '');

/// Cuts [stem] into words, "(...)" and "[...]" / "{...}" parts. Words end at
/// spaces, underscores, "-" and "+", and at dots if those are [dotted].
List<_Token> _scan(String stem, {required bool dotted}) {
  final tokens = <_Token>[];
  var dash = false;
  var joiner = '';
  var afterWord = false;

  bool endsWord(String char) =>
      char.trim().isEmpty ||
      char == '_' ||
      char == '-' ||
      char == '+' ||
      (dotted && char == '.') ||
      _brackets.containsKey(char) ||
      _brackets.containsValue(char);

  var i = 0;
  while (i < stem.length) {
    final char = stem[i];
    final closing = _brackets[char];
    if (closing != null) {
      final close = stem.indexOf(closing, i + 1);
      afterWord = false;
      joiner = '';
      if (close < 0 && char == '(') {
        // Never closed: an ordinary character.
        i++;
        continue;
      }
      final stop = close < 0 ? stem.length : close;
      tokens.add(
        _Token(
          stem.substring(i + 1, stop).trim(),
          char == '(' ? _Kind.paren : _Kind.bracket,
          dash: dash,
        ),
      );
      dash = false;
      i = stop + 1;
    } else if (char == '-' || char == '+') {
      if (char == '-') dash = true;
      if (afterWord) joiner = char;
      afterWord = false;
      i++;
    } else if (endsWord(char)) {
      afterWord = false;
      joiner = '';
      i++;
    } else {
      var stop = i + 1;
      while (stop < stem.length && !endsWord(stem[stop])) {
        stop++;
      }
      final word = stem.substring(i, stop);
      // "Baby and Me.2008.DVDRip": spaces in the title, dots among the tags.
      final parts = !dotted && word.contains('.') ? word.split('.') : [word];
      if (parts.length == 1 || !parts.any(_isCertainTag)) {
        tokens.add(_Token(word, _Kind.word, dash: dash, attached: joiner));
      } else {
        for (final part in parts) {
          if (part.isEmpty) continue;
          tokens.add(_Token(part, _Kind.word, dash: dash, attached: joiner));
          dash = false;
          joiner = '';
        }
      }
      dash = false;
      joiner = '';
      afterWord = true;
      i = stop;
    }
  }
  return tokens;
}

/// Puts the title back together from its tokens.
String _titleOf(List<_Token> tokens, {required bool dotted}) {
  final title = StringBuffer();
  for (var i = 0; i < tokens.length; i++) {
    final token = tokens[i];
    var text = token.kind == _Kind.paren ? '(${token.text})' : token.text;
    if (dotted && _isInitial(token)) {
      // "E.T.", "S.H.I.E.L.D.": those dots were not separators.
      var last = i;
      while (last + 1 < tokens.length &&
          _isInitial(tokens[last + 1]) &&
          !tokens[last + 1].dash) {
        last++;
      }
      if (last > i) {
        text = [for (var k = i; k <= last; k++) '${tokens[k].text}.'].join();
        i = last;
      }
    }
    if (title.isNotEmpty) {
      title.write(
        token.attached.isNotEmpty
            ? token.attached
            : token.dash
            ? ' - '
            : ' ',
      );
    }
    title.write(text);
  }
  return title.toString().replaceAll(_titleStart, '').replaceAll(_titleEnd, '');
}

bool _isCertainTag(String word) => _tagOf(_keyOf(word))?.strong ?? false;

bool _isInitial(_Token token) =>
    token.kind == _Kind.word && _oneLetter.hasMatch(token.text);

/// The release group: the last word after the tags, if it is not a tag
/// itself. Site names lose their ending ("Pahe.in" is "Pahe").
String? _groupOf(List<_Token> tokens, List<_Tag?> tags, int end) {
  var i = tokens.length - 1;
  // Skip closing remarks, empty brackets and what dots cut off a site name.
  while (i >= end) {
    final token = tokens[i];
    final skip = switch (token.kind) {
      _Kind.paren => true,
      _Kind.bracket => token.text.isEmpty,
      _Kind.word =>
        _siteEndings.contains(token.key) &&
            i > end &&
            tokens[i - 1].kind == _Kind.word &&
            tags[i - 1] == null,
    };
    if (!skip) break;
    i--;
  }
  if (i < end) return null;

  final last = tokens[i];
  final name = last.text.replaceFirst(_siteEnding, '');
  final isSite = name.length != last.text.length;
  if (last.kind == _Kind.bracket) {
    // "x264-[YTS.MX]" names a group; "[Concrete]" does not.
    final named = (last.dash || isSite) && _tagOf(_keyOf(name)) == null;
    return named && _groupName.hasMatch(name) ? name : null;
  }
  if (isSite) return _groupName.hasMatch(name) ? name : null;
  if (tags[i] != null) return null;

  // "Junaid-Zia": the words tied to it belong to the name.
  var first = i;
  while (first > end &&
      tokens[first].attached == '-' &&
      tokens[first - 1].kind == _Kind.word &&
      tags[first - 1] == null) {
    first--;
  }
  final parts = [for (var k = first; k <= i; k++) tokens[k].text];
  return parts.every(_groupName.hasMatch) ? parts.join('-') : null;
}

/// What a word of a release name stands for.
class _Tag {
  const _Tag({
    this.strong = false,
    this.trailing = false,
    this.height,
    this.source,
    this.codec,
    this.audio,
    this.language,
    this.is3d = false,
  });

  /// No title contains this word, so the title ends in front of it.
  final bool strong;

  /// Not [strong], but dropped from the end of a title that tags follow.
  final bool trailing;
  final int? height;
  final VideoSource? source;
  final VideoCodec? codec;
  final MultiAudio? audio;
  final String? language;
  final bool is3d;
}

/// The tags collected from one name.
class _Found {
  var any = false;
  int? height;
  int? looseHeight;
  VideoSource? source;
  VideoSource? looseSource;
  VideoCodec? codec;
  MultiAudio? audio;
  final languages = <String>[];
  var is3d = false;

  void add(_Tag tag) {
    any = true;
    // "1080p" and "BluRay" count for more than a bare "1080" or "BD".
    if (tag.strong) {
      height ??= tag.height;
      source ??= tag.source;
    } else {
      looseHeight ??= tag.height;
      looseSource ??= tag.source;
    }
    codec ??= tag.codec;
    audio ??= tag.audio;
    is3d = is3d || tag.is3d;
    final language = tag.language;
    if (language != null && !languages.contains(language)) {
      languages.add(language);
    }
  }
}

/// One entry per key: its tag, or `null`. Two words that make one tag
/// ("WEB-DL", "Dual Audio", "H.264" cut at the dot) both get it.
List<_Tag?> _classify(List<String> keys) {
  final tags = List<_Tag?>.filled(keys.length, null);
  for (var i = 0; i < keys.length; i++) {
    final key = keys[i];
    if (key.isEmpty) continue;
    final pair = i + 1 < keys.length ? _pairs['$key ${keys[i + 1]}'] : null;
    if (pair != null) {
      tags[i] = pair;
      tags[i + 1] = pair;
      i++;
    } else {
      tags[i] = _tagOf(key);
    }
  }
  return tags;
}

_Tag? _tagOf(String key) {
  // "h.264" and "web.dl" as one word.
  final flat = key.replaceAll('.', '');
  final known = _words[flat];
  if (known != null) return known;

  final lines = _resolution.firstMatch(key)?.group(1);
  if (lines != null && _heights.contains(lines)) {
    return _Tag(strong: true, height: int.parse(lines));
  }
  if (_heights.contains(key)) {
    return _Tag(trailing: true, height: int.parse(key));
  }
  if (_fileSize.hasMatch(key)) return _strongNoise;
  if (_channels.hasMatch(key) || _audioCodec.hasMatch(flat)) return _noise;
  final language = _languages[key];
  if (language != null) return _Tag(language: language);
  if (key.contains('www.') || _siteEnding.hasMatch(key)) return _noise;
  return null;
}

const _noise = _Tag(trailing: true);
const _strongNoise = _Tag(strong: true);
const _threeD = _Tag(trailing: true, is3d: true);

const _bluRay = _Tag(strong: true, source: VideoSource.bluRay);
const _webDl = _Tag(strong: true, source: VideoSource.webDl);
const _webRip = _Tag(strong: true, source: VideoSource.webRip);
const _hdRip = _Tag(strong: true, source: VideoSource.hdRip);
const _hdtv = _Tag(strong: true, source: VideoSource.hdtv);
const _dvd = _Tag(strong: true, source: VideoSource.dvd);
const _cam = _Tag(strong: true, source: VideoSource.cam);
const _h264 = _Tag(strong: true, codec: VideoCodec.h264);
const _hevc = _Tag(strong: true, codec: VideoCodec.hevc);

/// Tags that are one word. Words that are also ordinary words or titles
/// ("Cam", "Web", "TS", "3D") are not `strong`: they only count after the
/// title has ended.
const _words = <String, _Tag>{
  'bluray': _bluRay,
  'bdrip': _bluRay,
  'brrip': _bluRay,
  'bdremux': _bluRay,
  'bd': _Tag(trailing: true, source: VideoSource.bluRay),
  'webdl': _webDl,
  'webhd': _webDl,
  'web': _Tag(trailing: true, source: VideoSource.webDl),
  'webrip': _webRip,
  'hdrip': _hdRip,
  'hdtv': _hdtv,
  'hdtvrip': _hdtv,
  'pdtv': _hdtv,
  'dvdrip': _dvd,
  'dvdscr': _dvd,
  'dvdr': _dvd,
  'dvd': _Tag(trailing: true, source: VideoSource.dvd),
  'hdcam': _cam,
  'camrip': _cam,
  'hdts': _cam,
  'telesync': _cam,
  'cam': _Tag(source: VideoSource.cam),
  'ts': _Tag(source: VideoSource.cam),
  'tc': _Tag(source: VideoSource.cam),
  'x264': _h264,
  'h264': _h264,
  'avc': _Tag(trailing: true, codec: VideoCodec.h264),
  'x265': _hevc,
  'h265': _hevc,
  'hevc': _hevc,
  'av1': _Tag(trailing: true, codec: VideoCodec.av1),
  'xvid': _Tag(strong: true, codec: VideoCodec.xvid),
  'divx': _Tag(strong: true, codec: VideoCodec.divx),
  '4k': _Tag(trailing: true, height: 2160),
  'uhd': _Tag(trailing: true, height: 2160),
  '3d': _threeD,
  'sbs': _threeD,
  'hsbs': _threeD,
  'hou': _threeD,
  'esub': _strongNoise,
  'esubs': _strongNoise,
  'msub': _strongNoise,
  'msubs': _strongNoise,
  'sub': _noise,
  'subs': _noise,
  'subbed': _noise,
  'rosubbed': _noise,
  'dub': _noise,
  'dubbed': _noise,
  'proper': _noise,
  'repack': _noise,
  'rerip': _noise,
  'limited': _noise,
  'internal': _noise,
  'int': _noise,
  'unrated': _noise,
  'extended': _noise,
  'remastered': _noise,
  'uncut': _noise,
  'imax': _noise,
  'remux': _noise,
  'upscaled': _noise,
  'hc': _noise,
  'hq': _noise,
  'hd': _noise,
  'ws': _noise,
  '10bit': _noise,
  '8bit': _noise,
  'hi10p': _noise,
  'hdr': _noise,
  'hdr10': _noise,
  'nf': _noise,
  'amzn': _noise,
  'dsnp': _noise,
  'hmax': _noise,
  'atvp': _noise,
};

/// Tags that are two words, however they are joined ("WEB-DL", "WEB DL",
/// "WEB.DL").
const _pairs = <String, _Tag>{
  'blu ray': _bluRay,
  'web dl': _webDl,
  'web rip': _webRip,
  'hd rip': _hdRip,
  'hd tv': _hdtv,
  'dvd rip': _dvd,
  'hd cam': _cam,
  'hd ts': _cam,
  'h 264': _h264,
  'x 264': _h264,
  'h 265': _hevc,
  'x 265': _hevc,
  'dual audio': _Tag(strong: true, audio: MultiAudio.dual),
  'triple audio': _Tag(strong: true, audio: MultiAudio.triple),
  'multi audio': _Tag(strong: true, audio: MultiAudio.multi),
  'dts hd': _noise,
  'h sbs': _threeD,
  'half sbs': _threeD,
  'half ou': _threeD,
};

const _languages = <String, String>{
  'arabic': 'Arabic',
  'bangla': 'Bengali',
  'bengali': 'Bengali',
  'cantonese': 'Cantonese',
  'chinese': 'Chinese',
  'eng': 'English',
  'english': 'English',
  'french': 'French',
  'german': 'German',
  'hindi': 'Hindi',
  'indonesian': 'Indonesian',
  'italian': 'Italian',
  'jap': 'Japanese',
  'japanese': 'Japanese',
  'kannada': 'Kannada',
  'korean': 'Korean',
  'malayalam': 'Malayalam',
  'mandarin': 'Mandarin',
  'marathi': 'Marathi',
  'persian': 'Persian',
  'portuguese': 'Portuguese',
  'punjabi': 'Punjabi',
  'russian': 'Russian',
  'spanish': 'Spanish',
  'swedish': 'Swedish',
  'tamil': 'Tamil',
  'telugu': 'Telugu',
  'thai': 'Thai',
  'turkish': 'Turkish',
  'urdu': 'Urdu',
};

const _heights = {'360', '480', '540', '576', '720', '1080', '1440', '2160'};

/// "Extended", and "Directors Cut" as kind and noun, at the end of a title.
const _editionWords = {'extended', 'unrated', 'remastered', 'uncut'};
const _editionNouns = {'cut', 'edition', 'version'};
const _editionKinds = {
  'directors',
  "director's",
  'extended',
  'unrated',
  'theatrical',
  'special',
  'remastered',
};

/// What is left of a site name once dots have cut it up.
const _siteEndings = {
  'com',
  'net',
  'org',
  'in',
  'mx',
  'ws',
  'ag',
  'am',
  'to',
  'cc',
  'me',
  'io',
  'co',
};

const _brackets = {'(': ')', '[': ']', '{': '}'};

final _siteEnding = RegExp(
  r'(\.(com|net|org|in|mx|ws|ag|am|to|cc|me|io|co))+$',
  caseSensitive: false,
);
final _fourDigits = RegExp(r'^\d{4}$');
final _resolution = RegExp(r'^(\d{3,4})[pi]$');
final _fileSize = RegExp(r'^\d+(\.\d+)?[mg]b$');
final _channels = RegExp(r'^\d\.\d$');
final _audioCodec = RegExp(
  r'^(aac|ac3|eac3|dd|ddp|dts|dtshd|truehd|atmos|mp3|flac|opus)\d{0,2}$',
);
final _groupName = RegExp(r'^(?=.*\p{L})[\p{L}\p{N}@!$]{2,24}$', unicode: true);
final _oneLetter = RegExp(r'^\p{L}$', unicode: true);
final _edges = RegExp(r'^[^\p{L}\p{N}]+|[^\p{L}\p{N}]+$', unicode: true);
final _spaces = RegExp(r'\s+');
final _enclosed = RegExp(r'\[[^\]]*\]|\{[^}]*\}|\([^)]*\)');
final _innerSeparators = RegExp(r'[\s.,+\-&/|_]+');
final _titleStart = RegExp(r'^[\s\-~.,:;]+');
final _titleEnd = RegExp(r'[\s\-~,:;]+$');

/// Zero-width and text-direction characters: they show nothing, but would
/// keep words from being recognised and can reorder what is displayed.
final _invisible = RegExp('[\u200B-\u200F\u202A-\u202E\u2060-\u2064\uFEFF]');
