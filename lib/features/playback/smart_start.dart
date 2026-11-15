import 'dart:async';

import 'package:dhara/core/settings/settings_controller.dart';
import 'package:dhara/features/playback/copy_choice.dart';
import 'package:dhara/features/playback/copy_probe.dart';
import 'package:flutter/foundation.dart';

/// One copy a video could be played from.
@immutable
class PlayCandidate {
  const PlayCandidate(this.url, {this.height});

  /// Must come from `parseMediaUrl` or the library, never from raw input.
  final Uri url;

  /// The height of its picture, if its name tells.
  final int? height;
}

/// One video of the player's queue: what to call it, and the copies it can
/// be played from. With several, the player asks their servers and takes
/// the fastest at the preferred quality (see [chooseCopy]); the first is
/// the one to fall back on.
@immutable
class PlayEntry {
  const PlayEntry({required this.candidates, this.title});

  /// A video at one address: nothing to choose.
  PlayEntry.url(Uri url, {String? title})
    : this(candidates: [PlayCandidate(url)], title: title);

  final List<PlayCandidate> candidates;

  /// "The Bay · S1 · E2"; without it, the video goes by its file name.
  /// Shown as plain text only.
  final String? title;
}

/// A video that must not be opened: its server sends the player somewhere
/// the app is not allowed to go.
class PlaybackBlocked implements Exception {
  const PlaybackBlocked(this.message);

  /// Plain English, safe to show.
  final String message;

  @override
  String toString() => 'PlaybackBlocked: $message';
}

/// Which copy of a video is played, and what asking for it found.
@immutable
class CopyChoice {
  const CopyChoice({
    required this.url,
    required this.address,
    required this.asked,
    required this.answered,
    this.answeredIn,
  });

  /// The copy that was chosen (one of the candidates).
  final Uri url;

  /// Where the player fetches it from: [url], or where its server
  /// redirects to.
  final Uri address;

  /// How long its server took to answer; `null` if it did not, and the
  /// copy is opened all the same (the player then reports the problem).
  final Duration? answeredIn;

  /// How many copies were asked for, and how many of their servers had
  /// answered with the video by the time this one was chosen.
  final int asked;
  final int answered;
}

/// Decides which copy to play while the answers of a live ping come in.
///
/// - A copy that was left unfinished ([resume]) is gone on with, if its
///   server answers: the same file, whatever the others are like.
/// - Otherwise the copy whose quality suits [preferred] best (see
///   [qualityOrder]), and among those of one quality the first to answer.
///
/// All copies are asked at the same moment, so the first of a quality to
/// answer is the fastest of it. The choice is therefore made as soon as
/// no copy that would be preferred is still to answer, without waiting
/// for the slower servers.
class CopyPick {
  CopyPick(this.candidates, {required this.preferred, this.resume});

  final List<PlayCandidate> candidates;
  final PreferredQuality preferred;

  /// The address of the copy that has a position to resume from, if any.
  final Uri? resume;

  final _answers = <Uri, CopyProbe>{};

  /// How many copies answered with the video so far.
  int get answered => _answers.values.where((probe) => probe.ok).length;

  CopyProbe? answerOf(Uri url) => _answers[url];

  /// Every copy has answered, or failed to.
  bool get complete =>
      candidates.every((candidate) => _answers.containsKey(candidate.url));

  int _order(PlayCandidate candidate) =>
      qualityOrder(candidate.height, preferred);

  /// Takes one answer. Returns the copy to play if that is now certain,
  /// else `null` (more answers are needed).
  PlayCandidate? add(CopyProbe probe) {
    _answers[probe.url] = probe;
    final resume = this.resume;
    if (resume != null) {
      final answer = _answers[resume];
      // Nothing is decided before the copy to go on with has answered.
      if (answer == null) return null;
      if (answer.ok) {
        return candidates.firstWhere((each) => each.url == resume);
      }
    }
    final best = _best;
    if (best == null) return null;
    final betterToCome = candidates.any(
      (candidate) =>
          !_answers.containsKey(candidate.url) &&
          _order(candidate) < _order(best),
    );
    return betterToCome ? null : best;
  }

  /// The best of the copies that answered, when no more answers will
  /// come; `null` if none did.
  PlayCandidate? settle() {
    final resume = this.resume;
    if (resume != null && (_answers[resume]?.ok ?? false)) {
      return candidates.firstWhere((each) => each.url == resume);
    }
    return _best;
  }

  PlayCandidate? get _best {
    PlayCandidate? best;
    for (final candidate in candidates) {
      final answer = _answers[candidate.url];
      if (answer == null || !answer.ok) continue;
      if (best == null ||
          _order(candidate) < _order(best) ||
          (_order(candidate) == _order(best) &&
              answer.time! < _answers[best.url]!.time!)) {
        best = candidate;
      }
    }
    return best;
  }
}

/// Asks the servers for [candidates] (all at once, through [prober]) and
/// chooses the copy to play, as [CopyPick] says.
///
/// If no server answers with the video, the first copy that is not
/// blocked is opened unchecked: the player then reports the real problem.
/// Throws [PlaybackBlocked] if every copy is redirected to where the app
/// may not go.
Future<CopyChoice> chooseCopy(
  CopyProber prober,
  List<PlayCandidate> candidates, {
  PreferredQuality preferred = PreferredQuality.best,
  Uri? resume,
}) async {
  final pick = CopyPick(candidates, preferred: preferred, resume: resume);
  final chosen = Completer<PlayCandidate?>();
  final answers = prober
      .probe([for (final candidate in candidates) candidate.url])
      .listen(
        (probe) {
          final certain = pick.add(probe);
          if (certain != null && !chosen.isCompleted) chosen.complete(certain);
        },
        onDone: () {
          if (!chosen.isCompleted) chosen.complete(pick.settle());
        },
      );
  final copy = await chosen.future;
  // The slower servers are not waited for.
  unawaited(answers.cancel());

  final asked = {for (final candidate in candidates) candidate.url}.length;
  if (copy != null) {
    final answer = pick.answerOf(copy.url)!;
    return CopyChoice(
      url: copy.url,
      address: answer.address!,
      answeredIn: answer.time,
      asked: asked,
      answered: pick.answered,
    );
  }
  // No server answered with the video.
  for (final candidate in candidates) {
    final answer = pick.answerOf(candidate.url);
    if (answer != null && answer.blocked) continue;
    return CopyChoice(
      url: candidate.url,
      address: candidate.url,
      asked: asked,
      answered: 0,
    );
  }
  throw PlaybackBlocked(
    _lowerFirst(
      pick.answerOf(candidates.first.url)?.problem ??
          'The server redirects this video elsewhere.',
    ),
  );
}

// The player writes "Playback error: " before the message.
String _lowerFirst(String text) =>
    text.isEmpty ? text : text[0].toLowerCase() + text.substring(1);
