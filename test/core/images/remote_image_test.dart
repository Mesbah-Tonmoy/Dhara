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
}
