import 'dart:async';
import 'dart:isolate';

import 'package:dhara/core/db/library_db.dart';
import 'package:dhara/core/db/library_isolate.dart';
import 'package:dhara/core/net/safe_http_client.dart';
import 'package:dhara/features/indexer/crawler.dart';
import 'package:dhara/features/indexer/index_store.dart';
import 'package:dhara/features/sources/adapters/adapter_factory.dart';
import 'package:dhara/features/sources/source.dart';
import 'package:dhara/features/sources/source_store.dart';
import 'package:flutter/foundation.dart';

/// Runs the indexer for the app: starts and stops crawls in the library
/// isolate, keeps their progress and the size of the index for the UI, and
/// answers searches.
///
/// Also passes on every change of the [SourceStore], so a screen only has
/// to listen to this one object.
class IndexController extends ChangeNotifier {
  IndexController({
    required LibraryWorker library,
    required SourceStore sources,
    required String deviceId,
    DateTime Function() clock = DateTime.now,
  }) : _library = library,
       _sources = sources,
       _deviceId = deviceId,
       _clock = clock {
    _sources.addListener(_onSourcesChanged);
  }

  /// The index is brought up to date at start-up once the last complete
  /// crawl of an enabled source is older than this.
  static const updateAfter = Duration(hours: 24);

  final LibraryWorker _library;
  final SourceStore _sources;
  final String _deviceId;
  final DateTime Function() _clock;

  final _progress = <String, CrawlProgress>{};
  var _stats = <String, SourceIndexStats>{};
  var _knownIds = <String>{};
  Future<void>? _run;
  SendPort? _control;
  var _stopping = false;
  var _failed = false;
  var _disposed = false;

  /// A crawl is under way.
  bool get isRunning => _run != null;

  /// [stop] was called and the crawl is winding down.
  bool get isStopping => _stopping;

  /// The last crawl ended because of an error in the app itself.
  bool get failedUnexpectedly => _failed;

  /// How far the crawl of this source is, in the current or last run of
  /// this session.
  CrawlProgress? progressOf(String sourceId) => _progress[sourceId];

  /// What the index holds of this source, as of the last crawl's end.
  SourceIndexStats? statsOf(String sourceId) => _stats[sourceId];

  /// The sources a crawl reads: enabled, and of a type with an adapter.
  List<Source> get crawlableSources => [
    for (final source in _sources.sources)
      if (_sources.isEnabled(source.id) && source.type != SourceType.customSite)
        source,
  ];

  /// Reads what the index holds. Call once at start-up. Never throws.
  Future<void> load() => _refresh();

  /// Crawls every enabled source and completes when the crawl has ended.
  /// With [full], folders that look unchanged are read again too. While a
  /// crawl is under way this only waits for it.
  Future<void> start({bool full = false}) {
    final running = _run;
    if (running != null) return running;
    final sources = crawlableSources;
    if (sources.isEmpty) return Future.value();
    return _run = _crawl(sources, full);
  }

  /// Starts a crawl if the index was built before and an enabled source
  /// has not been crawled to the end within [updateAfter]. The very first
  /// crawl is big, so it only ever starts when the user asks for it.
  Future<void> updateIfStale() async {
    if (isRunning || _stats.isEmpty) return;
    final now = _clock();
    final stale = crawlableSources.any((source) {
      final finished = _stats[source.id]?.crawlFinishedAt;
      return finished == null || now.difference(finished) > updateAfter;
    });
    if (stale) await start();
  }

  /// Stops the crawl under way; what was found so far is kept and the next
  /// crawl carries on from there.
  void stop() {
    if (!isRunning || _stopping) return;
    _stopping = true;
    _control?.send(null);
    notifyListeners();
  }

  /// The indexed files of enabled sources that match [text], best first.
  Future<List<FileHit>> search(String text, {int limit = 50}) async {
    final ids = [
      for (final source in _sources.sources)
        if (_sources.isEnabled(source.id)) source.id,
    ];
    try {
      return await _library.run(_search, (text, ids, limit));
    } on LibraryWorkException {
      return const [];
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _sources.removeListener(_onSourcesChanged);
    super.dispose();
  }

  Future<void> _crawl(List<Source> sources, bool full) async {
    _progress.clear();
    _failed = false;
    final events = ReceivePort();
    events.listen((message) {
      if (message is SendPort) {
        _control = message;
        // Asked to stop before the crawl could be reached.
        if (_stopping) message.send(null);
      } else if (message is CrawlProgress) {
        _progress[message.sourceId] = message;
        _notify();
      }
    });
    // Lets the caller's `_run` be set before anyone is told.
    scheduleMicrotask(_notify);
    try {
      await _library.run(_crawlSources, (
        sources,
        full,
        _deviceId,
        events.sendPort,
      ));
    } on LibraryWorkException {
      _failed = true;
    } finally {
      events.close();
      _control = null;
      _stopping = false;
      _run = null;
      await _refresh();
    }
  }

  void _onSourcesChanged() {
    final ids = {for (final source in _sources.sources) source.id};
    // A source was removed: what was found on it goes too.
    if (_knownIds.difference(ids).isNotEmpty) unawaited(_refresh());
    _notify();
  }

  /// Reads the size of the index, after dropping sources that are gone
  /// from the source list.
  Future<void> _refresh() async {
    final ids = {for (final source in _sources.sources) source.id};
    // An empty or damaged source list is more likely a loading problem
    // than the user removing everything; the index is kept then.
    final forget = ids.isNotEmpty && !_sources.savedFileWasUnreadable;
    try {
      final stats = await _library.run(
        _readStats,
        forget ? ids.toList() : null,
      );
      _stats = {for (final entry in stats) entry.sourceId: entry};
      _knownIds = ids;
    } on LibraryWorkException {
      // The numbers stay as they were.
    }
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }
}

// What follows runs in the library isolate.

List<FileHit> _search(LibraryDb db, (String, List<String>, int) request) {
  final (text, sourceIds, limit) = request;
  return IndexStore(db).search(text, sourceIds: sourceIds, limit: limit);
}

List<SourceIndexStats> _readStats(LibraryDb db, List<String>? knownIds) {
  final store = IndexStore(db);
  if (knownIds != null) store.removeSourcesExcept(knownIds);
  return store.stats();
}

/// Crawls the sources and reports on `events`: first a port that stops the
/// crawl when anything is sent to it, then [CrawlProgress] values.
Future<void> _crawlSources(
  LibraryDb db,
  (List<Source>, bool, String, SendPort) request,
) async {
  final (sources, full, deviceId, events) = request;
  // The crawl may only talk to the servers of these sources. A redirect
  // or a link to any other host is refused by the client.
  final hosts = {
    for (final source in sources)
      for (final url in source.baseUrls) url.host,
  };
  final client = SafeHttpClient(isAllowedHost: hosts.contains);

  // A busy crawl reads many folders a second; the UI needs a few updates.
  final lastSent = <String, int>{};
  final clock = Stopwatch()..start();
  final crawler = Crawler(
    store: IndexStore(db),
    adapterFor: (source, baseUrl) =>
        adapterFor(source.type, client, baseUrl: baseUrl, deviceId: deviceId),
    onProgress: (progress) {
      if (progress.state == CrawlState.running) {
        final last = lastSent[progress.sourceId];
        final now = clock.elapsedMilliseconds;
        if (last != null && now - last < _progressEveryMs) return;
        lastSent[progress.sourceId] = now;
      }
      events.send(progress);
    },
  );

  final control = ReceivePort();
  control.listen((_) {
    crawler.cancel();
    // Ends the requests under way at once.
    client.close();
  });
  events.send(control.sendPort);
  try {
    await crawler.crawl(sources, full: full);
  } finally {
    control.close();
    client.close();
  }
}

const _progressEveryMs = 200;
