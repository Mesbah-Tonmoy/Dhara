import 'package:dhara/core/settings/settings_controller.dart';
import 'package:dhara/features/player/widgets/glass.dart';
import 'package:dhara/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Glass panel for choosing the skip step: separate "Back" and "Forward"
/// values, each picked from presets or typed as a custom number of seconds.
class SeekStepPanel extends StatelessWidget {
  const SeekStepPanel({
    super.key,
    required this.backSeconds,
    required this.forwardSeconds,
    required this.onBackChanged,
    required this.onForwardChanged,
  });

  final int backSeconds;
  final int forwardSeconds;
  final ValueChanged<int> onBackChanged;
  final ValueChanged<int> onForwardChanged;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PanelHeading('Seek step'),
          const SizedBox(height: 12),
          _StepRow(
            id: 'back',
            label: 'Back',
            forward: false,
            seconds: backSeconds,
            onChanged: onBackChanged,
          ),
          const SizedBox(height: 11),
          _StepRow(
            id: 'forward',
            label: 'Forward',
            forward: true,
            seconds: forwardSeconds,
            onChanged: onForwardChanged,
          ),
          const SizedBox(height: 13),
          const Text(
            'Used by the skip buttons and the ← → keys. '
            'Saved automatically.',
            style: TextStyle(fontSize: 11.5, color: DharaColors.text3),
          ),
        ],
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({
    required this.id,
    required this.label,
    required this.forward,
    required this.seconds,
    required this.onChanged,
  });

  /// Used in widget keys: `step-<id>-<preset>` and `step-<id>-custom`.
  final String id;
  final String label;
  final bool forward;
  final int seconds;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 96,
          height: 28,
          child: Row(
            children: [
              Transform.flip(
                flipX: forward,
                child: const Icon(
                  Icons.replay_rounded,
                  size: 16,
                  color: DharaColors.text2,
                ),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.fade,
                  style: const TextStyle(
                    fontSize: 13,
                    color: DharaColors.text2,
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final preset in SettingsController.seekStepPresets)
                DharaChip(
                  key: Key('step-$id-$preset'),
                  selected: seconds == preset,
                  onTap: () => onChanged(preset),
                  child: Text('${preset}s'),
                ),
              _CustomStepChip(
                key: Key('step-$id-custom'),
                label: label,
                seconds: seconds,
                onChanged: onChanged,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// "Custom [  ] s" chip: selected when the value is not one of the presets.
class _CustomStepChip extends StatefulWidget {
  const _CustomStepChip({
    super.key,
    required this.label,
    required this.seconds,
    required this.onChanged,
  });

  final String label;
  final int seconds;
  final ValueChanged<int> onChanged;

  @override
  State<_CustomStepChip> createState() => _CustomStepChipState();
}

class _CustomStepChipState extends State<_CustomStepChip> {
  late final TextEditingController _controller =
      TextEditingController(text: _textFor(widget.seconds));
  final _focusNode = FocusNode();

  bool get _isCustom =>
      !SettingsController.seekStepPresets.contains(widget.seconds);

  String _textFor(int seconds) {
    return SettingsController.seekStepPresets.contains(seconds)
        ? ''
        : '$seconds';
  }

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(_CustomStepChip oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Follow outside changes (a preset was picked), but never fight the
    // user's typing.
    if (!_focusNode.hasFocus && oldWidget.seconds != widget.seconds) {
      _controller.text = _textFor(widget.seconds);
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    // On leaving the field, show the value that is actually in effect
    // (e.g. 999 typed -> 600 applied).
    if (!_focusNode.hasFocus) _controller.text = _textFor(widget.seconds);
  }

  void _onTyped(String text) {
    final seconds = int.tryParse(text);
    if (seconds == null) return;
    widget.onChanged(
      seconds.clamp(
        SettingsController.minSeekStepSeconds,
        SettingsController.maxSeekStepSeconds,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selected = _isCustom;
    final textColor = selected ? Colors.white : DharaColors.text2;
    return DharaChip(
      selected: selected,
      onTap: _focusNode.requestFocus,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Custom'),
          SizedBox(
            width: 40,
            child: Semantics(
              label: '${widget.label} custom seconds',
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                textAlign: TextAlign.center,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(3),
                ],
                cursorColor: DharaColors.accent2,
                cursorHeight: 14,
                style: chipTextStyle.copyWith(
                  color: DharaColors.text,
                  fontWeight: FontWeight.w600,
                ),
                decoration: InputDecoration(
                  isCollapsed: true,
                  border: InputBorder.none,
                  hintText: '–',
                  hintStyle: chipTextStyle.copyWith(color: textColor),
                ),
                onChanged: _onTyped,
                // Enter hands the keyboard back to whatever had it before
                // (the player's shortcuts) instead of leaving nothing focused.
                onEditingComplete: () => _focusNode.unfocus(
                  disposition: UnfocusDisposition.previouslyFocusedChild,
                ),
              ),
            ),
          ),
          const Text('s'),
        ],
      ),
    );
  }
}
