// Checks the hardening against the real bundled libmpv.
//
// Needs `libmpv-2.dll` from a Windows build, so it is skipped until
// `flutter build windows` has run at least once on this machine.
import 'dart:io';

import 'package:dhara/features/player/secure_player.dart';
import 'package:dhara/features/player/subtitle_file.dart';
import 'package:dhara/features/player/track_options.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';

import '../../support/local_server.dart';
import 'libmpv_tuning_checks.dart' as tuning;

File? _findLibmpv() {
  for (final mode in ['Release', 'Debug', 'Profile']) {
    final file = File('build/windows/x64/runner/$mode/libmpv-2.dll');
    if (file.existsSync()) return file;
  }
  return null;
}

final _sampleVideo = File(
  r'C:\Windows\ImmersiveControlPanel\SystemSettings\Assets'
  r'\SDRSampleAccessibility.mkv',
);

void main() {
  final libmpv = _findLibmpv();

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

    test('is not hardened until hardenPlayer runs', () async {
      final actual = <String, String>{};
      for (final name in requiredMpvValues.keys) {
        actual[name] = await native.getProperty(name);
      }
      // Guards against the check passing vacuously.
      expect(findHardeningViolations(actual), isNotEmpty);
    });

    test('hardenPlayer applies and verifies every option', () async {
      await hardenPlayer(player);

      for (final entry in requiredMpvValues.entries) {
        expect(
          entry.value,
          contains(await native.getProperty(entry.key)),
          reason: entry.key,
        );
      }
    });

    test('every script mpv starts by itself is switched off', () async {
      final switches = (await native.getProperty('options'))
          .split(',')
          .where(isScriptSwitch)
          .toList();
      expect(switches, contains('load-scripts'));

      await hardenPlayer(player);

      for (final name in switches) {
        expect(await native.getProperty(name), 'no', reason: name);
      }
    });

    test('the yt-dlp hook is shut down, where the build has one', () async {
      // Its start is not seen from here; its end is, in mpv's own log.
      final logged = Player(
        configuration: const PlayerConfiguration(
          logLevel: MPVLogLevel.debug,
          protocolWhitelist: allowedPlayerProtocols,
        ),
      );
      addTearDown(logged.dispose);
      final lines = <String>[];
      final listening = logged.stream.log.listen((log) => lines.add(log.text));
      addTearDown(listening.cancel);
      final hasHook =
          await (logged.platform! as NativePlayer).getProperty('ytdl') ==
              'yes';

      await hardenPlayer(logged);
      await Future<void>.delayed(const Duration(milliseconds: 300));

      if (!hasHook) {
        markTestSkipped('this libmpv is built without Lua: no hook in it');
        return;
      }
      expect(
        lines,
        contains(contains('Unloading script @ytdl_hook.lua')),
      );
    });

    test('libmpv does not read user config files', () async {
      expect(await native.getProperty('config'), 'no');
    });

    test('subtitles are drawn by libmpv and can be resized and delayed',
        () async {
      await hardenPlayer(player);

      expect(await native.getProperty('sub-ass'), 'yes');
      expect(await native.getProperty('sub-visibility'), 'yes');

      await native.setProperty('sub-ass-override', 'scale');
      await native.setProperty('sub-scale', '1.50');
      await native.setProperty('sub-delay', '-0.3');
      expect(await native.getProperty('sub-ass-override'), 'scale');
      expect(double.parse(await native.getProperty('sub-scale')), 1.5);
      expect(double.parse(await native.getProperty('sub-delay')), -0.3);
    });

    test(
      'resuming: load paused, seek, then play continues from there',
      () async {
        await hardenPlayer(player);
        final loaded =
            player.stream.duration.firstWhere((d) => d > Duration.zero);
        await player.open(Media(_sampleVideo.path), play: false);
        await loaded;
        await player.seek(const Duration(seconds: 5));
        await player.play();

        // Playback must actually move on from the resume point.
        final position = await player.stream.position.firstWhere(
          (p) => p >= const Duration(seconds: 6),
        );
        expect(position.inSeconds, inInclusiveRange(6, 8));
        expect(player.state.playing, isTrue);
      },
      skip: _sampleVideo.existsSync() ? false : 'no sample video on this PC',
      timeout: const Timeout(Duration(seconds: 30)),
    );

    test(
      'a hardened player still loads an external subtitle file',
      () async {
        final dir = Directory.systemTemp.createTempSync('dhara_libmpv_');
        addTearDown(() => dir.deleteSync(recursive: true));
        final srt = File('${dir.path}${Platform.pathSeparator}sample.srt')
          ..writeAsStringSync(
            '1\n00:00:00,000 --> 00:00:09,000\nExternal line\n',
          );

        await hardenPlayer(player);
        await player.open(Media(_sampleVideo.path), play: false);
        await player.stream.duration.firstWhere((d) => d > Duration.zero);
        final file = await checkSubtitleFile(srt.path);
        await player.setSubtitleTrack(
          SubtitleTrack.uri(file.path, title: file.name),
        );
        await player.stream.tracks.firstWhere(
          (tracks) => tracks.subtitle.any((t) => t.title == 'sample.srt'),
        );

        final options = subtitleOptions(player.state.tracks.subtitle);
        expect(options.map((o) => o.label), ['Off', 'sample.srt · SRT']);
        expect(await native.getProperty('sid'), options.last.id);
      },
      // A video that ships with Windows; skipped where it does not exist.
      skip: _sampleVideo.existsSync() ? false : 'no sample video on this PC',
      timeout: const Timeout(Duration(seconds: 30)),
    );

    // The app only ever hands the player an http(s) address, but what a
    // server sends there need not be a video. mpv also reads playlists and
    // its own edit lists (EDL), and both can name other things to open.
    for (final (kind, list) in const [
      ('a playlist', '#EXTM3U\n@\n'),
      ('an edit list', '# mpv EDL v0\n@\n'),
    ]) {
      test(
        '$kind sent in place of a video cannot open a file of this PC',
        () async {
          final server = await LocalServer.start();
          addTearDown(server.close);
          server.serveFile('/film.mkv', _sampleVideo);
          server.serve(
            '/local.mkv',
            list.replaceFirst('@', _sampleVideo.path),
            contentType: 'video/x-matroska',
          );
          // The same list naming the server's own video plays: the one
          // above is refused, not merely not understood.
          server.serve(
            '/web.mkv',
            list.replaceFirst('@', '${server.url('/film.mkv')}'),
            contentType: 'video/x-matroska',
          );

          await hardenPlayer(player);
          Future<Duration> opened(String path) async {
            await player.open(Media('${server.url(path)}'), play: false);
            return player.stream.duration
                .firstWhere((d) => d > Duration.zero)
                .timeout(
                  const Duration(seconds: 4),
                  onTimeout: () => Duration.zero,
                );
          }

          expect(await opened('/local.mkv'), Duration.zero);
          expect(await native.getProperty('path'), isNot(_sampleVideo.path));
          expect(await opened('/web.mkv'), greaterThan(Duration.zero));
        },
        skip: _sampleVideo.existsSync() ? false : 'no sample video on this PC',
        timeout: const Timeout(Duration(seconds: 30)),
      );
    }
  }, skip: libmpv == null ? 'libmpv-2.dll not built yet' : false);

  // In this process, after the checks above (see the note in that file).
  tuning.main();
}
