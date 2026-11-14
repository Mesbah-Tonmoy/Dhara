import 'dart:async';
import 'dart:isolate';

import 'package:dhara/core/db/library_db.dart';
import 'package:dhara/core/db/library_isolate.dart';
import 'package:dhara/features/metadata/match_store.dart';
import 'package:dhara/features/metadata/metadata_store.dart';
import 'package:dhara/features/metadata/title_matcher.dart';
import 'package:dhara/features/metadata/titles_controller.dart';
import 'package:dhara/features/metadata/tmdb_cache.dart';
import 'package:dhara/features/metadata/tmdb_client.dart';
import 'package:dhara/features/metadata/tmdb_key.dart';
import 'package:flutter/widgets.dart';

/// How a run of matching ended.
enum MatchEnd {
  /// Every title has been looked up.
  finished,

  /// The user stopped it; it carries on from there next time.
  stopped,

  /// There is no TMDB key.
  noKey,

  /// TMDB does not accept the key.
  keyRefused,

  /// TMDB could not be reached, or kept failing.
  unreachable,

  /// An error in the app itself.
  failed,
}

/// How far a run of matching is.
@immutable
class MatchProgress {
  const MatchProgress({
    this.done = 0,
    this.total = 0,
    this.matched = 0,
    this.unsure = 0,
    this.notFound = 0,
  });

  /// Titles looked up in this run, and how many there were to look up.
  final int done;
  final int total;
  final int matched;
  final int unsure;
  final int notFound;
}

/// Looks the titles of the library up on TMDB (in the library isolate), so
/// that they get their posters and descriptions, and keeps count of how
/// many are matched.
///
/// The first run only starts when the user asks for it: it is thousands of
/// requests. After that, titles that crawls add are looked up by
/// themselves once their names have been read, as long as a key is saved.
class MatchController extends ChangeNotifier {
  MatchController({
    required LibraryWorker library,
    required TitlesController titles,
    required TmdbKeyController tmdbKey,
    Uri? tmdbUrl,
    int tmdbRetries = 3,
  }) : _library = library,
       _titles = titles,
       _tmdbKey = tmdbKey,
       _tmdbUrl = tmdbUrl,
       _tmdbRetries = tmdbRetries {
    _wasReading = titles.isReading;
    _titles.addListener(_onTitlesChanged);
  }

  final LibraryWorker _library;
  final TitlesController _titles;
  final TmdbKeyController _tmdbKey;

  /// Where TMDB is asked; only tests point this elsewhere.
  final Uri? _tmdbUrl;

  /// How often a request that failed is tried again.
  final int _tmdbRetries;

  MatchCounts? _counts;
  MatchProgress? _progress;
  MatchEnd? _lastEnd;
  Future<void>? _run;
  SendPort? _control;
  var _stopping = false;
  var _wasReading = false;
  var _disposed = false;

  /// How many titles are matched, as of the last count; `null` before the
  /// first.
  MatchCounts? get counts => _counts;

  /// A run is under way.
  bool get isRunning => _run != null;

  /// [stop] was called and the run is winding down.
  bool get isStopping => _stopping;

  /// How far the run under way is, or how far the last one got.
  MatchProgress? get progress => _progress;

  /// How the last run of this session ended; `null` if there was none.
  MatchEnd? get lastEnd => _lastEnd;

  /// Counts the titles again. Call once at start-up. Never throws.
  Future<void> load() => _refresh();

  /// Looks up every title that has not been looked up, and completes when
  /// the run has ended. While one is under way this only waits for it.
  /// Never throws.
  Future<void> start() => _run ??= _match();

  /// Stops the run under way. What was matched so far is kept.
  void stop() {
    if (!isRunning || _stopping) return;
    _stopping = true;
    _control?.send(null);
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    _titles.removeListener(_onTitlesChanged);
    super.dispose();
  }

  Future<void> _match() async {
    _progress = const MatchProgress();
    _lastEnd = null;
    final events = ReceivePort();
    events.listen((message) {
      if (message is SendPort) {
        _control = message;
        // Asked to stop before the run could be reached.
        if (_stopping) message.send(null);
      } else if (message case (
        final int done,
        final int total,
        final int matched,
        final int unsure,
        final int notFound,
      )) {
        _progress = MatchProgress(
          done: done,
          total: total,
          matched: matched,
          unsure: unsure,
          notFound: notFound,
        );
        _notify();
      }
    });
    // Lets the caller's `_run` be set before anyone is told.
    scheduleMicrotask(_notify);
    MatchEnd end;
    try {
      final key = await _tmdbKey.key();
      final kind = _tmdbKey.kind;
      if (key == null || kind == null) {
        end = MatchEnd.noKey;
      } else {
        // The key crosses to the library isolate in memory and goes no
        // further than the requests it signs.
        final (name, (done, total, matched, unsure, notFound)) = await _library
            .run(_matchTitles, (
              key,
              kind.index,
              _tmdbUrl,
              _tmdbRetries,
              events.sendPort,
            ));
        end = MatchEnd.values.asNameMap()[name] ?? MatchEnd.failed;
        // The numbers at the end, whatever became of the last report.
        _progress = MatchProgress(
          done: done,
          total: total,
          matched: matched,
          unsure: unsure,
          notFound: notFound,
        );
      }
    } on LibraryWorkException {
      end = MatchEnd.failed;
    }
    events.close();
    _control = null;
    _stopping = false;
    _lastEnd = end;
    _run = null;
    await _refresh();
  }

  /// Names were just read: there may be new titles to look up.
  void _onTitlesChanged() {
    final reading = _titles.isReading;
    final justRead = _wasReading && !reading;
    _wasReading = reading;
    if (justRead) unawaited(_afterNamesRead());
  }

  Future<void> _afterNamesRead() async {
    await _refresh();
    final counts = _counts;
    if (_disposed || isRunning || counts == null) return;
    // Not the first run, which the user starts, and not with a key TMDB
    // has just refused.
    if (counts.pending == 0 || counts.lookedUp == 0) return;
    if (_lastEnd == MatchEnd.keyRefused || !_tmdbKey.hasKey) return;
    await start();
  }

  Future<void> _refresh() async {
    try {
      _counts = await _library.run(_countMatches, null);
    } on LibraryWorkException {
      // The numbers stay as they were.
    }
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }
}

/// Makes the [MatchController] available to the widget tree.
class MatchScope extends InheritedNotifier<MatchController> {
  const MatchScope({
    super.key,
    required MatchController controller,
    required super.child,
  }) : super(notifier: controller);

  /// The controller; the calling widget rebuilds whenever it changes.
  static MatchController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<MatchScope>();
    assert(scope != null, 'No MatchScope above this widget');
    return scope!.notifier!;
  }
}

// What follows runs in the library isolate.

MatchCounts _countMatches(LibraryDb db, Object? _) => MatchStore(db).counts();

/// How many titles are looked up side by side; the TMDB client spaces the
/// requests out whatever this is.
const _sideBySide = 4;

/// After this many titles in a row that TMDB gave no answer for, the run
/// gives up until next time.
const _maxFailuresInARow = 3;

const _progressEveryMs = 200;

/// Looks up the titles that have not been looked up and reports on
/// `events`: first a port that stops the run when anything is sent to it,
/// then `(done, total, matched, unsure, notFound)` now and then. Returns
/// the name of the [MatchEnd] and those numbers as they stand at the end.
Future<(String, (int, int, int, int, int))> _matchTitles(
  LibraryDb db,
  (String, int, Uri?, int, SendPort) request,
) async {
  final (key, kind, tmdbUrl, retries, events) = request;
  final client = TmdbClient(
    key: key,
    kind: TmdbKeyKind.values[kind],
    baseUrl: tmdbUrl,
    retries: retries,
  );
  final store = MatchStore(db);
  final tmdb = CachedTmdb(client, MetadataStore(db));

  var stopping = false;
  final control = ReceivePort();
  control.listen((_) {
    stopping = true;
    // Ends the requests under way at once.
    client.close();
  });
  events.send(control.sendPort);

  var done = 0;
  var matched = 0;
  var unsure = 0;
  var notFound = 0;
  var total = 0;
  final clock = Stopwatch()..start();
  var lastSent = -_progressEveryMs;
  void report({bool always = false}) {
    final now = clock.elapsedMilliseconds;
    if (!always && now - lastSent < _progressEveryMs) return;
    lastSent = now;
    events.send((done, total, matched, unsure, notFound));
  }

  Future<MatchEnd> run() async {
    store.retryNotFound();
    tmdb.forgetOldAnswers();
    total = store.counts().pending;
    report(always: true);

    var after = 0;
    var failuresInARow = 0;
    var unanswered = 0;
    while (!stopping) {
      final batch = store.pendingTitles(after: after);
      if (batch.isEmpty) {
        // Titles TMDB gave no answer for are still to be looked up.
        return unanswered > 0 ? MatchEnd.unreachable : MatchEnd.finished;
      }
      for (var i = 0; i < batch.length && !stopping; i += _sideBySide) {
        final end = i + _sideBySide < batch.length
            ? i + _sideBySide
            : batch.length;
        final group = batch.sublist(i, end);
        final found = await Future.wait([
          for (final title in group) _lookUp(tmdb, title),
        ]);
        for (final (index, result) in found.indexed) {
          final title = group[index];
          switch (result) {
            case final TmdbException error:
              // Cut off by the stop, not by TMDB.
              if (stopping) continue;
              if (error.failure == TmdbFailure.invalidKey) {
                return MatchEnd.keyRefused;
              }
              unanswered++;
              if (++failuresInARow >= _maxFailuresInARow) {
                return MatchEnd.unreachable;
              }
            case null:
              failuresInARow = 0;
              store.markNotFound(title.id);
              notFound++;
              done++;
            case final ScoredCandidate best:
              failuresInARow = 0;
              if (best.confidence < unsureConfidence) {
                store.markNotFound(title.id, confidence: best.confidence);
                notFound++;
              } else {
                final (outcome, _) = store.apply(
                  title.id,
                  best.candidate,
                  confidence: best.confidence,
                );
                switch (outcome) {
                  case MatchOutcome.matched || MatchOutcome.merged:
                    matched++;
                  case MatchOutcome.unsure || MatchOutcome.unsureNotApplied:
                    unsure++;
                  case MatchOutcome.skipped:
                    break;
                }
              }
              done++;
          }
        }
        after = group.last.id;
        report();
      }
    }
    return MatchEnd.stopped;
  }

  try {
    final end = await run();
    return (end.name, (done, total, matched, unsure, notFound));
  } finally {
    control.close();
    client.close();
  }
}

/// The best candidate for [title], `null` if TMDB knows nothing like it,
/// or the error that kept TMDB from answering.
///
/// Asks by name and year first; if that is not a sure match, also without
/// the year (the servers and TMDB often differ by one) and by the name the
/// file gives the title.
Future<Object?> _lookUp(CachedTmdb tmdb, PendingTitle title) async {
  final query = title.query;
  try {
    final candidates = [
      ...await tmdb.candidates(title.kind, title.name, year: title.year),
    ];
    ScoredCandidate? best() => rankCandidates(query, candidates).firstOrNull;
    bool sure() => (best()?.confidence ?? 0) >= sureConfidence;

    if (!sure() && title.year != null) {
      candidates.addAll(await tmdb.candidates(title.kind, title.name));
    }
    final alt = title.altName;
    if (!sure() && alt != null) {
      candidates.addAll(
        await tmdb.candidates(title.kind, alt, year: title.year),
      );
    }
    return best();
  } on TmdbException catch (error) {
    return error;
  }
}
