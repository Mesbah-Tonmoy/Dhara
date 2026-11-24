import 'dart:io';

import 'package:dhara/features/update/installer_fetcher.dart';
import 'package:dhara/features/update/installer_launcher.dart';
import 'package:dhara/features/update/update_notice.dart';
import 'package:flutter_test/flutter_test.dart';

CheckedInstaller _checked(String path) =>
    CheckedInstaller.forTest(File(path), const AppVersion(1, 2, 0));

void main() {
  test(
    'starts the checked file by its whole path, with nothing added',
    () async {
      final started = <String>[];
      final launcher = InstallerLauncher(
        start: (path) async => started.add(path),
      );
      const path = r'C:\Users\Some One\AppData\update\Dhara-Setup-1.2.0.exe';

      expect(await launcher.start(_checked(path)), isTrue);
      expect(started, [path]);
    },
  );

  test('says so when Windows does not start it, and does not throw', () async {
    for (final Exception error in [
      const ProcessException('x.exe', [], 'Access is denied', 5),
      const FileSystemException('gone'),
      const FormatException('odd'),
    ]) {
      final launcher = InstallerLauncher(start: (path) async => throw error);
      expect(await launcher.start(_checked('x.exe')), isFalse);
    }
  });

  group('for real (Windows)', () {
    late Directory folder;
    setUp(() {
      // A space in the path, as a user name can have one.
      folder = Directory.systemTemp.createTempSync('dhara start ');
    });
    tearDown(() {
      try {
        folder.deleteSync(recursive: true);
      } on FileSystemException {
        // The program that was started may still hold its file.
      }
    });

    test('a file that is not there is not started', () async {
      final missing = '${folder.path}${Platform.pathSeparator}nothing.exe';
      expect(await const InstallerLauncher().start(_checked(missing)), isFalse);
    });

    test('a file that is no program is not started', () async {
      final file = File('${folder.path}${Platform.pathSeparator}text.exe')
        ..writeAsStringSync('not a program');
      expect(
        await const InstallerLauncher().start(_checked(file.path)),
        isFalse,
      );
    });

    test(
      'a program is started, from a folder with a space in its name',
      () async {
        // A small program of Windows itself that prints a name and ends,
        // standing in for an installer. It is copied so that the path that
        // is started is one the test made.
        final system = Platform.environment['SystemRoot'] ?? r'C:\Windows';
        final stand = File('$system\\System32\\whoami.exe');
        final copy = stand.copySync(
          '${folder.path}${Platform.pathSeparator}Dhara-Setup-1.2.0.exe',
        );
        expect(
          await const InstallerLauncher().start(_checked(copy.path)),
          isTrue,
        );
        // It runs by itself and is gone in a moment.
        await Future<void>.delayed(const Duration(milliseconds: 500));
      },
    );
  }, skip: Platform.isWindows ? false : 'starts a Windows program');
}
