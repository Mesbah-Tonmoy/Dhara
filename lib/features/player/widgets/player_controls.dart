import 'dart:async';

import 'package:dhara/core/settings/settings_controller.dart';
import 'package:dhara/features/player/seek_math.dart';
import 'package:dhara/features/player/widgets/player_controls_view.dart';
import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart';

/// Connects a media_kit [Player] and the user's settings to
/// [PlayerControlsView].
class PlayerControls extends StatefulWidget {
  const PlayerControls({
    super.key,
    required this.player,
    required this.settings,
    required this.title,
    required this.onBack,
  });

  final Player player;
  final SettingsController settings;
  final String title;
  final VoidCallback onBack;

  @override
  State<PlayerControls> createState() => _PlayerControlsState();
}

class _PlayerControlsState extends State<PlayerControls> {
  final _subscriptions = <StreamSubscription<Object?>>[];

  late bool _playing = widget.player.state.playing;
  late bool _buffering = widget.player.state.buffering;
  late Duration _position = widget.player.state.position;
  late Duration _duration = widget.player.state.duration;
  late Duration _buffered = widget.player.state.buffer;

  // The chosen level is kept here so muting does not lose it. It starts at
  // the saved level; mute itself is deliberately not remembered, so a new
  // video never starts silent.
  late double _volume = widget.settings.volume;
  bool _muted = false;

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
    ]);
    _applyVolume();
  }

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    super.dispose();
  }

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

  @override
  Widget build(BuildContext context) {
    final settings = widget.settings;
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
      ),
    );
  }
}
