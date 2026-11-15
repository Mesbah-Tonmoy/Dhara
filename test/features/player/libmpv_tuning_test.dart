// Checks the streaming set-up against the real bundled libmpv (skipped
// until a Windows build exists, like `libmpv_hardening_test.dart`).
import 'package:dhara/features/player/player_tuning.dart';
import 'package:dhara/features/player/secure_player.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';

import '../../support/local_server.dart';
import '../../support/real_libmpv.dart';

void main() {
  final libmpv = findLibmpv();
  final noVideo = sampleVideo.existsSync() ? false : 'no sample video here';

  group('real libmpv', () {
    late Player player;
    late NativePlayer native;

    setUpAll(() {
      MediaKit.ensureInitialized(libmpv: libmpv!.absolute.path);
      // No window or sound device is needed for these checks.
      NativePlayer.test = true;
    });

    setUp(() {
      player = createPlayer();
      native = player.platform! as NativePlayer;
    });

    tearDown(() => player.dispose());

    test('is not tuned until tunePlayer runs', () async {
      // media_kit's own choices: guards against the check passing
      // vacuously.
      expect(await native.getProperty('cache-on-disk'), 'yes');
      expect(
        await native.getProperty('demuxer-max-bytes'),
        '${32 * 1024 * 1024}',
      );
    });

    test('libmpv takes every option, and they stay hardened', () async {
      await hardenPlayer(player);
      const tuning = PlayerTuning();
      expect(await tunePlayer(player, tuning), isEmpty);

      expect(await native.getProperty('hwdec'), 'auto-safe');
      expect(await native.getProperty('cache'), 'yes');
      expect(await native.getProperty('cache-on-disk'), 'no');
      expect(
        await native.getProperty('demuxer-max-bytes'),
        '${tuning.forwardBytes}',
      );
      expect(
        await native.getProperty('demuxer-max-back-bytes'),
        '${tuning.backBytes}',
      );

      // Tuning must not undo the security options.
      final actual = <String, String>{};
      for (final name in requiredMpvValues.keys) {
        actual[name] = await native.getProperty(name);
      }
      expect(findHardeningViolations(actual), isEmpty);
    });

    test('hardware decoding off is taken too', () async {
      const tuning = PlayerTuning(hardwareDecoding: false, bufferMegabytes: 50);
      expect(await tunePlayer(player, tuning), isEmpty);
      expect(await native.getProperty('hwdec'), 'no');
    });

    test(
      'a tuned player plays a video from a server and buffers ahead',
      () async {
        final server = await LocalServer.start();
        addTearDown(server.close);
        server.serveFile('/film.mkv', sampleVideo);

        await hardenPlayer(player);
        expect(await tunePlayer(player, const PlayerTuning()), isEmpty);
        await player.open(Media('${server.url('/film.mkv')}'));

        final position = await player.stream.position.firstWhere(
          (p) => p >= const Duration(seconds: 1),
        );
        expect(position.inSeconds, inInclusiveRange(1, 3));
        // The whole of this short file is read ahead, into memory.
        expect(
          double.parse(await native.getProperty('demuxer-cache-duration')),
          greaterThan(3),
        );
        expect(await native.getProperty('demuxer-via-network'), 'yes');
      },
      skip: noVideo,
      timeout: const Timeout(Duration(seconds: 30)),
    );
  }, skip: libmpv == null ? 'libmpv-2.dll not built yet' : false);
}
