import 'dart:async';

import 'package:dhara/theme/tokens.dart';
import 'package:dhara/widgets/icons.dart';
import 'package:dhara/widgets/pressable.dart';
import 'package:dhara/widgets/surfaces.dart';
import 'package:flutter/material.dart';

/// The prototype's `.row`: a heading over one line of cards that scrolls
/// sideways.
///
/// Only the cards in view (and a few next to them) are built. The mouse
/// scrolls with the round buttons that show at the ends of the row while
/// the pointer is over it, or with Shift + wheel; the keyboard moves from
/// card to card with the arrow keys, and the row follows.
class CardRow extends StatefulWidget {
  const CardRow({
    super.key,
    required this.title,
    required this.itemCount,
    required this.itemBuilder,
    this.count,
    this.onSeeAll,
    this.leftInset = 0,
    this.rightInset = DharaLayout.pageRight,
    this.itemWidth = DharaLayout.posterWidth,
    this.itemAspectRatio = 2 / 3,
  });

  final String title;

  /// "148 titles" next to the heading, if given.
  final int? count;

  /// Shows "See all" at the end of the heading.
  final VoidCallback? onSeeAll;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;

  /// How far the heading and the first card start from the left edge.
  final double leftInset;
  final double rightInset;
  final double itemWidth;

  /// Width to height of a card.
  final double itemAspectRatio;

  /// Room above and below the cards for the one under the pointer to grow
  /// and glow in.
  static const padTop = .9 * rem;
  static const padBottom = 1.5 * rem;

  @override
  State<CardRow> createState() => _CardRowState();
}

class _CardRowState extends State<CardRow> {
  final _scroll = ScrollController();
  var _hovered = false;
  var _atStart = true;
  var _atEnd = true;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_measure);
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  @override
  void didUpdateWidget(CardRow old) {
    super.didUpdateWidget(old);
    if (old.itemCount != widget.itemCount) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _measure() {
    if (!mounted || !_scroll.hasClients) return;
    final position = _scroll.position;
    final atStart = position.pixels <= position.minScrollExtent + 1;
    final atEnd = position.pixels >= position.maxScrollExtent - 1;
    if (atStart != _atStart || atEnd != _atEnd) {
      setState(() {
        _atStart = atStart;
        _atEnd = atEnd;
      });
    }
  }

  /// Scrolls most of a screenful to the left (-1) or the right (1).
  void _page(int direction) {
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    final step = position.viewportDimension - widget.itemWidth;
    final target = (position.pixels + direction * step).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    final duration = motion(context, DharaMotion.slow);
    if (duration == Duration.zero) {
      _scroll.jumpTo(target);
    } else {
      unawaited(
        _scroll.animateTo(
          target,
          duration: duration,
          curve: DharaMotion.easeOut,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cardHeight = widget.itemWidth / widget.itemAspectRatio;
    final trackHeight = CardRow.padTop + cardHeight + CardRow.padBottom;
    final count = widget.count;
    final onSeeAll = widget.onSeeAll;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: EdgeInsets.only(
              left: widget.leftInset,
              right: widget.rightInset,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                // The heading and its count take all the room there is, so
                // that "See all" stands at the right edge.
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Flexible(
                        child: Text(
                          widget.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: DharaFonts.display,
                            fontSize: DharaType.lg,
                            fontWeight: DharaType.bold,
                            letterSpacing: -.01 * DharaType.lg,
                            height: DharaType.snug,
                            color: DharaColors.text,
                          ),
                        ),
                      ),
                      if (count != null && count > 0) ...[
                        const SizedBox(width: .7 * rem),
                        Text(
                          '$count ${count == 1 ? 'title' : 'titles'}',
                          style: const TextStyle(
                            fontFamily: DharaFonts.ui,
                            fontSize: DharaType.xs,
                            color: DharaColors.text3,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (onSeeAll != null) _SeeAll(onPressed: onSeeAll),
              ],
            ),
          ),
          SizedBox(
            height: trackHeight,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: ListView.builder(
                    controller: _scroll,
                    scrollDirection: Axis.horizontal,
                    // The card under the pointer grows past its place.
                    clipBehavior: Clip.none,
                    padding: EdgeInsets.only(
                      left: widget.leftInset,
                      // The last card has its own gap after it.
                      right: (widget.rightInset - DharaLayout.cardGap).clamp(
                        0,
                        double.infinity,
                      ),
                      top: CardRow.padTop,
                      bottom: CardRow.padBottom,
                    ),
                    itemExtent: widget.itemWidth + DharaLayout.cardGap,
                    itemCount: widget.itemCount,
                    itemBuilder: (context, index) => Padding(
                      padding: const EdgeInsets.only(
                        right: DharaLayout.cardGap,
                      ),
                      child: widget.itemBuilder(context, index),
                    ),
                  ),
                ),
                _RowNav(
                  key: const Key('row-prev'),
                  icon: DharaIcons.left,
                  label: 'Scroll left',
                  left: widget.leftInset - 1.3 * rem,
                  visible: _hovered && !_atStart,
                  onPressed: () => _page(-1),
                ),
                _RowNav(
                  key: const Key('row-next'),
                  icon: DharaIcons.right,
                  label: 'Scroll right',
                  right: 1 * rem,
                  visible: _hovered && !_atEnd,
                  onPressed: () => _page(1),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// "See all >" at the end of a row's heading.
class _SeeAll extends StatelessWidget {
  const _SeeAll({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Pressable(
    onPressed: onPressed,
    builder: (context, state) {
      final color = state.active ? DharaColors.text : DharaColors.text2;
      return FocusRing(
        visible: state.focused,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'See all',
              style: TextStyle(
                fontFamily: DharaFonts.ui,
                fontSize: DharaType.sm,
                color: color,
              ),
            ),
            AnimatedContainer(
              duration: motion(context, DharaMotion.fast),
              width: (state.active ? .35 : .15) * rem,
            ),
            Icon(DharaIcons.right, size: .9 * rem, color: color),
          ],
        ),
      );
    },
  );
}

/// The prototype's `.row-nav`: a round button at one end of a row, for the
/// mouse only (the keyboard walks the cards themselves).
class _RowNav extends StatefulWidget {
  const _RowNav({
    super.key,
    required this.icon,
    required this.label,
    required this.visible,
    required this.onPressed,
    this.left,
    this.right,
  });

  final IconData icon;
  final String label;
  final bool visible;
  final VoidCallback onPressed;
  final double? left;
  final double? right;

  static const size = 2.6 * rem;

  @override
  State<_RowNav> createState() => _RowNavState();
}

class _RowNavState extends State<_RowNav> {
  var _hovered = false;

  @override
  Widget build(BuildContext context) {
    final visible = widget.visible;
    return Positioned(
      left: widget.left,
      right: widget.right,
      // Centred on the cards, not on the room around them.
      top: 0,
      bottom: CardRow.padBottom - CardRow.padTop,
      child: Center(
        child: IgnorePointer(
          ignoring: !visible,
          child: AnimatedOpacity(
            opacity: visible ? 1 : 0,
            duration: motion(context, DharaMotion.base),
            child: AnimatedScale(
              scale: visible ? 1 : .9,
              duration: motion(context, DharaMotion.base),
              curve: DharaMotion.easeOut,
              child: Semantics(
                button: true,
                label: widget.label,
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  onEnter: (_) => setState(() => _hovered = true),
                  onExit: (_) => setState(() => _hovered = false),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: widget.onPressed,
                    child: AnimatedContainer(
                      duration: motion(context, DharaMotion.fast),
                      width: _RowNav.size,
                      height: _RowNav.size,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        // Solid where the prototype blurs.
                        color: _hovered
                            ? DharaColors.accent
                            : DharaColors.glassStrong,
                        border: Border.all(color: DharaColors.strokeStrong),
                        boxShadow: DharaShadows.card,
                      ),
                      child: Icon(
                        widget.icon,
                        size: 1.3 * rem,
                        color: DharaColors.text,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A row that is still being read: a grey heading over grey cards.
class CardRowSkeleton extends StatelessWidget {
  const CardRowSkeleton({super.key, this.leftInset = 0});

  final double leftInset;

  @override
  Widget build(BuildContext context) {
    const width = DharaLayout.posterWidth;
    return Padding(
      padding: EdgeInsets.only(left: leftInset),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Skeleton(width: 11 * rem, height: 1.3 * rem),
          const SizedBox(height: CardRow.padTop + .26 * rem),
          SizedBox(
            height: width * 1.5 + CardRow.padBottom,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.only(bottom: CardRow.padBottom),
              itemCount: 12,
              separatorBuilder: (_, _) =>
                  const SizedBox(width: DharaLayout.cardGap),
              itemBuilder: (_, _) => const Skeleton(
                width: width,
                height: width * 1.5,
                radius: DharaRadii.md,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
