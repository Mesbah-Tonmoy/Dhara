import 'dart:convert';
import 'dart:io';

import 'package:dhara/core/images/image_store.dart';
import 'package:dhara/core/images/remote_image.dart';
import 'package:dhara/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// One transparent pixel as PNG.
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA'
  '60e6kgAAAABJRU5ErkJggg==',
);

void main() {
  Widget picture(RemoteImageStore? store, String? path) => MaterialApp(
    theme: buildDharaTheme(),
    home: ImageStoreScope(
      store: store,
      child: Center(
        child: TmdbPicture(path: path, size: 'w154', width: 46, height: 69),
      ),
    ),
  );

  testWidgets('shows the placeholder when there is no picture', (tester) async {
    await tester.pumpWidget(picture(null, '/a.png'));
    expect(find.byIcon(Icons.movie_outlined), findsOneWidget);
    expect(find.byType(Image), findsNothing);

    final store = RemoteImageStore(folder: null);
    addTearDown(store.close);
    await tester.pumpWidget(picture(store, null));
    await tester.pump();
    expect(find.byIcon(Icons.movie_outlined), findsOneWidget);
    expect(tester.getSize(find.byType(TmdbPicture)), const Size(46, 69));
  });

  testWidgets('shows a picture that is on disk', (tester) async {
    late Directory folder;
    late RemoteImageStore store;
    await tester.runAsync(() async {
      folder = Directory.systemTemp.createTempSync('dhara_picture_test');
      File([folder.path, 'tmdb', 'w154', 'a.png'].join(Platform.pathSeparator))
        ..createSync(recursive: true)
        ..writeAsBytesSync(_png);
      store = RemoteImageStore(folder: folder);
    });
    addTearDown(() {
      store.close();
      folder.deleteSync(recursive: true);
    });

    await tester.pumpWidget(picture(store, '/a.png'));
    // Looking on disk takes real time, and each step of it only goes on
    // when the widget test lets it.
    for (var i = 0; i < 50 && find.byType(Image).evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }

    final image = tester.widget<Image>(find.byType(Image));
    expect(image.fit, BoxFit.cover);
    expect(find.byIcon(Icons.movie_outlined), findsNothing);

    // Another title in the same place: back to the placeholder at once.
    await tester.pumpWidget(picture(store, null));
    expect(find.byType(Image), findsNothing);
    expect(find.byIcon(Icons.movie_outlined), findsOneWidget);
  });

  group('TmdbCover', () {
    const placeholder = Key('placeholder');
    final told = <bool>[];

    Widget cover(RemoteImageStore? store, String? path) => MaterialApp(
      theme: buildDharaTheme(),
      home: ImageStoreScope(
        store: store,
        child: Center(
          child: SizedBox(
            width: 120,
            height: 180,
            child: TmdbCover(
              path: path,
              size: 'w342',
              placeholder: const ColoredBox(
                key: placeholder,
                color: Colors.indigo,
              ),
              onPicture: told.add,
            ),
          ),
        ),
      ),
    );

    setUp(told.clear);

    testWidgets('shows its placeholder when there is no picture', (
      tester,
    ) async {
      await tester.pumpWidget(cover(null, '/a.png'));
      expect(find.byKey(placeholder), findsOneWidget);
      expect(tester.getSize(find.byKey(placeholder)), const Size(120, 180));

      final store = RemoteImageStore(folder: null);
      addTearDown(store.close);
      await tester.pumpWidget(cover(store, null));
      await tester.pump();

      expect(find.byKey(placeholder), findsOneWidget);
      expect(find.byType(Image), findsNothing);
      expect(told, isEmpty);
    });

    testWidgets('fades a picture in over the placeholder and says so', (
      tester,
    ) async {
      late Directory folder;
      late RemoteImageStore store;
      await tester.runAsync(() async {
        folder = Directory.systemTemp.createTempSync('dhara_cover_test');
        File(
            [folder.path, 'tmdb', 'w342', 'a.png'].join(Platform.pathSeparator),
          )
          ..createSync(recursive: true)
          ..writeAsBytesSync(_png);
        store = RemoteImageStore(folder: folder);
      });
      addTearDown(() {
        store.close();
        folder.deleteSync(recursive: true);
      });

      await tester.pumpWidget(cover(store, '/a.png'));
      expect(find.byKey(placeholder), findsOneWidget);
      // Looking on disk and decoding take real time.
      for (var i = 0; i < 50 && told.isEmpty; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }

      expect(told, [true]);
      final image = tester.widget<Image>(find.byType(Image));
      expect(image.fit, BoxFit.cover);
      expect(tester.getSize(find.byType(Image)), const Size(120, 180));
      // Once it has faded in, nothing is drawn under it.
      await tester.pumpAndSettle();
      expect(find.byKey(placeholder), findsNothing);

      // Another title in the same place: the placeholder is back at once.
      await tester.pumpWidget(cover(store, null));
      await tester.pump();
      expect(find.byType(Image), findsNothing);
      expect(find.byKey(placeholder), findsOneWidget);
      expect(told, [true, false]);
    });

    testWidgets('does not ask for a picture while its list is flung', (
      tester,
    ) async {
      final store = _CountingStore();
      addTearDown(store.close);
      await tester.pumpWidget(
        MaterialApp(
          home: ImageStoreScope(
            store: store,
            child: ListView.builder(
              itemExtent: 200,
              itemBuilder: (context, index) => TmdbCover(
                path: '/p$index.png',
                size: 'w342',
                placeholder: const SizedBox.expand(),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      final atRest = store.asked.length;
      expect(atRest, greaterThan(0));

      await tester.fling(find.byType(ListView), const Offset(0, -600), 20000);
      await tester.pumpAndSettle();

      int number(String path) => int.parse(path.substring(2, path.length - 4));
      final shown = [
        for (final cover in tester.widgetList<TmdbCover>(
          find.byType(TmdbCover),
        ))
          number(cover.path!),
      ];
      expect(shown.first, greaterThan(25), reason: 'it went a long way');
      // What it came to rest on was asked for ...
      expect(store.asked.map(number), containsAll(shown.take(3)));
      // ... but most of what flew past was not.
      final passed = {
        for (final path in store.asked)
          if (number(path) > 8 && number(path) < shown.first - 8) path,
      };
      expect(passed.length, lessThan(shown.first ~/ 3));
    });
  });
}

/// A store that only notes which pictures were asked for.
class _CountingStore extends RemoteImageStore {
  _CountingStore() : super(folder: null);

  final asked = <String>[];

  @override
  Future<File?> file(String size, String path) {
    asked.add(path);
    return Future.value();
  }
}
