import 'dart:convert';

import 'package:flutter/foundation.dart';

/// The mpv properties the info panel is made from. Names checked against
/// the bundled libmpv (mpv 0.36) by reading each while a video played.
const playbackInfoProperties = <String>[
  'width',
  'height',
  'video-format',
  'estimated-vf-fps',
  'hwdec-current',
  'audio-codec-name',
  'audio-params/channel-count',
  // JSON: what is buffered ("fw-bytes", "cache-duration") and how fast
  // the server delivers ("raw-input-rate").
  'demuxer-cache-state',
  'frame-drop-count',
  'decoder-frame-drop-count',
];

/// What the player's info panel shows about the video being played: where
/// it comes from, how fast that server is, and how the PC copes with it.
///
/// Made for testing on a real connection: every line is a number that can
/// be read out. All texts are plain text; some come from the file.
@immutable
class PlaybackInfo {
  const PlaybackInfo({
    this.server,
    this.serverAnswered,
    this.startedIn,
    this.width,
    this.height,
    this.videoFormat,
    this.framesPerSecond,
    this.hardwareDecoder,
    this.softwareDecoding = false,
    this.audioFormat,
    this.audioChannels,
    this.bufferedAhead,
    this.bufferedBytes,
    this.bytesPerSecond,
    this.droppedFrames,
    this.notTaken = const [],
  });

  /// From what libmpv answered for [playbackInfoProperties] ([mpv], by
  /// name; an empty answer means "not known"), and what the app measured
  /// itself.
  factory PlaybackInfo.fromMpv(
    Map<String, String> mpv, {
    String? server,
    Duration? serverAnswered,
    Duration? startedIn,
    List<String> notTaken = const [],
  }) {
    String? text(String name) {
      final value = _plain(mpv[name] ?? '');
      return value.isEmpty ? null : value;
    }

    int? whole(String name) => int.tryParse(mpv[name] ?? '');

    Object? cache;
    try {
      cache = jsonDecode(mpv['demuxer-cache-state'] ?? '');
    } on FormatException {
      // No video open, or a libmpv that answers in another shape.
    }
    num? cached(String key) {
      final value = cache is Map ? cache[key] : null;
      return value is num ? value : null;
    }

    final decoder = text('hwdec-current');
    final ahead = cached('cache-duration');
    final dropped = whole('frame-drop-count');
    final skipped = whole('decoder-frame-drop-count');
    return PlaybackInfo(
      server: server,
      serverAnswered: serverAnswered,
      startedIn: startedIn,
      width: whole('width'),
      height: whole('height'),
      videoFormat: text('video-format'),
      framesPerSecond: double.tryParse(mpv['estimated-vf-fps'] ?? ''),
      hardwareDecoder: decoder == null || decoder == 'no' ? null : decoder,
      softwareDecoding: decoder == 'no',
      audioFormat: text('audio-codec-name'),
      audioChannels: whole('audio-params/channel-count'),
      bufferedAhead: ahead == null || ahead < 0
          ? null
          : Duration(milliseconds: (ahead * 1000).round()),
      bufferedBytes: cached('fw-bytes')?.toInt(),
      bytesPerSecond: cached('raw-input-rate')?.toInt(),
      droppedFrames: dropped == null && skipped == null
          ? null
          : (dropped ?? 0) + (skipped ?? 0),
      notTaken: notTaken,
    );
  }

  /// The server the video is fetched from: its name if it is one of the
  /// sources, and its address.
  final String? server;

  /// How long that server took to answer when it was asked for the video
  /// (before the player opened it).
  final Duration? serverAnswered;

  /// From Play to the first moving picture.
  final Duration? startedIn;

  final int? width;
  final int? height;

  /// `h264`, `hevc`, `vp9` ...
  final String? videoFormat;
  final double? framesPerSecond;

  /// The hardware decoder in use (`d3d11va`, `nvdec-copy` ...), or `null`.
  final String? hardwareDecoder;

  /// libmpv said the picture is decoded by the processor.
  final bool softwareDecoding;

  final String? audioFormat;
  final int? audioChannels;

  /// How much video lies ready ahead of the position.
  final Duration? bufferedAhead;
  final int? bufferedBytes;

  /// How fast the server delivers at the moment.
  final int? bytesPerSecond;

  /// Frames that were not shown because the PC could not keep up.
  final int? droppedFrames;

  /// Streaming options libmpv did not take (see `tunePlayer`).
  final List<String> notTaken;

  /// The lines of the panel: what, and its value. Only what is known.
  List<(String, String)> get rows {
    final picture = [
      if (width != null && height != null) '$width×$height',
      ?videoFormat,
      if (framesPerSecond case final fps? when fps > 0) '${_short(fps)} fps',
    ];
    final sound = [
      ?audioFormat,
      if (audioChannels case final channels?)
        channels == 1 ? '1 channel' : '$channels channels',
    ];
    final buffer = [
      if (bufferedAhead case final ahead?)
        '${_short(ahead.inMilliseconds / 1000)} s ahead',
      if (bufferedBytes case final bytes?) formatMegabytes(bytes),
    ];
    return [
      if (server case final server?) ('Server', server),
      if (serverAnswered case final time?)
        ('Server answered in', '${time.inMilliseconds} ms'),
      if (startedIn case final time?)
        ('Started in', '${_short(time.inMilliseconds / 1000)} s'),
      if (picture.isNotEmpty) ('Picture', picture.join(' · ')),
      if (hardwareDecoder case final decoder?)
        ('Decoding', 'Graphics card ($decoder)')
      else if (softwareDecoding)
        ('Decoding', 'Processor (software)'),
      if (sound.isNotEmpty) ('Sound', sound.join(' · ')),
      if (buffer.isNotEmpty) ('Buffer', buffer.join(' · ')),
      if (bytesPerSecond case final speed?)
        ('Server speed', '${formatMegabytes(speed)}/s'),
      if (droppedFrames case final frames?) ('Dropped frames', '$frames'),
      if (notTaken.isNotEmpty) ('Options not taken', notTaken.join(', ')),
    ];
  }
}

/// "61.4 MB", "0.8 MB": megabytes with one decimal.
String formatMegabytes(int bytes) =>
    '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';

/// One decimal, without a needless ".0".
String _short(double number) {
  final text = number.toStringAsFixed(1);
  return text.endsWith('.0') ? text.substring(0, text.length - 2) : text;
}

/// A short text from a file's own description: no control characters, and
/// not longer than fits a line of the panel.
String _plain(String value) {
  final clean = value.replaceAll(RegExp(r'[\x00-\x1f\x7f]'), ' ').trim();
  return clean.length <= 40 ? clean : '${clean.substring(0, 40)}…';
}
