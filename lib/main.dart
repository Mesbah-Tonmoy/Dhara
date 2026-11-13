import 'dart:async';
import 'dart:io';

import 'package:dhara/app.dart';
import 'package:dhara/core/db/library_db.dart';
import 'package:dhara/core/db/library_isolate.dart';
import 'package:dhara/core/settings/key_value_store.dart';
import 'package:dhara/core/settings/settings_controller.dart';
import 'package:dhara/features/indexer/index_controller.dart';
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
  final folder = await _appDataPath();
  final (store, sources, (library, libraryNotice)) = await (
    _openSettingsStore(),
    _openSourceStore(folder),
    _openLibrary(folder),
  ).wait;
  final deviceId = loadOrCreateDeviceId(store);
  final sourceTests = SourceTestController(
    store: sources,
    tester: SourceTester(deviceId: deviceId),
  );
  final index = IndexController(
    library: library,
    sources: sources,
    deviceId: deviceId,
    startupNotice: libraryNotice,
  );
  runApp(
    DharaApp(
      settings: SettingsController(store),
      resumeStore: ResumeStore(store),
      sourceTests: sourceTests,
      index: index,
    ),
  );
  // Notice enabled servers that died since they were last tested.
  unawaited(sourceTests.retestEnabledIfStale());
  unawaited(_keepIndexFresh(index));
}

/// Reads the size of the index, then, once the app has settled, brings an
/// index up to date that is more than a day old.
Future<void> _keepIndexFresh(IndexController index) async {
  await index.load();
  await Future<void>.delayed(const Duration(seconds: 15));
  await index.updateIfStale();
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
Future<SourceStore> _openSourceStore(String? folder) async {
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

/// The library database (`library.db`, next to the settings file) in its
/// background isolate, and what the user should know about it, if anything.
///
/// The app always gets a library: if the file cannot be used, one that
/// lasts for this run only.
Future<(LibraryWorker, String?)> _openLibrary(String? folder) async {
  if (folder == null) {
    return (
      await LibraryIsolate.spawn(),
      "The app's data folder was not found, so the index is kept for this "
          'run only.',
    );
  }
  try {
    final library = await LibraryIsolate.spawn(
      path: '$folder${Platform.pathSeparator}library.db',
    );
    return (
      library,
      library.replacedDamagedFile
          ? 'The index file was damaged, so a new index was started. The '
                'old file was kept as library.db.bad.'
          : null,
    );
  } on LibraryDbException catch (error) {
    return (
      await LibraryIsolate.spawn(),
      error.problem == LibraryDbProblem.newerVersion
          ? 'The index file was made by a newer version of Dhara and was '
                'left alone. This run uses an empty index that is not saved.'
          : 'The index file could not be opened. This run uses an empty '
                'index that is not saved.',
    );
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
