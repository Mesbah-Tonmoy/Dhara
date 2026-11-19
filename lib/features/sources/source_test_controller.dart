import 'dart:async';
import 'dart:io';

import 'package:dhara/features/sources/source.dart';
import 'package:dhara/features/sources/source_store.dart';
import 'package:dhara/features/sources/source_tester.dart';
import 'package:flutter/widgets.dart';

/// Where a source stands, for showing it in a list.
enum SourceStatus {
  /// Never tested from this PC.
  untested,

  /// Being tested, or waiting its turn, in the current run.
  testing,

  /// Answered, and the app can read its content.
  readable,

  /// Answered, but the app cannot read it (error, sign-in, no adapter).
  unreadable,
  unreachable,
}

/// Runs the BDIX Tester for the app and remembers what it finds: the full
/// results of this session in memory, and a short record per source in the
/// [SourceStore] so "dead" servers stay marked after a restart.
///
/// A server the app could read gets the type the test found it to be, if
/// the list said something else: a list taken from elsewhere cannot know,
/// and the type decides which adapter reads the server.
///
/// Also passes on every change of the [store], so a screen only has to
/// listen to this one object.
class SourceTestController extends ChangeNotifier {
  SourceTestController({
    required this.store,
    required SourceTester tester,
    DateTime Function() clock = DateTime.now,
  })  : _tester = tester,
        _clock = clock {
    store.addListener(_onStoreChanged);
  }

  /// Enabled sources are tested again on start-up once their last test is
  /// older than this.
  static const retestAfter = Duration(days: 7);

  final SourceStore store;
  final SourceTester _tester;
  final DateTime Function() _clock;

  final _results = <String, SourceTestResult>{};
  final _waiting = <String>{};
  StreamSubscription<SourceTestResult>? _run;
  Completer<void>? _runEnded;
  int _done = 0;
  int _total = 0;

  bool get isTesting => _run != null;

  /// Progress of the current run: [done] of [total] sources.
  int get done => _done;
  int get total => _total;

  /// The full result from this session, if the source was tested in it.
  SourceTestResult? resultOf(String id) => _results[id];

  SourceStatus statusOf(String id) {
    if (_waiting.contains(id)) return SourceStatus.testing;
    final result = _results[id];
    final health = store.healthOf(id);
    final reachable = result?.reachable ?? health?.reachable;
    if (reachable == null) return SourceStatus.untested;
    if (!reachable) return SourceStatus.unreachable;
    return (result?.readable ?? health!.readable)
        ? SourceStatus.readable
        : SourceStatus.unreadable;
  }

  /// The response time found by the latest test, this session's or saved.
  Duration? pingOf(String id) {
    final result = _results[id];
    return result == null ? store.healthOf(id)?.ping : result.ping;
  }

  Future<void> testAll() => test(store.sources);

  /// Tests [sources]. Completes when the run is over or cancelled; does
  /// nothing while another run is going.
  Future<void> test(Iterable<Source> sources) async {
    final list = sources.toList();
    if (isTesting || list.isEmpty) return;

    final health = <String, SourceHealth>{};
    final ended = _runEnded = Completer<void>();
    _waiting.addAll(list.map((source) => source.id));
    _done = 0;
    _total = list.length;
    _run = _tester.testAll(list).listen(
      (result) {
        final id = result.source.id;
        _results[id] = result;
        _waiting.remove(id);
        _done++;
        health[id] = SourceHealth(
          checkedAt: _clock(),
          reachable: result.reachable,
          readable: result.readable,
          ping: result.ping,
        );
        notifyListeners();
      },
      onDone: ended.complete,
    );
    notifyListeners();

    await ended.future;
    _run = null;
    _waiting.clear();
    notifyListeners();
    try {
      await store.recordHealth(health);
    } on FileSystemException {
      // Not saved: the results still show until the app closes.
    }

    final types = <String, SourceType>{};
    for (final id in health.keys) {
      // Gone if the source was edited or removed during the run.
      final result = _results[id];
      final found = result?.readableType;
      if (result == null || found == null) continue;
      if (found == result.source.type) continue;
      types[id] = found;
      // The result is of this same server: it stays with the source.
      _results[id] = SourceTestResult(
        source: result.source.withType(found),
        urls: result.urls,
      );
    }
    try {
      await store.correctTypes(types);
    } on FileSystemException {
      // As above.
    }
  }

  /// Stops the current run; sources already tested keep their results.
  Future<void> cancel() async {
    final run = _run;
    final ended = _runEnded;
    if (run == null || ended == null || ended.isCompleted) return;
    await run.cancel();
    ended.complete();
  }

  /// Enables every source the latest test found readable. Unreachable ones
  /// and ones without an adapter are left as they are.
  Future<void> enableAllReadable() => store.setEnabled(
        [
          for (final source in store.sources)
            if (statusOf(source.id) == SourceStatus.readable) source.id,
        ],
        enabled: true,
      );

  /// Tests the enabled sources whose last test is older than [retestAfter]
  /// (or missing), so servers that died are noticed without the user
  /// having to ask.
  Future<void> retestEnabledIfStale() {
    final oldest = _clock().subtract(retestAfter);
    return test([
      for (final source in store.sources)
        if (store.isEnabled(source.id) &&
            (store.healthOf(source.id)?.checkedAt.isBefore(oldest) ?? true))
          source,
    ]);
  }

  /// A result describes the source as it was when tested: drop it once
  /// that source was edited or removed.
  void _onStoreChanged() {
    final current = {for (final source in store.sources) source.id: source};
    _results.removeWhere((id, result) => current[id] != result.source);
    notifyListeners();
  }

  @override
  void dispose() {
    store.removeListener(_onStoreChanged);
    unawaited(_run?.cancel());
    super.dispose();
  }
}

/// Makes the [SourceTestController] (and through it the source store)
/// available to the widget tree.
class SourcesScope extends InheritedNotifier<SourceTestController> {
  const SourcesScope({
    super.key,
    required SourceTestController controller,
    required super.child,
  }) : super(notifier: controller);

  /// The controller; the calling widget rebuilds whenever it changes.
  static SourceTestController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<SourcesScope>();
    assert(scope != null, 'No SourcesScope above this widget');
    return scope!.notifier!;
  }

  /// The controller, without rebuilding on changes (for event handlers).
  static SourceTestController read(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<SourcesScope>();
    assert(scope != null, 'No SourcesScope above this widget');
    return scope!.notifier!;
  }
}
