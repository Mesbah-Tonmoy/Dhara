import 'package:dhara/features/player/open_url_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  /// Opens the dialog; what it plays ends up in [played].
  Future<void> open(WidgetTester tester, List<List<Uri>> played) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showOpenUrlDialog(
              context,
              onPlay: (_, urls) => played.add(urls),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  final field = find.byKey(const Key('url-field'));
  final play = find.byKey(const Key('play-button'));

  testWidgets('plays the URLs it is given, in order, and closes', (
    tester,
  ) async {
    final played = <List<Uri>>[];
    await open(tester, played);

    await tester.enterText(
      field,
      'http://h.example/e01.mkv\nhttps://h.example/e02.mkv',
    );
    await tester.tap(play);
    await tester.pumpAndSettle();

    expect(played, [
      [
        Uri.parse('http://h.example/e01.mkv'),
        Uri.parse('https://h.example/e02.mkv'),
      ],
    ]);
    expect(field, findsNothing);
  });

  testWidgets('rejects a non-http URL without playing anything', (
    tester,
  ) async {
    final played = <List<Uri>>[];
    await open(tester, played);

    await tester.enterText(field, 'file:///C:/Windows/win.ini');
    await tester.tap(play);
    await tester.pump();

    expect(
      find.text('Enter a full http:// or https:// video URL.'),
      findsOneWidget,
    );
    expect(field, findsOneWidget);
    expect(played, isEmpty);
  });

  testWidgets('names the bad line when several URLs are pasted', (
    tester,
  ) async {
    final played = <List<Uri>>[];
    await open(tester, played);

    await tester.enterText(
      field,
      'http://h.example/e01.mkv\nsmb://h.example/e02.mkv',
    );
    await tester.tap(play);
    await tester.pump();

    expect(
      find.text('Line 2 is not a full http:// or https:// video URL.'),
      findsOneWidget,
    );
    expect(played, isEmpty);
  });

  testWidgets('Enter plays; Cancel closes without playing', (tester) async {
    final played = <List<Uri>>[];
    await open(tester, played);

    await tester.enterText(field, 'http://h.example/film.mkv');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(played, hasLength(1));
    expect(field, findsNothing);

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(played, hasLength(1));
    expect(field, findsNothing);
  });
}
