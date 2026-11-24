import 'package:dhara/features/update/installer_fetcher.dart';
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
  bool canInstall = false,
}) {
  if (asking) return 'Asking whether a newer version exists…';
  if (available != null) {
    return canInstall
        ? 'Version ${available.version} is available; this copy is '
              '$current. Nothing is fetched or installed until you choose '
              'Install.'
        : 'Version ${available.version} is available; this copy is '
              '$current. Nothing is fetched or installed by itself: to '
              'have it, run its installer.';
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

/// Why an installer was not fetched or not started, for the user. Each
/// ends by saying what that means: nothing was installed.
String installerProblemWords(InstallerProblem problem) => switch (problem) {
  InstallerProblem.unreachable =>
    'The installer could not be fetched: the place it lies at did not '
        'answer, or stopped answering. Nothing was installed.',
  InstallerProblem.notThere =>
    'The installer is not where the update notice says it is. Nothing '
        'was installed.',
  InstallerProblem.notTheInstaller =>
    'What came is not the installer its maker signed, so it was removed '
        'and not started. Nothing was installed.',
  InstallerProblem.notSaved =>
    'The installer could not be saved on this PC. Is the disk full? '
        'Nothing was installed.',
  InstallerProblem.notStarted =>
    'The installer was fetched and checked, but Windows did not start '
        'it. Nothing was installed.',
};

/// A size in megabytes, as "48.3 MB".
String megabytes(int bytes) =>
    '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';

/// How long ago something was, in words.
String _ago(Duration time) {
  if (time.inMinutes < 2) return 'just now';
  if (time.inHours < 1) return '${time.inMinutes} minutes ago';
  if (time.inHours < 2) return 'an hour ago';
  if (time.inDays < 1) return '${time.inHours} hours ago';
  if (time.inDays < 2) return 'yesterday';
  return '${time.inDays} days ago';
}
