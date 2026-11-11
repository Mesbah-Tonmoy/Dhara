import 'dart:async';

import 'package:dhara/features/player/widgets/player_controls_view.dart';
import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart';

/// Connects a media_kit [Player] to [PlayerControlsView].
class PlayerControls extends StatefulWidget {
  const PlayerControls({
    super.key,
    required this.player,
    required this.title,
    required this.onBack,
  });

  final Player player;
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

  // The chosen level is kept here so muting does not lose it.
  double _volume = 100;
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
    // it, so the bar does not jump back for a moment.
    setState(() => _position = target);
    unawaited(widget.player.seek(target));
  }

  void _setVolume(double value) {
    setState(() {
      _volume = value;
      _muted = false;
    });
    _applyVolume();
  }

  void _toggleMute() {
    setState(() {
      if (!_muted && _volume <= 0) {
        // "Unmuting" a slider dragged to zero restores a usable level.
        _volume = 50;
      } else {
        _muted = !_muted;
      }
    });
    _applyVolume();
  }

  @override
  Widget build(BuildContext context) {
    return PlayerControlsView(
      title: widget.title,
      playing: _playing,
      buffering: _buffering,
      position: _position,
      duration: _duration,
      buffered: _buffered,
      volume: _volume,
      muted: _muted,
      onBack: widget.onBack,
      onTogglePlay: () => unawaited(widget.player.playOrPause()),
      onSeek: _seek,
      onVolumeChanged: _setVolume,
      onToggleMute: _toggleMute,
    );
  }
}
