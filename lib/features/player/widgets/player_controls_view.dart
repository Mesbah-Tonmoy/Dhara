import 'dart:async';

import 'package:dhara/core/format/duration_format.dart';
import 'package:dhara/features/player/widgets/seek_bar.dart';
import 'package:dhara/features/player/widgets/seek_step_panel.dart';
import 'package:dhara/theme/tokens.dart';
import 'package:flutter/material.dart';

/// The player's on-screen controls, drawn over the video.
///
/// Pure UI: it is given the playback state and reports what the user did, so
/// it can be tested without a native player. It owns only the auto-hide
/// behaviour: while playing, the controls (and the mouse cursor) disappear
/// after [hideDelay] without mouse or keyboard activity.
class PlayerControlsView extends StatefulWidget {
  const PlayerControlsView({
    super.key,
    required this.title,
    required this.playing,
    required this.buffering,
    required this.position,
    required this.duration,
    required this.buffered,
    required this.volume,
    required this.muted,
    required this.seekBackSeconds,
    required this.seekForwardSeconds,
    required this.onBack,
    required this.onTogglePlay,
    required this.onSeek,
    required this.onSkipBack,
    required this.onSkipForward,
    required this.onSeekBackChanged,
    required this.onSeekForwardChanged,
    required this.onVolumeChanged,
    required this.onVolumeChangeEnd,
    required this.onToggleMute,
    this.hideDelay = const Duration(seconds: 3),
  });

  /// Server-controlled text; rendered as plain text only.
  final String title;
  final bool playing;
  final bool buffering;
  final Duration position;
  final Duration duration;
  final Duration buffered;

  /// 0–100. Stays at the chosen level while [muted].
  final double volume;
  final bool muted;

  /// Step sizes shown on the skip buttons and in the seek-step panel.
  final int seekBackSeconds;
  final int seekForwardSeconds;

  final VoidCallback onBack;
  final VoidCallback onTogglePlay;
  final ValueChanged<Duration> onSeek;
  final VoidCallback onSkipBack;
  final VoidCallback onSkipForward;
  final ValueChanged<int> onSeekBackChanged;
  final ValueChanged<int> onSeekForwardChanged;
  final ValueChanged<double> onVolumeChanged;

  /// Fired once when a volume drag ends; the place to persist the level.
  final ValueChanged<double> onVolumeChangeEnd;
  final VoidCallback onToggleMute;
  final Duration hideDelay;

  @override
  State<PlayerControlsView> createState() => _PlayerControlsViewState();
}

class _PlayerControlsViewState extends State<PlayerControlsView> {
  Timer? _hideTimer;
  bool _awake = true;
  bool _pointerOnControls = false;
  bool _seekStepPanelOpen = false;

  /// Paused players always show their controls, and so does an open panel.
  bool get _shown => _awake || !widget.playing || _seekStepPanelOpen;

  @override
  void initState() {
    super.initState();
    _scheduleHide();
  }

  @override
  void didUpdateWidget(PlayerControlsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.playing != widget.playing) {
      _awake = true;
      _scheduleHide();
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    if (!widget.playing) return;
    _hideTimer = Timer(widget.hideDelay, () {
      if (!mounted || !widget.playing) return;
      if (_pointerOnControls || _seekStepPanelOpen) {
        _scheduleHide();
        return;
      }
      setState(() => _awake = false);
    });
  }

  void _toggleSeekStepPanel() {
    setState(() => _seekStepPanelOpen = !_seekStepPanelOpen);
    _onActivity();
  }

  /// A click on the picture closes an open panel; otherwise it toggles
  /// play/pause.
  void _onPictureTap() {
    _onActivity();
    if (_seekStepPanelOpen) {
      setState(() => _seekStepPanelOpen = false);
    } else {
      widget.onTogglePlay();
    }
  }

  void _onActivity() {
    if (!_awake) setState(() => _awake = true);
    _scheduleHide();
  }

  void _setPointerOnControls(bool value) {
    _pointerOnControls = value;
    _onActivity();
  }

  @override
  Widget build(BuildContext context) {
    final shown = _shown;
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (hasFocus) {
        if (hasFocus) _onActivity();
      },
      onKeyEvent: (_, __) {
        _onActivity();
        return KeyEventResult.ignored;
      },
      child: MouseRegion(
        cursor: shown ? MouseCursor.defer : SystemMouseCursors.none,
        onEnter: (_) => _onActivity(),
        onHover: (_) => _onActivity(),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Clicking the picture toggles play/pause.
            GestureDetector(
              key: const Key('video-hit-area'),
              behavior: HitTestBehavior.opaque,
              onTap: _onPictureTap,
            ),
            if (widget.buffering)
              const IgnorePointer(
                child: Center(
                  child: SizedBox(
                    width: 48,
                    height: 48,
                    child: CircularProgressIndicator(
                      key: Key('buffering-indicator'),
                      strokeWidth: 3,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            _Scrim(shown: shown, top: true),
            _Scrim(shown: shown, top: false),
            Align(
              alignment: Alignment.topCenter,
              child: _Reveal(
                key: const Key('top-controls'),
                shown: shown,
                hiddenOffset: const Offset(0, -.25),
                onPointer: _setPointerOnControls,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 14, 32, 8),
                  child: Row(
                    children: [
                      _ControlButton(
                        key: const Key('back-button'),
                        tooltip: 'Back',
                        icon: Icons.arrow_back_rounded,
                        onPressed: widget.onBack,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          widget.title,
                          key: const Key('player-title'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            height: 1.2,
                            color: DharaColors.text,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: _Reveal(
                key: const Key('bottom-controls'),
                shown: shown,
                hiddenOffset: const Offset(0, .25),
                onPointer: _setPointerOnControls,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(32, 8, 32, 18),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SeekBar(
                        position: widget.position,
                        duration: widget.duration,
                        buffered: widget.buffered,
                        onSeek: widget.onSeek,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          _ControlButton(
                            key: const Key('play-pause-button'),
                            tooltip: widget.playing ? 'Pause' : 'Play',
                            icon: widget.playing
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                            iconSize: 30,
                            onPressed: widget.onTogglePlay,
                          ),
                          const SizedBox(width: 4),
                          _SkipButton(
                            key: const Key('skip-back-button'),
                            seconds: widget.seekBackSeconds,
                            forward: false,
                            onPressed: widget.onSkipBack,
                          ),
                          const SizedBox(width: 4),
                          _SkipButton(
                            key: const Key('skip-forward-button'),
                            seconds: widget.seekForwardSeconds,
                            forward: true,
                            onPressed: widget.onSkipForward,
                          ),
                          const SizedBox(width: 4),
                          _VolumeControl(
                            volume: widget.volume,
                            muted: widget.muted,
                            onChanged: widget.onVolumeChanged,
                            onChangeEnd: widget.onVolumeChangeEnd,
                            onToggleMute: widget.onToggleMute,
                          ),
                          const SizedBox(width: 10),
                          _TimeLabel(
                            position: widget.position,
                            duration: widget.duration,
                          ),
                          const Spacer(),
                          _ControlButton(
                            key: const Key('seek-step-button'),
                            tooltip: 'Seek step',
                            icon: Icons.tune_rounded,
                            selected: _seekStepPanelOpen,
                            onPressed: _toggleSeekStepPanel,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // Seek-step panel, anchored above the right end of the controls.
            Positioned(
              right: 32,
              bottom: 104,
              left: 32,
              child: Align(
                alignment: Alignment.bottomRight,
                child: AnimatedSwitcher(
                  duration: DharaMotion.base,
                  switchInCurve: DharaMotion.easeOut,
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween(
                        begin: const Offset(0, .06),
                        end: Offset.zero,
                      ).animate(animation),
                      child: child,
                    ),
                  ),
                  child: !_seekStepPanelOpen
                      ? const SizedBox.shrink()
                      : ConstrainedBox(
                          key: const Key('seek-step-panel'),
                          constraints: const BoxConstraints(maxWidth: 520),
                          child: SeekStepPanel(
                            backSeconds: widget.seekBackSeconds,
                            forwardSeconds: widget.seekForwardSeconds,
                            onBackChanged: widget.onSeekBackChanged,
                            onForwardChanged: widget.onSeekForwardChanged,
                          ),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Dark gradient behind a control bar. Never takes pointer events, so clicks
/// next to the controls still reach the video.
class _Scrim extends StatelessWidget {
  const _Scrim({required this.shown, required this.top});

  final bool shown;
  final bool top;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedOpacity(
        duration: DharaMotion.base,
        opacity: shown ? 1 : 0,
        child: Align(
          alignment: top ? Alignment.topCenter : Alignment.bottomCenter,
          child: Container(
            height: top ? 120 : 170,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: top ? Alignment.topCenter : Alignment.bottomCenter,
                end: top ? Alignment.bottomCenter : Alignment.topCenter,
                colors: [
                  Color(top ? 0xC7000000 : 0xE0000000),
                  const Color(0x00000000),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Fades and slides a control bar in and out, and reports whether the mouse
/// is resting on it (the controls must not hide under the pointer).
class _Reveal extends StatelessWidget {
  const _Reveal({
    super.key,
    required this.shown,
    required this.hiddenOffset,
    required this.onPointer,
    required this.child,
  });

  final bool shown;
  final Offset hiddenOffset;
  final ValueChanged<bool> onPointer;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !shown,
      child: AnimatedSlide(
        duration: DharaMotion.base,
        curve: DharaMotion.easeOut,
        offset: shown ? Offset.zero : hiddenOffset,
        child: AnimatedOpacity(
          duration: DharaMotion.base,
          opacity: shown ? 1 : 0,
          child: MouseRegion(
            onEnter: (_) => onPointer(true),
            onExit: (_) => onPointer(false),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  const _ControlButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.iconSize = 24,
    this.selected = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;
  final double iconSize;

  /// Highlights the button while the panel it opens is showing.
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      iconSize: iconSize,
      isSelected: selected,
      icon: Icon(icon),
      style: IconButton.styleFrom(
        foregroundColor: DharaColors.text,
        backgroundColor: selected ? const Color(0x4D8B6CFF) : null,
        hoverColor: const Color(0x24FFFFFF),
        fixedSize: const Size.square(44),
        padding: EdgeInsets.zero,
      ),
    );
  }
}

/// Skip button: a circular arrow with the step size in its centre.
class _SkipButton extends StatelessWidget {
  const _SkipButton({
    super.key,
    required this.seconds,
    required this.forward,
    required this.onPressed,
  });

  final int seconds;
  final bool forward;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: forward ? 'Forward $seconds s' : 'Back $seconds s',
      onPressed: onPressed,
      style: IconButton.styleFrom(
        foregroundColor: DharaColors.text,
        hoverColor: const Color(0x24FFFFFF),
        fixedSize: const Size.square(44),
        padding: EdgeInsets.zero,
      ),
      icon: Stack(
        alignment: Alignment.center,
        children: [
          Transform.flip(
            flipX: forward,
            child: const Icon(Icons.replay_rounded, size: 32),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text(
              '$seconds',
              style: TextStyle(
                fontSize: seconds >= 100 ? 7.5 : 9,
                fontWeight: FontWeight.w800,
                height: 1,
                color: DharaColors.text,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Mute button plus a volume slider that slides out on hover or focus.
class _VolumeControl extends StatefulWidget {
  const _VolumeControl({
    required this.volume,
    required this.muted,
    required this.onChanged,
    required this.onChangeEnd,
    required this.onToggleMute,
  });

  final double volume;
  final bool muted;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;
  final VoidCallback onToggleMute;

  @override
  State<_VolumeControl> createState() => _VolumeControlState();
}

class _VolumeControlState extends State<_VolumeControl> {
  static const _sliderWidth = 104.0;

  bool _hovering = false;
  bool _sliderFocused = false;

  @override
  Widget build(BuildContext context) {
    final silent = widget.muted || widget.volume <= 0;
    final expanded = _hovering || _sliderFocused;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ControlButton(
            key: const Key('mute-button'),
            tooltip: silent ? 'Unmute' : 'Mute',
            icon: silent
                ? Icons.volume_off_rounded
                : widget.volume < 50
                    ? Icons.volume_down_rounded
                    : Icons.volume_up_rounded,
            onPressed: widget.onToggleMute,
          ),
          AnimatedContainer(
            duration: DharaMotion.base,
            curve: DharaMotion.easeOut,
            width: expanded ? _sliderWidth : 0,
            height: 44,
            child: ClipRect(
              child: OverflowBox(
                alignment: Alignment.centerLeft,
                minWidth: _sliderWidth,
                maxWidth: _sliderWidth,
                child: Focus(
                  canRequestFocus: false,
                  skipTraversal: true,
                  onFocusChange: (focused) =>
                      setState(() => _sliderFocused = focused),
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 3,
                      activeTrackColor: Colors.white,
                      inactiveTrackColor: const Color(0x40FFFFFF),
                      thumbColor: Colors.white,
                      overlayColor: const Color(0x1FFFFFFF),
                      thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 6,
                      ),
                      overlayShape: const RoundSliderOverlayShape(
                        overlayRadius: 12,
                      ),
                    ),
                    child: Slider(
                      key: const Key('volume-slider'),
                      max: 100,
                      value: widget.muted ? 0 : widget.volume.clamp(0, 100),
                      semanticFormatterCallback: (value) =>
                          'Volume ${value.round()}%',
                      onChanged: widget.onChanged,
                      onChangeEnd: widget.onChangeEnd,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TimeLabel extends StatelessWidget {
  const _TimeLabel({required this.position, required this.duration});

  final Duration position;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    const base = TextStyle(
      fontSize: 13,
      color: DharaColors.text2,
      fontFeatures: [FontFeature.tabularFigures()],
    );
    return Text.rich(
      key: const Key('time-label'),
      TextSpan(
        style: base,
        children: [
          TextSpan(
            text: formatDuration(position),
            style: const TextStyle(
              color: DharaColors.text,
              fontWeight: FontWeight.w600,
            ),
          ),
          TextSpan(text: ' / ${formatDuration(duration)}'),
        ],
      ),
    );
  }
}
