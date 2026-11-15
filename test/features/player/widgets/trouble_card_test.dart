import 'package:dhara/features/player/stall_watch.dart';
import 'package:dhara/features/player/widgets/trouble_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<({List<String> taps})> _pump(
  WidgetTester tester,
  Trouble trouble, {
  bool otherCopy = true,
}) async {
  final taps = <String>[];
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: TroubleCard(
            trouble: trouble,
            onOther: otherCopy ? () => taps.add('other') : null,
            onRetry: () => taps.add('retry'),
          ),
        ),
      ),
    ),
  );
  return (taps: taps);
}

void main() {
  testWidgets('says what is wrong and offers another copy, or the same '
      'again', (tester) async {
    final (:taps) = await _pump(tester, Trouble.notLoading);

    expect(find.text('The server stopped sending.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('trouble-other')));
    await tester.tap(find.byKey(const Key('trouble-retry')));
    expect(taps, ['other', 'retry']);
    expect(find.text('Try another copy'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('a video with one copy can only be tried again', (tester) async {
    final (:taps) = await _pump(tester, Trouble.notOpening, otherCopy: false);

    expect(find.text('This copy does not start.'), findsOneWidget);
    expect(find.byKey(const Key('trouble-other')), findsNothing);
    await tester.tap(find.byKey(const Key('trouble-retry')));
    expect(taps, ['retry']);
  });

  testWidgets('every kind of trouble is said in its own words', (tester) async {
    for (final trouble in Trouble.values) {
      await _pump(tester, trouble);
      expect(find.text(trouble.message), findsOneWidget);
    }
  });
}
