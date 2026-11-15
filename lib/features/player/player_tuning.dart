import 'package:dhara/core/settings/settings_controller.dart';
import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// How the player is set up for streaming from a server: how much it reads
/// ahead and keeps, and whether the graphics card decodes the picture.
///
/// Unlike the options of `secure_player.dart` these are about smoothness,
/// not safety: one that does not take is reported (see [tunePlayer]) and
/// the video plays all the same.
@immutable
class PlayerTuning {
  const PlayerTuning({
    this.bufferMegabytes = SettingsController.defaultBufferMegabytes,
    this.hardwareDecoding = true,
  }) : assert(
         bufferMegabytes >= SettingsController.minBufferMegabytes &&
             bufferMegabytes <= SettingsController.maxBufferMegabytes,
       );

  /// As the user's settings say (Buffer size, Hardware decoding).
  PlayerTuning.of(SettingsController settings)
    : this(
        bufferMegabytes: settings.bufferMegabytes,
        hardwareDecoding: settings.hardwareDecoding,
      );

  /// The memory the player may fill with video it has read from the
  /// server: what lies ahead, and what was just played (for skipping back
  /// without asking the server again).
  final int bufferMegabytes;

  /// The graphics card decodes the picture where mpv counts that as safe.
  final bool hardwareDecoding;

  static const _megabyte = 1024 * 1024;

  /// Three quarters of the buffer are for what lies ahead ...
  int get forwardBytes => bufferMegabytes * _megabyte ~/ 4 * 3;

  /// ... and a quarter for what was played. (mpv lends the part ahead that
  /// is not in use to the part behind: `demuxer-donate-buffer`.)
  int get backBytes => bufferMegabytes * _megabyte - forwardBytes;

  /// mpv `hwdec`: `auto-safe` only takes decoders mpv has on its list of
  /// ones known to work; plain `auto` (media_kit's default) takes any.
  String get hwdec => hardwareDecoding ? 'auto-safe' : 'no';

  /// The mpv options, by name. Names and values were checked against the
  /// manual of mpv 0.36 and by reading each back from the bundled libmpv.
  ///
  /// Read-ahead needs no option of its own: with the cache on, mpv reads
  /// ahead until [forwardBytes] are full (`cache-secs` is far higher by
  /// default, and `demuxer-readahead-secs` does not count then).
  Map<String, String> get mpvOptions => {
    // Read ahead even where mpv would not take the file for a network one.
    'cache': 'yes',
    // Keep what was read in memory. media_kit asks for a temporary file
    // on disk instead, which nothing here needs: the limits below hold.
    'cache-on-disk': 'no',
    'demuxer-max-bytes': '$forwardBytes',
    'demuxer-max-back-bytes': '$backBytes',
    // Skips inside what is buffered do not go back to the server.
    'demuxer-seekable-cache': 'yes',
    // A server that sends nothing for this long is asked again (FFmpeg
    // then reconnects where it was). media_kit's value, pinned here.
    'network-timeout': '5',
    'hwdec': hwdec,
  };
}

/// Applies [tuning] to [player] and reads every value back.
///
/// Returns the names of the options libmpv did not take (none, normally).
/// Call it after `hardenPlayer` and before the first `open`. Never throws.
Future<List<String>> tunePlayer(Player player, PlayerTuning tuning) async {
  final native = player.platform;
  if (native is! NativePlayer) return const [];
  final notTaken = <String>[];
  for (final MapEntry(key: name, value: wanted) in tuning.mpvOptions.entries) {
    try {
      await native.setProperty(name, wanted);
      final actual = await native.getProperty(name);
      if (!sameMpvValue(wanted, actual)) notTaken.add(name);
    } on Object {
      // A player that is being closed, or a libmpv without the option.
      notTaken.add(name);
    }
  }
  return notTaken;
}

/// Whether libmpv's answer [actual] is the value [wanted] that was set:
/// the same text, or the same number (it answers `5.000000` for `5`).
bool sameMpvValue(String wanted, String actual) {
  if (wanted == actual) return true;
  final number = double.tryParse(wanted);
  return number != null && number == double.tryParse(actual);
}

/// The single place a [VideoController] is created, so the picture of
/// every player is decoded as [tuning] says. (The controller sets `hwdec`
/// itself when it is ready; left alone it would set media_kit's `auto`.)
VideoController createVideoController(Player player, PlayerTuning tuning) =>
    VideoController(
      player,
      configuration: VideoControllerConfiguration(hwdec: tuning.hwdec),
    );
