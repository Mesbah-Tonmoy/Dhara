import 'package:dhara/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('app boots on the open-URL screen', (tester) async {
    await tester.pumpWidget(const DharaApp());

    expect(find.byKey(const Key('app-title')), findsOneWidget);
    expect(find.byKey(const Key('url-field')), findsOneWidget);
    expect(find.byKey(const Key('play-button')), findsOneWidget);
  });

  testWidgets('rejects a non-http URL without opening the player',
      (tester) async {
    await tester.pumpWidget(const DharaApp());

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
}
