import 'package:dhara/features/indexer/crawler.dart';
import 'package:dhara/features/indexer/index_controller.dart';
import 'package:dhara/features/metadata/match_controller.dart';
import 'package:dhara/features/metadata/titles_controller.dart';
import 'package:dhara/features/snapshot/first_start_controller.dart';
import 'package:dhara/theme/tokens.dart';
import 'package:flutter/material.dart';

/// What the app is doing to the library in the background, in the few
/// words the title bar has room for.
@immutable
class BackgroundActivity {
  const BackgroundActivity(this.label, this.progress, this.explanation);

  /// "Reading servers 12/29".
  final String label;

  /// How far it is, from 0 to 1; `null` if that cannot be said.
  final double? progress;

  /// A sentence for whoever points at it.
  final String explanation;
}

/// What to say in the title bar about the work under way, the first that
/// applies; `null` when nothing is being done.
///
/// The order is the order the work is done in: the library is made ready,
/// the servers are read, the names of new videos are read, and the titles
/// they make are looked up.
BackgroundActivity? backgroundActivity({
  bool gettingReady = false,
  double? readyProgress,
  bool readingServers = false,
  int serversDone = 0,
  int servers = 0,
  bool readingNames = false,
  int namesRead = 0,
  int namesToRead = 0,
  bool lookingUp = false,
  int lookedUp = 0,
  int toLookUp = 0,
}) {
  double? part(int done, int total) =>
      total > 0 ? (done / total).clamp(0, 1).toDouble() : null;
  String percent(double? progress) =>
      progress == null ? '' : ' ${(progress * 100).floor()}%';

  if (gettingReady) {
    return BackgroundActivity(
      'Getting ready${percent(readyProgress)}',
      readyProgress,
      'Dhara is getting its library ready. This is done once and takes a '
          'few minutes.',
    );
  }
  if (readingServers) {
    return BackgroundActivity(
      servers > 0 ? 'Reading servers $serversDone/$servers' : 'Reading servers',
      part(serversDone, servers),
      'Dhara is reading the servers for new films and shows. You can go on '
      'watching; what it finds appears by itself.',
    );
  }
  if (readingNames && namesToRead > 0) {
    final progress = part(namesRead, namesToRead);
    return BackgroundActivity(
      'Reading names${percent(progress)}',
      progress,
      'Dhara is working out which film or show each new video is.',
    );
  }
  if (lookingUp) {
    final progress = part(lookedUp, toLookUp);
    return BackgroundActivity(
      'Finding posters${percent(progress)}',
      progress,
      'Dhara is looking new films and shows up, for their posters and '
          'descriptions.',
    );
  }
  return null;
}

/// A small pill in the title bar that says what the app is doing to the
/// library in the background and how far it is, and is not there when
/// nothing is being done. For a production build, which has no page that
/// shows this.
class ActivityChip extends StatelessWidget {
  const ActivityChip({super.key});

  @override
  Widget build(BuildContext context) {
    final start = FirstStartScope.maybeOf(context);
    final index = IndexScope.of(context);
    final titles = TitlesScope.of(context);
    final match = MatchScope.of(context);

    final servers = index.crawlableSources;
    var serversDone = 0;
    for (final source in servers) {
      final progress = index.progressOf(source.id);
      if (progress != null && progress.state != CrawlState.running) {
        serversDone++;
      }
    }
    final activity = backgroundActivity(
      gettingReady: start?.isWorking ?? false,
      readyProgress: start?.progress,
      readingServers: index.isRunning,
      serversDone: serversDone,
      servers: servers.length,
      readingNames: titles.isReading,
      namesRead: titles.namesRead,
      namesToRead: titles.namesToRead,
      lookingUp: match.isRunning,
      lookedUp: match.progress?.done ?? 0,
      toLookUp: match.progress?.total ?? 0,
    );
    if (activity == null) return const SizedBox.shrink();

    return Tooltip(
      message: activity.explanation,
      child: Semantics(
        label: activity.explanation,
        value: activity.label,
        child: ExcludeSemantics(
          child: Container(
            key: const Key('shell-activity'),
            constraints: const BoxConstraints(maxWidth: 13 * rem),
            padding: const EdgeInsets.symmetric(
              horizontal: .65 * rem,
              vertical: .25 * rem,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(DharaRadii.pill),
              color: DharaColors.surface,
              border: Border.all(color: DharaColors.stroke),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // A ring that fills, never one that spins: nothing here
                // asks for a frame while the numbers stand still.
                SizedBox.square(
                  dimension: .72 * rem,
                  child: CircularProgressIndicator(
                    value: activity.progress ?? 0,
                    strokeWidth: 2,
                    color: DharaColors.accent2,
                    backgroundColor: DharaColors.strokeStrong,
                  ),
                ),
                const SizedBox(width: .5 * rem),
                Flexible(
                  child: Text(
                    activity.label,
                    key: const Key('shell-activity-label'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: DharaFonts.ui,
                      fontSize: DharaType.xs,
                      height: 1.3,
                      fontFeatures: [FontFeature.tabularFigures()],
                      color: DharaColors.text2,
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
