import 'package:dhara/core/db/library_db.dart';
import 'package:dhara/features/browse/ui/browse_screen.dart';
import 'package:dhara/features/home/home_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/test_app.dart';

/// Adds the film [name] to [library], as a crawl of the source "a" and a
/// matching run would leave it.
void _add(LibraryDb library, int id, String name) {
  library.db
    ..execute(
      'INSERT INTO titles (id, kind, name, year, tmdb_id, match_state, '
      'rating, votes, genres, added_at) '
      "VALUES (?, 0, ?, 2020, ?, 1, 7.0, 500, 'Drama', 0)",
      [id, name, id],
    )
    ..execute(
      'INSERT INTO files (folder, name, url, added_at) VALUES (1, ?, ?, 0)',
      ['$name.mkv', 'http://10.0.0.1/a/$id.mkv'],
    )
    ..execute(
      'INSERT INTO file_meta (file, parser, kind, title, height) '
      'VALUES (last_insert_rowid(), 1, 0, ?, 1080)',
      [id],
    );
}

void main() {
  testWidgets('counts all the titles again only when the library has '
      'changed', (tester) async {
    tester.view
      ..physicalSize = const Size(1280, 900)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final library = LibraryDb.inMemory();
    library.db
      ..execute("INSERT INTO sources (id, source_id) VALUES (1, 'a')")
      ..execute(
        'INSERT INTO folders (id, source, url, path, depth) '
        "VALUES (1, 1, 'http://10.0.0.1/a/', 'All', 0)",
      );
    for (var n = 1; n <= 4; n++) {
      _add(library, n, 'Film $n');
    }
    _add(library, 5, 'The Bay');
    final (:app, :sources) = testApp(db: library, sources: [testSource('a')]);
    await sources.setEnabled(['a'], enabled: true);
    await tester.pumpWidget(app);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('rail-search')));
    await tester.pumpAndSettle();

    String info() =>
        tester.widget<Text>(find.byKey(const Key('browse-info'))).data!;
    Future<void> type(String text) async {
      await tester.enterText(find.byKey(const Key('shell-search')), text);
      // The search waits until typing pauses.
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
    }

    await type('film');
    expect(info(), startsWith('4 of 5 titles'));

    // A title arrives, as a crawl would add it.
    _add(library, 77, 'Late');

    // The next search does not count: that takes longer than searching.
    await type('film 3');
    expect(info(), startsWith('1 of 5 titles'));

    // Home is read again whenever the library has changed, and the
    // search follows it.
    await HomeScope.read(tester.element(find.byType(BrowseScreen))).refresh();
    await tester.pumpAndSettle();
    expect(info(), startsWith('1 of 6 titles'));
  });
}
