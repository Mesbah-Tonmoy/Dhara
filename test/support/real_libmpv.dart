import 'dart:io';

/// The bundled `libmpv-2.dll` of a Windows build, or `null` until
/// `flutter build windows` has run at least once on this machine. Tests
/// against the real libmpv are skipped without it.
File? findLibmpv() {
  for (final mode in ['Release', 'Debug', 'Profile']) {
    final file = File('build/windows/x64/runner/$mode/libmpv-2.dll');
    if (file.existsSync()) return file;
  }
  return null;
}

/// A short video that ships with Windows (11.8 s, picture only).
final sampleVideo = File(
  r'C:\Windows\ImmersiveControlPanel\SystemSettings\Assets'
  r'\SDRSampleAccessibility.mkv',
);
