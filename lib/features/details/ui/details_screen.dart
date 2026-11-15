import 'dart:async';

import 'package:dhara/core/images/remote_image.dart';
import 'package:dhara/core/settings/settings_controller.dart';
import 'package:dhara/features/details/details_store.dart';
import 'package:dhara/features/details/next_to_play.dart';
import 'package:dhara/features/details/ui/copies_sheet.dart';
import 'package:dhara/features/details/ui/copies_table.dart';
import 'package:dhara/features/details/ui/copy_pings.dart';
import 'package:dhara/features/details/ui/episode_list.dart';
import 'package:dhara/features/home/home_store.dart';
import 'package:dhara/features/home/ui/card_row.dart';
import 'package:dhara/features/home/ui/hero_banner.dart';
import 'package:dhara/features/home/ui/poster_card.dart';
import 'package:dhara/features/home/ui/title_meta.dart';
import 'package:dhara/features/metadata/match_store.dart';
import 'package:dhara/features/metadata/metadata_store.dart';
import 'package:dhara/features/metadata/review_controller.dart';
import 'package:dhara/features/metadata/titles_controller.dart';
import 'package:dhara/features/metadata/ui/needs_review_screen.dart';
import 'package:dhara/features/metadata/video_identity.dart';
import 'package:dhara/features/playback/copy_choice.dart';
import 'package:dhara/features/playback/play.dart';
import 'package:dhara/features/sources/source_store.dart';
import 'package:dhara/features/sources/source_test_controller.dart';
import 'package:dhara/shell/page_bleed.dart';
import 'package:dhara/theme/tokens.dart';
import 'package:dhara/widgets/buttons.dart';
import 'package:dhara/widgets/icons.dart';
import 'package:dhara/widgets/placeholder_art.dart';
import 'package:dhara/widgets/surfaces.dart';
import 'package:dhara/widgets/toast.dart';
import 'package:flutter/material.dart';

/// Opens the page of [title] on top of the page [context] is in.
void openDetails(BuildContext context, TitleCard title) => unawaited(
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => DetailsScreen(titleId: title.id, preview: title),
    ),
  ),
);

/// The language a code stands for, as far as the app has a name for it.
String languageName(String code) =>
    const {
      'en': 'English',
      'bn': 'Bangla',
      'hi': 'Hindi',
      'ur': 'Urdu',
      'ta': 'Tamil',
      'te': 'Telugu',
      'ml': 'Malayalam',
      'kn': 'Kannada',
      'ja': 'Japanese',
      'ko': 'Korean',
      'zh': 'Chinese',
      'cn': 'Cantonese',
      'es': 'Spanish',
      'fr': 'French',
      'de': 'German',
      'it': 'Italian',
      'ru': 'Russian',
      'tr': 'Turkish',
      'ar': 'Arabic',
      'fa': 'Persian',
      'th': 'Thai',
      'id': 'Indonesian',
      'pt': 'Portuguese',
    }[code] ??
    code.toUpperCase();

/// The page of one film or show (the prototype's title details): its
/// backdrop under soft glass, poster, what is known about it, Play and My
/// List, every copy the enabled servers hold, and more titles like it.
///
/// A show lists its episodes by season instead; each plays with a click
/// (the ones after it follow) and lists its own copies in a side sheet.
///
/// [preview] is what the card that led here already knew; it is shown at
/// once, while the rest is read. Names, descriptions and file names come
/// from outside and are drawn as plain text only.
class DetailsScreen extends StatefulWidget {
  const DetailsScreen({super.key, required this.titleId, this.preview});

  final int titleId;
  final TitleCard? preview;

  @override
  State<DetailsScreen> createState() => _DetailsScreenState();
}

class _DetailsScreenState extends State<DetailsScreen> {
  final _scroll = ScrollController();
  final _copiesKey = GlobalKey();

  TitlePage? _page;
  var _asked = false;
  var _loaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_asked) return;
    _asked = true;
    unawaited(_load());
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final page = await TitlesScope.read(context).page(widget.titleId);
    if (!mounted) return;
    setState(() {
      _page = page;
      _loaded = true;
    });
  }

  Future<void> _play(TitleCopy copy) async {
    final page = _page;
    if (page == null) return;
    await playCopy(
      context,
      name: page.title.name,
      year: page.title.year,
      copy: copy,
      copies: page.copies,
      sources: TitlesScope.read(context).index.sources,
    );
    // What was watched shows on the page.
    if (mounted) await _load();
  }

  void _playNext() {
    final page = _page;
    if (page == null) return;
    final choice = nextToPlay(
      page,
      TitlesScope.read(context).index.sources,
      preferred: SettingsScope.read(context).preferredQuality,
    );
    if (choice == null) {
      ToastHost.show(
        context,
        page.copies.isEmpty
            ? 'is not on an enabled server any more.'
            : 'has no copy that can be played from here.',
        lead: page.title.name,
      );
      return;
    }
    unawaited(_play(choice.copy));
  }

  /// Plays an episode: on from where a copy of it was left, or else its
  /// best copy.
  void _playEpisode(EpisodeKey episode) {
    final page = _page;
    if (page == null) return;
    final sources = TitlesScope.read(context).index.sources;
    final copies = episodesIn(page.copies)[episode] ?? const <TitleCopy>[];
    TitleCopy? copy;
    Watched? seen;
    for (final each in copies) {
      final watched = page.watched['${each.url}'];
      if (watched == null || watched.finished) continue;
      if (!canPlayCopy(each, sources)) continue;
      if (seen == null || watched.at.isAfter(seen.at)) {
        copy = each;
        seen = watched;
      }
    }
    copy ??= bestCopy(
      copies,
      sources,
      preferred: SettingsScope.read(context).preferredQuality,
    );
    if (copy == null) {
      ToastHost.show(
        context,
        'has no copy that can be played from here.',
        lead: episodeCode(episode.$1, episode.$2),
      );
      return;
    }
    unawaited(_play(copy));
  }

  /// Lists the copies of an episode in the side sheet and plays the one
  /// that is picked there.
  Future<void> _showEpisodeCopies(EpisodeKey episode) async {
    final page = _page;
    if (page == null) return;
    final copies = episodesIn(page.copies)[episode] ?? const <TitleCopy>[];
    String? name;
    for (final copy in copies) {
      name ??= copy.episodeName;
    }
    final chosen = await showCopiesSheet(
      context,
      title: page.title.name,
      subtitle: [
        episodeCode(episode.$1, episode.$2),
        ?name,
        'the best copy first',
      ].join(' · '),
      copies: copies,
      watched: page.watched,
    );
    if (chosen != null && mounted) await _play(chosen);
  }

  void _showCopies() {
    final target = _copiesKey.currentContext;
    if (target == null) return;
    unawaited(
      Scrollable.ensureVisible(
        target,
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : DharaMotion.slow,
        curve: DharaMotion.easeOut,
      ),
    );
  }

  Future<void> _fixMatch() async {
    final item = await ReviewScope.read(context).itemFor(widget.titleId);
    if (!mounted) return;
    if (item == null) {
      ToastHost.show(
        context,
        'A title needs a video on an enabled server to be looked up.',
      );
      return;
    }
    await showReviewDialog(context, item);
    if (!mounted) return;
    await _load();
    // Now another title's film: this page has nothing left to show.
    if (mounted && _page == null) unawaited(Navigator.of(context).maybePop());
  }

  @override
  Widget build(BuildContext context) {
    // Re-ranks the copies when a server test ends.
    final sources = SourcesScope.of(context).store;
    final page = _page;
    final title = page?.title ?? widget.preview;

    if (title == null) {
      return ColoredBox(
        key: const Key('details'),
        color: DharaColors.bg,
        child: _loaded
            ? Center(
                child: EmptyState(
                  key: const Key('details-gone'),
                  icon: DharaIcons.movies,
                  title: 'This title is not in the library any more',
                  message:
                      'Its videos are gone from every server, or it became '
                      'part of another title.',
                  action: DharaButton(
                    label: 'Back',
                    icon: DharaIcons.back,
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                ),
              )
            : const SizedBox.expand(),
      );
    }

    final choice = page == null
        ? null
        : nextToPlay(
            page,
            sources,
            preferred: SettingsScope.of(context).preferredQuality,
          );
    final next = choice == null ? null : episodeOf(choice.copy);
    final series = title.kind == TitleKind.series;
    final episodes = page == null || !series
        ? const <EpisodeKey, List<TitleCopy>>{}
        : episodesIn(page.copies);
    // What a show holds besides its episodes; all there is of a film.
    final others = page == null
        ? const <TitleCopy>[]
        : [
            for (final copy in page.copies)
              if (episodes.isEmpty ||
                  episodeOf(copy) == null ||
                  copy.extra != null)
                copy,
          ];
    return ColoredBox(
      key: const Key('details'),
      color: DharaColors.bg,
      child: ListView(
        controller: _scroll,
        // The backdrop runs on under the title bar and the rail.
        clipBehavior: Clip.none,
        padding: const EdgeInsets.only(bottom: DharaSpace.s7),
        children: [
          ArtUnderShell.behind(
            height: 36 * rem,
            scroll: _scroll,
            art: _Backdrop(title: title),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                PageInsets.contentLeft,
                2.4 * rem,
                DharaLayout.pageRight,
                0,
              ),
              child: _Top(
                title: title,
                page: page,
                choice: choice,
                onPlay: page == null ? null : _playNext,
                onShowCopies: _showCopies,
                onEpisodeCopies: next == null || episodes.isEmpty
                    ? null
                    : () => unawaited(_showEpisodeCopies(next)),
                onFixMatch: _fixMatch,
              ),
            ),
          ),
          Padding(
            key: _copiesKey,
            padding: const EdgeInsets.fromLTRB(
              PageInsets.contentLeft,
              2.2 * rem,
              DharaLayout.pageRight,
              0,
            ),
            // Read in a moment: no grey flash for it, only its room.
            child: page == null
                ? const SizedBox(height: 12 * rem)
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (episodes.isNotEmpty)
                        EpisodeList(
                          page: page,
                          sources: sources,
                          next: next,
                          onPlay: _playEpisode,
                          onCopies: (episode) =>
                              unawaited(_showEpisodeCopies(episode)),
                        ),
                      if (episodes.isNotEmpty && others.isNotEmpty)
                        const SizedBox(height: 2.2 * rem),
                      if (episodes.isEmpty || others.isNotEmpty)
                        _Copies(
                          page: page,
                          copies: others,
                          heading: episodes.isEmpty
                              ? (series ? 'Videos' : 'Copies')
                              : 'Other videos',
                          sources: sources,
                          onPlay: _play,
                        ),
                    ],
                  ),
          ),
          if (page != null && page.similar.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2.4 * rem),
              child: CardRow(
                key: const Key('details-similar'),
                title: 'More like this',
                leftInset: PageInsets.contentLeft,
                itemCount: page.similar.length,
                itemBuilder: (context, index) => PosterCard(
                  title: page.similar[index],
                  onOpen: () => openDetails(context, page.similar[index]),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The prototype's `.detail-bg`: the backdrop, soft and faded into the
/// page, as the ground the top of the page stands on.
class _Backdrop extends StatelessWidget {
  const _Backdrop({required this.title});

  final TitleCard title;

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      const ColoredBox(color: DharaColors.bg),
      // Soft without a blur filter: the smallest size of the picture,
      // stretched over the whole width. A blur filter over the full-size
      // picture left white specks in its black parts on Windows, and costs
      // more.
      TmdbCover(
        path: title.backdropPath,
        size: 'w300',
        placeholder: PlaceholderArt(seed: title.name, wide: true),
      ),
      const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [DharaColors.bg, Color(0xBD06070C), Color(0x4D06070C)],
            stops: [0, .38, 1],
          ),
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [DharaColors.bg, DharaColors.bg, Color(0x0006070C)],
              stops: [0, .02, .62],
            ),
          ),
        ),
      ),
    ],
  );
}

/// The prototype's `.detail-top`: the poster, and beside it the title with
/// what is known about it and what can be done with it.
class _Top extends StatelessWidget {
  const _Top({
    required this.title,
    required this.page,
    required this.choice,
    required this.onPlay,
    required this.onShowCopies,
    required this.onEpisodeCopies,
    required this.onFixMatch,
  });

  final TitleCard title;

  /// `null` while it is being read.
  final TitlePage? page;
  final PlayChoice? choice;
  final VoidCallback? onPlay;
  final VoidCallback onShowCopies;

  /// Lists the copies of the episode Play would play; `null` for a film.
  final VoidCallback? onEpisodeCopies;
  final VoidCallback onFixMatch;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final size = (width * .036).clamp(2.2 * rem, 4.6 * rem);
    final overview = title.overview;
    final page = this.page;
    final copies = page?.copies.where((copy) => copy.extra == null).length;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The poster makes way in a narrow window.
        if (width >= 62 * rem) ...[
          SizedBox(
            width: 15.5 * rem,
            child: _Poster(title: title),
          ),
          const SizedBox(width: 2.4 * rem),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Eyebrow(
                title: title,
                text: title.genres.isEmpty
                    ? (title.kind == TitleKind.series ? 'Show' : 'Film')
                    : title.genres.join(', '),
              ),
              const SizedBox(height: .6 * rem),
              Text(
                title.name,
                key: const Key('details-title'),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: DharaFonts.display,
                  fontSize: size,
                  fontWeight: DharaType.bold,
                  height: 1.04,
                  letterSpacing: DharaType.displayTracking * size,
                  color: DharaColors.text,
                ),
              ),
              const SizedBox(height: .8 * rem),
              TitleMeta(title: title),
              if (overview != null && overview.isNotEmpty) ...[
                const SizedBox(height: .9 * rem),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 46 * rem),
                  child: Text(
                    overview,
                    key: const Key('details-overview'),
                    style: const TextStyle(
                      fontFamily: DharaFonts.ui,
                      fontSize: 1.02 * rem,
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
                    key: const Key('details-play'),
                    label: choice?.label ?? 'Play',
                    icon: DharaIcons.play,
                    style: DharaButtonStyle.primary,
                    autofocus: true,
                    onPressed: onPlay,
                  ),
                  MyListButton(title: title.id),
                  if (onEpisodeCopies != null && choice != null)
                    DharaButton(
                      key: const Key('details-copies'),
                      label:
                          'Copies for '
                          '${episodeCode(choice!.copy.season, choice!.copy.episode!)}',
                      icon: DharaIcons.list,
                      onPressed: onEpisodeCopies,
                    )
                  else if (copies != null && copies > 0)
                    DharaButton(
                      key: const Key('details-copies'),
                      label: title.kind == TitleKind.series
                          ? holdingsLabel(title)
                          : '$copies ${copies == 1 ? 'copy' : 'copies'}',
                      icon: DharaIcons.list,
                      onPressed: onShowCopies,
                    ),
                ],
              ),
              if (page != null) ...[
                const SizedBox(height: 1.6 * rem),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 60 * rem),
                  child: _Facts(page: page, onFixMatch: onFixMatch),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// The prototype's `.detail-poster`.
class _Poster extends StatefulWidget {
  const _Poster({required this.title});

  final TitleCard title;

  @override
  State<_Poster> createState() => _PosterState();
}

class _PosterState extends State<_Poster> {
  var _hasPoster = false;

  @override
  Widget build(BuildContext context) {
    const corners = BorderRadius.all(Radius.circular(DharaRadii.lg));
    final title = widget.title;
    return AspectRatio(
      aspectRatio: 2 / 3,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          borderRadius: corners,
          boxShadow: DharaShadows.pop,
        ),
        child: Container(
          foregroundDecoration: BoxDecoration(
            borderRadius: corners,
            border: Border.all(color: DharaColors.strokeStrong),
          ),
          child: ClipRRect(
            borderRadius: corners,
            child: Stack(
              fit: StackFit.expand,
              children: [
                TmdbCover(
                  path: title.posterPath,
                  size: 'w500',
                  placeholder: PlaceholderArt(seed: title.name),
                  onPicture: (showing) {
                    if (mounted && showing != _hasPoster) {
                      setState(() => _hasPoster = showing);
                    }
                  },
                ),
                if (!_hasPoster)
                  Positioned(
                    left: rem,
                    right: rem,
                    bottom: 1.2 * rem,
                    child: Text(
                      title.name.toUpperCase(),
                      textAlign: TextAlign.center,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: DharaFonts.display,
                        fontSize: 1.05 * rem,
                        fontWeight: DharaType.bold,
                        height: 1.15,
                        letterSpacing: .14 * 1.05 * rem,
                        color: DharaColors.text,
                        shadows: [
                          Shadow(
                            color: Color(0xB3000000),
                            offset: Offset(0, .1 * rem),
                            blurRadius: .6 * rem,
                          ),
                        ],
                      ),
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

/// The prototype's `.facts`: a few facts in a glass card.
class _Facts extends StatelessWidget {
  const _Facts({required this.page, required this.onFixMatch});

  final TitlePage page;
  final VoidCallback onFixMatch;

  @override
  Widget build(BuildContext context) {
    final languages = <String>{
      for (final copy in page.copies) ...copy.languages,
    };
    final original = page.originalName;
    final language = page.language;
    final match = switch (page.matchState) {
      MatchState.matched => 'Matched on TMDB',
      MatchState.unsure => 'Matched on TMDB, not surely',
      MatchState.notFound => 'Not found on TMDB',
      MatchState.byHand => 'Matched by you',
      MatchState.leftAlone => 'Left as the files name it',
      _ => 'Not looked up yet',
    };
    Widget fact(String name, Widget value, {int flex = 1}) => Expanded(
      flex: flex,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            name.toUpperCase(),
            style: const TextStyle(
              fontFamily: DharaFonts.ui,
              fontSize: DharaType.xs,
              letterSpacing: .12 * DharaType.xs,
              color: DharaColors.text3,
            ),
          ),
          const SizedBox(height: .2 * rem),
          value,
        ],
      ),
    );
    Widget text(String value) => Text(
      value,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        fontFamily: DharaFonts.ui,
        fontSize: DharaType.sm,
        height: 1.4,
        color: DharaColors.text,
      ),
    );
    return GlassCard(
      key: const Key('details-facts'),
      padding: const EdgeInsets.symmetric(horizontal: 1.2 * rem, vertical: rem),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              fact(
                page.title.kind == TitleKind.series ? 'Created by' : 'Director',
                text(page.makers.isEmpty ? '–' : page.makers.join(', ')),
              ),
              const SizedBox(width: 1.4 * rem),
              fact(
                'Cast',
                text(page.cast.isEmpty ? '–' : page.cast.take(6).join(', ')),
                flex: 2,
              ),
              const SizedBox(width: 1.4 * rem),
              fact(
                'Language',
                text(language == null ? '–' : languageName(language)),
              ),
            ],
          ),
          const SizedBox(height: rem),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              fact(
                'Original title',
                text(original == null || original.isEmpty ? '–' : original),
              ),
              const SizedBox(width: 1.4 * rem),
              fact(
                'Audio in the files',
                text(languages.isEmpty ? '–' : languages.take(4).join(', ')),
                flex: 2,
              ),
              const SizedBox(width: 1.4 * rem),
              fact(
                'Match',
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    text(match),
                    const SizedBox(height: .4 * rem),
                    // Shrinks rather than runs out of a narrow column.
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: DharaButton(
                        key: const Key('details-fix-match'),
                        label: 'Fix match',
                        small: true,
                        onPressed: onFixMatch,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The copies of a film, the best first; for a show, the videos that are
/// not one of its episodes (the episodes have their own list).
class _Copies extends StatelessWidget {
  const _Copies({
    required this.page,
    required this.copies,
    required this.heading,
    required this.sources,
    required this.onPlay,
  });

  final TitlePage page;

  /// The videos to list: all of the title's, or a part of them.
  final List<TitleCopy> copies;
  final String heading;
  final SourceStore sources;
  final ValueChanged<TitleCopy> onPlay;

  @override
  Widget build(BuildContext context) {
    final series = page.title.kind == TitleKind.series;
    final real = [
      for (final copy in copies)
        if (copy.extra == null) copy,
    ];
    final extras = [
      for (final copy in copies)
        if (copy.extra != null) copy,
    ];
    // The servers are asked for these copies as the list comes up.
    return CopyPings(
      copies: real,
      sources: sources,
      builder: (context, live) =>
          _list(context, live, series: series, real: real, extras: extras),
    );
  }

  Widget _list(
    BuildContext context,
    LivePings live, {
    required bool series,
    required List<TitleCopy> real,
    required List<TitleCopy> extras,
  }) {
    final pings = live.byFile;
    final servers = {
      for (final copy in real)
        if (reachOf(copy, sources, pings) == CopyReach.online) copy.sourceId,
    }.length;
    final tests = SourcesScope.of(context);
    // With live answers the button asks again; without, the servers are
    // tested as before.
    final ping = live.ping;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              heading,
              style: const TextStyle(
                fontFamily: DharaFonts.display,
                fontSize: DharaType.lg,
                fontWeight: DharaType.bold,
                letterSpacing: -.01 * DharaType.lg,
                height: DharaType.snug,
                color: DharaColors.text,
              ),
            ),
            const SizedBox(width: .7 * rem),
            Expanded(
              child: Text(
                real.isEmpty
                    ? ''
                    : live.pinging
                    ? '${real.length} found; asking their servers …'
                    : live.done && servers == 0
                    ? '${real.length} found; none of their servers answers '
                          'right now'
                    : live.done
                    ? '${real.length} found, on $servers '
                          '${servers == 1 ? 'server' : 'servers'} that '
                          '${servers == 1 ? 'answers' : 'answer'} right now'
                    : servers == 0
                    ? '${real.length} found; none of their servers has '
                          'answered a test yet'
                    : '${real.length} found, on $servers '
                          '${servers == 1 ? 'server' : 'servers'} that '
                          'answered the last test',
                key: const Key('details-copies-count'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: DharaFonts.ui,
                  fontSize: DharaType.xs,
                  color: DharaColors.text3,
                ),
              ),
            ),
            if (real.isNotEmpty && ping != null)
              DharaButton(
                key: const Key('details-ping'),
                label: live.pinging ? 'Pinging …' : 'Ping again',
                icon: DharaIcons.refresh,
                small: true,
                onPressed: live.pinging ? null : ping,
              )
            else if (real.isNotEmpty)
              DharaButton(
                key: const Key('details-retest'),
                label: tests.isTesting ? 'Testing …' : 'Re-test servers',
                icon: DharaIcons.refresh,
                small: true,
                onPressed: tests.isTesting
                    ? null
                    : () => unawaited(
                        tests.test([
                          for (final source in sources.sources)
                            if (copies.any(
                              (copy) => copy.sourceId == source.id,
                            ))
                              source,
                        ]),
                      ),
              ),
          ],
        ),
        const SizedBox(height: rem),
        if (copies.isEmpty)
          const EmptyState(
            key: Key('details-no-copies'),
            icon: DharaIcons.servers,
            title: 'No video of it is on an enabled server',
            message:
                'The servers that held it are switched off, or it is gone '
                'from them. It stays on My List if you put it there.',
          )
        else
          CopiesTable(
            copies: [
              // A film's copies by how good they are (by the live
              // answers once all are in, so that rows do not jump while
              // they arrive); a show's as they come, episode after
              // episode.
              if (series)
                ...real
              else
                ...rankCopies(
                  real,
                  sources,
                  pings: live.done ? pings : const {},
                  preferred: SettingsScope.of(context).preferredQuality,
                ),
              ...extras,
            ],
            sources: sources,
            pings: pings,
            watched: page.watched,
            withEpisode: series,
            onPlay: onPlay,
          ),
      ],
    );
  }
}
