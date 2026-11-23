import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:dhara/core/db/library_isolate.dart';
import 'package:dhara/core/settings/key_value_store.dart';
import 'package:dhara/features/home/home_controller.dart';
import 'package:dhara/features/indexer/index_controller.dart';
import 'package:dhara/features/metadata/titles_controller.dart';
import 'package:dhara/features/snapshot/snapshot_fetcher.dart';
import 'package:dhara/features/snapshot/snapshot_reader.dart';
import 'package:dhara/features/sources/source.dart';
import 'package:dhara/features/sources/source_store.dart';
import 'package:dhara/features/sources/source_test_controller.dart';
import 'package:flutter/widgets.dart';

/// What a first start is doing.
enum FirstStartStep {
  /// Finding out which servers answer from this connection.
  testingServers,

  /// Fetching the library snapshot.
  fetching,

  /// Reading the snapshot into the library.
  reading,
}

/// Why a first start did not fill the library.
enum FirstStartProblem {
  /// This build was made without an address to fetch a snapshot from, or
  /// the app has no folder to keep one in.
  nothingToFetch,

  /// The snapshot could not be fetched.
  notFetched,

  /// What was fetched is not a snapshot this version reads.
  notRead,
}

/// Makes a production build ready to use the first time it starts, with
/// nothing for the user to do: it fetches the library snapshot and fills
/// the empty library from it, and meanwhile finds out which servers of
/// the starter list answer from this connection and switches on the ones
/// the app can read.
///
/// It only ever acts on what is not there yet. A library that holds
/// something is left alone, and so are the servers once one of them is
/// switched on; a snapshot is fetched by itself once, until one was read.
/// So on a PC where Dhara is in use it does nothing.
///
/// The servers asked are those of the starter list that were checked by
/// hand, at their listed addresses only, like a run of the BDIX Tester:
/// not the unchecked candidates, and no address that is not in the list.
class FirstStartController extends ChangeNotifier {
  FirstStartController({
    required LibraryWorker library,
    required KeyValueStore settings,
    required SourceTestController sources,
    required IndexController index,
    required TitlesController titles,
    required HomeController home,
    required SnapshotFetcher? fetcher,
    required Directory? folder,
    DateTime Function() clock = DateTime.now,
  }) : _library = library,
       _settings = settings,
       _sources = sources,
       _index = index,
       _titles = titles,
       _home = home,
       _fetcher = fetcher,
       _folder = folder,
       _clock = clock;

  /// Where the time a snapshot was read is kept (milliseconds): with it
  /// set, none is fetched again without being asked.
  static const readAtKey = 'library.snapshotReadAt';

  final LibraryWorker _library;
  final KeyValueStore _settings;
  final SourceTestController _sources;
  final IndexController _index;
  final TitlesController _titles;
  final HomeController _home;
  final SnapshotFetcher? _fetcher;
  final Directory? _folder;
  final DateTime Function() _clock;

  Future<void>? _run;
  FirstStartStep? _step;
  FirstStartProblem? _problem;
  SnapshotFetchProblem? _fetchProblem;
  SnapshotProblem? _readProblem;
  var _testing = false;
  var _received = 0;
  int? _expected;
  var _rowsDone = 0;
  var _rowsTotal = 0;
  int? _serversFound;
  var _disposed = false;

  /// The library is being made ready right now.
  bool get isWorking => _run != null;

  /// What is being done; `null` when nothing is. The servers are tested
  /// while the snapshot is fetched and read, and this names the snapshot's
  /// step as long as there is one.
  FirstStartStep? get step =>
      _step ?? (_testing ? FirstStartStep.testingServers : null);

  /// How far the step is, from 0 to 1; `null` if that cannot be said.
  double? get progress => switch (step) {
    FirstStartStep.fetching => switch (_expected) {
      final int expected when expected > 0 =>
        (_received / expected).clamp(0, 1).toDouble(),
      _ => null,
    },
    FirstStartStep.reading =>
      _rowsTotal > 0 ? (_rowsDone / _rowsTotal).clamp(0, 1).toDouble() : null,
    FirstStartStep.testingServers =>
      _sources.total > 0
          ? (_sources.done / _sources.total).clamp(0, 1).toDouble()
          : null,
    null => null,
  };

  /// How much of the snapshot has been fetched, and how large it is if
  /// the place it comes from says.
  int get bytesFetched => _received;
  int? get bytesExpected => _expected;

  /// Why the library was not filled by the last try; `null` if it was, or
  /// if there was nothing to do.
  FirstStartProblem? get problem => _problem;

  /// More about [FirstStartProblem.notFetched] and
  /// [FirstStartProblem.notRead].
  SnapshotFetchProblem? get fetchProblem => _fetchProblem;
  SnapshotProblem? get readProblem => _readProblem;

  /// How many servers the last try found readable and switched on; `null`
  /// if it did not test them (one was switched on already).
  int? get serversFound => _serversFound;

  /// Does what a first start has to do, if anything, and completes when
  /// that has ended one way or the other. Call it once the app runs.
  /// Never throws.
  Future<void> start() => _run ??= _work(asked: false);

  /// Tries again after a [problem]: the user asked for it.
  Future<void> retry() => _run ??= _work(asked: true);

  @override
  void dispose() {
    _disposed = true;
    _fetcher?.close();
    super.dispose();
  }

  Future<void> _work({required bool asked}) async {
    try {
      final bool empty;
      try {
        empty = await _library.run(isLibraryEmpty, null);
      } on LibraryWorkException {
        // No library in this run: nothing to fill.
        return;
      }
      final fill = empty && (asked || _settings.getInt(readAtKey) == null);
      final store = _sources.store;
      final test = !store.sources.any((source) => store.isEnabled(source.id));
      if (!fill && !(test && empty)) return;

      _problem = null;
      _fetchProblem = null;
      _readProblem = null;
      _notify();
      await Future.wait([if (test) _testServers(), if (fill) _fillLibrary()]);
      if (_problem == null && fill) {
        // The names of the videos are counted and Home is read before the
        // work counts as done, so that Home goes from this to its rows.
        await _titles.refresh();
        await _home.refresh();
      }
    } finally {
      _step = null;
      _testing = false;
      _run = null;
      _notify();
    }
  }

  /// Tests the servers of the starter list that were checked by hand, and
  /// switches on the ones the app can read.
  Future<void> _testServers() async {
    final store = _sources.store;
    final servers = [
      for (final source in store.sources)
        if (!isCandidateCopy(source) && source.type != SourceType.customSite)
          source,
    ];
    _testing = true;
    _notify();
    void pass() => _notify();
    _sources.addListener(pass);
    try {
      await _sources.test(servers);
      final readable = [
        for (final source in servers)
          if (_sources.resultOf(source.id)?.readable ?? false) source.id,
      ];
      _serversFound = readable.length;
      try {
        await store.setEnabled(readable, enabled: true);
      } on FileSystemException {
        // Not saved: they are switched on until the app closes.
      }
    } finally {
      _sources.removeListener(pass);
      _testing = false;
      _notify();
    }
  }

  /// Fetches the snapshot, unless one lies here from a start that was cut
  /// off, and reads it into the library.
  Future<void> _fillLibrary() async {
    final fetcher = _fetcher;
    final folder = _folder;
    if (folder == null) {
      _problem = FirstStartProblem.nothingToFetch;
      return;
    }
    final file = File(
      '${folder.path}${Platform.pathSeparator}library.snapshot.gz',
    );
    try {
      // One that was fetched whole before the app was closed is read
      // without asking for it again; if it is not good, it is fetched.
      if (await file.exists() && await _read(file)) return;
      if (fetcher == null) {
        _problem = FirstStartProblem.nothingToFetch;
        return;
      }
      _step = FirstStartStep.fetching;
      _received = 0;
      _expected = null;
      _notify();
      final lastTold = Stopwatch()..start();
      final fetched = await fetcher.fetch(
        file,
        onProgress: (received, total) {
          _received = received;
          _expected = total;
          // A fast connection reports hundreds of times a second.
          if (lastTold.elapsedMilliseconds >= 100) {
            lastTold.reset();
            _notify();
          }
        },
      );
      if (!fetched.ok) {
        _problem = FirstStartProblem.notFetched;
        _fetchProblem = fetched.problem;
        return;
      }
      if (!await _read(file)) _problem = FirstStartProblem.notRead;
    } on FileSystemException {
      _problem = FirstStartProblem.notFetched;
      _fetchProblem = SnapshotFetchProblem.notSaved;
    }
  }

  /// Reads the snapshot in [file] into the library and removes the file;
  /// returns whether the library took it.
  Future<bool> _read(File file) async {
    // No crawl starts while the library is being filled.
    final release = _index.hold();
    _step = FirstStartStep.reading;
    _rowsDone = 0;
    _rowsTotal = 0;
    _notify();
    final events = ReceivePort();
    events.listen((message) {
      if (message case (final int done, final int total)) {
        _rowsDone = done;
        _rowsTotal = total;
        _notify();
      }
    });
    SnapshotRead read;
    try {
      read = await _library.run(readSnapshot, (
        file.path,
        _sources.store.sources,
        events.sendPort,
      ));
    } on LibraryWorkException {
      read = const SnapshotRead(problem: SnapshotProblem.libraryFailed);
    } finally {
      release();
      events.close();
    }
    // Read or refused, the file has done its part. A library that could
    // not be written may do better next time, with the same file.
    if (read.problem != SnapshotProblem.libraryFailed) {
      try {
        await file.delete();
      } on FileSystemException {
        // It is found, and tried, at the next start.
      }
    }
    _readProblem = read.problem;
    if (!read.ok) return false;
    await _settings.setInt(readAtKey, _clock().millisecondsSinceEpoch);
    await _index.load();
    return true;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }
}

/// Makes the [FirstStartController] available to the widget tree.
class FirstStartScope extends InheritedNotifier<FirstStartController> {
  const FirstStartScope({
    super.key,
    required FirstStartController controller,
    required super.child,
  }) : super(notifier: controller);

  /// The controller, if there is one above (only a production build has
  /// one); the calling widget rebuilds whenever it changes.
  static FirstStartController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<FirstStartScope>()?.notifier;

  /// The same, without rebuilding on changes (for event handlers).
  static FirstStartController? maybeRead(BuildContext context) =>
      context.getInheritedWidgetOfExactType<FirstStartScope>()?.notifier;
}
