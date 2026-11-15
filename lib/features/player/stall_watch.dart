import 'package:dhara/features/player/playback_progress.dart';

/// What is wrong with a video that does not play on.
enum Trouble {
  /// It was opened, and nothing of it came.
  notOpening('This copy does not start.'),

  /// It plays, and does not move: it waits for more of the video (or for
  /// a seek to be done), and nothing arrives.
  notLoading('The server stopped sending.'),

  /// It stopped before its end: the server broke off, and the player ran
  /// out of what it had read ahead.
  endedEarly('The server broke off before the end.');

  const Trouble(this.message);

  /// Plain English, for the player.
  final String message;
}

/// Notices when the video that is open does not play on: it never starts,
/// or it should be playing and its position stands still.
///
/// Told the state of the player about once a second ([tick]), with the
/// time on a clock that only runs forward. A video the user has paused is
/// never in trouble. Trouble is reported once; [restart] begins afresh
/// for the next video (or the next copy of this one).
class StallWatch {
  StallWatch({
    this.openTimeout = const Duration(seconds: 10),
    this.waitTimeout = const Duration(seconds: 10),
  });

  /// How long a video may take to open (its length to become known). The
  /// server has answered a ping by then, so this is generous.
  final Duration openTimeout;

  /// How long the position of a playing video may stand still. (libmpv
  /// does not always say that it is waiting for data: after a seek into
  /// a part that never arrives it reports neither buffering nor an
  /// error. So only the position counts.)
  final Duration waitTimeout;

  Duration? _openedAt;
  Duration? _waitingSince;
  Duration? _position;
  var _reported = false;

  /// Nothing is watched until the next [restart] (the servers are being
  /// asked, or nothing is open).
  void idle() => _openedAt = null;

  /// A video is being opened [now].
  void restart(Duration now) {
    _openedAt = now;
    _waitingSince = null;
    _position = null;
    _reported = false;
  }

  /// Takes the state of the player at [now]; returns what is wrong, the
  /// one time it is noticed.
  ///
  /// [opened]: the video's length is known. [playing]: it is not paused
  /// (by the user, or at its end). [completed]: it has reached its end.
  Trouble? tick({
    required Duration now,
    required bool opened,
    required bool playing,
    required bool completed,
    required Duration position,
  }) {
    final openedAt = _openedAt;
    if (openedAt == null || _reported) return null;
    if (!opened) {
      if (now - openedAt < openTimeout) return null;
      _reported = true;
      return Trouble.notOpening;
    }
    final waiting = playing && !completed && position == _position;
    _position = position;
    if (!waiting) {
      _waitingSince = null;
      return null;
    }
    final since = _waitingSince ??= now;
    if (now - since < waitTimeout) return null;
    _reported = true;
    return Trouble.notLoading;
  }
}

/// Whether a video that reported its end at [position] really broke off
/// on the way: its end is not near (see [isWatched]: the last 5% count as
/// the end), and more than a few seconds are missing.
bool endedEarly(Duration position, Duration duration) =>
    duration > Duration.zero &&
    !isWatched(position, duration) &&
    duration - position > const Duration(seconds: 3);
