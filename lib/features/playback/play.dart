import 'dart:async';

import 'package:dhara/core/settings/settings_controller.dart';
import 'package:dhara/features/home/home_controller.dart';
import 'package:dhara/features/metadata/metadata_store.dart';
import 'package:dhara/features/metadata/titles_controller.dart';
import 'package:dhara/features/playback/copy_choice.dart';
import 'package:dhara/features/playback/smart_start.dart';
import 'package:dhara/features/player/player_screen.dart';
import 'package:dhara/features/sources/source_store.dart';
import 'package:dhara/widgets/toast.dart';
import 'package:flutter/material.dart';

/// "S1 · E2", or "Episode 2" for a show numbered straight through.
String episodeCode(int? season, int episode) =>
    season == null ? 'Episode $episode' : 'S$season · E$episode';

/// What the player calls a copy of [name]: "Vivarium (2019)", or
/// "The Bay · S1 · E2 · Second One". Server-controlled text: show it as
/// plain text only.
String playLabel(String name, TitleCopy copy, {int? year}) {
  final episode = copy.episode;
  if (episode == null) return year == null ? name : '$name ($year)';
  return [
    name,
    episodeCode(copy.season, episode),
    if (copy.episodeName case final called?) called,
  ].join(' · ');
}

/// Opens the player above the shell for [entries], in order, and completes
/// when it is closed again. Home's Continue Watching row is read again
/// then, since something was watched.
Future<void> openPlayer(BuildContext context, List<PlayEntry> entries) async {
  final home = HomeScope.maybeRead(context);
  await Navigator.of(context, rootNavigator: true).push(
    MaterialPageRoute<void>(builder: (_) => PlayerScreen(entries: entries)),
  );
  unawaited(home?.refreshContinueWatching());
}

/// The copies the same video as [copy] can be played from: [copy] first,
/// then the other copies of that film, or of that episode, the best first
/// (see `rankCopies`). A trailer or a sample stands alone.
List<TitleCopy> sameVideo(
  TitleCopy copy,
  Iterable<TitleCopy> copies,
  SourceStore sources, {
  PreferredQuality preferred = PreferredQuality.best,
}) {
  if (copy.extra != null) return [copy];
  final others = [
    for (final other in copies)
      if (other.fileId != copy.fileId &&
          other.extra == null &&
          episodeOf(other) == episodeOf(copy) &&
          other.part == copy.part &&
          canPlayCopy(other, sources))
        other,
  ];
  return [copy, ...rankCopies(others, sources, preferred: preferred)];
}

/// The player's queue for [copy] of the title called [name]: that video,
/// and if it is an episode, the episodes after it (see [queueFrom]).
/// [copies] are all the videos of the title.
///
/// Each video can be played from every copy of it (see [sameVideo]); the
/// player asks their servers and takes the fastest at the preferred
/// quality. With [exact], the first video is played from [copy] and no
/// other: the user picked that copy from the list.
List<PlayEntry> playQueue({
  required String name,
  required TitleCopy copy,
  required List<TitleCopy> copies,
  required SourceStore sources,
  PreferredQuality preferred = PreferredQuality.best,
  int? year,
  bool exact = false,
}) {
  final queue = queueFrom(copy, copies, sources, preferred: preferred);
  return [
    for (final (index, entry) in queue.indexed)
      PlayEntry(
        title: playLabel(name, entry, year: year),
        candidates: [
          for (final each
              in index == 0 && exact
                  ? [entry]
                  : sameVideo(entry, copies, sources, preferred: preferred))
            PlayCandidate(each.url, height: each.height),
        ],
      ),
  ];
}

/// Plays [copy] of the title called [name], and what follows it (see
/// [playQueue]).
Future<void> playCopy(
  BuildContext context, {
  required String name,
  required TitleCopy copy,
  required List<TitleCopy> copies,
  required SourceStore sources,
  int? year,
  bool exact = false,
}) => openPlayer(
  context,
  playQueue(
    name: name,
    year: year,
    copy: copy,
    copies: copies,
    sources: sources,
    preferred: SettingsScope.read(context).preferredQuality,
    exact: exact,
  ),
);

/// Plays the title with the id [title] without asking which copy: the one
/// at [resumeUrl] if the sources still hold it (the player resumes it
/// where it was left), otherwise the best copy of the film, or of the
/// show's first episode. Says so if nothing of it can be played.
Future<void> playTitleById(
  BuildContext context, {
  required int title,
  required String name,
  int? year,
  String? resumeUrl,
}) async {
  final sources = TitlesScope.read(context).index.sources;
  final preferred = SettingsScope.read(context).preferredQuality;
  final copies = await TitlesScope.read(context).copiesOf(title);
  if (!context.mounted) return;

  TitleCopy? copy;
  if (resumeUrl != null) {
    for (final candidate in copies) {
      if ('${candidate.url}' == resumeUrl && canPlayCopy(candidate, sources)) {
        copy = candidate;
        break;
      }
    }
  }
  if (copy == null) {
    final episodes = episodesIn(copies);
    copy = bestCopy(
      episodes.isEmpty ? copies : episodes.values.first,
      sources,
      preferred: preferred,
    );
  }
  if (copy == null) {
    ToastHost.show(
      context,
      copies.isEmpty
          ? 'is not on an enabled server any more.'
          : 'has no copy that can be played from here.',
      lead: name,
    );
    return;
  }
  await playCopy(
    context,
    name: name,
    year: year,
    copy: copy,
    copies: copies,
    sources: sources,
  );
}
