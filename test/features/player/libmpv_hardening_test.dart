// Checks the hardening against the real bundled libmpv.
//
// Needs `libmpv-2.dll` from a Windows build, so it is skipped until
// `flutter build windows` has run at least once on this machine.
import 'dart:io';

import 'package:dhara/features/player/secure_player.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';

File? _findLibmpv() {
  for (final mode in ['Release', 'Debug', 'Profile']) {
    final file = File('build/windows/x64/runner/$mode/libmpv-2.dll');
    if (file.existsSync()) return file;
  }
  return null;
}

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
  }, skip: libmpv == null ? 'libmpv-2.dll not built yet' : false);
}
