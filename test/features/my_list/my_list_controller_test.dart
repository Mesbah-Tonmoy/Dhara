import 'package:dhara/core/db/library_db.dart';
import 'package:dhara/core/db/library_isolate.dart';
import 'package:dhara/features/my_list/my_list_controller.dart';
import 'package:dhara/features/my_list/my_list_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late LibraryDb db;

  setUp(() {
    db = LibraryDb.inMemory();
    addTearDown(db.close);
    for (final id in [1, 2, 3]) {
      db.db.execute(
        "INSERT INTO titles (id, kind, name, added_at) VALUES (?, 0, 'T', 0)",
        [id],
      );
    }
  });

  Future<MyListController> open([LibraryWorker? library]) async {
    final list = MyListController(library: library ?? LocalLibrary(db));
    addTearDown(list.dispose);
    await list.load();
    return list;
  }

  test('starts with what was saved, the one added last first', () async {
    MyListStore(db, now: () => DateTime(2026, 1, 1)).add(1);
    MyListStore(db, now: () => DateTime(2026, 1, 2)).add(3);

    final list = await open();

    expect(list.ids, [3, 1]);
    expect(list.contains(3), isTrue);
    expect(list.contains(2), isFalse);
  });

  test('toggle puts a title on, then takes it off, and tells its '
      'listeners at once', () async {
    final list = await open();
    var told = 0;
    list.addListener(() => told++);

    expect(list.toggle(2), isTrue);
    expect(list.contains(2), isTrue);
    expect(told, 1);
    expect(list.toggle(1), isTrue);
    expect(list.ids, [1, 2]);

    expect(list.toggle(2), isFalse);
    expect(list.ids, [1]);
    expect(told, 3);
  });

  test('what was changed is there after a restart', () async {
    final list = await open();
    list
      ..toggle(1)
      ..toggle(2)
      ..toggle(1);
    await pumpEventQueue();

    expect((await open()).ids, [2]);
  });

  test('without a library it lasts for this run, and never throws', () async {
    final list = await open(const NoLibrary());

    expect(list.ids, isEmpty);
    expect(list.toggle(5), isTrue);
    await pumpEventQueue();
    expect(list.contains(5), isTrue);
  });
}
