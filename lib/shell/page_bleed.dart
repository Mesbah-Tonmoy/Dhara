import 'package:dhara/shell/nav_rail.dart';
import 'package:dhara/shell/shell_controller.dart';
import 'package:dhara/theme/tokens.dart';
import 'package:flutter/widgets.dart';

/// How far the box of a page inside the shell is from the window's edges:
/// it starts below the title bar and to the right of the rail.
abstract final class PageInsets {
  static const left = NavRail.margin + NavRail.width + .5 * rem;
  static const top = DharaLayout.titleBarHeight;

  /// Where a page's content starts inside its box, so that it lines up
  /// with the prototype's page edge.
  static const contentLeft = DharaLayout.pageLeft - left;
}

/// Artwork at the top of a page that runs on under the title bar and the
/// rail, to the window's top-left corner, as the prototype's banner and
/// title backdrop do.
///
/// [height] is that of the artwork, measured from the window's top edge;
/// the page gets a box [PageInsets.top] shorter, with [child] laid out in
/// it. While the artwork is at the top of [scroll] the title bar is told to
/// be clear glass over it (see `ShellController.setArtUnderBar`).
///
/// The page's scroll view must not clip (`Clip.none`), and nothing in the
/// overhang can be clicked: it lies under the title bar and the rail.
class ArtUnderShell extends StatefulWidget {
  const ArtUnderShell({
    super.key,
    required this.height,
    required this.art,
    required this.child,
    this.scroll,
    this.overhangBelow = 0,
  });

  final double height;

  /// Fills the artwork's place, overhang included.
  final Widget art;

  /// What stands on the artwork, within the page's own box.
  final Widget child;

  /// The scroll view of the page, to know when the artwork has gone up.
  final ScrollController? scroll;

  /// How far the artwork also runs on below its box, under what follows.
  final double overhangBelow;

  @override
  State<ArtUnderShell> createState() => _ArtUnderShellState();
}

class _ArtUnderShellState extends State<ArtUnderShell> {
  ShellController? _shell;
  Route<dynamic>? _route;

  @override
  void initState() {
    super.initState();
    widget.scroll?.addListener(_tell);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _shell = ShellScope.maybeRead(context);
    _route = ModalRoute.of(context);
    WidgetsBinding.instance.addPostFrameCallback((_) => _tell());
  }

  @override
  void didUpdateWidget(ArtUnderShell old) {
    super.didUpdateWidget(old);
    if (old.scroll != widget.scroll) {
      old.scroll?.removeListener(_tell);
      widget.scroll?.addListener(_tell);
    }
  }

  @override
  void dispose() {
    widget.scroll?.removeListener(_tell);
    final route = _route;
    if (route != null) _shell?.setArtUnderBar(route, false);
    super.dispose();
  }

  void _tell() {
    final route = _route;
    if (!mounted || route == null) return;
    final scroll = widget.scroll;
    final offset = scroll != null && scroll.hasClients ? scroll.offset : 0.0;
    // Once a bar's height of it has gone, the bar needs its own ground.
    _shell?.setArtUnderBar(route, offset < PageInsets.top);
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    height: widget.height - PageInsets.top - widget.overhangBelow,
    child: Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: -PageInsets.left,
          top: -PageInsets.top,
          right: 0,
          bottom: -widget.overhangBelow,
          child: IgnorePointer(child: widget.art),
        ),
        Positioned(
          left: 0,
          top: 0,
          right: 0,
          bottom: -widget.overhangBelow,
          child: widget.child,
        ),
      ],
    ),
  );
}
