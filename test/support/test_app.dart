import 'package:dhara/app.dart';
import 'package:dhara/core/db/library_db.dart';
import 'package:dhara/core/db/library_isolate.dart';
import 'package:dhara/core/secrets/secret_store.dart';
import 'package:dhara/core/settings/key_value_store.dart';
import 'package:dhara/core/settings/settings_controller.dart';
import 'package:dhara/core/window/window_controller.dart';
import 'package:dhara/features/home/home_controller.dart';
import 'package:dhara/features/indexer/index_controller.dart';
import 'package:dhara/features/metadata/anime_controller.dart';
import 'package:dhara/features/metadata/match_controller.dart';
import 'package:dhara/features/metadata/review_controller.dart';
import 'package:dhara/features/metadata/titles_controller.dart';
import 'package:dhara/features/metadata/tmdb_key.dart';
import 'package:dhara/features/player/resume_store.dart';
import 'package:dhara/features/sources/source.dart';
import 'package:dhara/features/sources/source_store.dart';
import 'package:dhara/features/sources/source_test_controller.dart';
import 'package:dhara/features/sources/source_tester.dart';
import 'package:flutter/widgets.dart';

/// The whole app on an empty library kept in memory: no files, no network,
/// no native player.
///
/// [sources] are the servers it knows; [window] stands in for the app's
/// window, as `main` provides it; [db] is the library to start with, if
/// not an empty one.
({Widget app, SourceStore sources}) testApp({
  List<Source> sources = const [],
  WindowController? window,
  LibraryDb? db,
}) {
  final store = SourceStore(starter: sources);
  final library = LocalLibrary(db ?? LibraryDb.inMemory());
  final index = IndexController(
    library: library,
    sources: store,
    deviceId: 'dhara-test',
  );
  final titles = TitlesController(library: library, index: index);
  final tmdbKey = TmdbKeyController(MemorySecretStore());
  final match = MatchController(
    library: library,
    titles: titles,
    tmdbKey: tmdbKey,
  );
  final Widget app = DharaApp(
    settings: SettingsController(MemoryKeyValueStore()),
    resumeStore: ResumeStore(),
    sourceTests: SourceTestController(
      store: store,
      tester: SourceTester(deviceId: 'dhara-test'),
    ),
    index: index,
    titles: titles,
    tmdbKey: tmdbKey,
    match: match,
    review: ReviewController(
      library: library,
      titles: titles,
      match: match,
      tmdbKey: tmdbKey,
    ),
    anime: AnimeController(library: library),
    home: HomeController(library: library, titles: titles, match: match),
  );
  return (
    app: window == null ? app : WindowScope(controller: window, child: app),
    sources: store,
  );
}

Source testSource(String id) => Source(
  id: id,
  name: 'Server $id',
  type: SourceType.h5ai,
  category: SourceCategory.movies,
  baseUrls: [Uri.parse('http://10.0.0.1/$id/')],
);

/// A window that only notes what was asked of it.
class FakeWindow extends WindowController {
  FakeWindow({
    this.hasCustomFrame = true,
    this.isMaximized = false,
    this.isFullscreen = false,
  });

  @override
  bool hasCustomFrame;
  @override
  bool isMaximized;
  @override
  bool isFullscreen;

  /// Everything asked of the window, in order.
  final calls = <String>[];

  void change({bool? maximized, bool? fullscreen, bool? customFrame}) {
    isMaximized = maximized ?? isMaximized;
    isFullscreen = fullscreen ?? isFullscreen;
    hasCustomFrame = customFrame ?? hasCustomFrame;
    notifyListeners();
  }

  @override
  void startDrag() => calls.add('drag');

  @override
  void startResize(WindowEdge edge) => calls.add('resize ${edge.name}');

  @override
  void minimize() => calls.add('minimize');

  @override
  void toggleMaximize() {
    calls.add('toggleMaximize');
    change(maximized: !isMaximized);
  }

  @override
  void close() => calls.add('close');
}
