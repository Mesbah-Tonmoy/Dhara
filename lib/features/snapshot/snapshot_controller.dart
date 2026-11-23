import 'dart:async';
import 'dart:isolate';

import 'package:dhara/core/db/library_isolate.dart';
import 'package:dhara/features/indexer/index_controller.dart';
import 'package:dhara/features/metadata/match_controller.dart';
import 'package:dhara/features/metadata/titles_controller.dart';
import 'package:dhara/features/snapshot/snapshot_reader.dart';
import 'package:dhara/features/snapshot/snapshot_writer.dart';
import 'package:flutter/widgets.dart';

/// Writes the library out as a snapshot, which a production build starts
/// from, and fills an empty library from one; says how far either is.
class LibrarySnapshotController extends ChangeNotifier {
  LibrarySnapshotController({
    required LibraryWorker library,
    required IndexController index,
    required TitlesController titles,
    required MatchController match,
  }) : _library = library,
       _index = index,
       _titles = titles,
       _match = match {
    _index.addListener(_notify);
    _titles.addListener(_notify);
    _match.addListener(_notify);
  }

  final LibraryWorker _library;
  final IndexController _index;
  final TitlesController _titles;
  final MatchController _match;

  Future<void>? _run;
  var _reading = false;
  var _rowsDone = 0;
  var _rowsTotal = 0;
  SnapshotWritten? _written;
  SnapshotRead? _read;
  var _failed = false;
  var _disposed = false;

  /// A snapshot is being written.
  bool get isWriting => _run != null && !_reading;

  /// A snapshot is being read into the library.
  bool get isReading => _run != null && _reading;

  /// One can be written or read now: not while the other is under way, and
  /// not while the library is being changed by a crawl, the reading of
  /// file names or a run of matching.
  bool get isFree =>
      _run == null &&
      !_index.isRunning &&
      !_titles.isReading &&
      !_match.isRunning;

  /// How many rows of the one being written or read are done, and how many
  /// there are.
  int get rowsDone => _rowsDone;
  int get rowsTotal => _rowsTotal;

  /// The snapshot written last in this run of the app, if that went well.
  SnapshotWritten? get written => _written;

  /// The last one could not be written (the folder refused, the disk is
  /// full).
  bool get failed => _failed;

  /// What became of the snapshot read last in this run of the app.
  SnapshotRead? get lastRead => _read;

  /// Writes a snapshot to the file at [path], replacing what is there, and
  /// completes when that has ended one way or the other. Does nothing
  /// while [isFree] says no. Never throws.
  Future<void> write(String path) {
    if (!isFree) return Future.value();
    _reading = false;
    return _run = _work(() async {
      _failed = false;
      _written = null;
      _read = null;
      try {
        final written = await _library.run(writeSnapshot, (
          path,
          _events!.sendPort,
        ));
        _written = written;
        // The last word on the way may still be under way.
        _rowsDone = _rowsTotal = written.rows;
      } on LibraryWorkException {
        _failed = true;
      }
    });
  }

  /// Fills the library from the snapshot file at [path], if the library is
  /// empty, and returns what became of it; the index is read anew, so the
  /// names of the videos and Home follow. Does nothing, and returns
  /// `null`, while [isFree] says no. Never throws.
  ///
  /// Only what lies on a server of the source list is taken: see
  /// `readSnapshot`.
  Future<SnapshotRead?> read(String path) async {
    if (!isFree) return null;
    _reading = true;
    late SnapshotRead read;
    await (_run = _work(() async {
      _read = null;
      _written = null;
      _failed = false;
      // No crawl starts while the library is being filled.
      final release = _index.hold();
      try {
        read = await _library.run(readSnapshot, (
          path,
          _index.sources.sources,
          _events!.sendPort,
        ));
      } on LibraryWorkException {
        read = const SnapshotRead(problem: SnapshotProblem.libraryFailed);
      } finally {
        release();
      }
      _read = read;
    }));
    if (read.ok) await _index.load();
    return read;
  }

  @override
  void dispose() {
    _disposed = true;
    _index.removeListener(_notify);
    _titles.removeListener(_notify);
    _match.removeListener(_notify);
    super.dispose();
  }

  ReceivePort? _events;

  /// Does [work] as the one thing under way, with its progress heard.
  Future<void> _work(Future<void> Function() work) async {
    _rowsDone = 0;
    _rowsTotal = 0;
    final events = _events = ReceivePort();
    events.listen((message) {
      if (message case (final int done, final int total)) {
        _rowsDone = done;
        _rowsTotal = total;
        _notify();
      }
    });
    // Lets the caller's `_run` be set before anyone is told.
    scheduleMicrotask(_notify);
    try {
      await work();
    } finally {
      events.close();
      _events = null;
      _run = null;
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }
}

/// What to tell the user about a snapshot that was not taken.
String snapshotProblemText(SnapshotProblem problem) => switch (problem) {
  SnapshotProblem.unreadable => 'The snapshot file could not be read.',
  SnapshotProblem.notASnapshot => 'That file is not a library snapshot.',
  SnapshotProblem.newerVersion =>
    'The snapshot was written by a newer version of Dhara, which this one '
        'cannot read.',
  SnapshotProblem.cutShort =>
    'The snapshot is not whole: it ends before its end.',
  SnapshotProblem.libraryNotEmpty =>
    'The library is not empty, so nothing was read: a snapshot only fills '
        'an empty library.',
  SnapshotProblem.libraryFailed => 'The library could not be written.',
};

/// Makes the [LibrarySnapshotController] available to the widget tree.
class LibrarySnapshotScope
    extends InheritedNotifier<LibrarySnapshotController> {
  const LibrarySnapshotScope({
    super.key,
    required LibrarySnapshotController controller,
    required super.child,
  }) : super(notifier: controller);

  /// The controller, if there is one above; the calling widget rebuilds
  /// whenever it changes.
  static LibrarySnapshotController? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<LibrarySnapshotScope>()
      ?.notifier;
}
