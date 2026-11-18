import 'dart:convert';

import 'package:media_kit/media_kit.dart';

/// One selectable audio or subtitle choice, ready for display.
///
/// [label] contains server- or file-controlled text (track titles), so it
/// must only ever be shown through a plain `Text` widget.
class TrackOption {
  const TrackOption({required this.id, required this.label});

  /// mpv track id (`"1"`, `"2"`, ...), or [offId] for "no track".
  final String id;
  final String label;

  @override
  bool operator ==(Object other) =>
      other is TrackOption && other.id == id && other.label == label;

  @override
  int get hashCode => Object.hash(id, label);

  @override
  String toString() => 'TrackOption($id, $label)';
}

/// mpv's id for "no track selected".
const offId = 'no';

// media_kit lists these pseudo-tracks next to the real ones.
const _pseudoIds = {'auto', 'no'};

/// The audio tracks of the current file. Empty for a video without sound.
///
/// A track in a format the player has no decoder for (see
/// [decodableCodecs]) says so: the libmpv media_kit bundles has none for
/// Dolby TrueHD (the build the app ships has).
List<TrackOption> audioOptions(
  List<AudioTrack> tracks, {
  Set<String> decoders = const {},
}) {
  final real = tracks.where((t) => !_pseudoIds.contains(t.id)).toList();
  return [
    for (final (index, track) in real.indexed)
      TrackOption(
        id: track.id,
        label: [
          _label(
            language: track.language,
            title: track.title,
            detail: _audioDetail(track),
            fallback: 'Track ${index + 1}',
          ),
          if (!canDecode(track, decoders)) 'cannot be played',
        ].join(' · '),
      ),
  ];
}

/// The codecs libmpv has a decoder for, from its `decoder-list` property
/// (JSON: a list of `{"codec": "ac3", ...}`). Empty if that cannot be
/// read, which counts as "not known": nothing is ruled out then.
Set<String> decodableCodecs(String decoderList) {
  try {
    final list = jsonDecode(decoderList);
    if (list is! List) return const {};
    return {
      for (final entry in list)
        if (entry case {'codec': final String codec}) codec.toLowerCase(),
    };
  } on FormatException {
    return const {};
  }
}

/// Whether the player can decode [track], as far as [decoders] tell.
bool canDecode(AudioTrack track, Set<String> decoders) {
  final codec = track.codec?.trim().toLowerCase();
  return decoders.isEmpty ||
      codec == null ||
      codec.isEmpty ||
      decoders.contains(codec);
}

/// "TrueHD" for a track's format, or the codec's own name.
String audioFormatName(AudioTrack track) {
  final codec = track.codec?.trim().toLowerCase() ?? '';
  return _audioCodecs[codec] ?? (codec.isEmpty ? 'this format' : codec);
}

/// The audio track to play instead of the one libmpv chose ([currentId],
/// or [offId] if it gave up on it), when that one cannot be decoded: a
/// track that can, in the same language if there is one. `null` if the
/// current track is fine, or nothing better exists.
AudioTrack? audioFallback(
  List<AudioTrack> tracks,
  String currentId,
  Set<String> decoders,
) {
  final real = tracks.where((t) => !_pseudoIds.contains(t.id)).toList();
  final failed =
      real.where((t) => t.id == currentId).firstOrNull ??
      real.where((t) => !canDecode(t, decoders)).firstOrNull;
  if (failed == null || canDecode(failed, decoders)) return null;
  final playable = real.where((t) => canDecode(t, decoders)).toList();
  return playable.where((t) => t.language == failed.language).firstOrNull ??
      playable.firstOrNull;
}

/// The codec in libmpv's "Failed to initialize a decoder for codec 'x'."
/// if it is an audio one: the controls deal with that themselves (see
/// [audioFallback]), so it is not shown as an error. `null` otherwise.
String? undecodableAudioCodec(String error) {
  final codec = _decoderFailure.firstMatch(error)?[1]?.toLowerCase();
  if (codec == null) return null;
  final audio =
      _audioCodecs.containsKey(codec) ||
      codec == 'mlp' ||
      codec.startsWith('pcm_') ||
      codec.startsWith('wma') ||
      codec.startsWith('atrac') ||
      codec.startsWith('adpcm_');
  return audio ? codec : null;
}

final _decoderFailure = RegExp(
  r"Failed to initialize a decoder for codec '([A-Za-z0-9_]{1,40})'",
);

/// "Off" followed by the subtitle tracks of the current file (embedded ones
/// and any external file that was loaded).
List<TrackOption> subtitleOptions(List<SubtitleTrack> tracks) {
  final real = tracks.where((t) => !_pseudoIds.contains(t.id)).toList();
  return [
    const TrackOption(id: offId, label: 'Off'),
    for (final (index, track) in real.indexed)
      TrackOption(
        id: track.id,
        label: _label(
          language: track.language,
          title: track.title,
          detail: _subtitleFormat(track.codec),
          fallback: 'Track ${index + 1}',
        ),
      ),
  ];
}

/// The option after [currentId], wrapping around; used by the `S` shortcut
/// to step through Off → first track → ... → Off. Returns `null` when there
/// is nothing to switch to.
TrackOption? nextOption(List<TrackOption> options, String currentId) {
  if (options.length < 2) return null;
  final index = options.indexWhere((o) => o.id == currentId);
  return options[(index + 1) % options.length];
}

String _label({
  required String? language,
  required String? title,
  required String? detail,
  required String fallback,
}) {
  final languageName = languageNameFor(language);
  final cleanTitle = title?.trim();
  final parts = <String>[
    if (languageName != null) languageName,
    if (cleanTitle != null &&
        cleanTitle.isNotEmpty &&
        cleanTitle.toLowerCase() != languageName?.toLowerCase())
      cleanTitle,
  ];
  if (parts.isEmpty) parts.add(fallback);
  if (detail != null) parts.add(detail);
  return parts.join(' · ');
}

/// English name for an ISO 639 language code as found in media files, or
/// `null` for unknown / undetermined codes.
String? languageNameFor(String? code) {
  final key = code?.trim().toLowerCase();
  if (key == null || key.isEmpty) return null;
  return _languageNames[key];
}

const _languageNames = <String, String>{
  'ara': 'Arabic',
  'ar': 'Arabic',
  'ben': 'Bengali',
  'bn': 'Bengali',
  'chi': 'Chinese',
  'zho': 'Chinese',
  'zh': 'Chinese',
  'dan': 'Danish',
  'da': 'Danish',
  'dut': 'Dutch',
  'nld': 'Dutch',
  'nl': 'Dutch',
  'eng': 'English',
  'en': 'English',
  'fin': 'Finnish',
  'fi': 'Finnish',
  'fre': 'French',
  'fra': 'French',
  'fr': 'French',
  'ger': 'German',
  'deu': 'German',
  'de': 'German',
  'gre': 'Greek',
  'ell': 'Greek',
  'el': 'Greek',
  'heb': 'Hebrew',
  'he': 'Hebrew',
  'hin': 'Hindi',
  'hi': 'Hindi',
  'ind': 'Indonesian',
  'id': 'Indonesian',
  'ita': 'Italian',
  'it': 'Italian',
  'jpn': 'Japanese',
  'ja': 'Japanese',
  'kan': 'Kannada',
  'kn': 'Kannada',
  'kor': 'Korean',
  'ko': 'Korean',
  'mal': 'Malayalam',
  'ml': 'Malayalam',
  'may': 'Malay',
  'msa': 'Malay',
  'ms': 'Malay',
  'mar': 'Marathi',
  'mr': 'Marathi',
  'nor': 'Norwegian',
  'no': 'Norwegian',
  'nob': 'Norwegian',
  'per': 'Persian',
  'fas': 'Persian',
  'fa': 'Persian',
  'pol': 'Polish',
  'pl': 'Polish',
  'por': 'Portuguese',
  'pt': 'Portuguese',
  'pan': 'Punjabi',
  'pa': 'Punjabi',
  'rus': 'Russian',
  'ru': 'Russian',
  'spa': 'Spanish',
  'es': 'Spanish',
  'swe': 'Swedish',
  'sv': 'Swedish',
  'tam': 'Tamil',
  'ta': 'Tamil',
  'tel': 'Telugu',
  'te': 'Telugu',
  'tha': 'Thai',
  'th': 'Thai',
  'tur': 'Turkish',
  'tr': 'Turkish',
  'ukr': 'Ukrainian',
  'uk': 'Ukrainian',
  'urd': 'Urdu',
  'ur': 'Urdu',
  'vie': 'Vietnamese',
  'vi': 'Vietnamese',
};

String? _audioDetail(AudioTrack track) {
  final codec = _audioCodecs[track.codec?.toLowerCase()];
  final layout = switch (track.channelscount ?? track.audiochannels) {
    1 => 'Mono',
    2 => 'Stereo',
    6 => '5.1',
    8 => '7.1',
    _ => null,
  };
  final parts = [if (codec != null) codec, if (layout != null) layout];
  return parts.isEmpty ? null : parts.join(' ');
}

const _audioCodecs = <String, String>{
  'aac': 'AAC',
  'ac3': 'AC3',
  'eac3': 'E-AC3',
  'dts': 'DTS',
  'truehd': 'TrueHD',
  'mlp': 'MLP',
  'flac': 'FLAC',
  'opus': 'Opus',
  'vorbis': 'Vorbis',
  'mp3': 'MP3',
  'mp2': 'MP2',
};

String? _subtitleFormat(String? codec) =>
    _subtitleFormats[codec?.toLowerCase()];

const _subtitleFormats = <String, String>{
  'subrip': 'SRT',
  'srt': 'SRT',
  'ass': 'ASS',
  'ssa': 'SSA',
  'webvtt': 'VTT',
  'mov_text': 'Text',
  'hdmv_pgs_subtitle': 'PGS',
  'dvd_subtitle': 'VobSub',
  'dvb_subtitle': 'DVB',
};
