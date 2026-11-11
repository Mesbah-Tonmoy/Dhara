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
  }, skip: libmpv == null ? 'libmpv-2.dll not built yet' : false);
}
