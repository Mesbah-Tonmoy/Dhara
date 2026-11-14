import 'package:dhara/core/db/library_db.dart';
import 'package:dhara/features/my_list/my_list_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late LibraryDb library;
  late MyListStore store;
  late DateTime clock;

  setUp(() {
    library = LibraryDb.inMemory();
    clock = DateTime(2026, 11, 15, 21);
    store = MyListStore(library, now: () => clock = _later(clock));
    for (final (id, name) in [(1, 'A'), (2, 'B'), (3, 'C')]) {
      library.db.execute(
        'INSERT INTO titles (id, kind, name, added_at) VALUES (?, 0, ?, 0)',
        [id, name],
      );
    }
  });

  tearDown(() => library.close());

  test('lists the titles on it, the one added last first', () {
    expect(store.ids(), isEmpty);

    expect(store.add(2), isTrue);
    expect(store.add(1), isTrue);
    expect(store.add(3), isTrue);

    expect(store.ids(), [3, 1, 2]);
    expect(store.contains(1), isTrue);
  });

  test('a title that is on it already keeps its place', () {
    store
      ..add(1)
      ..add(2);

    expect(store.add(1), isTrue);

    expect(store.ids(), [2, 1]);
  });

  test('takes a title off again', () {
    store
      ..add(1)
      ..add(2)
      ..remove(1)
      // Not on it: nothing happens.
      ..remove(3);

    expect(store.ids(), [2]);
    expect(store.contains(1), isFalse);
  });

  test('does not take a title that is gone', () {
    expect(store.add(99), isFalse);
    expect(store.ids(), isEmpty);
  });

  test('a title that is removed from the library leaves the list', () {
    store.add(1);
    library.db.execute('DELETE FROM titles WHERE id = 1');

    expect(store.ids(), isEmpty);
  });
}

DateTime _later(DateTime time) => time.add(const Duration(seconds: 1));
