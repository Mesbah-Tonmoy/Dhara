import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dhara/features/update/installer_fetcher.dart';
import 'package:dhara/features/update/update_checker.dart';
import 'package:dhara/features/update/update_notice.dart';

/// An update notice as `tool/sign-update.ps1` writes it, for tests that
/// are not about the signature: [signature] is whatever the test's
/// stand-in for the check is to see.
///
/// [host] is where the test asks for the notice; the installer lies there
/// too, unless [installer] says otherwise.
String updateNoticeText({
  String version = '1.2.0',
  String host = 'updates.example',
  String? installer,
  int size = 50651234,
  String sha256 =
      '9f86d081884c7d659a2feabbc5a48a55f6b3f1a2c1d4e7b8a9c0d1e2f3a4b5c6',
  String? notes,
  List<int> signature = const [1, 2, 3],
}) => jsonEncode({
  'dhara_update': 1,
  'signed': base64.encode(
    utf8.encode(
      jsonEncode({
        'version': version,
        'installer': installer ?? 'https://$host/installer',
        'size': size,
        'sha256': sha256,
        'notes': ?notes,
      }),
    ),
  ),
  'signature': base64.encode(signature),
});

/// A fetcher that fetches nothing: [fetch] reports the bytes of
/// [progress] one after the other, says that it is checking, and gives a
/// checked installer, or [problem] if that is set.
class FakeInstallerFetcher extends InstallerFetcher {
  FakeInstallerFetcher({this.problem, this.progress = const [10, 20]})
    : super(folder: Directory('nowhere'), host: 'updates.example');

  InstallerProblem? problem;
  final List<int> progress;

  /// The notices an installer was fetched for, in order.
  final fetched = <UpdateNotice>[];

  /// How often what earlier fetches left was cleared, and how often a
  /// fetch was ended.
  var cleared = 0;
  var cancelled = 0;

  /// Completes when [fetch] may go on after its progress, if a test wants
  /// to hold it. [cancel] lets it go, as a real fetch would end.
  Completer<void>? hold;

  @override
  Future<InstallerFetched> fetch(
    UpdateNotice notice, {
    void Function(int received)? onProgress,
    void Function()? onChecking,
  }) async {
    fetched.add(notice);
    for (final received in progress) {
      await Future<void>.delayed(Duration.zero);
      onProgress?.call(received);
    }
    await hold?.future;
    if (cancelled > 0 && problem == null) {
      return const InstallerFetched.problem(InstallerProblem.unreachable);
    }
    final problemNow = problem;
    if (problemNow != null) return InstallerFetched.problem(problemNow);
    onChecking?.call();
    await Future<void>.delayed(Duration.zero);
    return InstallerFetched.checked(
      CheckedInstaller.forTest(
        File('nowhere/Dhara-Setup-${notice.version}.exe'),
        notice.version,
      ),
    );
  }

  @override
  Future<void> clear() async => cleared++;

  @override
  void cancel() {
    cancelled++;
    final held = hold;
    if (held != null && !held.isCompleted) held.complete();
  }
}

/// A checker that asks nobody: [ask] gives the next of [answers], which
/// are notices as text ([updateNoticeText]) or the problem to report.
/// Every signature fits unless [fits] says otherwise.
class FakeUpdateChecker extends UpdateChecker {
  FakeUpdateChecker({List<Object> answers = const [], this.fits = true})
    : answers = [...answers],
      super(
        Uri.parse('https://updates.example/notice'),
        signed: (message, signature) => true,
      );

  /// What the next askings answer, in order; the last one stays.
  final List<Object> answers;
  bool fits;

  /// How often the place was asked.
  var asked = 0;

  /// Completes when [ask] may answer, if a test wants to hold it.
  Future<void>? hold;

  @override
  Future<UpdateAnswer> ask() async {
    asked++;
    await hold;
    final answer = answers.length > 1 ? answers.removeAt(0) : answers.single;
    return switch (answer) {
      final String text => read(utf8.encode(text)),
      final UpdateAskProblem problem => UpdateAnswer.problem(problem),
      _ => throw ArgumentError.value(answer),
    };
  }

  @override
  UpdateAnswer read(List<int> bytes) {
    final read = readUpdateNotice(
      bytes,
      signed: (message, signature) => fits,
      askedAt: url,
    );
    final notice = read.notice;
    return notice != null
        ? UpdateAnswer.notice(notice, utf8.decode(bytes))
        : UpdateAnswer.problem(switch (read.problem!) {
            UpdateNoticeProblem.notANotice => UpdateAskProblem.notThere,
            UpdateNoticeProblem.notSigned => UpdateAskProblem.notSigned,
            UpdateNoticeProblem.notUsable => UpdateAskProblem.notUsable,
          });
  }
}
