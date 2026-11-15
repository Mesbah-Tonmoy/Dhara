import 'dart:async';

import 'package:dhara/core/images/remote_image.dart';
import 'package:dhara/features/browse/browse_controller.dart';
import 'package:dhara/features/browse/browse_store.dart';
import 'package:dhara/features/details/ui/details_screen.dart';
import 'package:dhara/features/home/home_controller.dart';
import 'package:dhara/features/home/ui/card_row.dart';
import 'package:dhara/features/home/ui/poster_card.dart';
import 'package:dhara/features/metadata/anilist_client.dart';
import 'package:dhara/features/metadata/anime_controller.dart';
import 'package:dhara/features/metadata/anime_store.dart';
import 'package:dhara/shell/page_bleed.dart';
import 'package:dhara/shell/shell_controller.dart';
import 'package:dhara/theme/tokens.dart';
import 'package:dhara/widgets/buttons.dart';
import 'package:dhara/widgets/chips.dart';
import 'package:dhara/widgets/icons.dart';
import 'package:dhara/widgets/placeholder_art.dart';
import 'package:dhara/widgets/pressable.dart';
import 'package:dhara/widgets/shade.dart';
import 'package:dhara/widgets/surfaces.dart';
import 'package:dhara/widgets/toast.dart';
import 'package:flutter/material.dart';

/// "TV · 12 episodes · 2026": what kind of anime it is, how long, and of
/// which year, as far as AniList says.
String describeAnime(AnimeEntry anime) => [
  switch (anime.format) {
    null => null,
    'MOVIE' => 'Film',
    'TV' => 'Series',
    'TV_SHORT' => 'Short series',
    'SPECIAL' => 'Special',
    final other => other,
  },
  if (anime.episodes case final count? when !anime.isFilm)
    '$count ${count == 1 ? 'episode' : 'episodes'}',
  if (anime.year case final year?) '$year',
].nonNulls.join(' · ');

/// The Anime page: the anime the library holds, then what AniList lists as
/// airing this season and as trending, each with its cover and marked with
/// whether it is on the enabled servers. One that is opens its page.
///
/// AniList is asked twice a day at most, the same two questions for
/// everyone; nothing about the library is sent. Covers come from AniList's
/// picture server and are kept on disk. Titles were written by AniList's
/// users and are drawn as plain text only.
class AnimeScreen extends StatefulWidget {
  const AnimeScreen({super.key});

  @override
  State<AnimeScreen> createState() => _AnimeScreenState();
}

class _AnimeScreenState extends State<AnimeScreen> {
  var _asked = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_asked) return;
    _asked = true;
    unawaited(AnimeScope.of(context).load());
  }

  void _open(AnimeRow row) {
    final id = row.titleId;
    if (id == null) {
      ToastHost.show(
        context,
        'is not on your enabled servers.',
        lead: row.anime.name,
      );
      return;
    }
    unawaited(
      Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => DetailsScreen(titleId: id)),
      ),
    );
  }

  /// Opens Search to browse all the anime of the library.
  void _browse() {
    final shell = ShellScope.maybeRead(context);
    final browse = BrowseScope.maybeRead(context);
    if (shell == null || browse == null) return;
    shell.searchText.clear();
    browse
      ..setText('')
      ..change((query) => query.copyWith(kind: BrowseKind.anime));
    shell.open(ShellDestination.search);
  }

  @override
  Widget build(BuildContext context) {
    final anime = AnimeScope.of(context);
    final mine = HomeScope.maybeOf(context)?.content?.anime ?? const [];
    final seasonal = anime.seasonal;
    final trending = anime.trending;
    final failure = anime.failure;
    String held(List<AnimeRow> rows) =>
        '${rows.where((row) => row.inLibrary).length} of ${rows.length}';
    final String info;
    if (seasonal == null && trending == null) {
      info = anime.isLoading
          ? 'Asking AniList …'
          : 'What AniList lists as airing and as trending, and which of '
                'it is on your servers.';
    } else {
      final parts = [
        if (seasonal != null) '${held(seasonal)} of this season',
        if (trending != null) '${held(trending)} of what is trending',
      ];
      info =
          '${parts.join(' and ')} on your servers. Nothing about your '
          'library is sent to AniList.';
    }

    Widget list(String key, String title, List<AnimeRow> rows) => Padding(
      padding: const EdgeInsets.only(top: .9 * rem),
      child: CardRow(
        key: Key(key),
        title: title,
        leftInset: PageInsets.contentLeft,
        itemCount: rows.length,
        itemBuilder: (context, index) => AnimeCard(
          key: Key('anime-${rows[index].anime.id}'),
          row: rows[index],
          onOpen: () => _open(rows[index]),
        ),
      ),
    );

    return ColoredBox(
      key: const Key('anime'),
      color: DharaColors.bg,
      child: ListView(
        padding: const EdgeInsets.only(top: 1.8 * rem, bottom: DharaSpace.s7),
        children: [
          Padding(
            padding: const EdgeInsets.only(
              left: PageInsets.contentLeft,
              right: DharaLayout.pageRight,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Anime',
                        style: TextStyle(
                          fontFamily: DharaFonts.display,
                          fontSize: DharaType.xxl,
                          fontWeight: DharaType.bold,
                          letterSpacing: -.03 * DharaType.xxl,
                          height: 1.1,
                          color: DharaColors.text,
                        ),
                      ),
                      const SizedBox(height: .3 * rem),
                      Text(
                        info,
                        key: const Key('anime-info'),
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
                const SizedBox(width: rem),
                DharaButton(
                  key: const Key('anime-refresh'),
                  label: anime.isLoading ? 'Asking …' : 'Ask again',
                  icon: DharaIcons.refresh,
                  small: true,
                  onPressed: anime.isLoading
                      ? null
                      : () => unawaited(anime.load(fresh: true)),
                ),
              ],
            ),
          ),
          if (failure != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                PageInsets.contentLeft,
                rem,
                DharaLayout.pageRight,
                0,
              ),
              child: GlassCard(
                radius: DharaRadii.md,
                padding: const EdgeInsets.symmetric(
                  horizontal: DharaSpace.s4,
                  vertical: DharaSpace.s3,
                ),
                child: Row(
                  children: [
                    const Icon(
                      DharaIcons.info,
                      size: 1.2 * rem,
                      color: DharaColors.warn,
                    ),
                    const SizedBox(width: DharaSpace.s3),
                    Expanded(
                      child: Text(
                        failure,
                        key: const Key('anime-failure'),
                        style: const TextStyle(
                          fontFamily: DharaFonts.ui,
                          fontSize: DharaType.sm,
                          height: DharaType.body,
                          color: DharaColors.text2,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (mine.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: .9 * rem),
              child: CardRow(
                key: const Key('anime-mine'),
                title: 'In your library',
                onSeeAll: _browse,
                leftInset: PageInsets.contentLeft,
                itemCount: mine.length,
                itemBuilder: (context, index) => PosterCard(
                  title: mine[index],
                  onOpen: () => openDetails(context, mine[index]),
                ),
              ),
            ),
          if (seasonal != null && seasonal.isNotEmpty)
            list(
              'anime-season',
              'Airing this season · ${anime.season.label} '
                  '${anime.seasonYear}',
              seasonal,
            ),
          if (trending != null && trending.isNotEmpty)
            list('anime-trending', 'Trending on AniList', trending),
          if (mine.isEmpty &&
              (seasonal?.isEmpty ?? true) &&
              (trending?.isEmpty ?? true) &&
              !anime.isLoading &&
              failure == null)
            const EmptyState(
              key: Key('anime-empty'),
              icon: DharaIcons.anime,
              title: 'No anime to show yet',
              message:
                  'AniList has not been asked, and the library holds '
                  'nothing that is known to be anime.',
            ),
        ],
      ),
    );
  }
}

/// An anime of one of AniList's lists, as a poster: its cover, its score,
/// and whether the library has it.
class AnimeCard extends StatelessWidget {
  const AnimeCard({super.key, required this.row, required this.onOpen});

  final AnimeRow row;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final anime = row.anime;
    final score = anime.score;
    const corners = BorderRadius.all(Radius.circular(DharaRadii.md));
    const small = TextStyle(
      fontFamily: DharaFonts.ui,
      fontSize: .68 * rem,
      height: 1.3,
      color: DharaColors.text2,
    );
    return Pressable(
      onPressed: onOpen,
      semanticLabel:
          '${anime.name}, '
          '${row.inLibrary ? 'in your library' : 'not on your servers'}',
      builder: (context, state) {
        final active = state.active;
        return ExcludeSemantics(
          child: AnimatedScale(
            scale: active ? DharaMotion.hoverScale : 1,
            duration: motion(context, DharaMotion.base),
            curve: DharaMotion.easeOut,
            child: AspectRatio(
              aspectRatio: 2 / 3,
              child: AnimatedContainer(
                duration: motion(context, DharaMotion.base),
                decoration: BoxDecoration(
                  color: DharaColors.bgElev,
                  borderRadius: corners,
                  // As on a poster card: no shadow while it rests.
                  boxShadow: active ? DharaShadows.glow : null,
                ),
                child: ClipRRect(
                  borderRadius: corners,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      TmdbCover.anilist(
                        path: anime.coverPath,
                        placeholder: PlaceholderArt(seed: anime.name),
                      ),
                      // What the library lacks is shown a little dimmed: the
                      // card's own colour laid over it, which looks like
                      // the cover at 55% and costs no layer of its own.
                      if (!row.inLibrary && !active)
                        const ColoredBox(
                          key: Key('anime-dimmed'),
                          color: Color(0x730D0F18),
                        ),
                      const Shade(_coverShade),
                      Positioned(
                        top: .5 * rem,
                        left: .5 * rem,
                        right: .5 * rem,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Shrinks rather than runs out of the card.
                            Expanded(
                              child: row.inLibrary
                                  ? const FittedBox(
                                      fit: BoxFit.scaleDown,
                                      alignment: Alignment.topLeft,
                                      child: DharaBadge(
                                        'IN LIBRARY',
                                        style: DharaBadgeStyle.good,
                                      ),
                                    )
                                  : const SizedBox.shrink(),
                            ),
                            const SizedBox(width: .3 * rem),
                            if (score != null)
                              Container(
                                height: 1.2 * rem,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: .4 * rem,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xA6000000),
                                  borderRadius: BorderRadius.circular(.3 * rem),
                                  border: Border.all(
                                    color: const Color(0x24FFFFFF),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      DharaIcons.star,
                                      size: .7 * rem,
                                      color: DharaColors.warn,
                                    ),
                                    const SizedBox(width: .2 * rem),
                                    Text(
                                      (score / 10).toStringAsFixed(1),
                                      style: const TextStyle(
                                        fontFamily: DharaFonts.ui,
                                        fontSize: .64 * rem,
                                        fontWeight: DharaType.bold,
                                        height: 1.2,
                                        color: DharaColors.text,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                      Positioned(
                        left: .7 * rem,
                        right: .7 * rem,
                        bottom: .7 * rem,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              anime.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontFamily: DharaFonts.ui,
                                fontSize: DharaType.sm,
                                fontWeight: DharaType.semibold,
                                height: 1.25,
                                color: DharaColors.text,
                              ),
                            ),
                            const SizedBox(height: .15 * rem),
                            Text(
                              describeAnime(anime),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: small,
                            ),
                            if (!row.inLibrary)
                              Text(
                                'Not on your servers',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: small.copyWith(color: DharaColors.text3),
                              ),
                          ],
                        ),
                      ),
                    ],
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

/// Darker towards the foot of a cover, under the name.
const _coverShade = ShadeSpec(
  colors: [Color(0x00000000), Color(0x00000000), Color(0xD9000000)],
  stops: [0, .5, 1],
);
