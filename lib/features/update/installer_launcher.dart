import 'dart:io';

import 'package:dhara/features/update/installer_fetcher.dart';

/// Starts the installer of a newer version: the one place in the app that
/// starts a program, and the one program it starts.
///
/// It takes a [CheckedInstaller] and nothing else, and only the fetcher
/// can make one, after it found the file to be the one a signed update
/// notice names. So no path that comes from a server, a setting or a
/// notice reaches this, and no file that was not checked.
///
/// The installer is started as it is, with no option: it shows its own
/// pages and asks before it changes anything, runs as the user who runs
/// the app, and needs no admin rights. It is started on the user's click
/// and never by the app itself.
class InstallerLauncher {
  const InstallerLauncher({
    Future<void> Function(String path) start = _startByItself,
  }) : _start = start;

  final Future<void> Function(String path) _start;

  /// Starts [installer], which then runs on by itself. Returns whether
  /// Windows started it. Never throws.
  Future<bool> start(CheckedInstaller installer) async {
    try {
      await _start(installer.file.path);
      return true;
    } on Exception {
      // The file is gone, or Windows refuses to run it.
      return false;
    }
  }

  /// Runs the program at [path] with no arguments and without a shell,
  /// not tied to this app: it goes on when the app closes.
  static Future<void> _startByItself(String path) async {
    await Process.start(path, const [], mode: ProcessStartMode.detached);
  }
}
