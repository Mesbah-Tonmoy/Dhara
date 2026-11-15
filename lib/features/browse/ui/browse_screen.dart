import 'package:dhara/features/browse/browse_controller.dart';
import 'package:dhara/features/browse/browse_store.dart';
import 'package:dhara/features/details/ui/details_screen.dart';
import 'package:dhara/features/home/ui/poster_card.dart';
import 'package:dhara/shell/page_bleed.dart';
import 'package:dhara/theme/tokens.dart';
import 'package:dhara/widgets/buttons.dart';
import 'package:dhara/widgets/chips.dart';
import 'package:dhara/widgets/icons.dart';
import 'package:dhara/widgets/surfaces.dart';
import 'package:flutter/material.dart';

/// "under 0.1", "3.4", "27": how long a search took, in milliseconds.
String tookLabel(Duration took) {
  final ms = took.inMicroseconds / 1000;
  if (ms < .1) return 'under 0.1';
  return ms < 10 ? ms.toStringAsFixed(1) : ms.round().toString();
}

/// The prototype's Search screen, which is also how Movies, Series and
/// everything else are browsed: what is typed into the title bar and the
/// filters here narrow one grid of posters, as they change.
///
/// The grid knows how many titles fit at once and builds only the cards in
/// view; their data is read a screenful at a time by the
/// [BrowseController] above. Titles come from the servers or from TMDB and
/// are drawn as plain text.
class BrowseScreen extends StatefulWidget {
  const BrowseScreen({super.key, this.now = DateTime.now});

  /// The year chips count back from this year.
  final DateTime Function() now;

  @override
  State<BrowseScreen> createState() => _BrowseScreenState();
}

class _BrowseScreenState extends State<BrowseScreen> {
  var _asked = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_asked) return;
    _asked = true;
    BrowseScope.read(context).ensureLoaded();
  }

  @override
  Widget build(BuildContext context) {
    final browse = BrowseScope.of(context);
    final query = browse.query;
    final result = browse.result;
    final text = query.text.trim();
    final heading = text.isNotEmpty
        ? 'Results for “$text”'
        : switch (query.kind) {
            BrowseKind.all => 'Browse everything',
            BrowseKind.movies => 'Movies',
            BrowseKind.series => 'Series',
            BrowseKind.anime => 'Anime',
          };

    const sides = EdgeInsets.only(
      left: PageInsets.contentLeft,
      right: DharaLayout.pageRight,
    );
    return ColoredBox(
      key: const Key('browse'),
      color: DharaColors.bg,
      child: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: sides.copyWith(top: 1.8 * rem),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              heading,
                              key: const Key('browse-heading'),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
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
                              result == null
                                  ? (browse.failed
                                        ? 'The library did not answer.'
                                        : 'Searching …')
                                  : '${result.ids.length} of ${result.total} '
                                        'titles · found in '
                                        '${tookLabel(result.took)} ms · '
                                        'results change as you type',
                              key: const Key('browse-info'),
                              style: const TextStyle(
                                fontFamily: DharaFonts.ui,
                                fontSize: DharaType.sm,
                                color: DharaColors.text2,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (!query.hasNoFilters)
                        DharaButton(
                          key: const Key('browse-reset'),
                          label: 'Reset filters',
                          icon: DharaIcons.close,
                          small: true,
                          onPressed: browse.resetFilters,
                        ),
                    ],
                  ),
                  const SizedBox(height: 1.4 * rem),
                  _Filters(browse: browse, year: widget.now().year),
                  const SizedBox(height: 1.6 * rem),
                ],
              ),
            ),
          ),
          if (result != null && result.ids.isEmpty)
            const SliverToBoxAdapter(
              child: EmptyState(
                key: Key('browse-empty'),
                icon: DharaIcons.search,
                title: 'Nothing matches',
                message: 'Try a shorter search, or take a filter off.',
              ),
            )
          else if (result != null)
            SliverPadding(
              padding: sides.copyWith(bottom: DharaSpace.s7),
              sliver: SliverLayoutBuilder(
                builder: (context, box) {
                  const gap = DharaLayout.cardGap;
                  // As many columns as fit with cards no narrower than a
                  // poster of the rows on Home.
                  final columns =
                      ((box.crossAxisExtent + gap) /
                              (DharaLayout.posterWidth + gap))
                          .floor()
                          .clamp(1, 40);
                  return SliverGrid.builder(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      crossAxisSpacing: gap,
                      mainAxisSpacing: 1.5 * rem,
                      childAspectRatio: 2 / 3,
                    ),
                    itemCount: result.ids.length,
                    itemBuilder: (context, index) {
                      final card = browse.cardAt(index);
                      // Its place, until its page of cards has been read.
                      if (card == null) return const _Waiting();
                      return PosterCard(
                        key: ValueKey(card.id),
                        title: card,
                        onOpen: () => openDetails(context, card),
                      );
                    },
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

/// The place of a card whose data is still being read: still, because a
/// screenful of shimmering boxes costs more than the wait is worth.
class _Waiting extends StatelessWidget {
  const _Waiting();

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: DharaColors.surface,
      borderRadius: BorderRadius.circular(DharaRadii.md),
    ),
  );
}

/// The prototype's `.filters`: type, order, quality, rating, year, genres.
class _Filters extends StatelessWidget {
  const _Filters({required this.browse, required this.year});

  final BrowseController browse;

  /// This year.
  final int year;

  @override
  Widget build(BuildContext context) {
    final query = browse.query;
    Widget chip(
      String key,
      String label,
      bool on,
      BrowseQuery Function(BrowseQuery) change,
    ) => PillChip(
      key: Key('filter-$key'),
      label: label,
      small: true,
      selected: on,
      onPressed: () => browse.change(change),
    );

    Widget line(String label, List<Widget> children) => Padding(
      padding: const EdgeInsets.symmetric(vertical: .35 * rem),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 4.6 * rem,
            child: Padding(
              padding: const EdgeInsets.only(top: .45 * rem),
              child: Text(
                label.toUpperCase(),
                style: const TextStyle(
                  fontFamily: DharaFonts.ui,
                  fontSize: DharaType.xs,
                  letterSpacing: .12 * DharaType.xs,
                  color: DharaColors.text3,
                ),
              ),
            ),
          ),
          Expanded(
            child: Wrap(
              spacing: .4 * rem,
              runSpacing: .4 * rem,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: children,
            ),
          ),
        ],
      ),
    );

    return GlassCard(
      key: const Key('browse-filters'),
      radius: DharaRadii.md,
      padding: const EdgeInsets.symmetric(
        horizontal: 1.1 * rem,
        vertical: .6 * rem,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          line('Type', [
            SegmentedPills<BrowseKind>(
              key: const Key('filter-kind'),
              choices: const {
                BrowseKind.all: 'All',
                BrowseKind.movies: 'Movies',
                BrowseKind.series: 'Series',
                BrowseKind.anime: 'Anime',
              },
              selected: query.kind,
              onSelected: (kind) =>
                  browse.change((query) => query.copyWith(kind: kind)),
            ),
          ]),
          line('Sort', [
            for (final (sort, label) in const [
              (BrowseSort.relevance, 'Relevance'),
              (BrowseSort.rating, 'Rating'),
              (BrowseSort.newest, 'Newest'),
              (BrowseSort.name, 'A–Z'),
            ])
              chip(
                'sort-${sort.name}',
                label,
                query.sort == sort,
                (query) => query.copyWith(sort: sort),
              ),
          ]),
          line('Quality', [
            for (final (height, label) in const [
              (null, 'Any'),
              (2160, '4K'),
              (1080, '1080p+'),
              (720, '720p+'),
            ])
              chip(
                'quality-${height ?? 'any'}',
                label,
                query.minHeight == height,
                (query) => query.copyWith(minHeight: () => height),
              ),
          ]),
          line('Rating', [
            for (final (rating, label) in const [
              (null, 'Any'),
              (7.0, '7+'),
              (8.0, '8+'),
            ])
              chip(
                'rating-${rating?.round() ?? 'any'}',
                label,
                query.minRating == rating,
                (query) => query.copyWith(minRating: () => rating),
              ),
          ]),
          line('Year', [
            chip(
              'year-any',
              'Any',
              query.year == null,
              (query) => query.copyWith(year: () => null, yearOrOlder: false),
            ),
            for (final each in [year, year - 1, year - 2])
              chip(
                'year-$each',
                '$each',
                query.year == each && !query.yearOrOlder,
                (query) => query.copyWith(year: () => each, yearOrOlder: false),
              ),
            chip(
              'year-older',
              '${year - 3} & older',
              query.year == year - 3 && query.yearOrOlder,
              (query) =>
                  query.copyWith(year: () => year - 3, yearOrOlder: true),
            ),
          ]),
          if (browse.genres.isNotEmpty)
            line('Genre', [
              for (final genre in browse.genres)
                chip(
                  'genre-$genre',
                  genre,
                  query.genres.contains(genre),
                  (query) => query.copyWith(
                    genres: query.genres.contains(genre)
                        ? ({...query.genres}..remove(genre))
                        : {...query.genres, genre},
                  ),
                ),
            ]),
        ],
      ),
    );
  }
}
