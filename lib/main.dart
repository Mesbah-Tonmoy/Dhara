import 'dart:async';
import 'dart:io';

import 'package:dhara/app.dart';
import 'package:dhara/core/db/library_db.dart';
import 'package:dhara/core/db/library_isolate.dart';
import 'package:dhara/core/images/image_store.dart';
import 'package:dhara/core/secrets/secret_store.dart';
import 'package:dhara/core/secrets/windows_credential_store.dart';
import 'package:dhara/core/settings/key_value_store.dart';
import 'package:dhara/core/settings/settings_controller.dart';
import 'package:dhara/core/window/native_window.dart';
import 'package:dhara/core/window/window_controller.dart';
import 'package:dhara/features/browse/browse_controller.dart';
import 'package:dhara/features/history/history_controller.dart';
import 'package:dhara/features/home/home_controller.dart';
import 'package:dhara/features/indexer/index_controller.dart';
import 'package:dhara/features/metadata/anime_controller.dart';
import 'package:dhara/features/metadata/episodes_controller.dart';
import 'package:dhara/features/metadata/film_details_controller.dart';
import 'package:dhara/features/metadata/match_controller.dart';
import 'package:dhara/features/metadata/review_controller.dart';
import 'package:dhara/features/metadata/titles_controller.dart';
import 'package:dhara/features/metadata/tmdb_key.dart';
import 'package:dhara/features/my_list/my_list_controller.dart';
import 'package:dhara/features/playback/copy_probe.dart';
import 'package:dhara/features/playback/media_sessions.dart';
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
  MediaKit.ensureInitialized(libmpv: _bundledLibmpv());
  // On Windows the app draws its own title bar. Asked for before the first
  // frame, so the window never shows with the system's one. Elsewhere, and if
  // this fails, the system's title bar stays and the app draws none.
  final window = NativeWindowController();
  if (Platform.isWindows) await window.useCustomFrame();
  final folder = await _appDataPath();
  final (store, sources, (library, libraryNotice, librarySaved)) = await (
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
  // Reads the names of the indexed videos whenever the index has changed;
  // the first time is when the index is loaded below.
  final titles = TitlesController(library: library, index: index);
  // The TMDB key lives in the secure storage of the system. Other systems
  // than Windows have none the app can use yet: there it lasts for this run.
  final tmdbKey = TmdbKeyController(
    Platform.isWindows && _dataFolderOverride.isEmpty
        ? const WindowsCredentialStore()
        : MemorySecretStore(),
  );
  unawaited(tmdbKey.load());
  // Looks titles up on TMDB: the first time when asked, later by itself
  // for what crawls add.
  final match = MatchController(
    library: library,
    titles: titles,
    tmdbKey: tmdbKey,
  );
  // Fetches the episodes of matched shows whenever titles were matched; it
  // lives as long as the controller it listens to.
  EpisodesController(library: library, match: match, tmdbKey: tmdbKey);
  final review = ReviewController(
    library: library,
    titles: titles,
    match: match,
    tmdbKey: tmdbKey,
  );
  // What Home shows is read now, from what the last run left, and again
  // whenever the library changes.
  final home = HomeController(library: library, titles: titles, match: match);
  unawaited(home.refresh());
  // Reads TMDB's page of each matched film (genres, length, people) once,
  // in the background; Home is read again when a run of that ends.
  final filmDetails = FilmDetailsController(
    library: library,
    match: match,
    tmdbKey: tmdbKey,
  );
  filmDetails.addListener(() {
    if (!filmDetails.isFetching && filmDetails.filmsDone > 0) {
      unawaited(home.refresh());
    }
  });
  final myList = MyListController(library: library);
  unawaited(myList.load());
  // Posters are kept next to the settings; without a data folder they are
  // not shown.
  final images = RemoteImageStore(
    folder: folder == null
        ? null
        : Directory('$folder${Platform.pathSeparator}images'),
  );
  // Positions go to the database only if it is the one on disk; with a
  // stand-in for this run they stay in the settings file, where they were.
  final resumeStore = ResumeStore(librarySaved ? library : null);
  await resumeStore.load(legacy: store);
  runApp(
    WindowScope(
      controller: window,
      child: DharaApp(
        settings: SettingsController(store),
        resumeStore: resumeStore,
        sourceTests: sourceTests,
        index: index,
        titles: titles,
        tmdbKey: tmdbKey,
        match: match,
        review: review,
        // AniList is asked when its screen is opened, not at start-up.
        anime: AnimeController(library: library),
        home: home,
        myList: myList,
        // Asked when Search is first used; follows Home after that.
        browse: BrowseController(library: library, titles: titles, home: home),
        history: HistoryController(
          library: library,
          titles: titles,
          resume: resumeStore,
          home: home,
        ),
        filmDetails: filmDetails,
        images: images,
        // A live ping may go to the configured sources, and nowhere else
        // (looked up each time: the list can change).
        mediaSessions: MediaSessions(
          deviceId: deviceId,
          sources: sourceTests.store,
        ),
        newCopyProber: () => CopyProber(
          isAllowedHost: (host) => sourceTests.store.sources.any(
            (source) => source.baseUrls.any((url) => url.host == host),
          ),
        ),
      ),
    ),
  );
  // Notice enabled servers that died since they were last tested.
  unawaited(sourceTests.retestEnabledIfStale());
  unawaited(_keepIndexFresh(index));
  // Once the app has settled, keeps the folder of posters within its limit.
  unawaited(
    Future<void>.delayed(
      const Duration(seconds: 40),
    ).then((_) => images.trim()),
  );
}

/// The `libmpv-2.dll` that lies beside the program, by its full path.
///
/// Left to look for itself, media_kit would first load whatever library the
/// `LIBMPV_LIBRARY_PATH` environment variable names, and after that search
/// by name alone. Named in full, the player is the file the installer put
/// there and no other. Systems other than Windows keep media_kit's search.
String? _bundledLibmpv() {
  if (!Platform.isWindows) return null;
  final folder = File(Platform.resolvedExecutable).parent.path;
  return '$folder${Platform.pathSeparator}libmpv-2.dll';
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
  // A development build with its own data folder keeps its hands off the
  // real settings too.
  if (_dataFolderOverride.isNotEmpty) return MemoryKeyValueStore();
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
/// background isolate, what the user should know about it, if anything, and
/// whether it is saved.
///
/// The app always gets a library and this never throws: if the file cannot
/// be used, the library lasts for this run only, and if no database can be
/// started at all, it is one that does nothing.
Future<(LibraryWorker, String?, bool)> _openLibrary(String? folder) async {
  String notice;
  if (folder == null) {
    notice =
        "The app's data folder was not found, so the index is kept "
        'for this run only.';
  } else {
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
        true,
      );
    } on LibraryDbException catch (error) {
      notice = error.problem == LibraryDbProblem.newerVersion
          ? 'The index file was made by a newer version of Dhara and was '
                'left alone. This run uses an empty index that is not saved.'
          : 'The index file could not be opened. This run uses an empty '
                'index that is not saved.';
    } on LibraryWorkException {
      notice =
          'The index file could not be opened. This run uses an empty '
          'index that is not saved.';
    }
  }
  try {
    return (await LibraryIsolate.spawn(), notice, false);
  } on Exception {
    // Not even in memory: SQLite itself did not start.
    return (
      const NoLibrary(),
      'The library database could not be started, so there is no index '
          'and no search in this run. Playing a pasted URL still works.',
      false,
    );
  }
}

/// For development only: another folder for the app's data, so that a test
/// build never touches the real library. Set when building, with
/// `--dart-define=DHARA_DATA_DIR=<folder>`; a build made without it has no
/// way to move its data. Such a build also keeps its settings in memory and
/// neither reads nor writes the TMDB key in Windows Credential Manager.
const _dataFolderOverride = String.fromEnvironment('DHARA_DATA_DIR');

/// The per-user application data folder (on Windows
/// `%APPDATA%\com.dhara\dhara`), or `null` if it cannot be found.
///
/// Asked through the platform interface that `shared_preferences` already
/// brings along for Windows and Linux; the `path_provider` front package
/// would add a dozen packages for platforms this app does not target.
Future<String?> _appDataPath() async {
  if (_dataFolderOverride.isNotEmpty) {
    try {
      return (await Directory(
        _dataFolderOverride,
      ).create(recursive: true)).path;
    } on FileSystemException {
      return null;
    }
  }
  try {
    return await PathProviderPlatform.instance.getApplicationSupportPath();
  } on Exception {
    return null;
  }
}
