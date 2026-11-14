import 'package:dhara/theme/tokens.dart';
import 'package:dhara/widgets/pressable.dart';
import 'package:flutter/material.dart';

/// The prototype's `.chip`: a pill for one choice among a few (a season, a
/// filter). The chosen one carries the soft accent gradient.
class PillChip extends StatelessWidget {
  const PillChip({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.selected = false,
    this.small = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool selected;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final icon = this.icon;
    final radius = BorderRadius.circular(DharaRadii.pill);
    return Pressable(
      onPressed: onPressed,
      selected: selected,
      builder: (context, state) {
        final color = selected
            ? DharaColors.onAccent
            : state.hovered
            ? DharaColors.text
            : DharaColors.text2;
        return FocusRing(
          visible: state.focused,
          radius: radius,
          child: AnimatedContainer(
            duration: motion(context, DharaMotion.fast),
            height: (small ? 1.75 : 2) * rem,
            padding: EdgeInsets.symmetric(
              horizontal: (small ? .65 : .85) * rem,
            ),
            decoration: BoxDecoration(
              borderRadius: radius,
              gradient: selected ? DharaColors.accentSoftGradient : null,
              color: selected
                  ? null
                  : state.hovered
                  ? DharaColors.surface2
                  : DharaColors.surface,
              border: Border.all(
                color: selected ? DharaColors.accentStroke : DharaColors.stroke,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: .95 * rem, color: color),
                  const SizedBox(width: .35 * rem),
                ],
                Text(
                  label,
                  maxLines: 1,
                  softWrap: false,
                  style: TextStyle(
                    fontFamily: DharaFonts.ui,
                    fontSize: small ? DharaType.xs : DharaType.sm,
                    height: 1.2,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// The prototype's `.seg`: a few choices in one pill, exactly one of them
/// chosen (All / Movies / Series, My List / History).
class SegmentedPills<T> extends StatelessWidget {
  const SegmentedPills({
    super.key,
    required this.choices,
    required this.selected,
    required this.onSelected,
  });

  /// Each value with the label it goes by, in order.
  final Map<T, String> choices;
  final T selected;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(DharaRadii.pill);
    return Container(
      padding: const EdgeInsets.all(.2 * rem),
      decoration: BoxDecoration(
        borderRadius: radius,
        color: DharaColors.surface,
        border: Border.all(color: DharaColors.stroke),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final MapEntry(key: value, value: label) in choices.entries)
            Pressable(
              onPressed: () => onSelected(value),
              selected: value == selected,
              builder: (context, state) {
                final on = value == selected;
                return FocusRing(
                  visible: state.focused,
                  radius: radius,
                  child: AnimatedContainer(
                    duration: motion(context, DharaMotion.fast),
                    height: 1.9 * rem,
                    padding: const EdgeInsets.symmetric(horizontal: rem),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      borderRadius: radius,
                      gradient: on ? DharaColors.accentGradient : null,
                    ),
                    child: Text(
                      label,
                      maxLines: 1,
                      softWrap: false,
                      style: TextStyle(
                        fontFamily: DharaFonts.ui,
                        fontSize: DharaType.sm,
                        height: 1.2,
                        fontWeight: on ? DharaType.semibold : DharaType.regular,
                        color: on
                            ? DharaColors.onAccent
                            : state.hovered
                            ? DharaColors.text
                            : DharaColors.text2,
                      ),
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

enum DharaBadgeStyle {
  /// An outline: 1080p, HDR, 5.1.
  plain,

  /// The accent gradient: 4K.
  accent,

  /// Green: the fastest copy, something to continue.
  good,
}

/// The prototype's `.badge`: a few capital letters in a small box.
class DharaBadge extends StatelessWidget {
  const DharaBadge(this.text, {super.key, this.style = DharaBadgeStyle.plain});

  final String text;
  final DharaBadgeStyle style;

  @override
  Widget build(BuildContext context) {
    final good = style == DharaBadgeStyle.good;
    final accent = style == DharaBadgeStyle.accent;
    return Container(
      height: 1.25 * rem,
      padding: const EdgeInsets.symmetric(horizontal: .4 * rem),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(.3 * rem),
        gradient: accent ? DharaColors.accentGradient : null,
        color: good ? const Color(0x1A3DDC97) : null,
        border: accent
            ? null
            : Border.all(
                color: good
                    ? const Color(0x803DDC97)
                    : DharaColors.strokeStrong,
              ),
      ),
      child: Text(
        text,
        maxLines: 1,
        softWrap: false,
        style: TextStyle(
          fontFamily: DharaFonts.ui,
          fontSize: .66 * rem,
          fontWeight: DharaType.bold,
          letterSpacing: .06 * .66 * rem,
          height: 1.2,
          color: good ? DharaColors.good : DharaColors.text,
        ),
      ),
    );
  }
}

/// The prototype's `.sw`: an on/off switch.
class DharaSwitch extends StatelessWidget {
  const DharaSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    required this.label,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;

  /// What it switches, for screen readers.
  final String label;

  @override
  Widget build(BuildContext context) {
    final onChanged = this.onChanged;
    const radius = BorderRadius.all(Radius.circular(rem));
    return Pressable(
      onPressed: onChanged == null ? null : () => onChanged(!value),
      semanticLabel: label,
      toggled: value,
      builder: (context, state) => Opacity(
        opacity: state.enabled ? 1 : .45,
        child: FocusRing(
          visible: state.focused,
          radius: radius,
          child: AnimatedContainer(
            duration: motion(context, DharaMotion.base),
            width: 2.5 * rem,
            height: 1.4 * rem,
            padding: const EdgeInsets.symmetric(horizontal: .15 * rem),
            decoration: BoxDecoration(
              borderRadius: radius,
              gradient: value ? DharaColors.accentGradient : null,
              color: value ? null : DharaColors.surface2,
              border: Border.all(
                color: value
                    ? const Color(0x00000000)
                    : DharaColors.strokeStrong,
              ),
            ),
            child: AnimatedAlign(
              duration: motion(context, DharaMotion.base),
              curve: DharaMotion.easeOut,
              alignment: value ? Alignment.centerRight : Alignment.centerLeft,
              child: const DecoratedBox(
                decoration: BoxDecoration(
                  color: Color(0xFFFFFFFF),
                  shape: BoxShape.circle,
                ),
                child: SizedBox.square(dimension: rem),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
