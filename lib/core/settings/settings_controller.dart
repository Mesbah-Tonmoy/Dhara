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
      ),
      _autoplayNext = _loadSwitch(_store.getInt(_autoplayNextKey), true),
      _rotateFeatured = _loadSwitch(_store.getInt(_rotateFeaturedKey), true),
      _reduceMotion = _loadSwitch(_store.getInt(_reduceMotionKey), false),
      _interfaceScalePercent = _loadInterfaceScale(
        _store.getInt(_interfaceScaleKey),
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

  /// The sizes the interface can be drawn in, in percent of its own size.
  static const interfaceScales = <int>[90, 100, 110, 125];
  static const defaultInterfaceScalePercent = 100;

  static const _seekBackKey = 'player.seekBackSeconds';
  static const _seekForwardKey = 'player.seekForwardSeconds';
  static const _volumeKey = 'player.volume';
  static const _subtitleScaleKey = 'player.subtitleScalePercent';
  static const _autoplayNextKey = 'player.autoplayNext';
  static const _rotateFeaturedKey = 'look.rotateFeatured';
  static const _reduceMotionKey = 'look.reduceMotion';
  static const _interfaceScaleKey = 'look.interfaceScalePercent';

  final KeyValueStore _store;
  int _seekBackSeconds;
  int _seekForwardSeconds;
  double _volume;
  int _subtitleScalePercent;
  bool _autoplayNext;
  bool _rotateFeatured;
  bool _reduceMotion;
  int _interfaceScalePercent;

  /// When a video ends, the next one of the queue (the next episode)
  /// starts by itself after a countdown.
  bool get autoplayNext => _autoplayNext;

  void setAutoplayNext(bool value) {
    if (value == _autoplayNext) return;
    _autoplayNext = value;
    notifyListeners();
    unawaited(_store.setInt(_autoplayNextKey, value ? 1 : 0));
  }

  /// The banner on Home moves on to the next title by itself.
  bool get rotateFeatured => _rotateFeatured;

  void setRotateFeatured(bool value) {
    if (value == _rotateFeatured) return;
    _rotateFeatured = value;
    notifyListeners();
    unawaited(_store.setInt(_rotateFeaturedKey, value ? 1 : 0));
  }

  /// No zooms, slides or fades: everything changes at once.
  bool get reduceMotion => _reduceMotion;

  void setReduceMotion(bool value) {
    if (value == _reduceMotion) return;
    _reduceMotion = value;
    notifyListeners();
    unawaited(_store.setInt(_reduceMotionKey, value ? 1 : 0));
  }

  /// The size of the interface, one of [interfaceScales] (percent).
  int get interfaceScalePercent => _interfaceScalePercent;

  void setInterfaceScalePercent(int percent) {
    if (!interfaceScales.contains(percent)) return;
    if (percent == _interfaceScalePercent) return;
    _interfaceScalePercent = percent;
    notifyListeners();
    unawaited(_store.setInt(_interfaceScaleKey, percent));
  }

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

  /// A switch is kept as 1 or 0; anything else is [fallback].
  static bool _loadSwitch(int? stored, bool fallback) => switch (stored) {
    1 => true,
    0 => false,
    _ => fallback,
  };

  static int _loadInterfaceScale(int? stored) =>
      stored != null && interfaceScales.contains(stored)
      ? stored
      : defaultInterfaceScalePercent;

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

  /// The controller; the calling widget rebuilds whenever a setting
  /// changes.
  static SettingsController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<SettingsScope>();
    assert(scope != null, 'No SettingsScope above this widget');
    return scope!.notifier!;
  }

  /// As [of], or `null` for a widget shown without the app around it.
  static SettingsController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SettingsScope>()?.notifier;

  /// The controller, without subscribing the caller to changes. Listen to
  /// the returned controller where rebuilds are wanted.
  static SettingsController read(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<SettingsScope>();
    assert(scope != null, 'No SettingsScope above this widget');
    return scope!.notifier!;
  }
}
