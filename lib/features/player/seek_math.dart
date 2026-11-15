/// Where a skip of [seconds] (negative = back) from [position] lands.
///
/// The result never goes below zero or past [duration]. While the duration
/// is still unknown (zero) only the lower bound applies.
Duration skipTarget({
  required Duration position,
  required Duration duration,
  required int seconds,
}) {
  var target = position + Duration(seconds: seconds);
  if (target < Duration.zero) target = Duration.zero;
  if (duration > Duration.zero && target > duration) target = duration;
  return target;
}

/// Skips up to this long land exactly where they say; longer ones land on
/// a keyframe (see [skipCommand]).
const longestExactSkip = Duration(seconds: 15);

/// This close to the end every skip is exact: a forward keyframe skip
/// lands on the keyframe *after* its target, and there may be none left.
const exactNearEnd = Duration(seconds: 30);

/// The arguments of mpv's `seek` command for a skip from [from] to
/// [target] (the skip buttons and the ← → keys).
///
/// A video can only start decoding at a keyframe, and these lie some
/// seconds apart. An exact seek decodes from the keyframe before the
/// target up to it, which takes a moment; a keyframe seek shows the
/// keyframe itself, at once, but lands up to a few seconds off.
///
/// - A short skip is exact: "back 10 seconds" should be 10 seconds.
/// - A long one goes to a keyframe: half a minute more or a few seconds
///   further makes no difference, the wait does. It is sent as a relative
///   seek, so mpv lands beyond the target in the direction of the skip (a
///   skip never ends where it began).
List<String> skipCommand({
  required Duration from,
  required Duration target,
  required Duration duration,
}) {
  final step = target - from;
  final nearEnd =
      duration > Duration.zero &&
      step > Duration.zero &&
      target > duration - exactNearEnd;
  if (step.abs() <= longestExactSkip || nearEnd) {
    return ['seek', _seconds(target), 'absolute+exact'];
  }
  return ['seek', _seconds(step), 'relative+keyframes'];
}

/// The arguments of mpv's `seek` command for a jump to [target] on the
/// seek bar: to the keyframe at or before it, so the picture is there at
/// once and nothing of the spot that was clicked is missed.
List<String> jumpCommand(Duration target) => [
  'seek',
  _seconds(target),
  'absolute+keyframes',
];

String _seconds(Duration time) =>
    (time.inMilliseconds / 1000).toStringAsFixed(3);
