import 'dart:async';
import 'dart:isolate';

import 'package:dhara/core/db/library_db.dart';
import 'package:dhara/core/db/library_isolate.dart';
import 'package:dhara/features/metadata/episode_store.dart';
import 'package:dhara/features/metadata/match_controller.dart';
import 'package:dhara/features/metadata/tmdb_client.dart';
import 'package:dhara/features/metadata/tmdb_key.dart';
import 'package:flutter/foundation.dart';

/// Fetches the seasons and episodes of matched shows from TMDB (in the
/// library isolate): their names, descriptions and stills.
///
/// It runs by itself whenever titles have been matched or counted, never
/// at the same time as a run of matching, and only with a TMDB key. Only
/// the seasons the library has videos of are asked for.
class EpisodesController extends ChangeNotifier {
  EpisodesController({
    required LibraryWorker library,
    required MatchController match,
    required TmdbKeyController tmdbKey,
    Uri? tmdbUrl,
    int tmdbRetries = 3,
  }) : _library = library,
       _match = match,
       _tmdbKey = tmdbKey,
       _tmdbUrl = tmdbUrl,
       _tmdbRetries = tmdbRetries {
    _match.addListener(_onMatchChanged);
  }

  final LibraryWorker _library;
  final MatchController _match;
  final TmdbKeyController _tmdbKey;

  /// Where TMDB is asked; only tests point this elsewhere.
  final Uri? _tmdbUrl;
  final int _tmdbRetries;

  Future<void>? _run;
  Object? _seen;
  var _done = 0;
  var _total = 0;
  var _failed = false;
  var _disposed = false;

  /// Shows are being asked about right now.
  bool get isFetching => _run != null;

  /// How many shows of this run have been fetched, and how many there
  /// were to fetch.
  int get showsDone => _done;
  int get showsToDo => _total;

  /// The last run ended early: TMDB could not be reached, refused the key,
  /// or the app failed.
  bool get failed => _failed;

  /// Asks TMDB about the shows that are due, and completes when that is
  /// done. Does nothing without a key or while titles are being matched.
  /// Never throws.
  Future<void> refresh() => _run ??= _fetch();

  @override
  void dispose() {
    _disposed = true;
    _match.removeListener(_onMatchChanged);
    super.dispose();
  }

  /// Titles were counted or matched: a show may be new, or have a new
  /// season.
  void _onMatchChanged() {
    if (_match.isRunning || isFetching) return;
    final counts = _match.counts;
    if (counts == null || identical(counts, _seen)) return;
    _seen = counts;
    unawaited(refresh());
  }

  Future<void> _fetch() async {
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
    scheduleMicrotask(_notify);
    try {
      final key = await _tmdbKey.key();
      final kind = _tmdbKey.kind;
      if (key != null && kind != null && !_match.isRunning) {
        final (ok, done, total) = await _library.run(_fetchEpisodes, (
          key,
          kind.index,
          _tmdbUrl,
          _tmdbRetries,
          events.sendPort,
        ));
        _failed = !ok;
        _done = done;
        _total = total;
      }
    } on LibraryWorkException {
      _failed = true;
    }
    events.close();
    _run = null;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }
}

// What follows runs in the library isolate.

/// After this many shows in a row that TMDB gave no answer for, the run
/// gives up until next time.
const _maxFailuresInARow = 3;

/// Asks TMDB about every show that is due and keeps the answers. Reports
/// `(done, total)` on `events` after every show. Returns whether it got
/// through, and those numbers at the end.
Future<(bool, int, int)> _fetchEpisodes(
  LibraryDb db,
  (String, int, Uri?, int, SendPort) request,
) async {
  final (key, kind, tmdbUrl, retries, events) = request;
  final store = EpisodeStore(db);
  final shows = store.showsToFetch();
  if (shows.isEmpty) return (true, 0, 0);

  final client = TmdbClient(
    key: key,
    kind: TmdbKeyKind.values[kind],
    baseUrl: tmdbUrl,
    retries: retries,
  );
  var done = 0;
  var failures = 0;
  try {
    for (final show in shows) {
      try {
        final details = await client.show(show.tmdbId);
        final listed = {for (final season in details.seasons) season.number};
        final seasons = <TmdbSeason>[];
        for (final number in show.seasons) {
          // TMDB may count the seasons differently than the folders do.
          if (!listed.contains(number)) continue;
          seasons.add(await client.season(show.tmdbId, number));
        }
        store.saveShow(show, details, seasons);
        failures = 0;
      } on TmdbException catch (error) {
        switch (error.failure) {
          case TmdbFailure.invalidKey:
            return (false, done, shows.length);
          case TmdbFailure.notFound:
            // Gone from TMDB: noted, so it is not asked for every time.
            store.saveShow(show, null, const []);
          case TmdbFailure.rateLimited ||
              TmdbFailure.unreachable ||
              TmdbFailure.badAnswer:
            if (++failures >= _maxFailuresInARow) {
              return (false, done, shows.length);
            }
            continue;
        }
      }
      done++;
      events.send((done, shows.length));
    }
    return (failures == 0, done, shows.length);
  } finally {
    client.close();
  }
}
