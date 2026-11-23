import 'package:dhara/core/images/image_store.dart';
import 'package:dhara/core/images/remote_image.dart';
import 'package:dhara/core/settings/settings_controller.dart';
import 'package:dhara/features/browse/browse_controller.dart';
import 'package:dhara/features/history/history_controller.dart';
import 'package:dhara/features/home/home_controller.dart';
import 'package:dhara/features/indexer/index_controller.dart';
import 'package:dhara/features/metadata/anime_controller.dart';
import 'package:dhara/features/metadata/film_details_controller.dart';
import 'package:dhara/features/metadata/match_controller.dart';
import 'package:dhara/features/metadata/review_controller.dart';
import 'package:dhara/features/metadata/titles_controller.dart';
import 'package:dhara/features/metadata/tmdb_key.dart';
import 'package:dhara/features/my_list/my_list_controller.dart';
import 'package:dhara/features/playback/copy_probe.dart';
import 'package:dhara/features/playback/media_sessions.dart';
import 'package:dhara/features/player/resume_store.dart';
import 'package:dhara/features/snapshot/snapshot_controller.dart';
import 'package:dhara/features/sources/source_test_controller.dart';
import 'package:dhara/shell/app_shell.dart';
import 'package:dhara/shell/page_keys.dart';
import 'package:dhara/theme/scale.dart';
import 'package:dhara/theme/theme.dart';
import 'package:dhara/widgets/toast.dart';
import 'package:flutter/material.dart';

/// Root widget. Creates no native player, so it is safe to pump in tests.
class DharaApp extends StatelessWidget {
  const DharaApp({
    super.key,
    required this.settings,
    required this.resumeStore,
    required this.sourceTests,
    required this.index,
    required this.titles,
    required this.tmdbKey,
    required this.match,
    required this.review,
    required this.anime,
    required this.home,
    required this.myList,
    required this.browse,
    required this.history,
    this.devTools = false,
    this.filmDetails,
    this.snapshots,
    this.images,
    this.newCopyProber,
    this.mediaSessions,
  });

  final SettingsController settings;
  final ResumeStore resumeStore;
  final SourceTestController sourceTests;
  final IndexController index;
  final TitlesController titles;
  final TmdbKeyController tmdbKey;
  final MatchController match;
  final ReviewController review;
  final AnimeController anime;
  final HomeController home;
  final MyListController myList;
  final BrowseController browse;
  final HistoryController history;

  /// A development build, which has the tools for working on the library;
  /// without it this is a production build (see `ShellController.devTools`).
  final bool devTools;

  /// Says how far the reading of film details is; without it, nothing
  /// does.
  final FilmDetailsController? filmDetails;

  /// Writes the library out as a snapshot: a development build has one.
  final LibrarySnapshotController? snapshots;

  /// Where posters are kept; without it, placeholders are shown.
  final RemoteImageStore? images;

  /// Makes what the pages ask servers for copies with (the live ping);
  /// without it, they show how the servers answered their last test.
  final CopyProber Function()? newCopyProber;

  /// Signs in to Emby and Jellyfin servers for playing their files;
  /// without it, those are asked for without a session.
  final MediaSessions? mediaSessions;

  @override
  Widget build(BuildContext context) {
    final filmDetails = this.filmDetails;
    final snapshots = this.snapshots;
    Widget app = MaterialApp(
      title: 'Dhara',
      debugShowCheckedModeBanner: false,
      theme: buildDharaTheme(),
      // Above the Navigator, so that dialogs and menus grow with the window
      // as well, and a message outlives the page that sent it.
      builder: (context, child) {
        final settings = SettingsScope.of(context);
        final media = MediaQuery.of(context);
        return MediaQuery(
          // The Reduce motion setting does what the system's does.
          data: media.copyWith(
            disableAnimations: media.disableAnimations || settings.reduceMotion,
          ),
          child: DharaScale(
            userScale: settings.interfaceScalePercent / 100,
            child: ToastHost(child: PageScrollKeys(child: child!)),
          ),
        );
      },
      home: AppShell(devTools: devTools),
    );
    // What every page can reach, the innermost first.
    for (final scope in <Widget Function(Widget child)>[
      (child) => ImageStoreScope(store: images, child: child),
      (child) => CopyProbeScope(make: newCopyProber, child: child),
      (child) => MediaSessionsScope(sessions: mediaSessions, child: child),
      (child) => HistoryScope(controller: history, child: child),
      (child) => BrowseScope(controller: browse, child: child),
      (child) => MyListScope(controller: myList, child: child),
      (child) => HomeScope(controller: home, child: child),
      (child) => AnimeScope(controller: anime, child: child),
      (child) => ReviewScope(controller: review, child: child),
      (child) => MatchScope(controller: match, child: child),
      (child) => TmdbKeyScope(controller: tmdbKey, child: child),
      (child) => TitlesScope(controller: titles, child: child),
      (child) => IndexScope(controller: index, child: child),
      (child) => SourcesScope(controller: sourceTests, child: child),
      (child) => ResumeStoreScope(store: resumeStore, child: child),
      (child) => SettingsScope(settings: settings, child: child),
      if (filmDetails != null)
        (child) => FilmDetailsScope(controller: filmDetails, child: child),
      if (snapshots != null)
        (child) => LibrarySnapshotScope(controller: snapshots, child: child),
    ]) {
      app = scope(app);
    }
    return app;
  }
}
