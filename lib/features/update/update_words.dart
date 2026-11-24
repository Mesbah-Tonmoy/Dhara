import 'package:dhara/features/update/update_checker.dart';
import 'package:dhara/features/update/update_notice.dart';

/// What Settings says about updates, in a sentence or two: the first of
/// these that applies.
String updateStatus({
  required AppVersion current,
  required bool asking,
  required UpdateNotice? available,
  required UpdateAskProblem? problem,
  required DateTime? askedAt,
  required DateTime now,
}) {
  if (asking) return 'Asking whether a newer version exists…';
  if (available != null) {
    return 'Version ${available.version} is available; this copy is '
        '$current. Nothing is fetched or installed by itself: to have it, '
        'run its installer.';
  }
  switch (problem) {
    case UpdateAskProblem.unreachable:
      return 'The place this copy asks for updates did not answer. Dhara '
          'asks again tomorrow; Check now asks at once.';
    case UpdateAskProblem.notThere:
      return 'The place this copy asks for updates has no update notice '
          'to give right now.';
    case UpdateAskProblem.notSigned:
      return 'An answer came that is not signed by whoever made this '
          'copy. It was ignored.';
    case UpdateAskProblem.notUsable:
      return 'The update notice is of a kind this version cannot use. A '
          'newer Dhara has to be installed by hand.';
    case null:
  }
  if (askedAt != null) {
    return 'This copy, $current, is the newest version. Asked '
        '${_ago(now.difference(askedAt))}.';
  }
  return 'Dhara asks once a day whether a newer version exists. Nothing '
      'is fetched or installed by itself.';
}

/// How long ago something was, in words.
String _ago(Duration time) {
  if (time.inMinutes < 2) return 'just now';
  if (time.inHours < 1) return '${time.inMinutes} minutes ago';
  if (time.inHours < 2) return 'an hour ago';
  if (time.inDays < 1) return '${time.inHours} hours ago';
  if (time.inDays < 2) return 'yesterday';
  return '${time.inDays} days ago';
}
