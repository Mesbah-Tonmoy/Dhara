import 'package:dhara/core/images/image_store.dart';
import 'package:dhara/core/images/remote_image.dart';
import 'package:dhara/core/settings/settings_controller.dart';
import 'package:dhara/features/indexer/index_controller.dart';
import 'package:dhara/features/metadata/anime_controller.dart';
import 'package:dhara/features/metadata/match_controller.dart';
import 'package:dhara/features/metadata/review_controller.dart';
import 'package:dhara/features/metadata/titles_controller.dart';
import 'package:dhara/features/metadata/tmdb_key.dart';
import 'package:dhara/features/player/open_url_screen.dart';
import 'package:dhara/features/player/resume_store.dart';
import 'package:dhara/features/sources/source_test_controller.dart';
import 'package:dhara/theme/scale.dart';
import 'package:dhara/theme/theme.dart';
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
    this.images,
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

  /// Where posters are kept; without it, placeholders are shown.
  final RemoteImageStore? images;

  @override
  Widget build(BuildContext context) {
    return SettingsScope(
      settings: settings,
      child: ResumeStoreScope(
        store: resumeStore,
        child: SourcesScope(
          controller: sourceTests,
          child: IndexScope(
            controller: index,
            child: TitlesScope(
              controller: titles,
              child: TmdbKeyScope(
                controller: tmdbKey,
                child: MatchScope(
                  controller: match,
                  child: ReviewScope(
                    controller: review,
                    child: AnimeScope(
                      controller: anime,
                      child: ImageStoreScope(
                        store: images,
                        child: MaterialApp(
                          title: 'Dhara',
                          debugShowCheckedModeBanner: false,
                          theme: buildDharaTheme(),
                          // Above the Navigator, so that dialogs and menus
                          // grow with the window as well.
                          builder: (context, child) =>
                              DharaScale(child: child!),
                          home: const OpenUrlScreen(),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
