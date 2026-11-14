import 'package:dhara/features/home/home_store.dart';
import 'package:dhara/features/home/ui/poster_card.dart';
import 'package:dhara/features/metadata/video_identity.dart';
import 'package:dhara/theme/tokens.dart';
import 'package:dhara/widgets/chips.dart';
import 'package:dhara/widgets/icons.dart';
import 'package:flutter/material.dart';

/// "1h 52m", "48 min".
String runtimeLabel(int minutes) => minutes >= 60
    ? '${minutes ~/ 60}h ${'${minutes % 60}'.padLeft(2, '0')}m'
    : '$minutes min';

/// "MOVIE", "SERIES" or "ANIME": what the pill over a title says.
String kindLabel(TitleCard title) => title.isAnime
    ? 'ANIME'
    : title.kind == TitleKind.series
    ? 'SERIES'
    : 'MOVIE';

/// The prototype's `.eyebrow`: a small pill with the kind of the title and
/// a few words next to it.
class Eyebrow extends StatelessWidget {
  const Eyebrow({super.key, required this.title, required this.text});

  final TitleCard title;
  final String text;

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(
      fontFamily: DharaFonts.ui,
      fontSize: DharaType.xs,
      fontWeight: DharaType.semibold,
      letterSpacing: .16 * DharaType.xs,
      height: 1.3,
      color: DharaColors.text2,
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: .55 * rem,
            vertical: .15 * rem,
          ),
          decoration: BoxDecoration(
            gradient: DharaColors.accentGradient,
            borderRadius: BorderRadius.circular(DharaRadii.pill),
          ),
          child: Text(
            kindLabel(title),
            style: style.copyWith(
              color: DharaColors.onAccent,
              letterSpacing: .12 * DharaType.xs,
            ),
          ),
        ),
        const SizedBox(width: .6 * rem),
        Flexible(
          child: Text(
            text.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style,
          ),
        ),
      ],
    );
  }
}

/// The prototype's `.meta` line under a title: rating, year, length,
/// genres and the best quality there is, as far as each is known.
class TitleMeta extends StatelessWidget {
  const TitleMeta({super.key, required this.title, this.genres = 3});

  final TitleCard title;

  /// How many genres to name at most.
  final int genres;

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(
      fontFamily: DharaFonts.ui,
      fontSize: DharaType.sm,
      height: 1.3,
      color: DharaColors.text2,
    );
    final rating = title.rating;
    final quality = qualityLabel(title.height);
    final facts = <Widget>[
      if (rating != null && rating > 0)
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              DharaIcons.star,
              size: .95 * rem,
              color: DharaColors.warn,
            ),
            const SizedBox(width: .25 * rem),
            Text(
              rating.toStringAsFixed(1),
              style: style.copyWith(
                color: DharaColors.text,
                fontWeight: DharaType.semibold,
              ),
            ),
          ],
        ),
      if (title.year case final year?) Text('$year', style: style),
      if (title.runtime case final minutes? when minutes > 0)
        Text(runtimeLabel(minutes), style: style),
      if (title.kind == TitleKind.series && title.episodes > 0)
        Text(holdingsLabel(title), style: style),
      if (title.genres.isNotEmpty)
        Text(title.genres.take(genres).join(', '), style: style),
    ];
    return Wrap(
      spacing: .55 * rem,
      runSpacing: .3 * rem,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final (index, fact) in facts.indexed) ...[
          if (index > 0)
            Container(
              width: .2 * rem,
              height: .2 * rem,
              decoration: const BoxDecoration(
                color: DharaColors.text3,
                shape: BoxShape.circle,
              ),
            ),
          fact,
        ],
        if (quality != null)
          // In a row of its own so that it is only as wide as its text.
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              DharaBadge(
                quality,
                style: quality == '4K'
                    ? DharaBadgeStyle.accent
                    : DharaBadgeStyle.plain,
              ),
            ],
          ),
      ],
    );
  }
}
