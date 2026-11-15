// Checks the streaming set-up against the real bundled libmpv (skipped
// until a Windows build exists).
//
// Not a test file of its own: `libmpv_hardening_test.dart` runs it. As two
// files, the two ran side by side in two processes, and every few runs
// one of them stopped without a word (seen 2026-11-16, five times in a
// day, never while there was one file).
import 'dart:io';

import 'package:dhara/core/settings/settings_controller.dart';
import 'package:dhara/features/player/player_tuning.dart';
import 'package:dhara/features/player/secure_player.dart';
import 'package:dhara/features/player/seek_math.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';

import '../../support/local_server.dart';
import '../../support/real_libmpv.dart';

void main() {
  final libmpv = findLibmpv();
  final noVideo = sampleVideo.existsSync() ? false : 'no sample video here';

  group('real libmpv, set up for streaming', () {
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

    test(
      'seeks: exact ones land on the spot, keyframe ones on a keyframe',
      () async {
        final server = await LocalServer.start();
        addTearDown(server.close);
        server.serveFile('/film.mkv', sampleVideo);
        await hardenPlayer(player);
        await tunePlayer(player, const PlayerTuning());
        expect(await native.getProperty('hr-seek-framedrop'), 'yes');
        final loaded = player.stream.duration.firstWhere(
          (d) => d > Duration.zero,
        );
        await player.open(Media('${server.url('/film.mkv')}'), play: false);
        final duration = await loaded;

        // Paused, so the position only moves by seeking.
        Future<double> after(List<String> command) async {
          await native.command(command);
          await Future<void>.delayed(const Duration(milliseconds: 400));
          return double.parse(await native.getProperty('time-pos'));
        }

        const second = Duration(seconds: 1);
        // A short skip: exact.
        final short = skipCommand(
          from: Duration.zero,
          target: second * 3,
          duration: const Duration(hours: 1),
        );
        expect(short.last, 'absolute+exact');
        expect(await after(short), closeTo(3, .1));

        // The seek bar: the keyframe at or before the spot (this video
        // has one at its start and one near 5 s).
        final early = await after(jumpCommand(second * 4));
        expect(early, lessThan(1));
        final late = await after(jumpCommand(second * 9));
        expect(late, inInclusiveRange(4, 9));

        // A long skip is relative: forward lands beyond its target ...
        await after(jumpCommand(Duration.zero));
        final forward = await after(['seek', '2.000', 'relative+keyframes']);
        expect(forward, greaterThan(2));
        // ... and back before it.
        final back = await after(['seek', '-2.000', 'relative+keyframes']);
        expect(back, lessThan(forward - 2));
        expect(duration.inSeconds, greaterThan(10));
      },
      skip: noVideo,
      timeout: const Timeout(Duration(seconds: 30)),
    );

    test(
      'a video that needs a session is fetched with its headers',
      () async {
        final server = await LocalServer.start();
        addTearDown(server.close);
        server.serveFile('/film.mkv', sampleVideo);
        final tokens = <String?>[];
        // As a media server: the file only for the token of a session.
        server.routes['/private.mkv'] = (request) async {
          final token = request.headers.value('x-emby-token');
          tokens.add(token);
          if (token != 'token-1') {
            request.response.statusCode = HttpStatus.unauthorized;
            await request.response.close();
            return;
          }
          await server.routes['/film.mkv']!(request);
        };
        await hardenPlayer(player);
        await tunePlayer(player, const PlayerTuning());

        await player.open(
          Media(
            '${server.url('/private.mkv')}',
            httpHeaders: const {'X-Emby-Token': 'token-1'},
          ),
        );
        final position = await player.stream.position.firstWhere(
          (p) => p >= const Duration(seconds: 1),
        );

        expect(position.inSeconds, inInclusiveRange(1, 3));
        expect(tokens, isNotEmpty);
        expect(tokens, everyElement('token-1'));
      },
      skip: noVideo,
      timeout: const Timeout(Duration(seconds: 30)),
    );

    test(
      'the track languages are taken, and "Off" lasts through an open',
      () async {
        // With a language, mpv is left to choose the track.
        expect(
          await tunePlayer(
            player,
            const PlayerTuning(subtitles: SubtitleLanguage.bangla),
          ),
          isEmpty,
        );
        expect(await native.getProperty('slang'), 'ben,bn');
        expect(await native.getProperty('alang'), '');
        expect(await native.getProperty('sid'), 'auto');

        const tuning = PlayerTuning(
          subtitles: SubtitleLanguage.off,
          audio: AudioLanguage.hindi,
        );
        expect(await tunePlayer(player, tuning), isEmpty);
        expect(await native.getProperty('alang'), 'hin,hi');
        expect(await native.getProperty('slang'), '');
        expect(await native.getProperty('subs-fallback'), 'default');
        expect(await native.getProperty('sid'), 'no');

        final loaded = player.stream.duration.firstWhere(
          (d) => d > Duration.zero,
        );
        await player.open(Media(sampleVideo.path), play: false);
        await loaded;
        // media_kit does not switch subtitles back on by itself.
        expect(await native.getProperty('sid'), 'no');
      },
      skip: noVideo,
      timeout: const Timeout(Duration(seconds: 30)),
    );

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
