import 'package:dhara/core/images/remote_image.dart';
import 'package:dhara/features/home/home_store.dart';
import 'package:dhara/features/metadata/video_identity.dart';
import 'package:dhara/theme/tokens.dart';
import 'package:dhara/widgets/icons.dart';
import 'package:dhara/widgets/placeholder_art.dart';
import 'package:dhara/widgets/pressable.dart';
import 'package:flutter/material.dart';

/// "4K", "1080p": what a card calls a picture [height] lines high; `null`
/// if no name of the title's videos says.
String? qualityLabel(int? height) => switch (height) {
  null => null,
  >= 2160 => '4K',
  >= 1440 => '1440p',
  >= 1080 => '1080p',
  >= 720 => '720p',
  >= 480 => '480p',
  _ => 'SD',
};

/// "3 copies" for a film, "24 episodes" for a show.
String holdingsLabel(TitleCard title) {
  String count(int number, String one, String many) =>
      '$number ${number == 1 ? one : many}';
  if (title.kind == TitleKind.series) {
    return title.episodes > 0
        ? count(title.episodes, 'episode', 'episodes')
        : count(title.videos, 'video', 'videos');
  }
  return count(title.videos, 'copy', 'copies');
}

/// The prototype's `.card`: a film or show as its poster, 2:3.
///
/// Under the pointer, or with the keyboard on it, the card grows a little,
/// glows, and a panel slides up with the title, the year and genres, and
/// what the sources hold of it. A title without a poster gets artwork
/// drawn from its name, with the name written on it.
///
/// The name comes from a server until TMDB has named the title: it is only
/// ever drawn as plain text.
class PosterCard extends StatefulWidget {
  const PosterCard({
    super.key,
    required this.title,
    required this.onOpen,
    this.rank,
    this.autofocus = false,
  });

  final TitleCard title;
  final VoidCallback? onOpen;

  /// Its place in a ranked row ("#1"), if it has one.
  final int? rank;
  final bool autofocus;

  @override
  State<PosterCard> createState() => _PosterCardState();
}

class _PosterCardState extends State<PosterCard> {
  /// The poster is showing: the name written over the artwork goes.
  var _hasPoster = false;

  @override
  void didUpdateWidget(PosterCard old) {
    super.didUpdateWidget(old);
    if (old.title.posterPath != widget.title.posterPath) _hasPoster = false;
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.title;
    final rank = widget.rank;
    final quality = qualityLabel(title.height);
    final rating = title.rating;
    const corners = BorderRadius.all(Radius.circular(DharaRadii.md));

    return Pressable(
      onPressed: widget.onOpen,
      autofocus: widget.autofocus,
      semanticLabel: title.name,
      builder: (context, state) {
        final active = state.active;
        // Read out as its name alone, not as everything written on it.
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
                  boxShadow: active ? DharaShadows.glow : DharaShadows.card,
                ),
                child: ClipRRect(
                  borderRadius: corners,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      AnimatedScale(
                        scale: active ? 1.06 : 1,
                        duration: motion(context, DharaMotion.slow),
                        curve: DharaMotion.easeOut,
                        child: TmdbCover(
                          path: title.posterPath,
                          size: 'w342',
                          placeholder: PlaceholderArt(seed: title.name),
                          onPicture: (showing) {
                            if (mounted && showing != _hasPoster) {
                              setState(() => _hasPoster = showing);
                            }
                          },
                        ),
                      ),
                      const _Shade(),
                      if (!_hasPoster)
                        Positioned(
                          left: .7 * rem,
                          right: .7 * rem,
                          bottom: .8 * rem,
                          child: AnimatedOpacity(
                            opacity: active ? 0 : 1,
                            duration: motion(context, DharaMotion.fast),
                            child: _ArtTitle(title.name),
                          ),
                        ),
                      Positioned(
                        top: .5 * rem,
                        left: .5 * rem,
                        right: .5 * rem,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (rank != null)
                              _Rank(rank)
                            else if (quality != null)
                              _Tag(quality, accent: quality == '4K'),
                            const SizedBox(width: .3 * rem),
                            // Shrinks rather than runs out of the card.
                            Expanded(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.topRight,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (rank != null && quality != null) ...[
                                      _Tag(quality, accent: quality == '4K'),
                                      const SizedBox(width: .3 * rem),
                                    ],
                                    if (rating != null && rating > 0)
                                      _Tag(
                                        rating.toStringAsFixed(1),
                                        star: true,
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Align(
                        alignment: Alignment.bottomCenter,
                        child: AnimatedSlide(
                          offset: Offset(0, active ? 0 : 1.02),
                          duration: motion(context, DharaMotion.base),
                          curve: DharaMotion.easeOut,
                          child: _Peek(title),
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

/// Darkens the foot of the poster, and its top a little, so that what is
/// written over it can be read on any picture.
class _Shade extends StatelessWidget {
  const _Shade();

  @override
  Widget build(BuildContext context) => const IgnorePointer(
    child: DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Color(0xC7000000), Color(0x00000000)],
          stops: [0, .46],
        ),
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0x59000000), Color(0x00000000)],
            stops: [0, .22],
          ),
        ),
      ),
    ),
  );
}

/// The name of a title, written across the foot of its drawn artwork.
class _ArtTitle extends StatelessWidget {
  const _ArtTitle(this.name);

  final String name;

  @override
  Widget build(BuildContext context) => Text(
    name.toUpperCase(),
    textAlign: TextAlign.center,
    maxLines: 4,
    overflow: TextOverflow.ellipsis,
    style: const TextStyle(
      fontFamily: DharaFonts.display,
      fontSize: .86 * rem,
      fontWeight: DharaType.bold,
      height: 1.15,
      letterSpacing: .14 * .86 * rem,
      color: DharaColors.text,
      shadows: [
        Shadow(
          color: Color(0xB3000000),
          offset: Offset(0, .1 * rem),
          blurRadius: .6 * rem,
        ),
      ],
    ),
  );
}

/// The prototype's `.tag`: the quality, or the rating behind a star.
class _Tag extends StatelessWidget {
  const _Tag(this.text, {this.accent = false, this.star = false});

  final String text;
  final bool accent;
  final bool star;

  @override
  Widget build(BuildContext context) => Container(
    height: 1.2 * rem,
    padding: const EdgeInsets.symmetric(horizontal: .4 * rem),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(.3 * rem),
      gradient: accent ? DharaColors.accentGradient : null,
      // The prototype blurs what is behind a tag; a card never does, so
      // the tag is a little darker instead.
      color: accent ? null : const Color(0xA6000000),
      border: accent ? null : Border.all(color: const Color(0x24FFFFFF)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (star) ...[
          const Icon(DharaIcons.star, size: .7 * rem, color: DharaColors.warn),
          const SizedBox(width: .2 * rem),
        ],
        Text(
          text,
          maxLines: 1,
          softWrap: false,
          style: const TextStyle(
            fontFamily: DharaFonts.ui,
            fontSize: .64 * rem,
            fontWeight: DharaType.bold,
            letterSpacing: .05 * .64 * rem,
            height: 1.2,
            color: DharaColors.text,
          ),
        ),
      ],
    ),
  );
}

/// The prototype's `.rank`: "#1" in the corner of a card of a ranked row.
class _Rank extends StatelessWidget {
  const _Rank(this.rank);

  final int rank;

  @override
  Widget build(BuildContext context) => Container(
    height: 1.7 * rem,
    constraints: const BoxConstraints(minWidth: 1.7 * rem),
    padding: const EdgeInsets.symmetric(horizontal: .35 * rem),
    alignment: Alignment.center,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(.5 * rem),
      gradient: DharaColors.accentGradient,
      boxShadow: const [
        BoxShadow(
          color: Color(0x80000000),
          offset: Offset(0, .3 * rem),
          blurRadius: .9 * rem,
        ),
      ],
    ),
    child: Text(
      '#$rank',
      style: const TextStyle(
        fontFamily: DharaFonts.ui,
        fontSize: .8 * rem,
        fontWeight: DharaType.black,
        height: 1.2,
        color: DharaColors.onAccent,
      ),
    ),
  );
}

/// The prototype's `.peek`: what slides up over the foot of a card.
class _Peek extends StatelessWidget {
  const _Peek(this.title);

  final TitleCard title;

  @override
  Widget build(BuildContext context) {
    final facts = [
      if (title.year case final year?) '$year',
      if (title.genres.isNotEmpty)
        title.genres.take(2).join(', ')
      else
        title.kind == TitleKind.series ? 'Show' : 'Film',
    ].join(' · ');
    const small = TextStyle(
      fontFamily: DharaFonts.ui,
      fontSize: .68 * rem,
      height: 1.3,
      color: DharaColors.text2,
    );
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(
        .7 * rem,
        .65 * rem,
        .7 * rem,
        .7 * rem,
      ),
      decoration: const BoxDecoration(
        // Solid where the prototype blurs: a card never blurs.
        color: Color(0xEB0A0C16),
        border: Border(top: BorderSide(color: DharaColors.stroke)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: DharaFonts.ui,
              fontSize: DharaType.sm,
              fontWeight: DharaType.semibold,
              height: 1.25,
              color: DharaColors.text,
            ),
          ),
          const SizedBox(height: .1 * rem),
          Text(
            facts,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: small,
          ),
          const SizedBox(height: .5 * rem),
          Row(
            children: [
              Container(
                width: 1.7 * rem,
                height: 1.7 * rem,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: DharaColors.accentGradient,
                ),
                child: const Icon(
                  DharaIcons.play,
                  size: 1 * rem,
                  color: DharaColors.onAccent,
                ),
              ),
              const SizedBox(width: .45 * rem),
              Expanded(
                child: Text(
                  holdingsLabel(title),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: small,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
