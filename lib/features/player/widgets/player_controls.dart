import 'dart:async';

import 'package:dhara/core/settings/settings_controller.dart';
import 'package:dhara/features/player/playback_progress.dart';
import 'package:dhara/features/player/seek_math.dart';
import 'package:dhara/features/player/subtitle_file.dart';
import 'package:dhara/features/player/track_options.dart';
import 'package:dhara/features/player/widgets/player_controls_view.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart';

/// Connects a media_kit [Player] and the user's settings to
/// [PlayerControlsView].
class PlayerControls extends StatefulWidget {
  const PlayerControls({
    super.key,
    required this.player,
    required this.settings,
    required this.mediaUrl,
    required this.title,
    required this.onBack,
    required this.fullscreen,
    required this.onToggleFullscreen,
    required this.nextTitle,
    required this.autoNext,
    required this.onPlayNext,
    required this.onCancelAutoNext,
    required this.resumedFrom,
    required this.onStartOver,
  });

  final Player player;
  final SettingsController settings;

  /// The video being played; a change means a new video was opened.
  final Uri mediaUrl;
  final String title;
  final VoidCallback onBack;
  final bool fullscreen;
  final VoidCallback onToggleFullscreen;

  /// Title of the next video in the queue, or `null` at the end of it.
  final String? nextTitle;

  /// Whether the next video starts by itself when this one ends.
  final bool autoNext;
  final VoidCallback onPlayNext;
  final VoidCallback onCancelAutoNext;

  /// Set for a few seconds after a video resumed from a saved position.
  final Duration? resumedFrom;
  final VoidCallback onStartOver;

  @override
  State<PlayerControls> createState() => _PlayerControlsState();
}

class _PlayerControlsState extends State<PlayerControls> {
  /// Furthest the subtitles can be shifted either way, in seconds.
  static const _maxSubtitleDelay = 60.0;

  /// mpv `sub-pos` (percent of the picture height) that clears the bar.
  static const _subtitlePositionAboveControls = '84';

  final _subscriptions = <StreamSubscription<Object?>>[];

  late bool _playing = widget.player.state.playing;
  late bool _buffering = widget.player.state.buffering;
  late Duration _position = widget.player.state.position;
  late Duration _duration = widget.player.state.duration;
  late Duration _buffered = widget.player.state.buffer;
  late Tracks _tracks = widget.player.state.tracks;
  late double _speed = widget.player.state.rate;

  // The chosen level is kept here so muting does not lose it. It starts at
  // the saved level; mute itself is deliberately not remembered, so a new
  // video never starts silent.
  late double _volume = widget.settings.volume;
  bool _muted = false;

  // What libmpv is actually playing (mpv track ids, or "no").
  String _audioId = offId;
  String _subtitleId = offId;

  // Per-video; a new video starts in sync again.
  double _subtitleDelay = 0;
  PlayerNotice? _notice;

  NativePlayer? get _native {
    final platform = widget.player.platform;
    return platform is NativePlayer ? platform : null;
  }

  @override
  void initState() {
    super.initState();
    final stream = widget.player.stream;
    _subscriptions.addAll([
      stream.playing.listen((v) => setState(() => _playing = v)),
      stream.buffering.listen((v) => setState(() => _buffering = v)),
      stream.position.listen((v) => setState(() => _position = v)),
      stream.duration.listen((v) => setState(() => _duration = v)),
      stream.buffer.listen((v) => setState(() => _buffered = v)),
      stream.rate.listen((v) => setState(() => _speed = v)),
      stream.tracks.listen((v) {
        setState(() => _tracks = v);
        unawaited(_refreshSelection());
      }),
      stream.track.listen((_) => unawaited(_refreshSelection())),
    ]);
    _applyVolume();
    unawaited(_setUpTracks());
  }

  @override
  void didUpdateWidget(PlayerControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mediaUrl != widget.mediaUrl) {
      // A subtitle delay belongs to one video; the next starts in sync.
      _subtitleDelay = 0;
      unawaited(_native?.setProperty('sub-delay', '0'));
    }
  }

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    super.dispose();
  }

  // ---- volume and seeking -------------------------------------------------

  void _applyVolume() {
    unawaited(widget.player.setVolume(_muted ? 0 : _volume));
  }

  void _seek(Duration target) {
    // Show the new position at once instead of waiting for libmpv to report
    // it, so the bar does not jump back for a moment (and so repeated skips
    // add up).
    setState(() => _position = target);
    unawaited(widget.player.seek(target));
  }

  void _skip(int seconds) {
    _seek(
      skipTarget(position: _position, duration: _duration, seconds: seconds),
    );
  }

  void _setVolume(double value) {
    setState(() {
      _volume = value;
      _muted = false;
    });
    _applyVolume();
  }

  void _setSpeed(double speed) {
    setState(() => _speed = speed);
    unawaited(widget.player.setRate(speed));
  }

  void _toggleMute() {
    if (!_muted && _volume <= 0) {
      // "Unmuting" a slider dragged to zero restores a usable level.
      setState(() => _volume = 50);
      widget.settings.setVolume(_volume);
    } else {
      setState(() => _muted = !_muted);
    }
    _applyVolume();
  }

  // ---- audio and subtitle tracks ------------------------------------------

  /// Applies the saved subtitle size and starts following which tracks
  /// libmpv has selected (it may pick a default track on its own).
  Future<void> _setUpTracks() async {
    final native = _native;
    if (native == null) return;
    // `scale` lets the size setting apply to styled (ASS) subtitles too.
    await native.setProperty('sub-ass-override', 'scale');
    if (!mounted) return;
    await _applySubtitleScale();
    if (!mounted) return;
    await native.observeProperty('aid', (_) => _refreshSelection());
    if (!mounted) return;
    await native.observeProperty('sid', (_) => _refreshSelection());
    await _refreshSelection();
  }

  Future<void> _refreshSelection() async {
    final native = _native;
    if (native == null || !mounted) return;
    final audioId = await native.getProperty('aid');
    final subtitleId = await native.getProperty('sid');
    if (!mounted) return;
    setState(() {
      _audioId = _normaliseTrackId(audioId);
      _subtitleId = _normaliseTrackId(subtitleId);
    });
  }

  /// libmpv reports "no", "auto" or a number; anything that is not a real
  /// track counts as "off".
  static String _normaliseTrackId(String id) {
    return int.tryParse(id) == null ? offId : id;
  }

  void _selectAudio(String id) {
    setState(() => _audioId = id);
    unawaited(widget.player.setAudioTrack(AudioTrack(id, null, null)));
  }

  void _selectSubtitle(String id) {
    setState(() => _subtitleId = id);
    unawaited(
      widget.player.setSubtitleTrack(
        id == offId ? SubtitleTrack.no() : SubtitleTrack(id, null, null),
      ),
    );
  }

  /// Lets the user pick a subtitle file and loads it. The file is validated
  /// first and only ever handed to the player as a subtitle.
  Future<void> _loadSubtitleFile() async {
    final XFile? picked;
    try {
      picked = await openFile(
        acceptedTypeGroups: const [
          XTypeGroup(label: 'Subtitles', extensions: subtitleFileExtensions),
        ],
      );
    } on Exception {
      _notify('Could not open the file picker');
      return;
    }
    if (picked == null || !mounted) return;

    try {
      final file = await checkSubtitleFile(picked.path);
      if (!mounted) return;
      await widget.player.setSubtitleTrack(
        SubtitleTrack.uri(file.path, title: file.name),
      );
      _notify('Subtitles: ${file.name}');
    } on SubtitleFileError catch (error) {
      _notify(error.message);
    }
  }

  void _notify(String text) {
    if (mounted) setState(() => _notice = PlayerNotice(text));
  }

  Future<void> _applySubtitleScale() async {
    if (!mounted) return;
    final scale = widget.settings.subtitleScalePercent / 100;
    await _native?.setProperty('sub-scale', scale.toStringAsFixed(2));
  }

  void _setSubtitleScale(int percent) {
    widget.settings.setSubtitleScalePercent(percent);
    unawaited(_applySubtitleScale());
  }

  /// Lifts the subtitles above the control bar while it is showing; libmpv
  /// draws them into the picture, so they would otherwise sit underneath.
  void _setControlsShown(bool shown) {
    if (!mounted) return;
    unawaited(
      _native?.setProperty(
        'sub-pos',
        shown ? _subtitlePositionAboveControls : '100',
      ),
    );
  }

  void _setSubtitleDelay(double seconds) {
    // Whole tenths only, so repeated presses cannot drift.
    final tenths = (seconds * 10).round();
    final delay = (tenths / 10).clamp(-_maxSubtitleDelay, _maxSubtitleDelay);
    setState(() => _subtitleDelay = delay);
    unawaited(_native?.setProperty('sub-delay', delay.toStringAsFixed(1)));
  }

  @override
  Widget build(BuildContext context) {
    final settings = widget.settings;
    final nextTitle = widget.nextTitle;
    final secondsToNext = nextTitle != null && widget.autoNext
        ? upNextSecondsLeft(_position, _duration)
        : null;
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) => PlayerControlsView(
        title: widget.title,
        playing: _playing,
        buffering: _buffering,
        position: _position,
        duration: _duration,
        buffered: _buffered,
        volume: _volume,
        muted: _muted,
        seekBackSeconds: settings.seekBackSeconds,
        seekForwardSeconds: settings.seekForwardSeconds,
        onBack: widget.onBack,
        onTogglePlay: () => unawaited(widget.player.playOrPause()),
        onSeek: _seek,
        onSkipBack: () => _skip(-settings.seekBackSeconds),
        onSkipForward: () => _skip(settings.seekForwardSeconds),
        onSeekBackChanged: settings.setSeekBackSeconds,
        onSeekForwardChanged: settings.setSeekForwardSeconds,
        onVolumeChanged: _setVolume,
        // Saved once per drag, not on every pixel of movement.
        onVolumeChangeEnd: settings.setVolume,
        onToggleMute: _toggleMute,
        audioOptions: audioOptions(_tracks.audio),
        selectedAudioId: _audioId,
        onAudioSelected: _selectAudio,
        subtitleOptions: subtitleOptions(_tracks.subtitle),
        selectedSubtitleId: _subtitleId,
        onSubtitleSelected: _selectSubtitle,
        onLoadSubtitle: () => unawaited(_loadSubtitleFile()),
        subtitleScalePercent: settings.subtitleScalePercent,
        onSubtitleScaleChanged: _setSubtitleScale,
        subtitleDelay: _subtitleDelay,
        onSubtitleDelayChanged: _setSubtitleDelay,
        speed: _speed,
        onSpeedChanged: _setSpeed,
        fullscreen: widget.fullscreen,
        onToggleFullscreen: widget.onToggleFullscreen,
        hasNext: nextTitle != null,
        onPlayNext: widget.onPlayNext,
        upNext: secondsToNext == null
            ? null
            : UpNext(title: nextTitle!, secondsLeft: secondsToNext),
        onCancelNext: widget.onCancelAutoNext,
        resumedFrom: widget.resumedFrom,
        onStartOver: widget.onStartOver,
        notice: _notice,
        onControlsShownChanged: _setControlsShown,
      ),
    );
  }
}
