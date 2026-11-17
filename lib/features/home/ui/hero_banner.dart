import 'package:dhara/core/images/remote_image.dart';
import 'package:dhara/core/settings/settings_controller.dart';
import 'package:dhara/features/home/home_store.dart';
import 'package:dhara/features/home/ui/title_meta.dart';
import 'package:dhara/features/my_list/my_list_controller.dart';
import 'package:dhara/shell/page_bleed.dart';
import 'package:dhara/theme/tokens.dart';
import 'package:dhara/widgets/buttons.dart';
import 'package:dhara/widgets/icons.dart';
import 'package:dhara/widgets/placeholder_art.dart';
import 'package:dhara/widgets/pressable.dart';
import 'package:flutter/material.dart';

/// The prototype's banner at the top of Home (`.heroA`): a few featured
/// titles, one at a time over its backdrop, with Play, My List and More
/// info. Small pictures at the right pick one; left alone, the banner
/// moves on by itself every [DharaMotion.heroInterval].
///
/// It stops moving on while the pointer is over it, and never does when
/// animations are switched off. Scrolled out of the window it holds still
/// altogether, so that a page left further down draws no frames for it.
/// The backdrop runs on under the title bar and the rail (see
/// [ArtUnderShell]).
class HeroBanner extends StatefulWidget {
  const HeroBanner({
    super.key,
    required this.titles,
    required this.onPlay,
    required this.onMore,
    this.resumable = const {},
    this.contentLeft = PageInsets.contentLeft,
    this.scroll,
  }) : assert(titles.length > 0);

  final List<TitleCard> titles;
  final ValueChanged<TitleCard> onPlay;
  final ValueChanged<TitleCard> onMore;

  /// The ids of the titles that have a video left unfinished: their button
  /// says Resume.
  final Set<int> resumable;
  final double contentLeft;

  /// The scroll view of the page the banner is the top of.
  final ScrollController? scroll;

  /// How far the rows after the banner move up over its foot.
  static const overlap = 4.6 * rem;

  /// The banner's height in a window [windowHeight] high.
  static double heightFor(double windowHeight) =>
      (windowHeight * .74).clamp(27 * rem, 48 * rem);

  @override
  State<HeroBanner> createState() => _HeroBannerState();
}

class _HeroBannerState extends State<HeroBanner>
    with SingleTickerProviderStateMixin {
  /// Runs once per title shown; at its end the next one comes.
  late final _turn = AnimationController(
    vsync: this,
    duration: DharaMotion.heroInterval,
  )..addStatusListener(_onTurn);

  var _index = 0;
  var _hovered = false;
  var _still = false;

  /// The "Rotate featured titles" setting.
  var _rotates = true;

  /// The page has scrolled the whole banner out of the window.
  var _away = false;

  @override
  void initState() {
    super.initState();
    widget.scroll?.addListener(_onScroll);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _still = MediaQuery.disableAnimationsOf(context);
    _rotates = SettingsScope.maybeOf(context)?.rotateFeatured ?? true;
    _run();
  }

  @override
  void didUpdateWidget(HeroBanner old) {
    super.didUpdateWidget(old);
    if (old.scroll != widget.scroll) {
      old.scroll?.removeListener(_onScroll);
      widget.scroll?.addListener(_onScroll);
    }
    if (_index >= widget.titles.length) _index = 0;
    _run();
  }

  @override
  void dispose() {
    widget.scroll?.removeListener(_onScroll);
    _turn.dispose();
    super.dispose();
  }

  void _onScroll() {
    final scroll = widget.scroll;
    if (!mounted || scroll == null || !scroll.hasClients) return;
    final height = HeroBanner.heightFor(MediaQuery.sizeOf(context).height);
    final away = scroll.offset >= height;
    if (away == _away) return;
    setState(() => _away = away);
    _run();
  }

  void _onTurn(AnimationStatus status) {
    if (status == AnimationStatus.completed) _show(_index + 1);
  }

  /// Lets the time of the title on show run, or holds it.
  void _run() {
    if (_still || !_rotates || _hovered || _away || widget.titles.length < 2) {
      _turn.stop();
    } else if (!_turn.isAnimating) {
      _turn.forward();
    }
  }

  void _show(int index) {
    setState(() => _index = index % widget.titles.length);
    _turn.value = 0;
    _run();
  }

  void _hover(bool hovered) {
    _hovered = hovered;
    _run();
  }

  @override
  Widget build(BuildContext context) {
    final titles = widget.titles;
    final title = titles[_index];
    final window = MediaQuery.sizeOf(context);
    final slow = _still ? Duration.zero : const Duration(seconds: 10);

    return MouseRegion(
      onEnter: (_) => _hover(true),
      onExit: (_) => _hover(false),
      // Out of the window, the zoom and the fades hold as well.
      child: TickerMode(
        enabled: !_away,
        child: _banner(context, titles, title, window, slow),
      ),
    );
  }

  Widget _banner(
    BuildContext context,
    List<TitleCard> titles,
    TitleCard title,
    Size window,
    Duration slow,
  ) {
    return ArtUnderShell(
      height: HeroBanner.heightFor(window.height),
      overhangBelow: HeroBanner.overlap,
      scroll: widget.scroll,
      // A backdrop is drawn larger than its place while it zooms out, and
      // the shade over it is not: without the clip its edge shows below
      // the banner's foot, over the first row.
      art: ClipRect(
        key: const Key('hero-art'),
        child: Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: DharaColors.bg),
            for (final (index, each) in titles.indexed)
              AnimatedOpacity(
                key: ValueKey('hero-art-${each.id}'),
                opacity: index == _index ? 1 : 0,
                duration: motion(context, DharaMotion.hero),
                curve: DharaMotion.easeInOut,
                child: AnimatedScale(
                  scale: index == _index ? 1 : 1.08,
                  duration: slow,
                  child: TmdbCover(
                    path: each.backdropPath,
                    size: 'w1280',
                    placeholder: PlaceholderArt(seed: each.name, wide: true),
                  ),
                ),
              ),
            const _Shade(),
          ],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            left: widget.contentLeft,
            right: DharaLayout.pageRight,
            bottom: 6.5 * rem,
            child: Align(
              alignment: Alignment.bottomLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 40 * rem),
                child: AnimatedSwitcher(
                  duration: motion(context, DharaMotion.slow),
                  switchInCurve: DharaMotion.easeOut,
                  layoutBuilder: (current, previous) => Stack(
                    alignment: Alignment.bottomLeft,
                    children: [...previous, ?current],
                  ),
                  child: _Body(
                    key: ValueKey(title.id),
                    title: title,
                    resume: widget.resumable.contains(title.id),
                    windowWidth: window.width,
                    onPlay: () => widget.onPlay(title),
                    onMore: () => widget.onMore(title),
                  ),
                ),
              ),
            ),
          ),
          // Only where there is room for it beside the text.
          if (titles.length > 1 && window.width >= 70 * rem)
            Positioned(
              right: DharaLayout.pageRight,
              bottom: 6.5 * rem,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final (index, each) in titles.indexed)
                    Padding(
                      padding: const EdgeInsets.only(left: .6 * rem),
                      child: _Pick(
                        key: Key('hero-pick-$index'),
                        title: each,
                        on: index == _index,
                        turn: _turn,
                        onPressed: () => _show(index),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Fades the backdrop into the page on the left and at the foot, where the
/// text and the first row stand.
class _Shade extends StatelessWidget {
  const _Shade();

  @override
  Widget build(BuildContext context) => const DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: [DharaColors.bg, Color(0xC706070C), Color(0x0006070C)],
        stops: [0, .26, .62],
      ),
    ),
    child: DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [DharaColors.bg, Color(0x8C06070C), Color(0x0006070C)],
          stops: [0, .22, .5],
        ),
      ),
    ),
  );
}

class _Body extends StatelessWidget {
  const _Body({
    super.key,
    required this.title,
    required this.resume,
    required this.windowWidth,
    required this.onPlay,
    required this.onMore,
  });

  final TitleCard title;
  final bool resume;
  final double windowWidth;
  final VoidCallback onPlay;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final overview = title.overview;
    final size = DharaType.display(windowWidth);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Eyebrow(title: title, text: 'Featured today'),
        const SizedBox(height: .7 * rem),
        Text(
          title.name,
          key: const Key('hero-title'),
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontFamily: DharaFonts.display,
            fontSize: size,
            fontWeight: DharaType.bold,
            height: DharaType.tight,
            letterSpacing: DharaType.displayTracking * size,
            color: DharaColors.text,
            shadows: const [
              Shadow(
                color: Color(0x80000000),
                offset: Offset(0, .2 * rem),
                blurRadius: 2 * rem,
              ),
            ],
          ),
        ),
        const SizedBox(height: .9 * rem),
        TitleMeta(title: title),
        if (overview != null && overview.isNotEmpty) ...[
          const SizedBox(height: .9 * rem),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 34 * rem),
            child: Text(
              overview,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: DharaFonts.ui,
                fontSize: DharaType.md,
                height: DharaType.body,
                color: DharaColors.text2,
              ),
            ),
          ),
        ],
        const SizedBox(height: 1.4 * rem),
        Wrap(
          spacing: .7 * rem,
          runSpacing: .7 * rem,
          children: [
            DharaButton(
              key: const Key('hero-play'),
              label: resume ? 'Resume' : 'Play',
              icon: DharaIcons.play,
              style: DharaButtonStyle.primary,
              onPressed: onPlay,
            ),
            MyListButton(title: title.id),
            DharaButton(
              key: const Key('hero-more'),
              icon: DharaIcons.info,
              semanticLabel: 'More info',
              tooltip: 'More info',
              onPressed: onMore,
            ),
          ],
        ),
      ],
    );
  }
}

/// The prototype's My List button: puts a title on the list or takes it
/// off, and shows which it is.
class MyListButton extends StatelessWidget {
  const MyListButton({super.key, required this.title});

  /// The id of the title.
  final int title;

  @override
  Widget build(BuildContext context) {
    final list = MyListScope.of(context);
    final on = list.contains(title);
    return DharaButton(
      key: const Key('my-list-button'),
      label: on ? 'In My List' : 'My List',
      icon: on ? DharaIcons.check : DharaIcons.add,
      on: on,
      onPressed: () => list.toggle(title),
    );
  }
}

/// The prototype's `.pickA`: a small picture of one featured title; the
/// one on show has a line along its foot that fills as its time runs.
class _Pick extends StatelessWidget {
  const _Pick({
    super.key,
    required this.title,
    required this.on,
    required this.turn,
    required this.onPressed,
  });

  final TitleCard title;
  final bool on;
  final Animation<double> turn;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    const corners = BorderRadius.all(Radius.circular(DharaRadii.sm));
    return Pressable(
      onPressed: onPressed,
      semanticLabel: title.name,
      selected: on,
      builder: (context, state) {
        final lit = on || state.active;
        return ExcludeSemantics(
          child: FocusRing(
            visible: state.focused,
            child: AnimatedSlide(
              offset: Offset(0, state.hovered && !on ? -.05 : 0),
              duration: motion(context, DharaMotion.base),
              curve: DharaMotion.easeOut,
              child: AnimatedOpacity(
                opacity: lit ? 1 : .6,
                duration: motion(context, DharaMotion.base),
                child: AnimatedContainer(
                  duration: motion(context, DharaMotion.base),
                  width: 7.2 * rem,
                  height: 7.2 * rem * 9 / 16,
                  foregroundDecoration: BoxDecoration(
                    borderRadius: corners,
                    border: Border.all(
                      color: on ? DharaColors.strokeStrong : DharaColors.stroke,
                    ),
                  ),
                  decoration: BoxDecoration(
                    borderRadius: corners,
                    boxShadow: on ? DharaShadows.glow : null,
                  ),
                  child: ClipRRect(
                    borderRadius: corners,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        TmdbCover(
                          path: title.backdropPath,
                          size: 'w300',
                          placeholder: PlaceholderArt(
                            seed: title.name,
                            wide: true,
                          ),
                        ),
                        if (on)
                          Align(
                            alignment: Alignment.bottomLeft,
                            child: AnimatedBuilder(
                              animation: turn,
                              builder: (context, _) => FractionallySizedBox(
                                widthFactor: turn.value,
                                child: const SizedBox(
                                  height: 3,
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      gradient: DharaColors.accentGradient,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
