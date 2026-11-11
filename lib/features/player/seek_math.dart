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
