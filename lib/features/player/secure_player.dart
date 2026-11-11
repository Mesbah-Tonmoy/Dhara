import 'package:media_kit/media_kit.dart';

/// FFmpeg protocols libmpv may use (BRIEF section 7). Notably excludes
/// `file`, `data`, `udp`, `rtp`, `rtmp` and friends from media_kit's default.
const allowedPlayerProtocols = <String>[
  'http',
  'https',
  'tcp',
  'tls',
  'crypto'
];

/// The single place a [Player] is created, so every player in the app shares
/// the same restricted configuration.
Player createPlayer() {
  return Player(
    configuration: const PlayerConfiguration(
      title: 'Dhara',
      protocolWhitelist: allowedPlayerProtocols,
    ),
  );
}
