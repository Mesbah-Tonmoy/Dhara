import 'package:dhara/core/db/library_db.dart';
import 'package:sqlite3/sqlite3.dart';

/// Reads and writes My List in the library database: the films and shows
/// the user wants to keep at hand.
///
/// A title stays on the list while its videos are gone from every source
/// (they may come back), and moves along when two titles turn out to be
/// one film (see `MatchStore.apply`).
///
/// Every value goes into SQL as a parameter, never as text.
class MyListStore {
  MyListStore(this._library, {DateTime Function() now = DateTime.now})
    : _clock = now;

  final LibraryDb _library;
  final DateTime Function() _clock;

  Database get _db => _library.db;

  /// Puts [title] on the list. Returns whether it is on it now: `false`
  /// if there is no such title (any more). One that is on the list already
  /// keeps its place.
  bool add(int title) {
    _db.execute(
      'INSERT OR IGNORE INTO my_list (title, added_at) '
      'SELECT id, ? FROM titles WHERE id = ?',
      [_clock().millisecondsSinceEpoch, title],
    );
    return contains(title);
  }

  void remove(int title) =>
      _db.execute('DELETE FROM my_list WHERE title = ?', [title]);

  bool contains(int title) =>
      _db.select('SELECT 1 FROM my_list WHERE title = ?', [title]).isNotEmpty;

  /// The ids of the titles on the list, the one added last first.
  List<int> ids() => [
    for (final row in _db.select(
      'SELECT title FROM my_list ORDER BY added_at DESC, title DESC',
    ))
      row['title'] as int,
  ];
}
