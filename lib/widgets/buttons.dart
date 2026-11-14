import 'package:dhara/theme/tokens.dart';
import 'package:dhara/widgets/pressable.dart';
import 'package:flutter/material.dart';

enum DharaButtonStyle {
  /// The one thing to do on a page (Play): the accent gradient.
  primary,

  /// Everything else: a light pane with a border.
  glass,
}

/// The prototype's `.btn`: a pill with a label, an icon, or both.
class DharaButton extends StatelessWidget {
  const DharaButton({
    super.key,
    required this.onPressed,
    this.label,
    this.icon,
    this.style = DharaButtonStyle.glass,
    this.small = false,
    this.danger = false,
    this.on = false,
    this.autofocus = false,
    this.focusNode,
    this.tooltip,
    this.semanticLabel,
  }) : assert(label != null || icon != null, 'A button needs something on it');

  final VoidCallback? onPressed;

  /// Without a label the button is a circle around its [icon].
  final String? label;
  final IconData? icon;
  final DharaButtonStyle style;
  final bool small;

  /// For removing and clearing things: the label turns red.
  final bool danger;

  /// A toggle that is switched on ("In My List").
  final bool on;
  final bool autofocus;
  final FocusNode? focusNode;
  final String? tooltip;

  /// Needed when there is no [label].
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final label = this.label;
    final icon = this.icon;
    final height = (small ? 2.2 : 2.9) * rem;
    final primary = style == DharaButtonStyle.primary;
    final color = danger
        ? DharaColors.bad
        : primary
        ? DharaColors.onAccent
        : DharaColors.text;

    return Pressable(
      onPressed: onPressed,
      autofocus: autofocus,
      focusNode: focusNode,
      tooltip: tooltip,
      semanticLabel: semanticLabel ?? (label == null ? tooltip : null),
      toggled: on ? true : null,
      builder: (context, state) {
        final hovered = state.hovered && !state.pressed;
        return Opacity(
          opacity: state.enabled ? 1 : .45,
          child: AnimatedScale(
            scale: state.pressed
                ? .98
                : hovered
                ? 1.02
                : 1,
            duration: motion(context, DharaMotion.fast),
            curve: DharaMotion.easeOut,
            child: FocusRing(
              visible: state.focused,
              radius: BorderRadius.circular(DharaRadii.pill),
              child: AnimatedContainer(
                duration: motion(context, DharaMotion.fast),
                height: height,
                width: label == null ? height : null,
                padding: label == null
                    ? EdgeInsets.zero
                    : EdgeInsets.symmetric(
                        horizontal: (small ? .95 : 1.4) * rem,
                      ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(DharaRadii.pill),
                  gradient: primary
                      ? DharaColors.accentGradient
                      : on
                      ? DharaColors.accentSoftGradient
                      : null,
                  color: primary || on
                      ? null
                      : hovered
                      ? _glassHover
                      : DharaColors.surface2,
                  border: primary
                      ? null
                      : Border.all(
                          color: on
                              ? DharaColors.accentStroke
                              : DharaColors.strokeStrong,
                        ),
                  boxShadow: primary
                      ? (hovered ? _primaryGlowHover : _primaryGlow)
                      : null,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (icon != null)
                      Icon(icon, size: (small ? 1 : 1.25) * rem, color: color),
                    if (icon != null && label != null)
                      const SizedBox(width: .5 * rem),
                    if (label != null)
                      Text(
                        label,
                        maxLines: 1,
                        softWrap: false,
                        style: TextStyle(
                          fontFamily: DharaFonts.ui,
                          fontSize: small ? DharaType.sm : DharaType.md,
                          fontWeight: DharaType.semibold,
                          height: 1.2,
                          color: color,
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

const _glassHover = Color(0x2EFFFFFF);
const _primaryGlow = [
  BoxShadow(
    color: Color(0x738B6CFF),
    offset: Offset(0, .6 * rem),
    blurRadius: 1.8 * rem,
  ),
];
const _primaryGlowHover = [
  BoxShadow(
    color: Color(0xA68B6CFF),
    offset: Offset(0, .8 * rem),
    blurRadius: 2.4 * rem,
  ),
];

/// The prototype's `.icon-btn`: a quiet square icon that lights up under
/// the pointer. [large] ones are round and brighter (the player's).
class DharaIconButton extends StatelessWidget {
  const DharaIconButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.large = false,
    this.focusNode,
  });

  final IconData icon;

  /// Shown as a tooltip and read out by screen readers.
  final String label;
  final VoidCallback? onPressed;
  final bool large;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final size = (large ? 2.6 : 2.1) * rem;
    final radius = BorderRadius.circular(large ? size / 2 : DharaRadii.sm);
    return Pressable(
      onPressed: onPressed,
      focusNode: focusNode,
      tooltip: label,
      semanticLabel: label,
      builder: (context, state) => Opacity(
        opacity: state.enabled ? 1 : .4,
        child: FocusRing(
          visible: state.focused,
          radius: radius,
          child: AnimatedContainer(
            duration: motion(context, DharaMotion.fast),
            width: size,
            height: size,
            decoration: BoxDecoration(
              borderRadius: radius,
              color: state.hovered ? DharaColors.surface2 : null,
            ),
            child: Icon(
              icon,
              size: 1.25 * rem,
              color: large || state.hovered
                  ? DharaColors.text
                  : DharaColors.text2,
            ),
          ),
        ),
      ),
    );
  }
}
