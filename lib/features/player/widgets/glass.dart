import 'dart:ui';

import 'package:dhara/theme/tokens.dart';
import 'package:flutter/material.dart';

/// Frosted "glass" surface used for the player's pop-up panels.
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    this.padding = const EdgeInsets.fromLTRB(20, 16, 20, 18),
    required this.child,
  });

  final EdgeInsetsGeometry padding;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(DharaRadii.lg);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: DharaShadows.pop,
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: DharaColors.glassStrong,
              borderRadius: radius,
              border: Border.all(color: DharaColors.strokeStrong),
            ),
            child: Padding(padding: padding, child: child),
          ),
        ),
      ),
    );
  }
}

/// Small upper-case heading at the top of a panel.
class PanelHeading extends StatelessWidget {
  const PanelHeading(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        fontSize: 11.5,
        letterSpacing: 1.6,
        color: DharaColors.text3,
      ),
    );
  }
}

/// Small pill button for cards; [primary] ones carry the accent gradient.
class DharaPillButton extends StatelessWidget {
  const DharaPillButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.primary = false,
  });

  final String label;
  final VoidCallback onPressed;
  final IconData? icon;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final icon = this.icon;
    return Material(
      type: MaterialType.transparency,
      child: Ink(
        height: 30,
        decoration: ShapeDecoration(
          shape: StadiumBorder(
            side: primary
                ? BorderSide.none
                : const BorderSide(color: DharaColors.strokeStrong),
          ),
          color: primary ? null : DharaColors.surface2,
          gradient: primary ? DharaColors.accentGradient : null,
        ),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 13),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 16, color: Colors.white),
                  const SizedBox(width: 4),
                ],
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

const chipTextStyle = TextStyle(fontSize: 11.5, height: 1.2);

/// Pill-shaped choice. [selected] chips get the accent gradient.
class DharaChip extends StatelessWidget {
  const DharaChip({
    super.key,
    this.selected = false,
    required this.child,
    this.onTap,
  });

  final bool selected;
  final VoidCallback? onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
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
            customBorder: const StadiumBorder(),
            hoverColor: DharaColors.surface2,
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 11),
              child: Center(
                widthFactor: 1,
                child: DefaultTextStyle.merge(
                  style: chipTextStyle.copyWith(
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

/// A card with one number: a small heading, the value, and a note below.
class StatCard extends StatelessWidget {
  const StatCard({
    super.key,
    required this.label,
    required this.value,
    required this.note,
    this.valueColor = DharaColors.text,
  });

  final String label;
  final String value;
  final String note;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
      decoration: BoxDecoration(
        color: DharaColors.surface,
        borderRadius: BorderRadius.circular(DharaRadii.md),
        border: Border.all(color: DharaColors.stroke),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PanelHeading(label),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: DharaFonts.display,
              fontSize: 26,
              fontWeight: FontWeight.w700,
              height: 1.25,
              color: valueColor,
            ),
          ),
          Text(
            note,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, color: DharaColors.text2),
          ),
        ],
      ),
    );
  }
}
