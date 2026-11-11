import 'dart:async';

import 'package:dhara/core/format/duration_format.dart';
import 'package:dhara/features/player/track_options.dart';
import 'package:dhara/features/player/widgets/seek_bar.dart';
import 'package:dhara/features/player/widgets/seek_step_panel.dart';
import 'package:dhara/features/player/widgets/track_panels.dart';
import 'package:dhara/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
    required this.audioOptions,
    required this.selectedAudioId,
    required this.onAudioSelected,
    required this.subtitleOptions,
    required this.selectedSubtitleId,
    required this.onSubtitleSelected,
    required this.onLoadSubtitle,
    required this.subtitleScalePercent,
    required this.onSubtitleScaleChanged,
    required this.subtitleDelay,
    required this.onSubtitleDelayChanged,
    this.notice,
    this.onControlsShownChanged,
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

  /// Audio tracks of the current file and the id of the active one.
  final List<TrackOption> audioOptions;
  final String selectedAudioId;
  final ValueChanged<String> onAudioSelected;

  /// "Off" plus the subtitle tracks, and the id of the active choice.
  final List<TrackOption> subtitleOptions;
  final String selectedSubtitleId;
  final ValueChanged<String> onSubtitleSelected;

  /// Asks for an external subtitle file to be picked and loaded.
  final VoidCallback onLoadSubtitle;
  final int subtitleScalePercent;
  final ValueChanged<int> onSubtitleScaleChanged;
  final double subtitleDelay;
  final ValueChanged<double> onSubtitleDelayChanged;

  /// Flashed on screen whenever a new instance is passed in.
  final PlayerNotice? notice;

  /// Reports when the control bars appear or disappear (first call: the
  /// initial state), so subtitles can be kept clear of them.
  final ValueChanged<bool>? onControlsShownChanged;
  final Duration hideDelay;

  @override
  State<PlayerControlsView> createState() => _PlayerControlsViewState();
}

class _PlayerControlsViewState extends State<PlayerControlsView> {
  /// How much one press of ↑ / ↓ changes the volume.
  static const _volumeKeyStep = 5.0;
  static const _osdDuration = Duration(milliseconds: 900);

  /// Receives the player's keyboard shortcuts. It wraps every control, so
  /// keys pressed while a button has focus still reach [_onKey].
  final _keyFocus = FocusNode(debugLabel: 'player shortcuts');

  Timer? _hideTimer;
  Timer? _osdTimer;
  bool _awake = true;
  bool _pointerOnControls = false;
  _Panel? _panel;

  // The text stays in place while the pill fades out.
  String _osd = '';
  bool _osdVisible = false;

  /// Paused players always show their controls, and so does an open panel.
  bool get _shown => _awake || !widget.playing || _panel != null;

  // Last value passed to [PlayerControlsView.onControlsShownChanged].
  bool? _reportedShown;

  void _reportShown(bool shown) {
    if (shown == _reportedShown) return;
    _reportedShown = shown;
    // Reported after the frame: listeners may call setState.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onControlsShownChanged?.call(shown);
    });
  }

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
    final notice = widget.notice;
    if (notice != null && !identical(notice, oldWidget.notice)) {
      // setState is not allowed while the parent is rebuilding us.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showOsd(notice.text);
      });
    }
  }

  /// `S`: step through Off → first subtitle track → ... → Off.
  void _cycleSubtitles() {
    final next = nextOption(widget.subtitleOptions, widget.selectedSubtitleId);
    if (next == null) {
      _showOsd('No subtitles');
      return;
    }
    widget.onSubtitleSelected(next.id);
    _showOsd('Subtitles: ${next.label}');
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _osdTimer?.cancel();
    _keyFocus.dispose();
    super.dispose();
  }

  /// Briefly shows [message] near the top of the picture.
  void _showOsd(String message) {
    _osdTimer?.cancel();
    setState(() {
      _osd = message;
      _osdVisible = true;
    });
    _osdTimer = Timer(_osdDuration, () {
      if (mounted) setState(() => _osdVisible = false);
    });
  }

  void _skipBack() {
    widget.onSkipBack();
    _showOsd('− ${widget.seekBackSeconds} s');
  }

  void _skipForward() {
    widget.onSkipForward();
    _showOsd('+ ${widget.seekForwardSeconds} s');
  }

  void _nudgeVolume(double delta) {
    final from = widget.muted ? 0.0 : widget.volume;
    final volume = (from + delta).clamp(0.0, 100.0);
    widget.onVolumeChanged(volume);
    widget.onVolumeChangeEnd(volume);
    _showOsd('Volume ${volume.round()}%');
  }

  void _toggleMute() {
    final silent = widget.muted || widget.volume <= 0;
    widget.onToggleMute();
    _showOsd(silent ? 'Sound on' : 'Muted');
  }

  /// Esc backs out one level: text field, then panel, then the player.
  void _escape() {
    if (_isEditingText) {
      _keyFocus.requestFocus();
    } else if (_panel != null) {
      setState(() => _panel = null);
    } else {
      widget.onBack();
    }
  }

  bool get _isEditingText {
    final context = FocusManager.instance.primaryFocus?.context;
    if (context == null) return false;
    return context.widget is EditableText ||
        context.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  /// Keyboard shortcuts. Arrow keys repeat while held; the others act once
  /// per press.
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final firstPress = event is KeyDownEvent;

    if (key == LogicalKeyboardKey.escape) {
      if (firstPress) _escape();
      return KeyEventResult.handled;
    }
    // While a number is being typed, every other key belongs to the field.
    // ↑ / ↓ mean nothing in a one-line number field, so they are dropped
    // rather than passed on to Flutter's multi-line caret handling.
    if (_isEditingText) {
      final vertical = key == LogicalKeyboardKey.arrowUp ||
          key == LogicalKeyboardKey.arrowDown;
      return vertical ? KeyEventResult.handled : KeyEventResult.ignored;
    }
    // Leave combinations such as Alt+F4 or Ctrl+M to the system.
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isControlPressed ||
        keyboard.isAltPressed ||
        keyboard.isMetaPressed) {
      return KeyEventResult.ignored;
    }

    if (key == LogicalKeyboardKey.space) {
      if (firstPress) widget.onTogglePlay();
    } else if (key == LogicalKeyboardKey.keyM) {
      if (firstPress) _toggleMute();
    } else if (key == LogicalKeyboardKey.keyS) {
      if (firstPress) _cycleSubtitles();
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      _skipBack();
    } else if (key == LogicalKeyboardKey.arrowRight) {
      _skipForward();
    } else if (key == LogicalKeyboardKey.arrowUp) {
      _nudgeVolume(_volumeKeyStep);
    } else if (key == LogicalKeyboardKey.arrowDown) {
      _nudgeVolume(-_volumeKeyStep);
    } else {
      return KeyEventResult.ignored;
    }
    _onActivity();
    return KeyEventResult.handled;
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    if (!widget.playing) return;
    _hideTimer = Timer(widget.hideDelay, () {
      if (!mounted || !widget.playing) return;
      if (_pointerOnControls || _panel != null) {
        _scheduleHide();
        return;
      }
      setState(() => _awake = false);
    });
  }

  /// Opens [panel], or closes it when it is already open. Only one panel is
  /// open at a time.
  void _togglePanel(_Panel panel) {
    _keyFocus.requestFocus();
    setState(() => _panel = _panel == panel ? null : panel);
    _onActivity();
  }

  /// A click on the picture closes an open panel; otherwise it toggles
  /// play/pause. Either way the shortcuts get the keyboard back (this also
  /// ends typing in the panel's custom field).
  void _onPictureTap() {
    _onActivity();
    _keyFocus.requestFocus();
    if (_panel != null) {
      setState(() => _panel = null);
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
    _reportShown(shown);
    return Focus(
      focusNode: _keyFocus,
      autofocus: true,
      onFocusChange: (hasFocus) {
        if (hasFocus) _onActivity();
      },
      onKeyEvent: _onKey,
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
            // Short feedback for skips and volume changes.
            Align(
              alignment: const Alignment(0, -.56),
              child: IgnorePointer(
                child: AnimatedOpacity(
                  key: const Key('osd'),
                  duration: DharaMotion.base,
                  opacity: _osdVisible ? 1 : 0,
                  child: _OsdPill(text: _osd),
                ),
              ),
            ),
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
                        tooltip: 'Back (Esc)',
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
                            tooltip: widget.playing
                                ? 'Pause (Space)'
                                : 'Play (Space)',
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
                            onPressed: _skipBack,
                          ),
                          const SizedBox(width: 4),
                          _SkipButton(
                            key: const Key('skip-forward-button'),
                            seconds: widget.seekForwardSeconds,
                            forward: true,
                            onPressed: _skipForward,
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
                            key: const Key('audio-button'),
                            tooltip: 'Audio track',
                            icon: Icons.graphic_eq_rounded,
                            selected: _panel == _Panel.audio,
                            onPressed: () => _togglePanel(_Panel.audio),
                          ),
                          const SizedBox(width: 4),
                          _ControlButton(
                            key: const Key('subtitles-button'),
                            tooltip: 'Subtitles (S switches track)',
                            icon: Icons.closed_caption_rounded,
                            selected: _panel == _Panel.subtitles,
                            onPressed: () => _togglePanel(_Panel.subtitles),
                          ),
                          const SizedBox(width: 4),
                          _ControlButton(
                            key: const Key('seek-step-button'),
                            tooltip: 'Seek step',
                            icon: Icons.tune_rounded,
                            selected: _panel == _Panel.seekStep,
                            onPressed: () => _togglePanel(_Panel.seekStep),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // The open panel, anchored above the right end of the controls.
            Positioned(
              right: 32,
              bottom: 104,
              left: 32,
              child: Align(
                alignment: Alignment.bottomRight,
                child: AnimatedSwitcher(
                  duration: DharaMotion.base,
                  switchInCurve: DharaMotion.easeOut,
                  layoutBuilder: (current, previous) => Stack(
                    alignment: Alignment.bottomRight,
                    children: [...previous, if (current != null) current],
                  ),
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
                  child: _buildPanel(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPanel() {
    switch (_panel) {
      case null:
        return const SizedBox.shrink();
      case _Panel.audio:
        return ConstrainedBox(
          key: const Key('audio-panel'),
          constraints: const BoxConstraints(maxWidth: 340),
          child: AudioPanel(
            options: widget.audioOptions,
            selectedId: widget.selectedAudioId,
            onSelected: widget.onAudioSelected,
          ),
        );
      case _Panel.subtitles:
        return ConstrainedBox(
          key: const Key('subtitles-panel'),
          constraints: const BoxConstraints(maxWidth: 360),
          child: SubtitlePanel(
            options: widget.subtitleOptions,
            selectedId: widget.selectedSubtitleId,
            onSelected: widget.onSubtitleSelected,
            onLoadFile: widget.onLoadSubtitle,
            scalePercent: widget.subtitleScalePercent,
            onScaleChanged: widget.onSubtitleScaleChanged,
            delaySeconds: widget.subtitleDelay,
            onDelayChanged: widget.onSubtitleDelayChanged,
          ),
        );
      case _Panel.seekStep:
        return ConstrainedBox(
          key: const Key('seek-step-panel'),
          constraints: const BoxConstraints(maxWidth: 520),
          child: SeekStepPanel(
            backSeconds: widget.seekBackSeconds,
            forwardSeconds: widget.seekForwardSeconds,
            onBackChanged: widget.onSeekBackChanged,
            onForwardChanged: widget.onSeekForwardChanged,
          ),
        );
    }
  }
}

/// The pop-up panels of the player; at most one is open.
enum _Panel { audio, subtitles, seekStep }

/// A short message for the player to flash on screen, e.g. the result of
/// loading a subtitle file. A new instance is shown even if the text is the
/// same as the previous one.
class PlayerNotice {
  const PlayerNotice(this.text);

  final String text;
}

/// Glass pill for short on-screen messages such as "+ 30 s".
class _OsdPill extends StatelessWidget {
  const _OsdPill({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xB30A0C16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: DharaColors.stroke),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.w700,
            color: DharaColors.text,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
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
      tooltip: forward ? 'Forward $seconds s (→)' : 'Back $seconds s (←)',
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

/// Mute button plus a volume slider that slides out on hover.
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

  @override
  Widget build(BuildContext context) {
    final silent = widget.muted || widget.volume <= 0;
    final expanded = _hovering;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ControlButton(
            key: const Key('mute-button'),
            tooltip: silent ? 'Unmute (M)' : 'Mute (M)',
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
                // Mouse-only: the slider never takes keyboard focus, so the
                // arrow keys keep their player meaning (↑ / ↓ set the volume).
                child: ExcludeFocus(
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
