import 'package:media_kit/media_kit.dart';

/// FFmpeg protocols libmpv may use (BRIEF section 7). Notably excludes
/// `file`, `data`, `udp`, `rtp`, `rtmp` and friends from media_kit's default.
const allowedPlayerProtocols = <String>[
  'http',
  'https',
  'tcp',
  'tls',
  'crypto',
];

final String _whitelistOption =
    'protocol_whitelist=[${allowedPlayerProtocols.join(',')}]';

/// mpv options applied to every player right after libmpv initialises.
///
/// Names verified against the mpv manual and the bundled libmpv
/// (mpv 0.36, FFmpeg 6.0) by reading each value back at runtime.
///
/// media_kit creates the mpv handle itself, so these are set after
/// `mpv_initialize`. That is early enough: nothing is loaded before the first
/// `open`, and [hardenPlayer] must complete before any `open` call.
final Map<String, String> hardenedMpvOptions = Map.unmodifiable({
  // No yt-dlp hook: never spawn an external program for a URL.
  'ytdl': 'no',
  // No user scripts. (The bundled libmpv has no Lua/JS backend at all; this
  // keeps us safe if a future build gains one.)
  'load-scripts': 'no',
  // Playlists fetched from a server may not point at local files or other
  // special URLs.
  'load-unsafe-playlists': 'no',
  // Never pick up extra files on mpv's own initiative; external subtitles
  // are added explicitly by the app.
  'autoload-files': 'no',
  'sub-auto': 'no',
  'audio-file-auto': 'no',
  'cover-art-auto': 'no',
  // Protocol whitelist for the stream layer (the main URL) ...
  'stream-lavf-o': _whitelistOption,
  // ... and for the demuxer (nested resources such as HLS segments). This
  // also replaces media_kit's default, dropping its `allowed_extensions=ALL`
  // and `strict=experimental` relaxations.
  'demuxer-lavf-o': _whitelistOption,
});

/// Values each option must report when read back. An empty string means the
/// option does not exist in this libmpv build.
final Map<String, Set<String>> requiredMpvValues = Map.unmodifiable({
  // libmpv never loads mpv.conf / input.conf unless asked to. It cannot be
  // changed after initialisation, so it is only checked.
  'config': const {'no'},
  // Absent when libmpv is built without Lua, which is equally safe.
  'ytdl': const {'no', ''},
  'load-scripts': const {'no'},
  'load-unsafe-playlists': const {'no'},
  'autoload-files': const {'no'},
  'sub-auto': const {'no'},
  'audio-file-auto': const {'no'},
  'cover-art-auto': const {'no'},
  'stream-lavf-o': {
    'protocol_whitelist=${allowedPlayerProtocols.join(',')}',
  },
  'demuxer-lavf-o': {
    'protocol_whitelist=${allowedPlayerProtocols.join(',')}',
  },
});

/// Compares read-back option values with [requiredMpvValues] and returns one
/// message per mismatch. An empty list means the player is hardened.
List<String> findHardeningViolations(Map<String, String> actual) {
  final violations = <String>[];
  for (final entry in requiredMpvValues.entries) {
    final value = actual[entry.key];
    if (value == null) {
      violations.add('${entry.key} was not checked');
    } else if (!entry.value.contains(value)) {
      violations.add('${entry.key} is "$value"');
    }
  }
  return violations;
}

/// Thrown when the player could not be put into its restricted configuration.
/// Playback must not start in that case.
class PlayerHardeningError implements Exception {
  const PlayerHardeningError(this.violations);

  final List<String> violations;

  @override
  String toString() => 'PlayerHardeningError(${violations.join('; ')})';
}

/// The single place a [Player] is created, so every player in the app shares
/// the same restricted configuration. Call [hardenPlayer] before `open`.
Player createPlayer() {
  return Player(
    configuration: const PlayerConfiguration(
      title: 'Dhara',
      protocolWhitelist: allowedPlayerProtocols,
      // libmpv draws subtitles itself (libass). That keeps styled ASS
      // subtitles (anime) and picture-based ones (PGS, VobSub) working;
      // media_kit's Flutter text overlay can show neither.
      libass: true,
    ),
  );
}

/// Applies [hardenedMpvOptions] and verifies them by reading every value
/// back from libmpv. Fails closed: throws [PlayerHardeningError] rather than
/// letting an unverified player open a URL.
Future<void> hardenPlayer(Player player) async {
  final native = player.platform;
  if (native is! NativePlayer) {
    throw const PlayerHardeningError(['unsupported player backend']);
  }

  for (final option in hardenedMpvOptions.entries) {
    await native.setProperty(option.key, option.value);
  }

  final actual = <String, String>{};
  for (final name in requiredMpvValues.keys) {
    actual[name] = await native.getProperty(name);
  }

  final violations = findHardeningViolations(actual);
  if (violations.isNotEmpty) throw PlayerHardeningError(violations);
}
