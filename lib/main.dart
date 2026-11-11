import 'package:dhara/app.dart';
import 'package:dhara/core/settings/key_value_store.dart';
import 'package:dhara/core/settings/settings_controller.dart';
import 'package:dhara/features/player/resume_store.dart';
import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Loads the bundled libmpv; no external player install is needed.
  MediaKit.ensureInitialized();
  final store = await _openSettingsStore();
  runApp(
    DharaApp(
      settings: SettingsController(store),
      resumeStore: ResumeStore(store),
    ),
  );
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
