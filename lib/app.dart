import 'package:dhara/core/settings/settings_controller.dart';
import 'package:dhara/features/indexer/index_controller.dart';
import 'package:dhara/features/metadata/titles_controller.dart';
import 'package:dhara/features/player/open_url_screen.dart';
import 'package:dhara/features/player/resume_store.dart';
import 'package:dhara/features/sources/source_test_controller.dart';
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
  });

  final SettingsController settings;
  final ResumeStore resumeStore;
  final SourceTestController sourceTests;
  final IndexController index;
  final TitlesController titles;

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
              child: MaterialApp(
                title: 'Dhara',
                debugShowCheckedModeBanner: false,
                theme: buildDharaTheme(),
                home: const OpenUrlScreen(),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
