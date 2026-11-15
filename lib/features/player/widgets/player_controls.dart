import 'dart:async';

import 'package:dhara/core/settings/settings_controller.dart';
import 'package:dhara/features/player/playback_info.dart';
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
    this.server,
    this.serverAnswered,
    this.copiesAsked = 0,
    this.copiesAnswered = 0,
    this.startedIn,
    this.optionsNotTaken = const [],
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

  // For the info panel (see [PlaybackInfo]): what the screen knows about
  // the video being played.
  final String? server;
  final Duration? serverAnswered;
  final int copiesAsked;
  final int copiesAnswered;
  final Duration? startedIn;
  final List<String> optionsNotTaken;

  @override
  State<PlayerControls> createState() => _PlayerControlsState();
}

class _PlayerControlsState extends State<PlayerControls> {
  /// Furthest the subtitles can be shifted either way, in seconds.
  static const _maxSubtitleDelay = 60.0;

  /// How often the info panel reads its numbers while it is open.
  static const _infoInterval = Duration(seconds: 1);

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

  // The codecs this libmpv can decode (empty: not known), and whether the
  // current video's sound was already looked at (see [_checkAudio]).
  Set<String> _decoders = const {};
  bool _audioChecked = false;

  // Per-video; a new video starts in sync again.
  double _subtitleDelay = 0;
  PlayerNotice? _notice;

  // What libmpv last answered for the info panel; `null` while the panel
  // is closed (nothing is read then).
  Map<String, String>? _infoValues;
  Timer? _infoTimer;

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
      _audioChecked = false;
      // A subtitle delay belongs to one video; the next starts in sync.
      _subtitleDelay = 0;
      unawaited(_native?.setProperty('sub-delay', '0'));
    }
  }

  @override
  void dispose() {
    _infoTimer?.cancel();
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    super.dispose();
  }

  // ---- info panel ---------------------------------------------------------

  void _toggleInfo() {
    _infoTimer?.cancel();
    if (_infoValues != null) {
      setState(() => _infoValues = null);
      return;
    }
    setState(() => _infoValues = const {});
    unawaited(_readInfo());
    _infoTimer = Timer.periodic(_infoInterval, (_) => unawaited(_readInfo()));
  }

  Future<void> _readInfo() async {
    final native = _native;
    if (native == null) return;
    final values = <String, String>{};
    try {
      for (final name in playbackInfoProperties) {
        values[name] = await native.getProperty(name);
      }
    } on Object {
      // The player is being closed.
      return;
    }
    if (mounted && _infoValues != null) setState(() => _infoValues = values);
  }

  // ---- volume and seeking -------------------------------------------------

  void _applyVolume() {
    unawaited(widget.player.setVolume(_muted ? 0 : _volume));
  }

  /// A jump on the seek bar.
  void _seek(Duration target) => _seekWith(jumpCommand(target), target);

  /// A skip by the seek step (buttons and arrow keys).
  void _skip(int seconds) {
    final target = skipTarget(
      position: _position,
      duration: _duration,
      seconds: seconds,
    );
    _seekWith(
      skipCommand(from: _position, target: target, duration: _duration),
      target,
    );
  }

  /// Sends [command] (mpv's `seek`, see `seek_math.dart`), which leads to
  /// about [target].
  void _seekWith(List<String> command, Duration target) {
    // Show the new position at once instead of waiting for libmpv to report
    // it, so the bar does not jump back for a moment (and so repeated skips
    // add up).
    setState(() => _position = target);
    final native = _native;
    // After the end of a video media_kit has to hear of the seek itself,
    // or it would not report the next end.
    if (native == null || widget.player.state.completed) {
      unawaited(widget.player.seek(target));
    } else {
      unawaited(_command(native, command));
    }
  }

  Future<void> _command(NativePlayer native, List<String> command) async {
    try {
      await native.command(command);
    } on Object {
      // The player is being closed.
    }
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
    _decoders = decodableCodecs(await native.getProperty('decoder-list'));
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
    _checkAudio();
  }

  /// Once per video, when its tracks are known: if libmpv picked a sound
  /// track it has no decoder for (Dolby TrueHD, on a 4K film), another one
  /// is played instead, and the user is told.
  void _checkAudio() {
    final real = _tracks.audio.where((track) => int.tryParse(track.id) != null);
    if (_audioChecked || real.isEmpty) return;
    _audioChecked = true;
    final unplayable = real.where((track) => !canDecode(track, _decoders));
    if (unplayable.isEmpty) return;
    final instead = audioFallback(_tracks.audio, _audioId, _decoders);
    if (instead != null) {
      final label = audioOptions(
        _tracks.audio,
      ).firstWhere((option) => option.id == instead.id).label;
      _selectAudio(instead.id);
      _notify(
        '${audioFormatName(unplayable.first)} sound cannot be played: '
        'switched to $label',
      );
    } else if (real.every((track) => !canDecode(track, _decoders))) {
      _notify(
        'The sound of this video (${audioFormatName(unplayable.first)}) '
        'cannot be played.',
      );
    }
  }

  /// libmpv reports "no", "auto" or a number; anything that is not a real
  /// track counts as "off".
  static String _normaliseTrackId(String id) {
    return int.tryParse(id) == null ? offId : id;
  }

  void _selectAudio(String id) {
    final track = _tracks.audio.where((t) => t.id == id).firstOrNull;
    if (track != null && !canDecode(track, _decoders)) {
      _notify('${audioFormatName(track)} sound cannot be played.');
      return;
    }
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
    final infoValues = _infoValues;
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
        audioOptions: audioOptions(_tracks.audio, decoders: _decoders),
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
        info: infoValues == null
            ? null
            : PlaybackInfo.fromMpv(
                infoValues,
                server: widget.server,
                serverAnswered: widget.serverAnswered,
                copiesAsked: widget.copiesAsked,
                copiesAnswered: widget.copiesAnswered,
                startedIn: widget.startedIn,
                notTaken: widget.optionsNotTaken,
              ),
        onToggleInfo: _toggleInfo,
        onControlsShownChanged: _setControlsShown,
      ),
    );
  }
}
