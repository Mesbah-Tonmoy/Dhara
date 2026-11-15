import 'package:dhara/core/images/remote_image.dart';
import 'package:dhara/core/net/media_url.dart';
import 'package:dhara/features/home/home_store.dart';
import 'package:dhara/features/playback/play.dart';
import 'package:dhara/theme/tokens.dart';
import 'package:dhara/widgets/icons.dart';
import 'package:dhara/widgets/placeholder_art.dart';
import 'package:dhara/widgets/pressable.dart';
import 'package:dhara/widgets/shade.dart';
import 'package:flutter/material.dart';

/// "1h 05m left", "34 min left", "Under a minute left".
String timeLeftLabel(Duration left) {
  final minutes = left.inMinutes;
  if (minutes < 1) return 'Under a minute left';
  if (minutes < 60) return '$minutes min left';
  return '${minutes ~/ 60}h ${'${minutes % 60}'.padLeft(2, '0')}m left';
}

/// What a video left unfinished is called on its card: the title it is a
/// copy of, or else its file name. Server-controlled text.
String continueName(ContinueItem item) {
  final title = item.title;
  if (title != null) return title.name;
  final url = Uri.tryParse(item.url);
  return item.fileName ?? (url == null ? item.url : mediaTitleFromUrl(url));
}

/// The prototype's `.card.wide`: a video left unfinished, 16:9, with how
/// far it was watched along its foot. A click plays it on from there.
class WideCard extends StatelessWidget {
  const WideCard({super.key, required this.item, required this.onPlay});

  final ContinueItem item;
  final VoidCallback? onPlay;

  @override
  Widget build(BuildContext context) {
    final name = continueName(item);
    final episode = item.episode;
    final sub = [
      if (episode != null) episodeCode(item.season, episode),
      timeLeftLabel(item.duration - item.position),
    ].join(' · ');
    const corners = BorderRadius.all(Radius.circular(DharaRadii.md));

    return Pressable(
      onPressed: onPlay,
      semanticLabel: 'Resume $name, $sub',
      builder: (context, state) {
        final active = state.active;
        return ExcludeSemantics(
          child: AnimatedScale(
            scale: active ? DharaMotion.hoverScale : 1,
            duration: motion(context, DharaMotion.base),
            curve: DharaMotion.easeOut,
            child: AspectRatio(
              aspectRatio: 16 / 9,
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
                      AnimatedScale(
                        scale: active ? 1.06 : 1,
                        duration: motion(context, DharaMotion.slow),
                        curve: DharaMotion.easeOut,
                        child: TmdbCover(
                          path: item.title?.backdropPath,
                          size: 'w780',
                          placeholder: PlaceholderArt(seed: name, wide: true),
                        ),
                      ),
                      const Shade(_wideShade),
                      Center(
                        child: AnimatedOpacity(
                          opacity: active ? 1 : 0,
                          duration: motion(context, DharaMotion.base),
                          child: AnimatedScale(
                            scale: active ? 1 : .6,
                            duration: motion(context, DharaMotion.base),
                            curve: DharaMotion.easeOut,
                            child: const _Disc(),
                          ),
                        ),
                      ),
                      Positioned(
                        left: .8 * rem,
                        right: .8 * rem,
                        bottom: .85 * rem,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontFamily: DharaFonts.ui,
                                fontSize: DharaType.md,
                                fontWeight: DharaType.semibold,
                                height: 1.2,
                                color: DharaColors.text,
                              ),
                            ),
                            Text(
                              sub,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontFamily: DharaFonts.ui,
                                fontSize: DharaType.xs,
                                height: 1.4,
                                color: DharaColors.text2,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Align(
                        alignment: Alignment.bottomLeft,
                        child: WatchedBar(progress: item.progress),
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

/// The prototype's `.progress`: how much of a video was watched, as a thin
/// bar along the foot of its picture.
class WatchedBar extends StatelessWidget {
  const WatchedBar({super.key, required this.progress});

  /// 0 to 1.
  final double progress;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 4,
    width: double.infinity,
    child: ColoredBox(
      color: const Color(0x2EFFFFFF),
      child: FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: progress.clamp(0, 1).toDouble(),
        child: const DecoratedBox(
          decoration: BoxDecoration(gradient: DharaColors.accentGradient),
        ),
      ),
    ),
  );
}

/// Darker towards the foot, under the name.
const _wideShade = ShadeSpec(
  colors: [Color(0x00000000), Color(0x00000000), Color(0xD9000000)],
  stops: [0, .4, 1],
);

/// The prototype's `.disc`: the round play mark over a picture.
class _Disc extends StatelessWidget {
  const _Disc();

  @override
  Widget build(BuildContext context) => Container(
    width: 3 * rem,
    height: 3 * rem,
    decoration: const BoxDecoration(
      shape: BoxShape.circle,
      gradient: DharaColors.accentGradient,
      boxShadow: [
        BoxShadow(
          color: Color(0x80000000),
          offset: Offset(0, .5 * rem),
          blurRadius: 1.5 * rem,
        ),
      ],
    ),
    child: const Icon(
      DharaIcons.play,
      size: 1.7 * rem,
      color: DharaColors.onAccent,
    ),
  );
}
