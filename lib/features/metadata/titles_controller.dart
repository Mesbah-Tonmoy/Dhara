import 'dart:async';
import 'dart:isolate';

import 'package:dhara/core/db/library_db.dart';
import 'package:dhara/core/db/library_isolate.dart';
import 'package:dhara/features/details/details_store.dart';
import 'package:dhara/features/indexer/index_controller.dart';
import 'package:dhara/features/metadata/metadata_store.dart';
import 'package:dhara/features/metadata/video_identity.dart';
import 'package:flutter/widgets.dart';

/// Turns the indexed videos into titles: reads the name of every video the
/// index holds (in the library isolate), so that all copies of a film or
/// show end up under one title, and answers searches over the titles.
///
/// The names are read by themselves: whenever the index has changed and no
/// crawl is under way. While a crawl runs new files keep arriving, so
/// reading waits for its end.
class TitlesController extends ChangeNotifier {
  TitlesController({
    required LibraryWorker library,
    required IndexController index,
  }) : _library = library,
       _index = index {
    _index.addListener(_onIndexChanged);
  }

  final LibraryWorker _library;
  final IndexController _index;

  TitleCounts? _counts;
  Future<void>? _pass;
  String? _readFor;
  var _done = 0;
  var _total = 0;
  var _failed = false;
  var _disposed = false;

  /// The index this belongs to.
  IndexController get index => _index;

  /// How much the library holds, as of the last time names were read;
  /// `null` before the first time.
  TitleCounts? get counts => _counts;

  /// Names are being read right now.
  bool get isReading => _pass != null;

  /// How many names of this pass have been read, and how many there were
  /// to read. Both are 0 if there was nothing to read.
  int get namesRead => _done;
  int get namesToRead => _total;

  /// The last pass ended because of an error in the app itself.
  bool get failed => _failed;

  /// Reads the names that have not been read yet and completes when that
  /// is done. While a pass is under way this only waits for it. Never
  /// throws.
  Future<void> refresh() => _pass ??= _read();

  /// The titles on enabled sources whose name matches [text], best first.
  Future<List<TitleHit>> search(String text, {int limit = 50}) async {
    try {
      return await _library.run(_searchTitles, (text, _enabledIds(), limit));
    } on LibraryWorkException {
      return const [];
    }
  }

  /// Every video of [title] on enabled sources, in the order to show them.
  Future<List<TitleCopy>> copiesOf(int title) async {
    try {
      return await _library.run(_copiesOf, (title, _enabledIds()));
    } on LibraryWorkException {
      return const [];
    }
  }

  /// Everything the page of [title] shows about it; `null` if the title
  /// is gone, or the library does not answer.
  Future<TitlePage?> page(int title) async {
    try {
      return await _library.run(_readPage, (title, _enabledIds()));
    } on LibraryWorkException {
      return null;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _index.removeListener(_onIndexChanged);
    super.dispose();
  }

  void _onIndexChanged() {
    if (_index.isRunning || isReading) return;
    if (_indexState() != _readFor) unawaited(refresh());
  }

  Future<void> _read() async {
    final state = _indexState();
    _failed = false;
    _done = 0;
    _total = 0;
    final events = ReceivePort();
    events.listen((message) {
      if (message case (final int done, final int total)) {
        _done = done;
        _total = total;
        _notify();
      }
    });
    // Lets the caller's `_pass` be set before anyone is told.
    scheduleMicrotask(_notify);
    try {
      _counts = await _library.run(_readNames, events.sendPort);
    } on LibraryWorkException {
      _failed = true;
    } finally {
      events.close();
      // Also after a failure: the next change of the index tries again,
      // not every notification in between.
      _readFor = state;
      _pass = null;
      _notify();
    }
    // The index changed while its names were being read.
    if (!_disposed && !_failed) _onIndexChanged();
  }

  /// What the index holds, as far as it matters here: a change means there
  /// may be names to read or titles to drop.
  String _indexState() => [
    for (final source in _index.sources.sources)
      '${source.id}:${_index.statsOf(source.id)?.files}',
  ].join(',');

  List<String> _enabledIds() => [
    for (final source in _index.sources.sources)
      if (_index.sources.isEnabled(source.id)) source.id,
  ];

  void _notify() {
    if (!_disposed) notifyListeners();
  }
}

/// Makes the [TitlesController] available to the widget tree.
class TitlesScope extends InheritedNotifier<TitlesController> {
  const TitlesScope({
    super.key,
    required TitlesController controller,
    required super.child,
  }) : super(notifier: controller);

  /// The controller; the calling widget rebuilds whenever it changes.
  static TitlesController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<TitlesScope>();
    assert(scope != null, 'No TitlesScope above this widget');
    return scope!.notifier!;
  }

  /// The controller, without rebuilding on changes (for event handlers).
  static TitlesController read(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<TitlesScope>();
    assert(scope != null, 'No TitlesScope above this widget');
    return scope!.notifier!;
  }
}

// What follows runs in the library isolate.

/// How many names are read between two pauses. A batch takes a few
/// hundredths of a second, so a search asked meanwhile is answered soon.
const _batch = 200;

/// Reads every name that has not been read, ties each video to its title,
/// and drops the titles left without a video. Reports `(read, toRead)` on
/// [progress] after every batch.
Future<TitleCounts> _readNames(LibraryDb db, SendPort progress) async {
  final store = MetadataStore(db);
  final total = store.counts().unreadFiles;
  var done = 0;
  int? previous;
  while (true) {
    final files = store.unreadFiles(limit: _batch);
    // The same batch twice would mean it cannot be saved: give up instead
    // of going round for ever.
    if (files.isEmpty || files.first.id == previous) break;
    previous = files.first.id;
    store.saveIdentities({
      for (final file in files)
        file.id: identifyVideo(
          path: file.path,
          name: file.name,
          videosInFolder: file.videosInFolder,
        ),
    });
    done += files.length;
    progress.send((done, total));
    // Lets a search, or the answers a crawl is waiting for, in between.
    await Future<void>.delayed(Duration.zero);
  }
  store.removeTitlesWithoutFiles();
  return store.counts();
}

List<TitleHit> _searchTitles(
  LibraryDb db,
  (String, List<String>, int) request,
) {
  final (text, sourceIds, limit) = request;
  return MetadataStore(
    db,
  ).searchTitles(text, sourceIds: sourceIds, limit: limit);
}

TitlePage? _readPage(LibraryDb db, (int, List<String>) request) {
  final (title, sourceIds) = request;
  return DetailsStore(db, sourceIds: sourceIds).page(title);
}

List<TitleCopy> _copiesOf(LibraryDb db, (int, List<String>) request) {
  final (title, sourceIds) = request;
  return MetadataStore(db).copiesOf(title, sourceIds: sourceIds);
}
