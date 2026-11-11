import 'package:media_kit_video/media_kit_video.dart';

/// Switches the app window in or out of fullscreen.
///
/// Uses the native window helper that already ships with media_kit_video, so
/// no extra window plugin is needed yet. This is the one place to change when
/// the custom title bar brings its own window management.
Future<void> setWindowFullscreen(bool fullscreen) {
  return fullscreen
      ? defaultEnterNativeFullscreen()
      : defaultExitNativeFullscreen();
}
