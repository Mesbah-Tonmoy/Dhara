import 'dart:async';
import 'dart:io';

import 'package:dhara/app.dart';
import 'package:dhara/core/settings/key_value_store.dart';
import 'package:dhara/core/settings/settings_controller.dart';
import 'package:dhara/features/player/resume_store.dart';
import 'package:dhara/features/sources/device_id.dart';
import 'package:dhara/features/sources/source.dart';
import 'package:dhara/features/sources/source_list.dart';
import 'package:dhara/features/sources/source_store.dart';
import 'package:dhara/features/sources/source_test_controller.dart';
import 'package:dhara/features/sources/source_tester.dart';
import 'package:dhara/features/sources/starter_sources.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Loads the bundled libmpv; no external player install is needed.
  MediaKit.ensureInitialized();
  final (store, sources) =
      await (_openSettingsStore(), _openSourceStore()).wait;
  final sourceTests = SourceTestController(
    store: sources,
    tester: SourceTester(deviceId: loadOrCreateDeviceId(store)),
  );
  runApp(
    DharaApp(
      settings: SettingsController(store),
      resumeStore: ResumeStore(store),
      sourceTests: sourceTests,
    ),
  );
  // Notice enabled servers that died since they were last tested.
  unawaited(sourceTests.retestEnabledIfStale());
}

/// Opens the on-disk settings. If that fails (unreadable profile folder,
/// broken file) the app still starts, with defaults that last for this run.
Future<KeyValueStore> _openSettingsStore() async {
  try {
    return await SharedPrefsStore.open();
  } on Exception {
    return MemoryKeyValueStore();
  }
}

/// The starter list with the user's saved changes on top. The changes live
/// in `sources.json`, next to the settings file.
Future<SourceStore> _openSourceStore() async {
  final folder = await _appDataPath();
  final store = SourceStore(
    starter: await _loadStarterSources(),
    // Without a data folder, changes last for this run only.
    file: folder == null
        ? null
        : File('$folder${Platform.pathSeparator}sources.json'),
  );
  await store.load();
  return store;
}

Future<List<Source>> _loadStarterSources() async {
  try {
    return await loadStarterSources(rootBundle);
  } on SourceFormatException {
    // A broken bundled list (tests guard against it) must not stop the app;
    // sources can still be added or imported by hand.
    return const [];
  }
}

/// The per-user application data folder (on Windows
/// `%APPDATA%\com.dhara\dhara`), or `null` if it cannot be found.
///
/// Asked through the platform interface that `shared_preferences` already
/// brings along for Windows and Linux; the `path_provider` front package
/// would add a dozen packages for platforms this app does not target.
Future<String?> _appDataPath() async {
  try {
    return await PathProviderPlatform.instance.getApplicationSupportPath();
  } on Exception {
    return null;
  }
}
