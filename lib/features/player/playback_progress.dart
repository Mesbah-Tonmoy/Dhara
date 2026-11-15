/// How long before the end the "up next" countdown appears.
const upNextCountdown = Duration(seconds: 15);

/// How long before a video ends the next one of the queue is got ready
/// (see [nearEnd]).
const readyNextAhead = Duration(seconds: 60);

/// Whether a video at [position] is so near its end that the next one
/// should be got ready: its servers asked, its copy chosen.
bool nearEnd(Duration position, Duration duration) =>
    duration > Duration.zero &&
    position < duration &&
    duration - position <= readyNextAhead;

/// Whether stopping at [position] is worth resuming from later.
///
/// The first moments and the last 5% (credits) do not count: a video left
/// there simply starts from the beginning next time. "First moments" is 10
/// seconds, or 5% of the video for clips shorter than about three minutes.
bool isResumable(Duration position, Duration duration) {
  if (duration <= Duration.zero) return false;
  final fivePercent = duration * 0.05;
  const tenSeconds = Duration(seconds: 10);
  final earliest = fivePercent < tenSeconds ? fivePercent : tenSeconds;
  return position >= earliest && position < duration - fivePercent;
}

/// Whether a video left at [position] counts as watched to the end: only
/// the last 5% (the credits) were left.
bool isWatched(Duration position, Duration duration) =>
    duration > Duration.zero && position >= duration - duration * 0.05;

/// Seconds left until the next video starts, or `null` while the countdown
/// should not be showing (too early, already over, or duration unknown).
int? upNextSecondsLeft(Duration position, Duration duration) {
  if (duration <= Duration.zero) return null;
  final left = duration - position;
  if (left <= Duration.zero || left > upNextCountdown) return null;
  return (left.inMilliseconds / 1000).ceil();
}
