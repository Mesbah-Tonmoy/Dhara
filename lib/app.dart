import 'package:dhara/core/settings/settings_controller.dart';
import 'package:dhara/features/player/open_url_screen.dart';
import 'package:flutter/material.dart';

/// Root widget. Creates no native player, so it is safe to pump in tests.
class DharaApp extends StatelessWidget {
  const DharaApp({super.key, required this.settings});

  final SettingsController settings;

  @override
  Widget build(BuildContext context) {
    return SettingsScope(
      settings: settings,
      child: MaterialApp(
        title: 'Dhara',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF8B6CFF),
            brightness: Brightness.dark,
          ),
          scaffoldBackgroundColor: const Color(0xFF06070C),
        ),
        home: const OpenUrlScreen(),
      ),
    );
  }
}
