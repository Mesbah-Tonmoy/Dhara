import 'dart:ui';

import 'package:dhara/core/settings/settings_controller.dart';
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
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(DharaRadii.lg),
        boxShadow: DharaShadows.pop,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(DharaRadii.lg),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: DharaColors.glassStrong,
              borderRadius: BorderRadius.circular(DharaRadii.lg),
              border: Border.all(color: DharaColors.strokeStrong),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'SEEK STEP',
                    style: TextStyle(
                      fontSize: 11.5,
                      letterSpacing: 1.6,
                      color: DharaColors.text3,
                    ),
                  ),
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
            ),
          ),
        ),
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
                _Chip(
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

const _chipTextStyle = TextStyle(fontSize: 11.5, height: 1.2);

class _Chip extends StatelessWidget {
  const _Chip({
    super.key,
    required this.selected,
    required this.child,
    this.onTap,
  });

  final bool selected;
  final VoidCallback? onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    const shape = StadiumBorder();
    return Semantics(
      selected: selected,
      child: Material(
        type: MaterialType.transparency,
        child: Ink(
          height: 28,
          decoration: ShapeDecoration(
            shape: StadiumBorder(
              side: BorderSide(
                color: selected ? DharaColors.accentStroke : DharaColors.stroke,
              ),
            ),
            color: selected ? null : DharaColors.surface,
            gradient: selected ? DharaColors.accentSoftGradient : null,
          ),
          child: InkWell(
            customBorder: shape,
            hoverColor: DharaColors.surface2,
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 11),
              child: Center(
                widthFactor: 1,
                child: DefaultTextStyle.merge(
                  style: _chipTextStyle.copyWith(
                    color: selected ? Colors.white : DharaColors.text2,
                  ),
                  child: child,
                ),
              ),
            ),
          ),
        ),
      ),
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
    return _Chip(
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
                style: _chipTextStyle.copyWith(
                  color: DharaColors.text,
                  fontWeight: FontWeight.w600,
                ),
                decoration: InputDecoration(
                  isCollapsed: true,
                  border: InputBorder.none,
                  hintText: '–',
                  hintStyle: _chipTextStyle.copyWith(color: textColor),
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
