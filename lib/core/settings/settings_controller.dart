import 'dart:async';

import 'package:dhara/core/settings/key_value_store.dart';
import 'package:flutter/widgets.dart';

/// The user's settings: loaded once at start-up, changed through the setters
/// below, and saved as soon as they change.
///
/// Every value is validated on the way in and on the way out of storage, so
/// the rest of the app can rely on the ranges documented here.
class SettingsController extends ChangeNotifier {
  SettingsController(this._store)
      : _seekBackSeconds = _loadSeekStep(
          _store.getInt(_seekBackKey),
          defaultSeekBackSeconds,
        ),
        _seekForwardSeconds = _loadSeekStep(
          _store.getInt(_seekForwardKey),
          defaultSeekForwardSeconds,
        ),
        _volume = _loadVolume(_store.getDouble(_volumeKey)),
        _subtitleScalePercent = _loadSubtitleScale(
          _store.getInt(_subtitleScaleKey),
        );

  /// One-tap choices for the skip step, in seconds.
  static const seekStepPresets = <int>[5, 10, 15, 30, 60, 90, 120];
  static const minSeekStepSeconds = 1;
  static const maxSeekStepSeconds = 600;
  static const defaultSeekBackSeconds = 10;
  static const defaultSeekForwardSeconds = 30;
  static const defaultVolume = 100.0;

  /// Subtitle size range, in percent of the normal size, in steps of 10.
  static const minSubtitleScalePercent = 50;
  static const maxSubtitleScalePercent = 200;
  static const subtitleScaleStepPercent = 10;
  static const defaultSubtitleScalePercent = 100;

  static const _seekBackKey = 'player.seekBackSeconds';
  static const _seekForwardKey = 'player.seekForwardSeconds';
  static const _volumeKey = 'player.volume';
  static const _subtitleScaleKey = 'player.subtitleScalePercent';

  final KeyValueStore _store;
  int _seekBackSeconds;
  int _seekForwardSeconds;
  double _volume;
  int _subtitleScalePercent;

  /// Subtitle size, 50–200 percent.
  int get subtitleScalePercent => _subtitleScalePercent;

  void setSubtitleScalePercent(int percent) {
    final value = _snapSubtitleScale(percent);
    if (value == _subtitleScalePercent) return;
    _subtitleScalePercent = value;
    notifyListeners();
    unawaited(_store.setInt(_subtitleScaleKey, value));
  }

  /// How far the "skip back" button and the ← key jump.
  int get seekBackSeconds => _seekBackSeconds;

  /// How far the "skip forward" button and the → key jump.
  int get seekForwardSeconds => _seekForwardSeconds;

  /// Player volume, 0–100.
  double get volume => _volume;

  void setSeekBackSeconds(int seconds) {
    final value = _clampSeekStep(seconds);
    if (value == _seekBackSeconds) return;
    _seekBackSeconds = value;
    notifyListeners();
    unawaited(_store.setInt(_seekBackKey, value));
  }

  void setSeekForwardSeconds(int seconds) {
    final value = _clampSeekStep(seconds);
    if (value == _seekForwardSeconds) return;
    _seekForwardSeconds = value;
    notifyListeners();
    unawaited(_store.setInt(_seekForwardKey, value));
  }

  void setVolume(double volume) {
    final value = volume.isNaN ? defaultVolume : volume.clamp(0.0, 100.0);
    if (value == _volume) return;
    _volume = value;
    notifyListeners();
    unawaited(_store.setDouble(_volumeKey, value));
  }

  static int _clampSeekStep(int seconds) =>
      seconds.clamp(minSeekStepSeconds, maxSeekStepSeconds);

  static int _loadSeekStep(int? stored, int fallback) {
    if (stored == null ||
        stored < minSeekStepSeconds ||
        stored > maxSeekStepSeconds) {
      return fallback;
    }
    return stored;
  }

  /// Clamps to the allowed range and rounds to the nearest step.
  static int _snapSubtitleScale(int percent) {
    final clamped = percent.clamp(
      minSubtitleScalePercent,
      maxSubtitleScalePercent,
    );
    return (clamped / subtitleScaleStepPercent).round() *
        subtitleScaleStepPercent;
  }

  static int _loadSubtitleScale(int? stored) {
    if (stored == null ||
        stored < minSubtitleScalePercent ||
        stored > maxSubtitleScalePercent) {
      return defaultSubtitleScalePercent;
    }
    return _snapSubtitleScale(stored);
  }

  static double _loadVolume(double? stored) {
    if (stored == null || stored.isNaN || stored < 0 || stored > 100) {
      return defaultVolume;
    }
    return stored;
  }
}

/// Makes the [SettingsController] available to the widget tree.
class SettingsScope extends InheritedNotifier<SettingsController> {
  const SettingsScope({
    super.key,
    required SettingsController settings,
    required super.child,
  }) : super(notifier: settings);

  /// The controller, without subscribing the caller to changes. Listen to
  /// the returned controller where rebuilds are wanted.
  static SettingsController read(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<SettingsScope>();
    assert(scope != null, 'No SettingsScope above this widget');
    return scope!.notifier!;
  }
}
