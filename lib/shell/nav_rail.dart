import 'dart:ui';

import 'package:dhara/features/browse/browse_controller.dart';
import 'package:dhara/features/browse/browse_store.dart';
import 'package:dhara/shell/shell_controller.dart';
import 'package:dhara/theme/tokens.dart';
import 'package:dhara/widgets/icons.dart';
import 'package:dhara/widgets/pressable.dart';
import 'package:flutter/material.dart';

/// The floating navigation rail on the left: one icon per place, the one
/// in use lit up. The arrow keys move along it.
///
/// Movies and Series are not pages of their own: they open Search with
/// its type set, as the prototype does.
class NavRail extends StatelessWidget {
  const NavRail({super.key});

  /// Its width, and how far it stands from the window's edges.
  static const width = 3.6 * rem;
  static const margin = .85 * rem;

  @override
  Widget build(BuildContext context) {
    final shell = ShellScope.of(context);
    final browse = BrowseScope.of(context);
    final searching = shell.current == ShellDestination.search;
    final typed = browse.query.text.trim().isNotEmpty;
    final kind = browse.query.kind;

    /// Opens Search to browse [kind]; what was typed goes.
    void browseKind(BrowseKind kind) {
      shell.searchText.clear();
      browse
        ..setText('')
        ..change((query) => query.copyWith(kind: kind));
      shell.open(ShellDestination.search);
    }

    Widget button(ShellDestination place) => switch (place) {
      // Lit unless Movies or Series is what is being browsed.
      ShellDestination.search => _RailButton(
        key: const Key('rail-search'),
        label: place.label,
        icon: place.icon,
        selected:
            searching &&
            (typed || (kind != BrowseKind.movies && kind != BrowseKind.series)),
        onPressed: shell.openSearch,
      ),
      // Lit too while one of the tools opened from it is on screen.
      ShellDestination.settings => _RailButton(
        key: const Key('rail-settings'),
        label: place.label,
        icon: place.icon,
        selected: shell.current == place || !shell.current.onRail,
        onPressed: () => shell.open(place),
      ),
      _ => _RailButton(
        key: Key('rail-${place.name}'),
        label: place.label,
        icon: place.icon,
        selected: shell.current == place,
        onPressed: () => shell.open(place),
      ),
    };
    Widget browsing(String name, String label, IconData icon, BrowseKind of) =>
        _RailButton(
          key: Key('rail-$name'),
          label: label,
          icon: icon,
          selected: searching && !typed && kind == of,
          onPressed: () => browseKind(of),
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
                    if (place.onRail && !place.low) ...[
                      button(place),
                      if (place == ShellDestination.search) ...[
                        browsing(
                          'movies',
                          'Movies',
                          DharaIcons.movies,
                          BrowseKind.movies,
                        ),
                        browsing(
                          'series',
                          'Series',
                          DharaIcons.series,
                          BrowseKind.series,
                        ),
                      ],
                    ],
                  const Spacer(),
                  for (final place in ShellDestination.values)
                    if (place.onRail && place.low) button(place),
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
    required this.label,
    required this.icon,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(DharaRadii.md);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: .15 * rem),
      child: Pressable(
        onPressed: onPressed,
        tooltip: label,
        semanticLabel: label,
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
              icon,
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
