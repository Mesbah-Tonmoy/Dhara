import 'package:dhara/core/settings/settings_controller.dart';
import 'package:dhara/features/details/details_store.dart';
import 'package:dhara/features/metadata/metadata_store.dart';
import 'package:dhara/features/playback/copy_choice.dart';
import 'package:dhara/features/playback/play.dart';
import 'package:dhara/features/sources/source_store.dart';
import 'package:flutter/foundation.dart';

/// What the Play button of a title's page plays.
@immutable
class PlayChoice {
  const PlayChoice(this.copy, {required this.resume});

  final TitleCopy copy;

  /// It was left unfinished: the player goes on from there.
  final bool resume;

  /// "Play", "Resume", "Play S1 · E2", "Resume Episode 7".
  String get label {
    final verb = resume ? 'Resume' : 'Play';
    final episode = copy.episode;
    return episode == null
        ? verb
        : '$verb ${episodeCode(copy.season, episode)}';
  }
}

/// Which video of [page] to play without asking:
///
/// - the one watched last, if it was left unfinished (it resumes);
/// - after an episode that was watched to the end, the next one;
/// - otherwise the film, or the show's first episode;
///
/// each time the best copy that can be played (see [bestCopy]), for a next
/// episode on the same server if it has one. `null` if nothing can be
/// played.
PlayChoice? nextToPlay(
  TitlePage page,
  SourceStore sources, {
  PreferredQuality preferred = PreferredQuality.best,
}) {
  final copies = page.copies;
  final episodes = episodesIn(copies);

  // The video of it that was watched last.
  TitleCopy? last;
  Watched? seen;
  for (final copy in copies) {
    final watched = page.watched['${copy.url}'];
    if (watched == null || copy.extra != null) continue;
    if (seen == null || watched.at.isAfter(seen.at)) {
      last = copy;
      seen = watched;
    }
  }

  if (last != null && seen != null) {
    if (!seen.finished && canPlayCopy(last, sources)) {
      return PlayChoice(last, resume: true);
    }
    final key = episodeOf(last);
    if (seen.finished && key != null) {
      final keys = episodes.keys.toList();
      for (final next in keys.skip(keys.indexOf(key) + 1)) {
        final copy =
            bestCopy(
              [
                for (final other in episodes[next]!)
                  if (other.sourceId == last.sourceId) other,
              ],
              sources,
              preferred: preferred,
            ) ??
            bestCopy(episodes[next]!, sources, preferred: preferred);
        if (copy != null) return PlayChoice(copy, resume: false);
      }
    }
  }

  final first = bestCopy(
    episodes.isEmpty ? copies : episodes.values.first,
    sources,
    preferred: preferred,
  );
  return first == null ? null : PlayChoice(first, resume: false);
}
