import 'dart:async';
import 'dart:isolate';

import 'package:dhara/core/db/library_isolate.dart';
import 'package:dhara/features/indexer/index_controller.dart';
import 'package:dhara/features/metadata/match_controller.dart';
import 'package:dhara/features/metadata/titles_controller.dart';
import 'package:dhara/features/snapshot/snapshot_writer.dart';
import 'package:flutter/widgets.dart';

/// Writes the library out as a snapshot for a production build to start
/// from, and says how far that is. Only a development build has one.
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
  var _rowsDone = 0;
  var _rowsTotal = 0;
  SnapshotWritten? _written;
  var _failed = false;
  var _disposed = false;

  /// A snapshot is being written.
  bool get isWriting => _run != null;

  /// One can be written now: not while the library is being changed by a
  /// crawl, the reading of file names or a run of matching, which would
  /// leave it half of each.
  bool get canWrite =>
      !isWriting &&
      !_index.isRunning &&
      !_titles.isReading &&
      !_match.isRunning;

  /// How many rows of the one being written are in the file, and how many
  /// there are.
  int get rowsDone => _rowsDone;
  int get rowsTotal => _rowsTotal;

  /// The snapshot written last in this run of the app, if that went well.
  SnapshotWritten? get written => _written;

  /// The last one could not be written (the folder refused, the disk is
  /// full).
  bool get failed => _failed;

  /// Writes a snapshot to the file at [path], replacing what is there, and
  /// completes when that has ended one way or the other. Does nothing
  /// while [canWrite] says no. Never throws.
  Future<void> write(String path) {
    if (!canWrite) return _run ?? Future.value();
    return _run = _write(path);
  }

  @override
  void dispose() {
    _disposed = true;
    _index.removeListener(_notify);
    _titles.removeListener(_notify);
    _match.removeListener(_notify);
    super.dispose();
  }

  Future<void> _write(String path) async {
    _failed = false;
    _written = null;
    _rowsDone = 0;
    _rowsTotal = 0;
    final events = ReceivePort();
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
      final written = await _library.run(writeSnapshot, (
        path,
        events.sendPort,
      ));
      _written = written;
      // The last word on the way may still be under way.
      _rowsDone = _rowsTotal = written.rows;
    } on LibraryWorkException {
      _failed = true;
    } finally {
      events.close();
      _run = null;
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }
}

/// Makes the [LibrarySnapshotController] available to the widget tree.
class LibrarySnapshotScope
    extends InheritedNotifier<LibrarySnapshotController> {
  const LibrarySnapshotScope({
    super.key,
    required LibrarySnapshotController controller,
    required super.child,
  }) : super(notifier: controller);

  /// The controller, if there is one above (a production build has none);
  /// the calling widget rebuilds whenever it changes.
  static LibrarySnapshotController? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<LibrarySnapshotScope>()
      ?.notifier;
}
