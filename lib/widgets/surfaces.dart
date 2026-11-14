import 'dart:ui';

import 'package:dhara/theme/tokens.dart';
import 'package:flutter/material.dart';

/// The prototype's `.glass-card`: a faint pane with a hairline border that
/// groups a table, a form or a block of facts.
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.blur = false,
    this.radius = DharaRadii.lg,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  /// Blurs what is behind the card. Costly: only for the few panes that
  /// float over artwork, never for cards in a list.
  final bool blur;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final corners = BorderRadius.circular(radius);
    final pane = DecoratedBox(
      decoration: BoxDecoration(
        color: DharaColors.surface,
        borderRadius: corners,
        border: Border.all(color: DharaColors.stroke),
      ),
      child: Padding(padding: padding, child: child),
    );
    return ClipRRect(
      borderRadius: corners,
      child: blur
          ? BackdropFilter(
              filter: ImageFilter.blur(
                sigmaX: DharaBlur.glass,
                sigmaY: DharaBlur.glass,
              ),
              child: pane,
            )
          : pane,
    );
  }
}

/// A grey box with a light sweeping across it, shown where content is
/// still on its way (the prototype's skeleton loaders).
///
/// Give it the size of what it stands in for, or let its parent size it.
class Skeleton extends StatefulWidget {
  const Skeleton({super.key, this.width, this.height, this.radius = .4 * rem});

  final double? width;
  final double? height;
  final double radius;

  /// One sweep of the light.
  static const period = Duration(milliseconds: 1200);

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton>
    with SingleTickerProviderStateMixin {
  late final _sweep = AnimationController(
    vsync: this,
    duration: Skeleton.period,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // No sweep when animations are switched off: a still grey box.
    if (MediaQuery.disableAnimationsOf(context)) {
      _sweep.stop();
    } else if (!_sweep.isAnimating) {
      _sweep.repeat();
    }
  }

  @override
  void dispose() {
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: ClipRRect(
      borderRadius: BorderRadius.circular(widget.radius),
      child: AnimatedBuilder(
        animation: _sweep,
        builder: (context, _) {
          // The light enters at the right edge and leaves at the left.
          final centre = 2 - 4 * _sweep.value;
          return DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment(centre - 2, 0),
                end: Alignment(centre + 2, 0),
                colors: const [
                  DharaColors.surface,
                  DharaColors.surface2,
                  DharaColors.surface,
                ],
                stops: const [.3, .5, .7],
              ),
            ),
            child: SizedBox(width: widget.width, height: widget.height),
          );
        },
      ),
    ),
  );
}

/// What a page shows when it has nothing to list (the prototype's
/// `.empty`): an icon, a short title, and what to do about it.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;

  /// A button below the text, if there is something to do.
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final action = this.action;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4 * rem, horizontal: rem),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 2.6 * rem, color: DharaColors.text3),
          const SizedBox(height: .6 * rem),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: DharaFonts.display,
              fontSize: DharaType.lg,
              fontWeight: DharaType.bold,
              height: DharaType.snug,
              color: DharaColors.text,
            ),
          ),
          const SizedBox(height: .2 * rem),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: DharaFonts.ui,
              fontSize: DharaType.md,
              height: DharaType.body,
              color: DharaColors.text2,
            ),
          ),
          if (action != null) ...[const SizedBox(height: 1.2 * rem), action],
        ],
      ),
    );
  }
}
