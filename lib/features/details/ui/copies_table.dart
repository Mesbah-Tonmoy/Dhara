import 'package:dhara/features/details/details_store.dart';
import 'package:dhara/features/home/ui/poster_card.dart';
import 'package:dhara/features/metadata/metadata_store.dart';
import 'package:dhara/features/metadata/release_name.dart';
import 'package:dhara/features/playback/copy_choice.dart';
import 'package:dhara/features/playback/copy_probe.dart';
import 'package:dhara/features/playback/play.dart';
import 'package:dhara/features/sources/source.dart';
import 'package:dhara/features/sources/source_store.dart';
import 'package:dhara/theme/tokens.dart';
import 'package:dhara/widgets/buttons.dart';
import 'package:dhara/widgets/chips.dart';
import 'package:dhara/widgets/icons.dart';
import 'package:dhara/widgets/surfaces.dart';
import 'package:flutter/material.dart';

/// A file size the way people say it: "1.6 GB", "700 MB".
String sizeLabel(int bytes) {
  const mb = 1024 * 1024;
  const gb = 1024 * mb;
  if (bytes >= gb) return '${(bytes / gb).toStringAsFixed(1)} GB';
  if (bytes >= mb) return '${(bytes / mb).round()} MB';
  return '${(bytes / 1024).ceil()} KB';
}

/// What the name of a copy says about its sound, for one line: "Dual
/// Audio · Hindi, English".
String describeSound(TitleCopy copy) => [
  if (copy.audio case final audio?) audio.label,
  if (copy.languages.isNotEmpty) copy.languages.join(', '),
].join(' · ');

/// What kind of server a source is, and whose: "h5ai · Carnival".
String describeSource(Source source) => [
  switch (source.type) {
    SourceType.directoryListing => 'Folder listing',
    SourceType.h5ai => 'h5ai',
    SourceType.emby => 'Emby',
    SourceType.jellyfin => 'Jellyfin',
    SourceType.customSite => 'Website',
  },
  if (source.isp ?? source.provider case final who?) who,
].join(' · ');

/// The prototype's copies list (`.copies`): every copy of a film or of one
/// episode with its server, file, quality, size, and how fast its server
/// answers (just now where it was asked, see [pings]; else at its last
/// test); each with a Play button.
///
/// [copies] are listed in the order given (see `rankCopies`); the first
/// one that can be played from a server that answered is marked as the
/// best. File and server names come from outside and are drawn as plain
/// text.
class CopiesTable extends StatelessWidget {
  const CopiesTable({
    super.key,
    required this.copies,
    required this.sources,
    required this.onPlay,
    this.watched = const {},
    this.withEpisode = false,
    this.pings = const {},
  });

  final List<TitleCopy> copies;
  final SourceStore sources;
  final ValueChanged<TitleCopy> onPlay;

  /// What the servers answered when they were asked for the copies just
  /// now, by file id (see `CopyPings`).
  final Map<int, CopyProbe> pings;

  /// How far each copy was watched, by its address.
  final Map<String, Watched> watched;

  /// Says which episode each copy is of: for a list that mixes them.
  final bool withEpisode;

  @override
  Widget build(BuildContext context) {
    TitleCopy? best;
    for (final copy in copies) {
      if (copy.extra == null &&
          canPlayCopy(copy, sources) &&
          reachOf(copy, sources, pings) == CopyReach.online) {
        best = copy;
        break;
      }
    }
    // Without a server that answered, the first that can be played leads.
    final lead =
        best ??
        copies
            .where((copy) => copy.extra == null && canPlayCopy(copy, sources))
            .firstOrNull;
    return GlassCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _Line(
            head: true,
            server: _Head('Server'),
            file: _Head('File'),
            quality: _Head('Quality'),
            size: _Head('Size'),
            ping: _Head('Ping'),
            action: SizedBox.shrink(),
          ),
          for (final copy in copies)
            _CopyLine(
              key: ValueKey('copy-${copy.fileId}'),
              copy: copy,
              sources: sources,
              live: pings[copy.fileId],
              best: identical(copy, best),
              lead: identical(copy, lead),
              watched: watched['${copy.url}'],
              withEpisode: withEpisode,
              onPlay: () => onPlay(copy),
            ),
        ],
      ),
    );
  }
}

class _Head extends StatelessWidget {
  const _Head(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    maxLines: 1,
    style: const TextStyle(
      fontFamily: DharaFonts.ui,
      fontSize: DharaType.xs,
      letterSpacing: .12 * DharaType.xs,
      color: DharaColors.text3,
    ),
  );
}

/// One line of the table: the columns of the prototype's `.copy` grid.
class _Line extends StatelessWidget {
  const _Line({
    required this.server,
    required this.file,
    required this.quality,
    required this.size,
    required this.ping,
    required this.action,
    this.head = false,
    this.hovered = false,
  });

  final Widget server;
  final Widget file;
  final Widget quality;
  final Widget size;
  final Widget ping;
  final Widget action;
  final bool head;
  final bool hovered;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: hovered ? DharaColors.surface : null,
      border: head
          ? null
          : const Border(top: BorderSide(color: DharaColors.stroke)),
    ),
    child: Padding(
      padding: EdgeInsets.symmetric(
        horizontal: 1.1 * rem,
        vertical: (head ? .6 : .8) * rem,
      ),
      child: Row(
        children: [
          Expanded(flex: 14, child: server),
          const SizedBox(width: rem),
          Expanded(flex: 16, child: file),
          const SizedBox(width: rem),
          SizedBox(width: 9.5 * rem, child: quality),
          const SizedBox(width: rem),
          SizedBox(width: 4.6 * rem, child: size),
          const SizedBox(width: rem),
          SizedBox(width: 6.2 * rem, child: ping),
          const SizedBox(width: rem),
          SizedBox(
            width: 6.4 * rem,
            // Shrinks rather than runs out of its column.
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: action,
            ),
          ),
        ],
      ),
    ),
  );
}

class _CopyLine extends StatefulWidget {
  const _CopyLine({
    super.key,
    required this.copy,
    required this.sources,
    required this.live,
    required this.best,
    required this.lead,
    required this.watched,
    required this.withEpisode,
    required this.onPlay,
  });

  final TitleCopy copy;
  final SourceStore sources;

  /// What its server answered just now, if it was asked.
  final CopyProbe? live;
  final bool best;
  final bool lead;
  final Watched? watched;
  final bool withEpisode;
  final VoidCallback onPlay;

  @override
  State<_CopyLine> createState() => _CopyLineState();
}

class _CopyLineState extends State<_CopyLine> {
  var _hovered = false;

  @override
  Widget build(BuildContext context) {
    final copy = widget.copy;
    final sources = widget.sources;
    final source = sourceOf(copy, sources);
    final live = widget.live;
    final pings = {if (live != null) copy.fileId: live};
    final reach = reachOf(copy, sources, pings);
    final playable = canPlayCopy(copy, sources);
    final quality = qualityLabel(copy.height);
    final seen = widget.watched;
    final episode = copy.episode;
    const small = TextStyle(
      fontFamily: DharaFonts.ui,
      fontSize: DharaType.xs,
      height: 1.4,
      color: DharaColors.text3,
    );
    final under = [
      if (widget.withEpisode && episode != null)
        episodeCode(copy.season, episode),
      if (describeSound(copy) case final sound when sound.isNotEmpty) sound,
      if (seen != null && seen.finished) 'Watched',
    ].join(' · ');

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Opacity(
        opacity: reach == CopyReach.offline ? .5 : 1,
        child: _Line(
          hovered: _hovered,
          server: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      source?.name ?? copy.sourceId,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: DharaFonts.ui,
                        fontSize: DharaType.md,
                        fontWeight: DharaType.semibold,
                        height: 1.3,
                        color: DharaColors.text,
                      ),
                    ),
                  ),
                  if (widget.best) ...[
                    const SizedBox(width: .4 * rem),
                    const DharaBadge('BEST', style: DharaBadgeStyle.good),
                  ],
                ],
              ),
              if (source != null)
                Text(
                  describeSource(source),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: small,
                ),
            ],
          ),
          file: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Tooltip(
                message: copy.name,
                waitDuration: const Duration(milliseconds: 600),
                child: Text(
                  copy.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: DharaFonts.mono,
                    fontFamilyFallback: DharaFonts.monoFallback,
                    fontSize: DharaType.xs,
                    height: 1.4,
                    color: DharaColors.text2,
                  ),
                ),
              ),
              if (under.isNotEmpty)
                Text(
                  under,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: small,
                ),
            ],
          ),
          quality: Wrap(
            spacing: .3 * rem,
            runSpacing: .3 * rem,
            children: [
              for (final (text, style) in [
                if (copy.extra case final extra?)
                  (
                    extra == ExtraKind.trailer ? 'TRAILER' : 'SAMPLE',
                    DharaBadgeStyle.plain,
                  ),
                if (quality != null)
                  (
                    quality,
                    quality == '4K'
                        ? DharaBadgeStyle.accent
                        : DharaBadgeStyle.plain,
                  ),
                if (copy.codec case final codec?)
                  (codec.label.toUpperCase(), DharaBadgeStyle.plain),
                if (copy.is3d) ('3D', DharaBadgeStyle.plain),
              ])
                // In a row of its own so that it is only as wide as its text.
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [DharaBadge(text, style: style)],
                ),
            ],
          ),
          size: Text(
            switch (copy.size) {
              null => '–',
              final bytes => sizeLabel(bytes),
            },
            maxLines: 1,
            style: const TextStyle(
              fontFamily: DharaFonts.ui,
              fontSize: DharaType.sm,
              fontFeatures: [FontFeature.tabularFigures()],
              color: DharaColors.text2,
            ),
          ),
          ping: PingLabel(
            reach: reach,
            ping: pingOf(copy, sources, pings),
            problem: live?.problem,
          ),
          action: playable
              ? DharaButton(
                  key: Key('play-copy-${copy.fileId}'),
                  label: seen != null && !seen.finished ? 'Resume' : 'Play',
                  icon: DharaIcons.play,
                  small: true,
                  style: widget.lead
                      ? DharaButtonStyle.primary
                      : DharaButtonStyle.glass,
                  onPressed: widget.onPlay,
                )
              : Text(
                  // A media server wants a sign-in, which the player
                  // cannot give yet; anything else is no address to play.
                  source?.type == SourceType.emby ||
                          source?.type == SourceType.jellyfin
                      ? 'Needs sign-in'
                      : 'Cannot be played',
                  textAlign: TextAlign.right,
                  style: small,
                ),
        ),
      ),
    );
  }
}

/// The prototype's `.ping`: how a server answered (its last test, or a
/// live ping), as bars and milliseconds; "Offline" if it did not, "Not
/// tested" if it never was. A live ping that found the video missing says
/// "No answer", with [problem] as the reason on hover.
class PingLabel extends StatelessWidget {
  const PingLabel({super.key, required this.reach, this.ping, this.problem});

  final CopyReach reach;
  final Duration? ping;

  /// Why a live ping failed, in plain English.
  final String? problem;

  @override
  Widget build(BuildContext context) {
    if (reach != CopyReach.online) {
      final offline = reach == CopyReach.offline;
      if (problem case final problem? when offline && problem.isNotEmpty) {
        return Tooltip(
          message: problem,
          child: const PingLabel(reach: CopyReach.offline, problem: ''),
        );
      }
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (offline) ...[
            Container(
              width: .45 * rem,
              height: .45 * rem,
              decoration: const BoxDecoration(
                color: DharaColors.bad,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: .4 * rem),
          ],
          Flexible(
            child: Text(
              !offline
                  ? 'Not tested'
                  : problem == null
                  ? 'Offline'
                  : 'No answer',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: DharaFonts.ui,
                fontSize: DharaType.sm,
                color: offline ? DharaColors.bad : DharaColors.text3,
              ),
            ),
          ),
        ],
      );
    }
    final ms = ping?.inMilliseconds;
    final (bars, color) = switch (ms) {
      null => (4, DharaColors.good),
      < 30 => (4, DharaColors.good),
      < 80 => (3, DharaColors.good),
      < 200 => (2, DharaColors.warn),
      _ => (1, DharaColors.bad),
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: .9 * rem,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final (index, share) in const [.3, .55, .78, 1.0].indexed)
                Padding(
                  padding: const EdgeInsets.only(right: 2),
                  child: FractionallySizedBox(
                    heightFactor: share,
                    child: Container(
                      width: 3,
                      decoration: BoxDecoration(
                        color: index < bars ? color : DharaColors.surface2,
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: .45 * rem),
        Flexible(
          child: Text(
            ms == null ? 'Online' : '$ms ms',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: DharaFonts.ui,
              fontSize: DharaType.sm,
              fontWeight: DharaType.semibold,
              fontFeatures: const [FontFeature.tabularFigures()],
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}
