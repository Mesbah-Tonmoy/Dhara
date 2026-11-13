import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:dhara/core/db/library_db.dart';

/// Work to do on the library database. It must be a top-level or static
/// function: it is sent to another isolate, and a closure would drag along
/// whatever it can see.
typedef LibraryWork<A, R> = FutureOr<R> Function(LibraryDb db, A argument);

/// A piece of work on the library failed. [message] is for logs and tests.
class LibraryWorkException implements Exception {
  const LibraryWorkException(this.message);

  final String message;

  @override
  String toString() => 'LibraryWorkException: $message';
}

/// Where work on the library database is done. The UI only ever reaches
/// the database through this, so it never waits for the disk.
abstract interface class LibraryWorker {
  /// Does [work] on the database and returns its result. [argument] and
  /// the result cross to another isolate, so they must be plain data.
  ///
  /// Completes with a [LibraryWorkException] if the work throws.
  Future<R> run<A, R>(LibraryWork<A, R> work, A argument);

  /// Waits for the work under way, then closes the database.
  Future<void> close();
}

/// The library database in a background isolate of its own, which holds
/// the only connection. SQLite calls block, and so does reading large
/// folder pages; here they cannot hold up a frame.
class LibraryIsolate implements LibraryWorker {
  // Listening starts here, before the isolate does: its first message says
  // whether there is a library at all.
  LibraryIsolate._() {
    _replies.listen(_onReply);
  }

  /// Opens the database at [path] in a new isolate; without a path it
  /// lives in memory, for this run only.
  ///
  /// A file that is not a usable database is set aside as `<name>.bad` and
  /// a new one is started (see [replacedDamagedFile]): the index can be
  /// crawled again. Throws a [LibraryDbException] for a file made by a
  /// newer version of the app, and when no database can be opened at all
  /// ([LibraryDbProblem.unavailable]); the file is left alone in both
  /// cases.
  static Future<LibraryIsolate> spawn({String? path}) async {
    try {
      return await _spawn(path);
    } on LibraryDbException catch (error) {
      if (path == null || error.problem != LibraryDbProblem.damaged) rethrow;
    }
    await _setAside(path);
    return (await _spawn(path)).._replacedDamagedFile = true;
  }

  static Future<LibraryIsolate> _spawn(String? path) async {
    final library = LibraryIsolate._();
    try {
      await Isolate.spawn(
        _serve,
        (library._replies.sendPort, path),
        debugName: 'library',
        // Sends `null` when the isolate is gone, however that happened.
        onExit: library._replies.sendPort,
      );
      library._commands = await library._opened.future;
      return library;
    } on Object {
      library._replies.close();
      rethrow;
    }
  }

  final _replies = ReceivePort();
  final _opened = Completer<SendPort>();
  final _closed = Completer<void>();
  final _waiting = <int, Completer<Object?>>{};
  late final SendPort _commands;
  var _nextId = 0;
  var _replacedDamagedFile = false;

  /// The file found at start-up was damaged and has been replaced by an
  /// empty database.
  bool get replacedDamagedFile => _replacedDamagedFile;

  @override
  Future<R> run<A, R>(LibraryWork<A, R> work, A argument) async {
    if (_closed.isCompleted) {
      throw const LibraryWorkException('The library is closed.');
    }
    final id = _nextId++;
    final reply = _waiting[id] = Completer();
    _commands.send(_Request<A, R>(id, work, argument));
    return await reply.future as R;
  }

  @override
  Future<void> close() async {
    if (_closed.isCompleted) return;
    _commands.send(null);
    await _closed.future;
  }

  void _onReply(Object? message) {
    switch (message) {
      case final SendPort commands:
        _opened.complete(commands);
      case final LibraryDbProblem problem:
        _opened.completeError(LibraryDbException(problem));
      case _Reply(:final id, :final result, :final error):
        final reply = _waiting.remove(id);
        if (error == null) {
          reply?.complete(result);
        } else {
          reply?.completeError(LibraryWorkException(error));
        }
      case null:
        // The isolate is gone: it closed the database, could not open it,
        // or broke down.
        const gone = LibraryWorkException('The library is closed.');
        if (!_opened.isCompleted) _opened.completeError(gone);
        for (final reply in _waiting.values) {
          reply.completeError(gone);
        }
        _waiting.clear();
        if (!_closed.isCompleted) _closed.complete();
        _replies.close();
    }
  }

  static Future<void> _setAside(String path) async {
    final bad = File('$path.bad');
    try {
      if (await bad.exists()) await bad.delete();
      await File(path).rename(bad.path);
      // What SQLite keeps next to a database belongs to the old file.
      for (final suffix in const ['-wal', '-shm']) {
        final extra = File('$path$suffix');
        if (await extra.exists()) await extra.delete();
      }
    } on FileSystemException {
      // The second attempt reports whatever is still wrong.
    }
  }
}

/// The library database in the calling isolate: for tests, where nothing
/// may run on a real second thread.
class LocalLibrary implements LibraryWorker {
  LocalLibrary(this._db);

  final LibraryDb _db;

  @override
  Future<R> run<A, R>(LibraryWork<A, R> work, A argument) async {
    try {
      return await work(_db, argument);
    } on Object catch (error) {
      // Errors too, as the isolate does.
      throw LibraryWorkException('$error');
    }
  }

  @override
  Future<void> close() async => _db.close();
}

/// Stands in when no database could be opened, so the rest of the app
/// still runs: every piece of work fails.
class NoLibrary implements LibraryWorker {
  const NoLibrary();

  @override
  Future<R> run<A, R>(LibraryWork<A, R> work, A argument) =>
      Future.error(const LibraryWorkException('There is no library.'));

  @override
  Future<void> close() async {}
}

class _Request<A, R> {
  const _Request(this.id, this.work, this.argument);

  final int id;
  final LibraryWork<A, R> work;
  final A argument;

  FutureOr<R> call(LibraryDb db) => work(db, argument);
}

class _Reply {
  const _Reply(this.id, {this.result, this.error});

  final int id;
  final Object? result;
  final String? error;
}

/// The other isolate: opens the database, then does the work it is sent
/// until told to close.
void _serve((SendPort, String?) start) {
  final (replies, path) = start;
  final LibraryDb db;
  try {
    db = path == null ? LibraryDb.inMemory() : LibraryDb.open(path);
  } on LibraryDbException catch (error) {
    replies.send(error.problem);
    return;
  } on Object {
    // No database to be had: the file cannot be reached (no access, held
    // by another program, a folder in its place) or SQLite itself did not
    // load. Errors too: an uncaught one would leave the caller waiting.
    replies.send(LibraryDbProblem.unavailable);
    return;
  }

  final commands = ReceivePort();
  final underWay = <Future<void>>{};

  Future<void> answer(_Request<Object?, Object?> request) async {
    try {
      final result = await request.call(db);
      try {
        replies.send(_Reply(request.id, result: result));
      } on ArgumentError {
        replies.send(
          _Reply(request.id, error: 'The result cannot leave the isolate.'),
        );
      }
    } on Object catch (error) {
      // Errors too: an uncaught one would end the isolate and leave every
      // caller waiting.
      replies.send(_Reply(request.id, error: '$error'));
    }
  }

  commands.listen((message) async {
    if (message is _Request) {
      late final Future<void> work;
      work = answer(message).whenComplete(() {
        underWay.remove(work);
      });
      underWay.add(work);
      return;
    }
    // Told to close: no new work, finish what is under way. With its last
    // port closed the isolate ends, which tells the other side.
    commands.close();
    await Future.wait(underWay.toList());
    db.close();
  });
  replies.send(commands.sendPort);
}
