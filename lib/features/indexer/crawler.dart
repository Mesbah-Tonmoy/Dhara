import 'dart:async';
import 'dart:collection';

import 'package:dhara/core/net/safe_http_client.dart';
import 'package:dhara/features/indexer/index_store.dart';
import 'package:dhara/features/indexer/media_files.dart';
import 'package:dhara/features/sources/adapters/source_adapter.dart';
import 'package:dhara/features/sources/source.dart';
import 'package:flutter/foundation.dart';

/// What keeps a crawl polite to the servers and sure to end.
@immutable
class CrawlLimits {
  const CrawlLimits({
    this.maxDepth = 12,
    this.maxFoldersPerSource = 50000,
    this.requestsPerSource = 2,
    this.hostsAtOnce = 6,
    this.retryDelays = const [Duration(seconds: 2), Duration(seconds: 8)],
    this.failuresToStop = 3,
  });

  /// Folders this many levels below a base URL are the last ones read.
  final int maxDepth;
  final int maxFoldersPerSource;

  /// How many folders of one source are read at the same time.
  final int requestsPerSource;

  /// How many servers are crawled at the same time. Sources on the same
  /// host take turns.
  final int hostsAtOnce;

  /// The waits before trying a folder again after a timeout, a connection
  /// error or a "busy" answer; one more try per entry.
  final List<Duration> retryDelays;

  /// After this many folders in a row failed that way, the server counts
  /// as down and the source is left for the next crawl.
  final int failuresToStop;
}

enum CrawlState {
  running,

  /// Every folder was read.
  complete,

  /// The crawl reached the end, but some folders could not be read.
  incomplete,

  /// The server stopped answering; the next crawl carries on from here.
  stopped,

  /// Stopped by [Crawler.cancel]; the next crawl carries on from here.
  cancelled,

  /// There is no adapter for this type of source.
  skipped,
}

/// How far the crawl of one source is, in this run.
@immutable
class CrawlProgress {
  const CrawlProgress({
    required this.sourceId,
    required this.state,
    this.foldersRead = 0,
    this.foldersFailed = 0,
    this.filesAdded = 0,
    this.filesRemoved = 0,
    this.folder,
    this.message,
  });

  final String sourceId;
  final CrawlState state;
  final int foldersRead;
  final int foldersFailed;
  final int filesAdded;
  final int filesRemoved;

  /// The folder read last, as a path below the base URL. Server-controlled
  /// text: show it only through a plain `Text` widget.
  final String? folder;

  /// What went wrong, in plain English; safe to show.
  final String? message;
}

/// Walks the folders of sources through their adapters and keeps the index
/// in step with what it finds.
///
/// It only ever asks an adapter for a base URL of the source or a folder
/// found below one, a few at a time (see [CrawlLimits]). A folder that
/// cannot be read keeps what the index already holds of it.
class Crawler {
  Crawler({
    required IndexStore store,
    required SourceAdapter? Function(Source source, Uri baseUrl) adapterFor,
    this.limits = const CrawlLimits(),
    void Function(CrawlProgress progress)? onProgress,
    Future<void> Function(Duration delay) wait = _delay,
  }) : _store = store,
       _adapterFor = adapterFor,
       _onProgress = onProgress,
       _wait = wait;

  final IndexStore _store;
  final SourceAdapter? Function(Source source, Uri baseUrl) _adapterFor;
  final void Function(CrawlProgress progress)? _onProgress;
  final Future<void> Function(Duration delay) _wait;
  final CrawlLimits limits;

  final _cancelled = Completer<void>();

  /// Stops the crawl: no new folder is started and waits are cut short.
  /// [crawl] completes once the requests under way have ended (closing the
  /// HTTP client ends them at once). What was found so far is kept.
  void cancel() {
    if (!_cancelled.isCompleted) _cancelled.complete();
  }

  /// Crawls [sources] and completes when all of them have ended, one way
  /// or another; it never throws for a server's sake. With [full], folders
  /// that look unchanged are read too.
  Future<void> crawl(Iterable<Source> sources, {bool full = false}) async {
    final byHost = <String, List<Source>>{};
    for (final source in sources) {
      byHost.putIfAbsent(source.baseUrls.first.host, () => []).add(source);
    }
    final hosts = byHost.values.iterator;

    Future<void> worker() async {
      while (!_cancelled.isCompleted && hosts.moveNext()) {
        for (final source in hosts.current) {
          if (_cancelled.isCompleted) break;
          await _SourceCrawl(this, source).run(full: full);
        }
      }
    }

    await Future.wait([for (var i = 0; i < limits.hostsAtOnce; i++) worker()]);
  }

  static Future<void> _delay(Duration delay) => Future.delayed(delay);
}

/// The crawl of one source in one run.
class _SourceCrawl {
  _SourceCrawl(this._crawler, this._source);

  final Crawler _crawler;
  final Source _source;

  /// One adapter per base URL, so a signed-in session is used throughout.
  final _adapters = <String, SourceAdapter>{};

  var _foldersRead = 0;
  var _foldersFailed = 0;
  var _filesAdded = 0;
  var _filesRemoved = 0;
  var _folderCount = 0;

  /// Folders in a row that failed because the server did not answer.
  var _noAnswers = 0;
  String? _lastProblem;
  String? _stopReason;

  IndexStore get _store => _crawler._store;
  CrawlLimits get _limits => _crawler.limits;
  bool get _cancelled => _crawler._cancelled.isCompleted;

  Future<void> run({required bool full}) async {
    for (final baseUrl in _source.baseUrls) {
      final adapter = _crawler._adapterFor(_source, baseUrl);
      if (adapter != null) _adapters[baseUrl.toString()] = adapter;
    }
    if (_adapters.isEmpty) {
      _report(
        CrawlState.skipped,
        message: 'This type of source is not readable yet.',
      );
      return;
    }

    try {
      final source = _store.beginCrawl(_source.id, [
        for (final url in _adapters.keys) Uri.parse(url),
      ], full: full);
      _folderCount = _store.folderCount(source);
      _report(CrawlState.running);
      await _readPending(source);

      final message = _stopReason ?? _summary();
      _store.finishCrawl(source, error: message);
      _report(
        _cancelled
            ? CrawlState.cancelled
            : _stopReason != null
            ? CrawlState.stopped
            : _foldersFailed > 0
            ? CrawlState.incomplete
            : CrawlState.complete,
        message: message,
      );
    } on Exception {
      // The database refused (disk full, file locked). The other sources
      // still get their turn.
      _report(CrawlState.stopped, message: 'The index could not be written.');
    }
  }

  /// Reads waiting folders, a few at a time, until none is left or the
  /// crawl of this source has to stop.
  Future<void> _readPending(int source) async {
    final waiting = Queue<PendingFolder>();
    final running = <int, Future<void>>{};

    PendingFolder? next() {
      if (waiting.isEmpty) {
        // The folders being read are still marked as waiting.
        waiting.addAll(
          _store
              .pendingFolders(source, limit: 50 + running.length)
              .where((folder) => !running.containsKey(folder.id)),
        );
      }
      return waiting.isEmpty ? null : waiting.removeFirst();
    }

    while (true) {
      while (!_cancelled &&
          _stopReason == null &&
          running.length < _limits.requestsPerSource) {
        final folder = next();
        if (folder == null) break;
        // A block body: `remove` returns this very future, and returning
        // it from the callback would make the future wait for itself.
        running[folder.id] = _read(folder).whenComplete(() {
          running.remove(folder.id);
        });
      }
      if (running.isEmpty) return;
      await Future.any(running.values);
    }
  }

  /// Reads one folder and saves what it holds. Never throws for a
  /// server's sake.
  Future<void> _read(PendingFolder folder) async {
    final FolderListing listing;
    try {
      final adapter = _adapterOf(folder);
      if (adapter == null) {
        throw const SourceReadException('The folder is outside the source.');
      }
      // Once the server has stopped answering, later folders get one try
      // each until it answers again.
      final entries = await _list(adapter, folder.url, retry: _noAnswers == 0);
      listing = await _sort(adapter, entries);
    } on SafeHttpException catch (error) {
      return _failed(folder, error.message, noAnswer: _isTemporary(error));
    } on SourceReadException catch (error) {
      return _failed(folder, error.message, noAnswer: _isTemporary(error));
    } on Exception {
      // Whatever else a strange answer trips over.
      return _failed(folder, 'The answer could not be read.', noAnswer: false);
    }

    final saved = _write(() {
      final changes = _store.saveListing(
        folder,
        listing,
        maxDepth: _limits.maxDepth,
        folderBudget: _limits.maxFoldersPerSource - _folderCount,
      );
      _folderCount += changes.foldersAdded;
      _filesAdded += changes.filesAdded;
      _filesRemoved += changes.filesRemoved;
    });
    if (!saved) return;
    _foldersRead++;
    _noAnswers = 0;
    _report(CrawlState.running, folder: folder.path);
  }

  /// Makes a change to the index. If the database refuses (disk full, file
  /// locked), the crawl of this source stops.
  bool _write(void Function() change) {
    try {
      change();
      return true;
    } on Exception {
      _stopReason = 'The index could not be written.';
      return false;
    }
  }

  void _failed(PendingFolder folder, String problem, {required bool noAnswer}) {
    // A request cut off by cancelling says nothing about the folder; it
    // stays in the queue.
    if (_cancelled) return;
    if (!_write(() => _store.markFailed(folder.id))) return;
    _foldersFailed++;
    _lastProblem = problem;
    _noAnswers = noAnswer ? _noAnswers + 1 : 0;
    if (_noAnswers >= _limits.failuresToStop) {
      _stopReason =
          'The server stopped answering. '
          'The next run carries on from here.';
    }
    _report(CrawlState.running, folder: folder.path);
  }

  /// The adapter of the base URL [folder] is below.
  SourceAdapter? _adapterOf(PendingFolder folder) {
    final url = folder.url.toString();
    String? best;
    for (final baseUrl in _adapters.keys) {
      if (url.startsWith(baseUrl) &&
          (best == null || baseUrl.length > best.length)) {
        best = baseUrl;
      }
    }
    return _adapters[best];
  }

  Future<List<RemoteEntry>> _list(
    SourceAdapter adapter,
    Uri folder, {
    required bool retry,
  }) async {
    for (var attempt = 0; ; attempt++) {
      try {
        return await adapter.list(folder);
      } on Exception catch (error) {
        if (!retry ||
            attempt >= _limits.retryDelays.length ||
            !_isTemporary(error)) {
          rethrow;
        }
        await Future.any([
          _crawler._wait(_limits.retryDelays[attempt]),
          _crawler._cancelled.future,
        ]);
        if (_cancelled) rethrow;
      }
    }
  }

  /// Reduces what a folder holds to what the index keeps: the folders to
  /// read next and the videos, each with its subtitles.
  Future<FolderListing> _sort(
    SourceAdapter adapter,
    List<RemoteEntry> entries,
  ) async {
    final folders = <RemoteEntry>[];
    final videos = <RemoteEntry>[];
    final subtitles = <RemoteEntry>[];
    for (final entry in entries) {
      if (entry.isFolder) {
        folders.add(entry);
      } else {
        switch (mediaKindOf(entry.name)) {
          case MediaKind.video:
            videos.add(entry);
          case MediaKind.subtitle:
            subtitles.add(entry);
          case null:
        }
      }
    }

    // A "Subs" folder next to videos holds their subtitles. It is read
    // right away and, unless it turns out to be an ordinary folder, not
    // crawled as one. Without videos next to it, "Subs" may just as well
    // be a category of subtitled films.
    final subs = videos.isEmpty
        ? null
        : folders.where((entry) => isSubtitleFolder(entry.name)).firstOrNull;
    if (subs != null) {
      try {
        final inside = await _list(adapter, subs.url, retry: false);
        final ordinary = inside.any(
          (entry) =>
              entry.isFolder || mediaKindOf(entry.name) == MediaKind.video,
        );
        if (!ordinary) {
          folders.remove(subs);
          subtitles.addAll(
            inside.where(
              (entry) => mediaKindOf(entry.name) == MediaKind.subtitle,
            ),
          );
        }
      } on Exception {
        // The videos are worth keeping without their subtitles.
        folders.remove(subs);
      }
    }

    final videoOf = matchSubtitles(
      [for (final video in videos) video.name],
      [for (final subtitle in subtitles) subtitle.name],
    );
    final subtitlesOf = <int, List<RemoteEntry>>{};
    for (final (index, video) in videoOf.indexed) {
      if (video != null) (subtitlesOf[video] ??= []).add(subtitles[index]);
    }
    return FolderListing(
      folders: folders,
      videos: [
        for (final (index, video) in videos.indexed)
          IndexedVideo(video, subtitlesOf[index] ?? const []),
      ],
    );
  }

  String? _summary() {
    final parts = [
      if (_foldersFailed > 0)
        '$_foldersFailed ${_foldersFailed == 1 ? 'folder' : 'folders'} could '
            'not be read. Last problem: $_lastProblem',
      if (_folderCount >= _limits.maxFoldersPerSource)
        'The source has more than ${_limits.maxFoldersPerSource} folders; '
            'the rest was left out.',
    ];
    return parts.isEmpty ? null : parts.join(' ');
  }

  void _report(CrawlState state, {String? folder, String? message}) =>
      _crawler._onProgress?.call(
        CrawlProgress(
          sourceId: _source.id,
          state: state,
          foldersRead: _foldersRead,
          foldersFailed: _foldersFailed,
          filesAdded: _filesAdded,
          filesRemoved: _filesRemoved,
          folder: folder,
          message: message,
        ),
      );
}

/// Whether trying again later may help: the server did not answer, or said
/// it is busy.
bool _isTemporary(Exception error) => switch (error) {
  SafeHttpException(:final failure) =>
    failure == SafeHttpFailure.timeout || failure == SafeHttpFailure.network,
  SourceReadException(:final statusCode?) =>
    statusCode == 408 || statusCode == 429 || statusCode >= 500,
  _ => false,
};
