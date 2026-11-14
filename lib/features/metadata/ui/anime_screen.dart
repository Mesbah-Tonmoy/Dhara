import 'dart:async';

import 'package:dhara/features/metadata/anime_controller.dart';
import 'package:dhara/features/metadata/anime_store.dart';
import 'package:dhara/features/metadata/metadata_store.dart';
import 'package:dhara/features/metadata/ui/titles_screen.dart';
import 'package:dhara/features/metadata/video_identity.dart';
import 'package:dhara/features/player/widgets/glass.dart';
import 'package:dhara/theme/tokens.dart';
import 'package:flutter/material.dart';

/// AniList's lists of anime: what is trending and what airs this season,
/// each marked with whether the library has it. An anime the library has
/// opens with its episodes.
///
/// A working screen until the real Home arrives in Phase 6. Titles come
/// from AniList's users and are shown through plain `Text` widgets only.
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
    if (id == null) return;
    unawaited(
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => TitleCopiesScreen(
            title: TitleHit(
              id: id,
              kind: row.titleKind ?? TitleKind.series,
              name: row.anime.name,
              copies: 0,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final anime = AnimeScope.of(context);
    final trending = anime.trending;
    final seasonal = anime.seasonal;
    final rows = [
      if (seasonal != null) ...[
        _Heading(
          '${anime.season.label} ${anime.seasonYear}  ·  '
          '${_inLibrary(seasonal)} of ${seasonal.length} in your library',
        ),
        ...seasonal,
      ],
      if (trending != null) ...[
        _Heading(
          'Trending now  ·  '
          '${_inLibrary(trending)} of ${trending.length} in your library',
        ),
        ...trending,
      ],
    ];

    return Scaffold(
      body: LayoutBuilder(
        builder: (context, box) {
          final gutter = box.maxWidth >= 900 ? 40.0 : 20.0;
          final sides = EdgeInsets.symmetric(horizontal: gutter);
          return CustomScrollView(
            slivers: [
              SliverPadding(
                padding: sides.copyWith(top: 28, bottom: 6),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.end,
                        spacing: 16,
                        runSpacing: 14,
                        children: [
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 760),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: 'Back',
                                  onPressed: () =>
                                      Navigator.of(context).maybePop(),
                                  icon: const Icon(Icons.arrow_back_rounded),
                                ),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Anime',
                                        style: Theme.of(
                                          context,
                                        ).textTheme.headlineMedium,
                                      ),
                                      const SizedBox(height: 4),
                                      const Text(
                                        'What AniList lists as trending and '
                                        'as airing this season, and which of '
                                        'it is on your servers. Nothing about '
                                        'your library is sent to AniList.',
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: DharaColors.text2,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          DharaPillButton(
                            key: const Key('anime-refresh'),
                            icon: Icons.refresh_rounded,
                            label: anime.isLoading ? 'Asking …' : 'Ask again',
                            onPressed: () => unawaited(anime.load(fresh: true)),
                          ),
                        ],
                      ),
                      if (anime.failure case final failure?) ...[
                        const SizedBox(height: 14),
                        Text(
                          trending == null
                              ? failure
                              : '$failure These are the lists as they were '
                                    'last fetched.',
                          key: const Key('anime-failure'),
                          style: const TextStyle(
                            fontSize: 13,
                            color: DharaColors.warn,
                          ),
                        ),
                      ],
                      if (rows.isEmpty && anime.failure == null) ...[
                        const SizedBox(height: 18),
                        const PanelHeading('Asking AniList …'),
                      ],
                    ],
                  ),
                ),
              ),
              SliverPadding(
                padding: sides,
                sliver: SliverList.builder(
                  itemCount: rows.length,
                  itemBuilder: (context, i) => switch (rows[i]) {
                    _Heading(:final text) => Padding(
                      padding: const EdgeInsets.only(top: 16, bottom: 8),
                      child: PanelHeading(text),
                    ),
                    final AnimeRow row => _AnimeRowTile(
                      row: row,
                      onOpen: () => _open(row),
                    ),
                    _ => const SizedBox.shrink(),
                  },
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 36)),
            ],
          );
        },
      ),
    );
  }
}

int _inLibrary(List<AnimeRow> rows) =>
    rows.where((row) => row.inLibrary).length;

class _Heading {
  const _Heading(this.text);

  final String text;
}

class _AnimeRowTile extends StatelessWidget {
  const _AnimeRowTile({required this.row, required this.onOpen});

  final AnimeRow row;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final anime = row.anime;
    final year = anime.year;
    final episodes = anime.episodes;
    final score = anime.score;
    final romaji = anime.romaji;
    final details = [
      if (romaji != null && romaji != anime.name) romaji,
      switch (anime.format) {
        'TV' => 'Series',
        'MOVIE' => 'Film',
        'TV_SHORT' => 'Short series',
        final String other => other,
        null => 'Anime',
      },
      if (episodes != null) episodes == 1 ? '1 episode' : '$episodes episodes',
      if (score != null) '$score / 100',
    ].join('  ·  ');

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: Key('anime-${anime.id}'),
          borderRadius: BorderRadius.circular(DharaRadii.md),
          onTap: row.inLibrary ? onOpen : null,
          child: Ink(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            decoration: BoxDecoration(
              color: DharaColors.surface,
              borderRadius: BorderRadius.circular(DharaRadii.md),
              border: Border.all(color: DharaColors.stroke),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        year == null ? anime.name : '${anime.name} ($year)',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        details,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: DharaColors.text3,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Text(
                  row.inLibrary ? 'In your library' : 'Not on your servers',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: row.inLibrary ? DharaColors.good : DharaColors.text3,
                  ),
                ),
                if (row.inLibrary) ...[
                  const SizedBox(width: 6),
                  const Icon(
                    Icons.chevron_right_rounded,
                    size: 20,
                    color: DharaColors.text3,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
