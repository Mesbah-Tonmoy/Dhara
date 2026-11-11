import 'package:dhara/core/settings/settings_controller.dart';
import 'package:dhara/features/player/open_url_screen.dart';
import 'package:dhara/features/player/resume_store.dart';
import 'package:dhara/theme/theme.dart';
import 'package:flutter/material.dart';

/// Root widget. Creates no native player, so it is safe to pump in tests.
class DharaApp extends StatelessWidget {
  const DharaApp({
    super.key,
    required this.settings,
    required this.resumeStore,
  });

  final SettingsController settings;
  final ResumeStore resumeStore;

  @override
  Widget build(BuildContext context) {
    return SettingsScope(
      settings: settings,
      child: ResumeStoreScope(
        store: resumeStore,
        child: MaterialApp(
          title: 'Dhara',
          debugShowCheckedModeBanner: false,
          theme: buildDharaTheme(),
          home: const OpenUrlScreen(),
        ),
      ),
    );
  }
}
