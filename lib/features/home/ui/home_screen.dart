import 'dart:async';

import 'package:dhara/features/home/home_controller.dart';
import 'package:dhara/features/home/home_store.dart';
import 'package:dhara/features/home/ui/card_row.dart';
import 'package:dhara/features/home/ui/poster_card.dart';
import 'package:dhara/features/indexer/index_controller.dart';
import 'package:dhara/features/metadata/metadata_store.dart';
import 'package:dhara/features/metadata/titles_controller.dart';
import 'package:dhara/features/metadata/tmdb_key.dart';
import 'package:dhara/features/metadata/ui/titles_screen.dart';
import 'package:dhara/features/player/open_url_dialog.dart';
import 'package:dhara/shell/shell_controller.dart';
import 'package:dhara/theme/tokens.dart';
import 'package:dhara/widgets/buttons.dart';
import 'package:dhara/widgets/icons.dart';
import 'package:dhara/widgets/logo.dart';
import 'package:dhara/widgets/surfaces.dart';
import 'package:flutter/material.dart';

/// Opens a film or show from its card.
typedef OpenTitle = void Function(BuildContext context, TitleCard title);

/// Until the details screen is built (the next increments of Phase 6), a
/// card opens the working list of the title's copies.
void _openCopies(BuildContext context, TitleCard title) => unawaited(
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => TitleCopiesScreen(
        title: TitleHit(
          id: title.id,
          kind: title.kind,
          name: title.name,
          year: title.year,
          posterPath: title.posterPath,
          copies: title.videos,
        ),
      ),
    ),
  ),
);

/// Home: the library as rows of posters (Recently Added, Movies, Series,
/// Anime, Top Rated), read by the `HomeController` above it.
///
/// While the library is read for the first time the rows are grey
/// placeholders; with nothing to show yet, Home says what to do first.
/// Titles and file names come from the servers and are only ever drawn as
/// plain text.
class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    this.contentLeft = 1.3 * rem,
    this.onOpenTitle = _openCopies,
  });

  /// How far the content starts from the left edge of the page.
  final double contentLeft;
  final OpenTitle onOpenTitle;

  @override
  Widget build(BuildContext context) {
    final home = HomeScope.of(context);
    final content = home.content;
    final Widget body;
    if (content == null) {
      body = home.failed
          ? _Centered(
              key: const Key('home-failed'),
              left: contentLeft,
              child: const EmptyState(
                icon: DharaIcons.library,
                title: 'The library could not be read',
                message:
                    'Its database did not answer, so there is nothing to '
                    'list in this run. Playing a pasted URL still works.',
                action: _PlayUrlButton(primary: true),
              ),
            )
          : _Loading(left: contentLeft);
    } else if (content.hasNoTitles) {
      body = _Centered(
        key: const Key('home-start'),
        left: contentLeft,
        child: const _GetStarted(),
      );
    } else {
      body = _Rows(
        content: content,
        left: contentLeft,
        onOpenTitle: onOpenTitle,
      );
    }
    return ColoredBox(
      key: const Key('home'),
      color: DharaColors.bg,
      child: body,
    );
  }
}

class _Rows extends StatelessWidget {
  const _Rows({
    required this.content,
    required this.left,
    required this.onOpenTitle,
  });

  final HomeContent content;
  final double left;
  final OpenTitle onOpenTitle;

  @override
  Widget build(BuildContext context) {
    final shell = ShellScope.read(context);
    final counts = TitlesScope.of(context).counts;
    final tmdbKey = TmdbKeyScope.of(context);
    void seeAll() => shell.open(ShellDestination.titles);

    Widget? row(
      String key,
      String title,
      List<TitleCard> cards, {
      int? count,
      VoidCallback? onSeeAll,
      bool ranked = false,
    }) {
      if (cards.isEmpty) return null;
      return Padding(
        padding: const EdgeInsets.only(top: .9 * rem),
        child: CardRow(
          key: Key('home-row-$key'),
          title: title,
          count: count,
          onSeeAll: onSeeAll,
          leftInset: left,
          itemCount: cards.length,
          itemBuilder: (context, index) => PosterCard(
            title: cards[index],
            rank: ranked ? index + 1 : null,
            onOpen: () => onOpenTitle(context, cards[index]),
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.only(top: .9 * rem, bottom: DharaSpace.s7),
      children: [
        if (tmdbKey.isLoaded && !tmdbKey.hasKey && !tmdbKey.unreadable)
          Padding(
            padding: EdgeInsets.only(
              left: left,
              right: DharaLayout.pageRight,
              top: .9 * rem,
            ),
            child: _KeyNotice(onAdd: seeAll),
          ),
        ?row('recent', 'Recently Added', content.recentlyAdded),
        ?row(
          'movies',
          'Movies',
          content.movies,
          count: counts?.movies,
          onSeeAll: seeAll,
        ),
        ?row(
          'series',
          'Series',
          content.series,
          count: counts?.shows,
          onSeeAll: seeAll,
        ),
        ?row('anime', 'Anime', content.anime),
        ?row('top', 'Top Rated', content.topRated, ranked: true),
        Padding(
          padding: EdgeInsets.only(left: left, top: DharaSpace.s5),
          child: const Align(
            alignment: Alignment.centerLeft,
            child: _PlayUrlButton(),
          ),
        ),
      ],
    );
  }
}

/// Without a TMDB key the cards are drawn from the names of the files;
/// says so once, with the way to add a key.
class _KeyNotice extends StatelessWidget {
  const _KeyNotice({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) => GlassCard(
    key: const Key('home-key-notice'),
    radius: DharaRadii.md,
    padding: const EdgeInsets.symmetric(
      horizontal: DharaSpace.s4,
      vertical: DharaSpace.s3,
    ),
    child: Row(
      children: [
        const Icon(DharaIcons.info, size: 1.2 * rem, color: DharaColors.text2),
        const SizedBox(width: DharaSpace.s3),
        const Expanded(
          child: Text(
            'Posters, ratings and descriptions come from TMDB. Add your own '
            'free key to get them; until then titles are named as the files '
            'spell them.',
            style: TextStyle(
              fontFamily: DharaFonts.ui,
              fontSize: DharaType.sm,
              height: DharaType.body,
              color: DharaColors.text2,
            ),
          ),
        ),
        const SizedBox(width: DharaSpace.s4),
        DharaButton(
          key: const Key('home-add-key'),
          label: 'Add TMDB key',
          small: true,
          onPressed: onAdd,
        ),
      ],
    ),
  );
}

class _PlayUrlButton extends StatelessWidget {
  const _PlayUrlButton({this.primary = false});

  final bool primary;

  @override
  Widget build(BuildContext context) => DharaButton(
    key: const Key('home-open-url'),
    label: 'Play a URL',
    icon: DharaIcons.link,
    tooltip: 'Ctrl+O',
    small: !primary,
    style: primary ? DharaButtonStyle.primary : DharaButtonStyle.glass,
    onPressed: () => unawaited(showOpenUrlDialog(context)),
  );
}

/// The rows as grey placeholders, shown only if the first read takes long
/// enough to be noticed: a flash of grey would be worse than a blank
/// moment.
class _Loading extends StatefulWidget {
  const _Loading({required this.left});

  final double left;

  static const delay = Duration(milliseconds: 250);

  @override
  State<_Loading> createState() => _LoadingState();
}

class _LoadingState extends State<_Loading> {
  Timer? _timer;
  var _show = false;

  @override
  void initState() {
    super.initState();
    // Home was never read (the app does so as it starts): read it now.
    final home = HomeScope.read(context);
    if (!home.isLoading) unawaited(home.refresh());
    _timer = Timer(_Loading.delay, () {
      if (mounted) setState(() => _show = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_show) return const SizedBox.expand();
    return ListView(
      key: const Key('home-loading'),
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.only(top: 1.8 * rem),
      children: [
        for (var i = 0; i < 3; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: .9 * rem),
            child: CardRowSkeleton(leftInset: widget.left),
          ),
      ],
    );
  }
}

/// [child] in the middle of the page, scrolling if the window is short.
class _Centered extends StatelessWidget {
  const _Centered({super.key, required this.left, required this.child});

  final double left;
  final Widget child;

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        left,
        DharaSpace.s5,
        DharaLayout.pageRight,
        DharaSpace.s5,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 46 * rem),
        child: child,
      ),
    ),
  );
}

/// What Home shows while the library holds nothing to list: the three
/// steps that fill it, each with where it stands.
class _GetStarted extends StatelessWidget {
  const _GetStarted();

  @override
  Widget build(BuildContext context) {
    final shell = ShellScope.read(context);
    final index = IndexScope.of(context);
    final titles = TitlesScope.of(context);
    final tmdbKey = TmdbKeyScope.of(context);
    final sources = index.sources;

    final enabled = [
      for (final source in sources.sources)
        if (sources.isEnabled(source.id)) source.id,
    ];
    var videos = 0;
    for (final id in enabled) {
      videos += index.statsOf(id)?.files ?? 0;
    }
    final hasServers = enabled.isNotEmpty;
    final hasIndex = videos > 0;

    final String indexNote;
    if (index.isRunning) {
      indexNote =
          'Reading the servers now … this can take a while the '
          'first time.';
    } else if (titles.isReading) {
      indexNote =
          'Reading file names … ${titles.namesRead} of '
          '${titles.namesToRead}.';
    } else if (hasIndex) {
      indexNote = '$videos videos found.';
    } else {
      indexNote =
          'Dhara reads what the enabled servers hold, so that you '
          'can browse and search it. The first time takes a while.';
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const DharaLogo(size: 2.8 * rem),
        const SizedBox(height: DharaSpace.s4),
        const Text(
          'Welcome to Dhara',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: DharaFonts.display,
            fontSize: DharaType.xxl,
            fontWeight: DharaType.bold,
            letterSpacing: -.03 * DharaType.xxl,
            height: 1.1,
            color: DharaColors.text,
          ),
        ),
        const SizedBox(height: DharaSpace.s2),
        const Text(
          'Your library is empty. Three steps fill it.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: DharaFonts.ui,
            fontSize: DharaType.md,
            height: DharaType.body,
            color: DharaColors.text2,
          ),
        ),
        const SizedBox(height: DharaSpace.s5),
        _Step(
          number: 1,
          done: hasServers,
          title: 'Find your servers',
          note: hasServers
              ? '${enabled.length} '
                    '${enabled.length == 1 ? 'server is' : 'servers are'} '
                    'switched on.'
              : 'Test the BDIX servers on the list and switch on the ones '
                    'your connection reaches.',
          action: DharaButton(
            key: const Key('home-step-servers'),
            label: 'Server Discovery',
            icon: DharaIcons.servers,
            small: true,
            autofocus: !hasServers,
            style: hasServers
                ? DharaButtonStyle.glass
                : DharaButtonStyle.primary,
            onPressed: () => shell.open(ShellDestination.discovery),
          ),
        ),
        _Step(
          number: 2,
          done: hasIndex && !index.isRunning && !titles.isReading,
          title: 'Build the index',
          note: indexNote,
          action: DharaButton(
            key: const Key('home-step-index'),
            label: 'Library index',
            icon: DharaIcons.library,
            small: true,
            autofocus: hasServers && !hasIndex,
            style: hasServers && !hasIndex
                ? DharaButtonStyle.primary
                : DharaButtonStyle.glass,
            onPressed: hasServers
                ? () => shell.open(ShellDestination.library)
                : null,
          ),
        ),
        _Step(
          number: 3,
          done: tmdbKey.hasKey,
          title: 'Add a TMDB key',
          note: tmdbKey.hasKey
              ? 'A key is saved. Titles get their posters as they are '
                    'looked up.'
              : 'Optional: posters, ratings and descriptions come from '
                    'TMDB, with your own free key.',
          action: DharaButton(
            key: const Key('home-step-key'),
            label: tmdbKey.hasKey ? 'Films and shows' : 'Add TMDB key',
            small: true,
            onPressed: () => shell.open(ShellDestination.titles),
          ),
        ),
        const SizedBox(height: DharaSpace.s4),
        const _PlayUrlButton(),
      ],
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({
    required this.number,
    required this.done,
    required this.title,
    required this.note,
    required this.action,
  });

  final int number;
  final bool done;
  final String title;
  final String note;
  final Widget action;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: DharaSpace.s3),
    child: GlassCard(
      radius: DharaRadii.md,
      padding: const EdgeInsets.all(DharaSpace.s4),
      child: Row(
        children: [
          Container(
            width: 2 * rem,
            height: 2 * rem,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: done ? const Color(0x1A3DDC97) : DharaColors.surface2,
              border: Border.all(
                color: done ? const Color(0x803DDC97) : DharaColors.stroke,
              ),
            ),
            child: done
                ? Icon(
                    DharaIcons.check,
                    key: Key('home-step-$number-done'),
                    size: 1.1 * rem,
                    color: DharaColors.good,
                  )
                : Text(
                    '$number',
                    style: const TextStyle(
                      fontFamily: DharaFonts.ui,
                      fontSize: DharaType.sm,
                      fontWeight: DharaType.bold,
                      color: DharaColors.text2,
                    ),
                  ),
          ),
          const SizedBox(width: DharaSpace.s4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontFamily: DharaFonts.ui,
                    fontSize: DharaType.md,
                    fontWeight: DharaType.semibold,
                    height: DharaType.snug,
                    color: DharaColors.text,
                  ),
                ),
                const SizedBox(height: .15 * rem),
                Text(
                  note,
                  style: const TextStyle(
                    fontFamily: DharaFonts.ui,
                    fontSize: DharaType.sm,
                    height: DharaType.body,
                    color: DharaColors.text2,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: DharaSpace.s4),
          action,
        ],
      ),
    ),
  );
}
