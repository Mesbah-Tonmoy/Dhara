import 'package:dhara/features/snapshot/first_start_controller.dart';
import 'package:dhara/features/snapshot/snapshot_fetcher.dart';
import 'package:dhara/features/snapshot/snapshot_reader.dart';
import 'package:flutter/foundation.dart';

/// A first start that is wherever a test puts it. Call [change] after
/// setting what it should say.
class FakeFirstStart extends ChangeNotifier implements FirstStartController {
  @override
  bool isWorking = false;
  @override
  FirstStartStep? step;
  @override
  double? progress;
  @override
  int bytesFetched = 0;
  @override
  int? bytesExpected;
  @override
  FirstStartProblem? problem;
  @override
  SnapshotFetchProblem? fetchProblem;
  @override
  SnapshotProblem? readProblem;
  @override
  int? serversFound;

  /// How often the user asked to try again.
  var retries = 0;

  void change() => notifyListeners();

  @override
  Future<void> start() async {}

  @override
  Future<void> retry() async => retries++;
}
