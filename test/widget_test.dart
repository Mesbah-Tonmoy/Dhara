import 'package:dhara/app.dart';
import 'package:dhara/core/db/library_db.dart';
import 'package:dhara/core/db/library_isolate.dart';
import 'package:dhara/core/settings/key_value_store.dart';
import 'package:dhara/core/settings/settings_controller.dart';
import 'package:dhara/features/indexer/index_controller.dart';
import 'package:dhara/features/player/resume_store.dart';
import 'package:dhara/features/sources/source_store.dart';
import 'package:dhara/features/sources/source_test_controller.dart';
import 'package:dhara/features/sources/source_tester.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app() {
  final store = MemoryKeyValueStore();
  final sources = SourceStore(starter: const []);
  return DharaApp(
    settings: SettingsController(store),
    resumeStore: ResumeStore(store),
    sourceTests: SourceTestController(
      store: sources,
      tester: SourceTester(deviceId: 'dhara-test'),
    ),
    index: IndexController(
      library: LocalLibrary(LibraryDb.inMemory()),
      sources: sources,
      deviceId: 'dhara-test',
    ),
  );
}

void main() {
  testWidgets('app boots on the open-URL screen', (tester) async {
    await tester.pumpWidget(_app());

    expect(find.byKey(const Key('app-title')), findsOneWidget);
    expect(find.byKey(const Key('url-field')), findsOneWidget);
    expect(find.byKey(const Key('play-button')), findsOneWidget);
  });

  testWidgets('rejects a non-http URL without opening the player',
      (tester) async {
    await tester.pumpWidget(_app());

    await tester.enterText(
      find.byKey(const Key('url-field')),
      'file:///C:/Windows/win.ini',
    );
    await tester.tap(find.byKey(const Key('play-button')));
    await tester.pump();

    expect(
      find.text('Enter a full http:// or https:// video URL.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('url-field')), findsOneWidget);
  });

  testWidgets('names the bad line when several URLs are pasted',
      (tester) async {
    await tester.pumpWidget(_app());

    await tester.enterText(
      find.byKey(const Key('url-field')),
      'http://h.example/e01.mkv\nsmb://h.example/e02.mkv',
    );
    await tester.tap(find.byKey(const Key('play-button')));
    await tester.pump();

    expect(
      find.text('Line 2 is not a full http:// or https:// video URL.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('url-field')), findsOneWidget);
  });
}
