import 'dart:async';

import 'package:dhara/core/settings/key_value_store.dart';
import 'package:dhara/theme/logo_style.dart';
import 'package:flutter/widgets.dart';

/// The picture quality Play goes for when a title has copies in several.
enum PreferredQuality {
  /// The sharpest there is.
  best('Auto (best)', null),
  uhd('4K', 2160),
  fullHd('1080p', 1080),
  hd('720p', 720);

  const PreferredQuality(this.label, this.height);

  final String label;

  /// The picture height that goes by this name; `null` for [best].
  final int? height;
}

/// The subtitles a video starts with, if it has them.
enum SubtitleLanguage {
  /// None; they can still be switched on while it plays.
  off('Off', []),
  english('English', ['eng', 'en']),
  bangla('Bangla', ['ben', 'bn']);

  const SubtitleLanguage(this.label, this.codes);

  final String label;

  /// The language codes files use for it (ISO 639-2 and 639-1).
  final List<String> codes;
}

/// The sound track a video starts with, where it has several.
enum AudioLanguage {
  /// The one the file puts first.
  original('Original', []),
  english('English', ['eng', 'en']),
  bangla('Bangla', ['ben', 'bn']),
  hindi('Hindi', ['hin', 'hi']);

  const AudioLanguage(this.label, this.codes);

  final String label;
  final List<String> codes;
}

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
      _bufferMegabytes = _loadBuffer(_store.getInt(_bufferKey)),
      _preferredQuality = _loadQuality(_store.getInt(_preferredQualityKey)),
      _subtitleLanguage = _loadNamed(
        SubtitleLanguage.values,
        _store.getString(_subtitleLanguageKey),
        SubtitleLanguage.english,
      ),
      _audioLanguage = _loadNamed(
        AudioLanguage.values,
        _store.getString(_audioLanguageKey),
        AudioLanguage.original,
      ),
      _hardwareDecoding = _loadSwitch(
        _store.getInt(_hardwareDecodingKey),
        true,
      ),
      _rotateFeatured = _loadSwitch(_store.getInt(_rotateFeaturedKey), true),
      _reduceMotion = _loadSwitch(_store.getInt(_reduceMotionKey), false),
      _interfaceScalePercent = _loadInterfaceScale(
        _store.getInt(_interfaceScaleKey),
      ),
      _browseFiltersShown = _loadSwitch(
        _store.getInt(_browseFiltersShownKey),
        true,
      ),
      _logoStyle = _loadNamed(
        DharaLogoStyle.values,
        _store.getString(_logoStyleKey),
        defaultLogoStyle,
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

  /// The player's buffer, in megabytes, in steps of 50.
  static const minBufferMegabytes = 50;
  static const maxBufferMegabytes = 500;
  static const bufferStepMegabytes = 50;
  static const defaultBufferMegabytes = 150;

  /// The sizes the interface can be drawn in, in percent of its own size.
  static const interfaceScales = <int>[90, 100, 110, 125];
  static const defaultInterfaceScalePercent = 100;

  static const _seekBackKey = 'player.seekBackSeconds';
  static const _seekForwardKey = 'player.seekForwardSeconds';
  static const _volumeKey = 'player.volume';
  static const _subtitleScaleKey = 'player.subtitleScalePercent';
  static const _autoplayNextKey = 'player.autoplayNext';
  static const _bufferKey = 'player.bufferMegabytes';
  static const _preferredQualityKey = 'player.preferredQualityHeight';
  static const _subtitleLanguageKey = 'player.subtitleLanguage';
  static const _audioLanguageKey = 'player.audioLanguage';
  static const _hardwareDecodingKey = 'player.hardwareDecoding';
  static const _rotateFeaturedKey = 'look.rotateFeatured';
  static const _reduceMotionKey = 'look.reduceMotion';
  static const _interfaceScaleKey = 'look.interfaceScalePercent';
  static const _browseFiltersShownKey = 'look.browseFiltersShown';
  static const _logoStyleKey = 'look.logo';

  final KeyValueStore _store;
  int _seekBackSeconds;
  int _seekForwardSeconds;
  double _volume;
  int _subtitleScalePercent;
  bool _autoplayNext;
  int _bufferMegabytes;
  PreferredQuality _preferredQuality;
  SubtitleLanguage _subtitleLanguage;
  AudioLanguage _audioLanguage;
  bool _hardwareDecoding;
  bool _rotateFeatured;
  bool _reduceMotion;
  int _interfaceScalePercent;
  bool _browseFiltersShown;
  DharaLogoStyle _logoStyle;

  /// The drawing of the app's mark in the title bar and on Home. The
  /// program's icon in Windows does not follow it.
  DharaLogoStyle get logoStyle => _logoStyle;

  void setLogoStyle(DharaLogoStyle value) {
    if (value == _logoStyle) return;
    _logoStyle = value;
    notifyListeners();
    unawaited(_store.setString(_logoStyleKey, value.name));
  }

  /// The filters of the search and browse page are unfolded. Folded away,
  /// they still count.
  bool get browseFiltersShown => _browseFiltersShown;

  void setBrowseFiltersShown(bool value) {
    if (value == _browseFiltersShown) return;
    _browseFiltersShown = value;
    notifyListeners();
    unawaited(_store.setInt(_browseFiltersShownKey, value ? 1 : 0));
  }

  /// When a video ends, the next one of the queue (the next episode)
  /// starts by itself after a countdown.
  bool get autoplayNext => _autoplayNext;

  void setAutoplayNext(bool value) {
    if (value == _autoplayNext) return;
    _autoplayNext = value;
    notifyListeners();
    unawaited(_store.setInt(_autoplayNextKey, value ? 1 : 0));
  }

  /// The quality Play takes where a title has copies in several: the copy
  /// at it whose server answers fastest. Without one at it, the nearest
  /// below, then the nearest above.
  PreferredQuality get preferredQuality => _preferredQuality;

  void setPreferredQuality(PreferredQuality value) {
    if (value == _preferredQuality) return;
    _preferredQuality = value;
    notifyListeners();
    // Kept as the picture height, 0 for the sharpest.
    unawaited(_store.setInt(_preferredQualityKey, value.height ?? 0));
  }

  /// The subtitles a video starts with: those in this language if it has
  /// them (else the ones its file marks as the default, if any), or none.
  /// Counts from the next video that is opened.
  SubtitleLanguage get subtitleLanguage => _subtitleLanguage;

  void setSubtitleLanguage(SubtitleLanguage value) {
    if (value == _subtitleLanguage) return;
    _subtitleLanguage = value;
    notifyListeners();
    unawaited(_store.setString(_subtitleLanguageKey, value.name));
  }

  /// The sound track a video with several starts with: the one in this
  /// language if it has one, else the one the file puts first. Counts
  /// from the next video that is opened.
  AudioLanguage get audioLanguage => _audioLanguage;

  void setAudioLanguage(AudioLanguage value) {
    if (value == _audioLanguage) return;
    _audioLanguage = value;
    notifyListeners();
    unawaited(_store.setString(_audioLanguageKey, value.name));
  }

  /// How much of a video the player may keep in memory (what lies ahead
  /// and a part of what was played), 50–500 MB. Counts from the next
  /// video that is opened.
  int get bufferMegabytes => _bufferMegabytes;

  void setBufferMegabytes(int megabytes) {
    final value = _snapBuffer(megabytes);
    if (value == _bufferMegabytes) return;
    _bufferMegabytes = value;
    notifyListeners();
    unawaited(_store.setInt(_bufferKey, value));
  }

  /// The graphics card decodes the picture where mpv counts that as safe.
  /// Counts from the next video that is opened.
  bool get hardwareDecoding => _hardwareDecoding;

  void setHardwareDecoding(bool value) {
    if (value == _hardwareDecoding) return;
    _hardwareDecoding = value;
    notifyListeners();
    unawaited(_store.setInt(_hardwareDecodingKey, value ? 1 : 0));
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

  /// The one of [values] that is called [stored]; [fallback] for any
  /// other text.
  static T _loadNamed<T extends Enum>(
    List<T> values,
    String? stored,
    T fallback,
  ) {
    for (final value in values) {
      if (value.name == stored) return value;
    }
    return fallback;
  }

  static PreferredQuality _loadQuality(int? stored) {
    for (final quality in PreferredQuality.values) {
      if (quality.height == stored) return quality;
    }
    return PreferredQuality.best;
  }

  /// Clamps to the allowed range and rounds to the nearest step.
  static int _snapBuffer(int megabytes) {
    final clamped = megabytes.clamp(minBufferMegabytes, maxBufferMegabytes);
    return (clamped / bufferStepMegabytes).round() * bufferStepMegabytes;
  }

  static int _loadBuffer(int? stored) {
    if (stored == null ||
        stored < minBufferMegabytes ||
        stored > maxBufferMegabytes) {
      return defaultBufferMegabytes;
    }
    return _snapBuffer(stored);
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
