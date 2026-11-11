import 'package:dhara/core/format/duration_format.dart';
import 'package:dhara/theme/tokens.dart';
import 'package:flutter/material.dart';

/// The player's seek bar: buffered and played fills, a knob and a time
/// tooltip on hover, click to seek and drag to scrub.
///
/// While dragging only the bar moves; [onSeek] fires once on release so a
/// network stream is not asked to seek dozens of times per second.
class SeekBar extends StatefulWidget {
  const SeekBar({
    super.key,
    required this.position,
    required this.duration,
    required this.buffered,
    required this.onSeek,
  });

  final Duration position;
  final Duration duration;

  /// How far the stream has been buffered, as an absolute position.
  final Duration buffered;
  final ValueChanged<Duration> onSeek;

  @override
  State<SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<SeekBar> {
  static const _hitHeight = 24.0;
  static const _knobSize = 15.0;
  static const _tipWidth = 64.0;

  bool _hovering = false;
  double? _hoverFraction;
  double? _dragFraction;

  bool get _enabled => widget.duration > Duration.zero;

  double _fractionOf(Duration value) {
    if (!_enabled) return 0;
    return (value.inMilliseconds / widget.duration.inMilliseconds)
        .clamp(0.0, 1.0);
  }

  Duration _timeAt(double fraction) {
    return Duration(
      milliseconds: (widget.duration.inMilliseconds * fraction).round(),
    );
  }

  double _fractionAt(double dx, double width) {
    if (width <= 0) return 0;
    return (dx / width).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final played = _dragFraction ?? _fractionOf(widget.position);
        final buffered = _fractionOf(widget.buffered);
        final active = _enabled && (_hovering || _dragFraction != null);
        final tipFraction = _dragFraction ?? _hoverFraction;

        return Semantics(
          slider: true,
          label: 'Seek',
          value: '${formatDuration(widget.position)} of '
              '${formatDuration(widget.duration)}',
          child: MouseRegion(
            cursor: _enabled ? SystemMouseCursors.click : MouseCursor.defer,
            onEnter: (_) => setState(() => _hovering = true),
            onExit: (_) => setState(() {
              _hovering = false;
              _hoverFraction = null;
            }),
            onHover: (event) => setState(() {
              _hoverFraction = _fractionAt(event.localPosition.dx, width);
            }),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: !_enabled
                  ? null
                  : (details) => widget.onSeek(
                        _timeAt(_fractionAt(details.localPosition.dx, width)),
                      ),
              onHorizontalDragStart: !_enabled
                  ? null
                  : (details) => setState(() {
                        _dragFraction =
                            _fractionAt(details.localPosition.dx, width);
                      }),
              onHorizontalDragUpdate: !_enabled
                  ? null
                  : (details) => setState(() {
                        _dragFraction =
                            _fractionAt(details.localPosition.dx, width);
                      }),
              onHorizontalDragEnd: !_enabled
                  ? null
                  : (_) {
                      final fraction = _dragFraction;
                      setState(() => _dragFraction = null);
                      if (fraction != null) widget.onSeek(_timeAt(fraction));
                    },
              onHorizontalDragCancel: () =>
                  setState(() => _dragFraction = null),
              child: SizedBox(
                height: _hitHeight,
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.centerLeft,
                  children: [
                    AnimatedContainer(
                      duration: DharaMotion.fast,
                      height: active ? 7 : 4,
                      decoration: BoxDecoration(
                        color: const Color(0x33FFFFFF),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          FractionallySizedBox(
                            alignment: Alignment.centerLeft,
                            widthFactor: buffered,
                            child: const ColoredBox(color: Color(0x47FFFFFF)),
                          ),
                          FractionallySizedBox(
                            key: const Key('seek-fill'),
                            alignment: Alignment.centerLeft,
                            widthFactor: played,
                            child: const DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: DharaColors.accentGradient,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Positioned(
                      left: played * width - _knobSize / 2,
                      child: AnimatedScale(
                        duration: DharaMotion.fast,
                        scale: active ? 1 : 0,
                        child: Container(
                          width: _knobSize,
                          height: _knobSize,
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Color(0x598B6CFF),
                                spreadRadius: 5,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (_enabled && tipFraction != null)
                      Positioned(
                        left: (tipFraction * width - _tipWidth / 2).clamp(0.0,
                            width - _tipWidth > 0 ? width - _tipWidth : 0.0),
                        bottom: _hitHeight + 3,
                        width: _tipWidth,
                        child: IgnorePointer(
                          child: Center(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: const Color(0xD9000000),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: DharaColors.stroke),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                child: Text(
                                  formatDuration(_timeAt(tipFraction)),
                                  key: const Key('seek-tip'),
                                  style: const TextStyle(
                                    fontSize: 11.5,
                                    color: DharaColors.text,
                                    fontFeatures: [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
