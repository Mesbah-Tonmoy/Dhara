import 'dart:async';
import 'dart:isolate';

import 'package:dhara/core/db/library_db.dart';
import 'package:dhara/core/db/library_isolate.dart';
import 'package:dhara/features/metadata/film_details_store.dart';
import 'package:dhara/features/metadata/match_controller.dart';
import 'package:dhara/features/metadata/tmdb_client.dart';
import 'package:dhara/features/metadata/tmdb_key.dart';
import 'package:flutter/widgets.dart';

/// Reads TMDB's page of every matched film once (in the library isolate):
/// its genres, length, director and cast, which a match does not bring.
///
/// It runs by itself whenever titles have been matched or counted, never
/// at the same time as a run of matching, and only with a TMDB key. A
/// large library takes a while the first time (one request per film);
/// what was read is kept, so a run that is cut short goes on from there
/// next time.
class FilmDetailsController extends ChangeNotifier {
  FilmDetailsController({
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
  SendPort? _control;
  Object? _seen;
  var _done = 0;
  var _total = 0;
  var _failed = false;
  var _disposed = false;

  /// Films are being asked about right now.
  bool get isFetching => _run != null;

  /// How many films of this run have been read, and how many there were
  /// to read.
  int get filmsDone => _done;
  int get filmsToDo => _total;

  /// The last run ended early: TMDB could not be reached, refused the key,
  /// or the app failed.
  bool get failed => _failed;

  /// Reads the films that are due, and completes when that is done. Does
  /// nothing without a key or while titles are being matched. Never
  /// throws.
  Future<void> refresh() => _run ??= _fetch();

  @override
  void dispose() {
    _disposed = true;
    _control?.send(null);
    _match.removeListener(_onMatchChanged);
    super.dispose();
  }

  /// Titles were counted or matched: there may be new films. A run of
  /// matching that starts has the line to TMDB to itself.
  void _onMatchChanged() {
    if (_match.isRunning) {
      _control?.send(null);
      return;
    }
    if (isFetching) return;
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
      switch (message) {
        case final SendPort control:
          _control = control;
        case (final int done, final int total):
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
        final (ok, done, total) = await _library.run(_fetchFilms, (
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
    _control = null;
    _run = null;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }
}

/// Makes the [FilmDetailsController] available to the widget tree.
class FilmDetailsScope extends InheritedNotifier<FilmDetailsController> {
  const FilmDetailsScope({
    super.key,
    required FilmDetailsController controller,
    required super.child,
  }) : super(notifier: controller);

  /// The controller, if there is one above; the calling widget rebuilds
  /// whenever it changes.
  static FilmDetailsController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<FilmDetailsScope>()?.notifier;
}

// What follows runs in the library isolate.

/// After this many films in a row that TMDB gave no answer for, the run
/// gives up until next time.
const _maxFailuresInARow = 5;

/// How many films are asked about at the same time, and how far apart the
/// requests start: about fourteen a second, well below what TMDB allows.
const _workers = 4;
const _spacing = Duration(milliseconds: 70);

/// Reads the page of every film that is due and keeps what it says.
/// Reports `(done, total)` on `events` as it goes, after first sending a
/// port; anything sent to that port stops the run. Returns whether it got
/// through, and those numbers at the end.
Future<(bool, int, int)> _fetchFilms(
  LibraryDb db,
  (String, int, Uri?, int, SendPort) request,
) async {
  final (key, kind, tmdbUrl, retries, events) = request;
  final store = FilmDetailsStore(db);
  final total = store.countToFetch();
  if (total == 0) return (true, 0, 0);

  var stopping = false;
  final control = ReceivePort();
  control.listen((_) => stopping = true);
  events.send(control.sendPort);

  final client = TmdbClient(
    key: key,
    kind: TmdbKeyKind.values[kind],
    baseUrl: tmdbUrl,
    retries: retries,
    spacing: _spacing,
    maxInFlight: _workers,
  );
  var done = 0;
  var failures = 0;
  var unanswered = 0;
  var refused = false;
  var after = 0;
  var lastSent = 0;
  try {
    while (!stopping && !refused && failures < _maxFailuresInARow) {
      final batch = store.filmsToFetch(after: after);
      if (batch.isEmpty) break;
      after = batch.last.title;
      var next = 0;

      // Each takes the next film of the batch as soon as it is done with
      // its last, so one slow answer holds nobody up.
      Future<void> worker() async {
        while (!stopping &&
            !refused &&
            failures < _maxFailuresInARow &&
            next < batch.length) {
          final film = batch[next++];
          try {
            store.saveFilm(film, await client.movie(film.tmdbId));
            failures = 0;
          } on TmdbException catch (error) {
            switch (error.failure) {
              case TmdbFailure.invalidKey:
                refused = true;
                return;
              case TmdbFailure.notFound:
                // Gone from TMDB: noted, so it is not asked for again.
                store.saveFilm(film, null);
                failures = 0;
              case TmdbFailure.rateLimited ||
                  TmdbFailure.unreachable ||
                  TmdbFailure.badAnswer:
                failures++;
                unanswered++;
                continue;
            }
          }
          done++;
          // Often enough to see it move, not once per film.
          if (done - lastSent >= 10 || done == total) {
            lastSent = done;
            events.send((done, total));
          }
        }
      }

      await Future.wait([for (var i = 0; i < _workers; i++) worker()]);
      // Lets other work on the library in between.
      await Future<void>.delayed(Duration.zero);
    }
    final ok = !refused && failures < _maxFailuresInARow && unanswered == 0;
    return (ok || stopping, done, total);
  } finally {
    control.close();
    client.close();
  }
}
