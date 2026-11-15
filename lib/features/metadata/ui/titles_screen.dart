import 'dart:async';

import 'package:dhara/features/metadata/match_controller.dart';
import 'package:dhara/features/metadata/titles_controller.dart';
import 'package:dhara/features/metadata/tmdb_key.dart';
import 'package:dhara/features/metadata/ui/match_panel.dart';
import 'package:dhara/features/metadata/ui/needs_review_screen.dart';
import 'package:dhara/features/metadata/ui/tmdb_key_card.dart';
import 'package:dhara/shell/page_bleed.dart';
import 'package:dhara/theme/tokens.dart';
import 'package:dhara/widgets/buttons.dart';
import 'package:dhara/widgets/icons.dart';
import 'package:dhara/widgets/page_parts.dart';
import 'package:flutter/material.dart';

/// Titles and matching: how many films and shows the indexed videos are
/// copies of, how far TMDB has been asked about them, and the way to the
/// TMDB key and to the titles that need a decision.
///
/// Opened from Settings. Looking for a title is the Search page's job.
class TitlesScreen extends StatelessWidget {
  const TitlesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final titles = TitlesScope.of(context);
    final tmdbKey = TmdbKeyScope.of(context);
    final match = MatchScope.of(context);
    final toReview = match.counts?.toReview ?? 0;

    return ColoredBox(
      key: const Key('titles'),
      color: DharaColors.bg,
      // Tooltips and the dialogs opened from here are Material's.
      child: Material(
        type: MaterialType.transparency,
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(
            left: PageInsets.contentLeft,
            right: DharaLayout.pageRight,
            top: 1.8 * rem,
            bottom: DharaSpace.s7,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PageHead(
                title: 'Titles and matching',
                subtitle:
                    'Every copy of a film, and every episode of a show, '
                    'goes under one title: worked out from the names of the '
                    'files and folders in the index, then looked up on '
                    'TMDB for posters and descriptions.',
                actions: [
                  if (toReview > 0)
                    DharaButton(
                      key: const Key('titles-review'),
                      icon: DharaIcons.review,
                      label: 'Needs review ($toReview)',
                      onPressed: () => unawaited(
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const NeedsReviewScreen(),
                          ),
                        ),
                      ),
                    ),
                  DharaButton(
                    key: const Key('titles-tmdb-key'),
                    icon: DharaIcons.key,
                    label: tmdbKey.hasKey ? 'TMDB key' : 'Add TMDB key',
                    onPressed: () =>
                        unawaited(showTmdbKeyDialog(context, tmdbKey)),
                  ),
                ],
              ),
              if (titles.failed) ...[
                const SizedBox(height: rem),
                const NoticeBar(
                  'The names of the videos could not be read because of an '
                  'error in the app.',
                ),
              ],
              const SizedBox(height: 1.4 * rem),
              _Stats(titles: titles),
              const SizedBox(height: rem),
              MatchPanel(match: match, tmdbKey: tmdbKey),
            ],
          ),
        ),
      ),
    );
  }
}

class _Stats extends StatelessWidget {
  const _Stats({required this.titles});

  final TitlesController titles;

  @override
  Widget build(BuildContext context) {
    final counts = titles.counts;
    final reading = titles.isReading && titles.namesToRead > 0;
    String count(int? number) => number == null ? '–' : '$number';
    return StatRow(
      tiles: [
        StatTile(
          key: const Key('titles-films'),
          label: 'Films',
          value: count(counts?.movies),
          note: reading
              ? 'Reading file names … ${titles.namesRead} / '
                    '${titles.namesToRead}'
              : 'one title, however many copies',
        ),
        StatTile(
          key: const Key('titles-shows'),
          label: 'Shows',
          value: count(counts?.shows),
          note: 'episodes grouped by season',
        ),
        StatTile(
          key: const Key('titles-other'),
          label: 'Other videos',
          value: count(counts?.otherVideos),
          note: 'clips and songs, found by file name',
        ),
      ],
    );
  }
}
