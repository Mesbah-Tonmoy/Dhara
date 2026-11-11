import 'package:dhara/core/settings/settings_controller.dart';
import 'package:dhara/features/player/subtitle_file.dart';
import 'package:dhara/features/player/track_options.dart';
import 'package:dhara/features/player/widgets/glass.dart';
import 'package:dhara/theme/tokens.dart';
import 'package:flutter/material.dart';

/// Panel listing the audio tracks of the current file.
class AudioPanel extends StatelessWidget {
  const AudioPanel({
    super.key,
    required this.options,
    required this.selectedId,
    required this.onSelected,
  });

  final List<TrackOption> options;
  final String selectedId;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      padding: const EdgeInsets.all(10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _Heading('Audio track'),
          if (options.isEmpty)
            const _Note('This video has no audio track.')
          else
            _TrackList(
              keyPrefix: 'audio-option',
              options: options,
              selectedId: selectedId,
              onSelected: onSelected,
            ),
        ],
      ),
    );
  }
}

/// Panel for subtitles: track list, external file, size and delay.
class SubtitlePanel extends StatelessWidget {
  const SubtitlePanel({
    super.key,
    required this.options,
    required this.selectedId,
    required this.onSelected,
    required this.onLoadFile,
    required this.scalePercent,
    required this.onScaleChanged,
    required this.delaySeconds,
    required this.onDelayChanged,
  });

  /// How much one press of a delay chip shifts the subtitles.
  static const delayStepSeconds = 0.1;

  final List<TrackOption> options;
  final String selectedId;
  final ValueChanged<String> onSelected;
  final VoidCallback onLoadFile;

  final int scalePercent;
  final ValueChanged<int> onScaleChanged;

  /// Positive values show subtitles later, negative values earlier.
  final double delaySeconds;
  final ValueChanged<double> onDelayChanged;

  @override
  Widget build(BuildContext context) {
    const min = SettingsController.minSubtitleScalePercent;
    const max = SettingsController.maxSubtitleScalePercent;
    const step = SettingsController.subtitleScaleStepPercent;

    return GlassPanel(
      padding: const EdgeInsets.all(10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _Heading('Subtitles'),
          _TrackList(
            keyPrefix: 'subtitle-option',
            options: options,
            selectedId: selectedId,
            onSelected: onSelected,
          ),
          _Row(
            key: const Key('load-subtitle'),
            onTap: onLoadFile,
            leading: const Icon(
              Icons.upload_file_rounded,
              size: 16,
              color: DharaColors.text2,
            ),
            label: 'Load external subtitle…',
            trailing: subtitleFileExtensions.map((e) => '.$e').join(' '),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 6, horizontal: 10),
            child: Divider(height: 1, color: DharaColors.stroke),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              children: [
                const SizedBox(width: 44, child: _Label('Size')),
                Expanded(
                  // Mouse-only, so the arrow keys keep their player meaning.
                  child: ExcludeFocus(
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 3,
                        activeTrackColor: DharaColors.accent,
                        inactiveTrackColor: const Color(0x40FFFFFF),
                        thumbColor: Colors.white,
                        overlayColor: const Color(0x1FFFFFFF),
                        showValueIndicator: ShowValueIndicator.never,
                        tickMarkShape: SliderTickMarkShape.noTickMark,
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 6,
                        ),
                        overlayShape: const RoundSliderOverlayShape(
                          overlayRadius: 12,
                        ),
                      ),
                      child: Slider(
                        key: const Key('subtitle-size-slider'),
                        min: min.toDouble(),
                        max: max.toDouble(),
                        divisions: (max - min) ~/ step,
                        value: scalePercent.clamp(min, max).toDouble(),
                        semanticFormatterCallback: (value) =>
                            'Subtitle size ${value.round()}%',
                        onChanged: (value) => onScaleChanged(value.round()),
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  width: 44,
                  child: Text(
                    '$scalePercent%',
                    key: const Key('subtitle-size-value'),
                    textAlign: TextAlign.end,
                    style: _valueStyle,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 2, 10, 8),
            child: Row(
              children: [
                const SizedBox(width: 44, child: _Label('Delay')),
                const Spacer(),
                DharaChip(
                  key: const Key('subtitle-delay-minus'),
                  onTap: () => onDelayChanged(delaySeconds - delayStepSeconds),
                  child: const Text('−0.1 s'),
                ),
                SizedBox(
                  width: 68,
                  child: Text(
                    formatSubtitleDelay(delaySeconds),
                    key: const Key('subtitle-delay-value'),
                    textAlign: TextAlign.center,
                    style: _valueStyle,
                  ),
                ),
                DharaChip(
                  key: const Key('subtitle-delay-plus'),
                  onTap: () => onDelayChanged(delaySeconds + delayStepSeconds),
                  child: const Text('+0.1 s'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// `+0.3 s`, `-1.2 s`, or `0.0 s` (never `-0.0 s`).
String formatSubtitleDelay(double seconds) {
  final tenths = (seconds * 10).round();
  if (tenths == 0) return '0.0 s';
  return '${tenths > 0 ? '+' : '-'}${(tenths.abs() / 10).toStringAsFixed(1)} s';
}

const _valueStyle = TextStyle(
  fontSize: 13,
  color: DharaColors.text,
  fontWeight: FontWeight.w600,
  fontFeatures: [FontFeature.tabularFigures()],
);

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 7, 10, 8),
      child: PanelHeading(text),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(fontSize: 13, color: DharaColors.text2),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 2, 10, 10),
      child: Text(
        text,
        style: const TextStyle(fontSize: 13, color: DharaColors.text3),
      ),
    );
  }
}

/// Scrollable list of track choices with a check mark on the active one.
class _TrackList extends StatelessWidget {
  const _TrackList({
    required this.keyPrefix,
    required this.options,
    required this.selectedId,
    required this.onSelected,
  });

  final String keyPrefix;
  final List<TrackOption> options;
  final String selectedId;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 230),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final option in options)
              _Row(
                key: Key('$keyPrefix-${option.id}'),
                selected: option.id == selectedId,
                onTap: () => onSelected(option.id),
                leading: Icon(
                  Icons.check_rounded,
                  size: 16,
                  color: option.id == selectedId
                      ? DharaColors.accent2
                      : Colors.transparent,
                ),
                // Track titles come from the file or server: plain text only.
                label: option.label,
              ),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    super.key,
    required this.onTap,
    required this.leading,
    required this.label,
    this.trailing,
    this.selected = false,
  });

  final VoidCallback onTap;
  final Widget leading;
  final String label;
  final String? trailing;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final trailing = this.trailing;
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(DharaRadii.sm),
          hoverColor: DharaColors.surface2,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            child: Row(
              children: [
                leading,
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      color: selected ? Colors.white : DharaColors.text,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: 10),
                  Text(
                    trailing,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: DharaColors.text3,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
