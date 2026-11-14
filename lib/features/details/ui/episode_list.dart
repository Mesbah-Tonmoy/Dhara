import 'package:dhara/core/images/remote_image.dart';
import 'package:dhara/features/details/details_store.dart';
import 'package:dhara/features/home/ui/title_meta.dart';
import 'package:dhara/features/home/ui/wide_card.dart';
import 'package:dhara/features/metadata/metadata_store.dart';
import 'package:dhara/features/playback/copy_choice.dart';
import 'package:dhara/features/playback/play.dart';
import 'package:dhara/features/sources/source_store.dart';
import 'package:dhara/theme/tokens.dart';
import 'package:dhara/widgets/chips.dart';
import 'package:dhara/widgets/icons.dart';
import 'package:dhara/widgets/placeholder_art.dart';
import 'package:dhara/widgets/pressable.dart';
import 'package:flutter/material.dart';

/// What a season is called on its chip: TMDB's name for it, or "Season 2";
/// "Specials" for season 0, "Episodes" for a show numbered straight
/// through.
String seasonLabel(int? season, Map<int, String> names) => switch (season) {
  null => 'Episodes',
  0 => names[0] ?? 'Specials',
  _ => names[season] ?? 'Season $season',
};

/// The prototype's episodes section: a chip for every season the enabled
/// servers hold something of, and that season's episodes, one line each.
///
/// Only episodes with a video are listed. A click on a line plays the
/// episode ([onPlay]); the chip at its end lists its copies ([onCopies]).
/// Episode names and descriptions come from TMDB or from file names and
/// are drawn as plain text.
class EpisodeList extends StatefulWidget {
  const EpisodeList({
    super.key,
    required this.page,
    required this.sources,
    required this.onPlay,
    required this.onCopies,
    this.next,
  });

  final TitlePage page;
  final SourceStore sources;

  /// Plays the best copy of the episode.
  final ValueChanged<EpisodeKey> onPlay;

  /// Shows the copies of the episode.
  final ValueChanged<EpisodeKey> onCopies;

  /// The episode the Play button of the page would play: it is marked, and
  /// its season is the one shown first.
  final EpisodeKey? next;

  @override
  State<EpisodeList> createState() => _EpisodeListState();
}

class _EpisodeListState extends State<EpisodeList> {
  /// The season on show; `null` is also a season (see [seasonLabel]), so
  /// whether one was picked is kept apart.
  int? _season;
  var _picked = false;

  @override
  Widget build(BuildContext context) {
    final page = widget.page;
    final episodes = episodesIn(page.copies);
    final seasons = <int?>[];
    for (final key in episodes.keys) {
      if (!seasons.contains(key.$1)) seasons.add(key.$1);
    }
    if (seasons.isEmpty) return const SizedBox.shrink();
    final season = _picked && seasons.contains(_season)
        ? _season
        : seasons.contains(widget.next?.$1) && widget.next != null
        ? widget.next!.$1
        : seasons.first;
    final shown = [
      for (final key in episodes.keys)
        if (key.$1 == season) key,
    ];
    final info = {
      for (final episode in page.episodes)
        (episode.season, episode.episode): episode,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Wrap(
          spacing: rem,
          runSpacing: .6 * rem,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Text(
              'Episodes',
              style: TextStyle(
                fontFamily: DharaFonts.display,
                fontSize: DharaType.lg,
                fontWeight: DharaType.bold,
                letterSpacing: -.01 * DharaType.lg,
                height: DharaType.snug,
                color: DharaColors.text,
              ),
            ),
            if (seasons.length > 1)
              Wrap(
                spacing: .5 * rem,
                runSpacing: .5 * rem,
                children: [
                  for (final each in seasons)
                    PillChip(
                      key: Key('season-${each ?? 'all'}'),
                      label: seasonLabel(each, page.seasonNames),
                      selected: each == season,
                      onPressed: () => setState(() {
                        _season = each;
                        _picked = true;
                      }),
                    ),
                ],
              ),
            Text(
              '${shown.length} ${shown.length == 1 ? 'episode' : 'episodes'}',
              key: const Key('episode-count'),
              style: const TextStyle(
                fontFamily: DharaFonts.ui,
                fontSize: DharaType.xs,
                color: DharaColors.text3,
              ),
            ),
          ],
        ),
        const SizedBox(height: rem),
        for (final key in shown)
          Padding(
            padding: const EdgeInsets.only(bottom: .35 * rem),
            child: _EpisodeLine(
              key: Key('episode-${key.$1 ?? 'x'}-${key.$2}'),
              showName: page.title.name,
              episode: key,
              copies: episodes[key]!,
              info: key.$1 == null ? null : info[(key.$1!, key.$2)],
              watched: page.watched,
              sources: widget.sources,
              next: key == widget.next,
              onPlay: () => widget.onPlay(key),
              onCopies: () => widget.onCopies(key),
            ),
          ),
      ],
    );
  }
}

/// The prototype's `.ep`: number, picture, name with what it is about, and
/// the chip that lists its copies.
class _EpisodeLine extends StatelessWidget {
  const _EpisodeLine({
    super.key,
    required this.showName,
    required this.episode,
    required this.copies,
    required this.info,
    required this.watched,
    required this.sources,
    required this.next,
    required this.onPlay,
    required this.onCopies,
  });

  final String showName;
  final EpisodeKey episode;
  final List<TitleCopy> copies;
  final EpisodeInfo? info;
  final Map<String, Watched> watched;
  final SourceStore sources;
  final bool next;
  final VoidCallback onPlay;
  final VoidCallback onCopies;

  @override
  Widget build(BuildContext context) {
    final (season, number) = episode;
    final info = this.info;
    // The copy watched last says how far the episode was watched.
    Watched? seen;
    for (final copy in copies) {
      final each = watched['${copy.url}'];
      if (each != null && (seen == null || each.at.isAfter(seen.at))) {
        seen = each;
      }
    }
    String? fromFile;
    for (final copy in copies) {
      fromFile ??= copy.episodeName;
    }
    final name = info?.name ?? fromFile ?? 'Episode $number';
    final overview = info?.overview;
    final code = episodeCode(season, number);
    final playable = copies.any((copy) => canPlayCopy(copy, sources));
    final radius = BorderRadius.circular(DharaRadii.md);

    return Pressable(
      onPressed: playable ? onPlay : null,
      semanticLabel: '$code, $name',
      builder: (context, state) => FocusRing(
        visible: state.focused,
        radius: radius,
        child: AnimatedContainer(
          duration: motion(context, DharaMotion.fast),
          padding: const EdgeInsets.fromLTRB(.4 * rem, .6 * rem, rem, .6 * rem),
          decoration: BoxDecoration(
            color: next || state.active ? DharaColors.surface : null,
            borderRadius: radius,
            border: Border.all(
              color: next
                  ? const Color(0x808B6CFF)
                  : state.active
                  ? DharaColors.stroke
                  : const Color(0x00FFFFFF),
            ),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 2.4 * rem,
                child: Text(
                  '$number',
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.fade,
                  style: TextStyle(
                    fontFamily: DharaFonts.display,
                    // Four figures (a show numbered straight through)
                    // still fit.
                    fontSize: number > 999
                        ? DharaType.md
                        : number > 99
                        ? DharaType.lg
                        : DharaType.xl,
                    fontWeight: DharaType.bold,
                    color: DharaColors.text3,
                  ),
                ),
              ),
              const SizedBox(width: 1.1 * rem),
              SizedBox(
                width: 11.5 * rem,
                child: _Still(
                  seed: '$showName ${season ?? ''}x$number',
                  path: info?.stillPath,
                  progress: seen?.progress,
                  active: state.active,
                ),
              ),
              const SizedBox(width: 1.1 * rem),
              Expanded(
                child: ExcludeSemantics(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontFamily: DharaFonts.ui,
                                fontSize: DharaType.md,
                                fontWeight: DharaType.semibold,
                                height: 1.4,
                                color: DharaColors.text,
                              ),
                            ),
                          ),
                          if (seen != null && seen.finished) ...[
                            const SizedBox(width: .5 * rem),
                            const DharaBadge('WATCHED'),
                          ] else if (next) ...[
                            const SizedBox(width: .5 * rem),
                            DharaBadge(
                              seen == null ? 'UP NEXT' : 'CONTINUE',
                              style: DharaBadgeStyle.good,
                            ),
                          ],
                        ],
                      ),
                      if (overview != null && overview.isNotEmpty)
                        Text(
                          overview,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: DharaFonts.ui,
                            fontSize: DharaType.sm,
                            height: 1.45,
                            color: DharaColors.text2,
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.only(top: .15 * rem),
                        child: Text(
                          [
                            if (info?.runtime case final minutes?
                                when minutes > 0)
                              runtimeLabel(minutes),
                            code,
                            if (!playable) 'cannot be played from here',
                          ].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: DharaFonts.ui,
                            fontSize: DharaType.xs,
                            color: DharaColors.text3,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: .5 * rem),
              PillChip(
                key: Key('episode-copies-${season ?? 'x'}-$number'),
                label:
                    '${copies.length} ${copies.length == 1 ? 'copy' : 'copies'}',
                icon: DharaIcons.list,
                small: true,
                onPressed: onCopies,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The prototype's `.thumb`: the still of an episode, with the play mark
/// when the line is under the pointer and how far it was watched.
class _Still extends StatelessWidget {
  const _Still({
    required this.seed,
    required this.path,
    required this.progress,
    required this.active,
  });

  final String seed;
  final String? path;
  final double? progress;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final progress = this.progress;
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(DharaRadii.sm),
        child: Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: DharaColors.bgElev),
            TmdbCover(
              path: path,
              size: 'w300',
              placeholder: PlaceholderArt(seed: seed, wide: true),
            ),
            Center(
              child: AnimatedOpacity(
                opacity: active ? 1 : 0,
                duration: motion(context, DharaMotion.base),
                child: AnimatedScale(
                  scale: active ? 1 : .6,
                  duration: motion(context, DharaMotion.base),
                  curve: DharaMotion.easeOut,
                  child: Container(
                    width: 2.3 * rem,
                    height: 2.3 * rem,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: DharaColors.accentGradient,
                    ),
                    child: const Icon(
                      DharaIcons.play,
                      size: 1.3 * rem,
                      color: DharaColors.onAccent,
                    ),
                  ),
                ),
              ),
            ),
            if (progress != null && progress > 0)
              Align(
                alignment: Alignment.bottomLeft,
                child: WatchedBar(progress: progress),
              ),
          ],
        ),
      ),
    );
  }
}
