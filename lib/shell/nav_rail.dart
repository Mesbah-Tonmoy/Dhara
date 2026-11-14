import 'dart:ui';

import 'package:dhara/shell/shell_controller.dart';
import 'package:dhara/theme/tokens.dart';
import 'package:dhara/widgets/pressable.dart';
import 'package:flutter/material.dart';

/// The floating navigation rail on the left: one icon per place, the one
/// in use lit up. The arrow keys move along it.
class NavRail extends StatelessWidget {
  const NavRail({super.key});

  /// Its width, and how far it stands from the window's edges.
  static const width = 3.6 * rem;
  static const margin = .85 * rem;

  @override
  Widget build(BuildContext context) {
    final shell = ShellScope.of(context);
    Widget button(ShellDestination place) => _RailButton(
      key: Key('rail-${place.name}'),
      place: place,
      selected: shell.current == place,
      onPressed: () => shell.open(place),
    );
    final corners = BorderRadius.circular(DharaRadii.lg);
    return FocusTraversalGroup(
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: corners,
          boxShadow: DharaShadows.card,
        ),
        // Glass: artwork and cards pass under the rail.
        child: ClipRRect(
          borderRadius: corners,
          child: BackdropFilter(
            filter: ImageFilter.blur(
              sigmaX: DharaBlur.glass,
              sigmaY: DharaBlur.glass,
            ),
            child: Container(
              width: width,
              padding: const EdgeInsets.symmetric(vertical: .6 * rem),
              decoration: BoxDecoration(
                color: DharaColors.glass,
                borderRadius: corners,
                border: Border.all(color: DharaColors.stroke),
              ),
              child: Column(
                children: [
                  for (final place in ShellDestination.values)
                    if (!place.low) button(place),
                  const Spacer(),
                  for (final place in ShellDestination.values)
                    if (place.low) button(place),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RailButton extends StatelessWidget {
  const _RailButton({
    super.key,
    required this.place,
    required this.selected,
    required this.onPressed,
  });

  final ShellDestination place;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(DharaRadii.md);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: .15 * rem),
      child: Pressable(
        onPressed: onPressed,
        tooltip: place.label,
        semanticLabel: place.label,
        selected: selected,
        builder: (context, state) => FocusRing(
          visible: state.focused,
          radius: radius,
          child: AnimatedContainer(
            duration: motion(context, DharaMotion.fast),
            width: 2.6 * rem,
            height: 2.6 * rem,
            decoration: BoxDecoration(
              borderRadius: radius,
              gradient: selected ? DharaColors.accentSoftGradient : null,
              color: !selected && state.hovered ? DharaColors.surface2 : null,
              border: selected
                  ? Border.all(color: const Color(0x29FFFFFF))
                  : null,
              boxShadow: selected ? _selectedGlow : null,
            ),
            child: Icon(
              place.icon,
              size: 1.25 * rem,
              color: selected
                  ? DharaColors.onAccent
                  : state.hovered
                  ? DharaColors.text
                  : DharaColors.text2,
            ),
          ),
        ),
      ),
    );
  }
}

const _selectedGlow = [
  BoxShadow(
    color: Color(0x666366F1),
    offset: Offset(0, .4 * rem),
    blurRadius: 1.2 * rem,
  ),
];
