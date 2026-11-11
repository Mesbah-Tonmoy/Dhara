import 'package:dhara/features/player/track_options.dart';
import 'package:dhara/features/player/widgets/track_panels.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(WidgetTester tester, Widget panel) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(child: SizedBox(width: 360, child: panel)),
      ),
    ),
  );
}

bool _selected(WidgetTester tester, String key) {
  final row = tester.widget<Semantics>(
    find
        .descendant(of: find.byKey(Key(key)), matching: find.byType(Semantics))
        .first,
  );
  return row.properties.selected ?? false;
}

void main() {
  group('AudioPanel', () {
    testWidgets('marks the active track and reports a new choice',
        (tester) async {
      final chosen = <String>[];
      await _pump(
        tester,
        AudioPanel(
          options: const [
            TrackOption(id: '1', label: 'English · AC3 5.1'),
            TrackOption(id: '2', label: 'Hindi · AAC Stereo'),
          ],
          selectedId: '2',
          onSelected: chosen.add,
        ),
      );

      expect(_selected(tester, 'audio-option-1'), isFalse);
      expect(_selected(tester, 'audio-option-2'), isTrue);

      await tester.tap(find.text('English · AC3 5.1'));
      expect(chosen, ['1']);
    });

    testWidgets('explains an empty list', (tester) async {
      await _pump(
        tester,
        AudioPanel(options: const [], selectedId: 'no', onSelected: (_) {}),
      );

      expect(find.text('This video has no audio track.'), findsOneWidget);
    });

    testWidgets('shows a track title literally, never as markup',
        (tester) async {
      await _pump(
        tester,
        AudioPanel(
          options: const [TrackOption(id: '1', label: '<i>x</i> & y')],
          selectedId: '1',
          onSelected: (_) {},
        ),
      );

      expect(find.text('<i>x</i> & y'), findsOneWidget);
    });
  });

  group('SubtitlePanel', () {
    Future<Map<String, List<Object>>> pumpPanel(
      WidgetTester tester, {
      String selectedId = 'no',
      int scalePercent = 100,
      double delaySeconds = 0,
    }) async {
      final calls = <String, List<Object>>{
        'selected': [],
        'load': [],
        'scale': [],
        'delay': [],
      };
      await _pump(
        tester,
        SubtitlePanel(
          options: const [
            TrackOption(id: 'no', label: 'Off'),
            TrackOption(id: '1', label: 'English · SRT'),
          ],
          selectedId: selectedId,
          onSelected: (id) => calls['selected']!.add(id),
          onLoadFile: () => calls['load']!.add(true),
          scalePercent: scalePercent,
          onScaleChanged: (v) => calls['scale']!.add(v),
          delaySeconds: delaySeconds,
          onDelayChanged: (v) => calls['delay']!.add(v),
        ),
      );
      return calls;
    }

    testWidgets('lists Off and the tracks, marking the active one',
        (tester) async {
      final calls = await pumpPanel(tester, selectedId: '1');

      expect(_selected(tester, 'subtitle-option-no'), isFalse);
      expect(_selected(tester, 'subtitle-option-1'), isTrue);

      await tester.tap(find.byKey(const Key('subtitle-option-no')));
      expect(calls['selected'], ['no']);
    });

    testWidgets('offers to load an external file and names the types',
        (tester) async {
      final calls = await pumpPanel(tester);

      expect(find.text('.srt .ass .ssa .vtt'), findsOneWidget);
      await tester.tap(find.byKey(const Key('load-subtitle')));

      expect(calls['load'], hasLength(1));
    });

    testWidgets('shows the size and reports slider changes in steps of 10',
        (tester) async {
      final calls = await pumpPanel(tester, scalePercent: 130);
      expect(find.text('130%'), findsOneWidget);

      final slider = find.byKey(const Key('subtitle-size-slider'));
      await tester.tapAt(tester.getTopLeft(slider) + const Offset(30, 10));
      await tester.pump();

      expect(calls['scale'], isNotEmpty);
      final value = calls['scale']!.last as int;
      expect(value % 10, 0);
      expect(value, inInclusiveRange(50, 200));
      expect(value, lessThan(130));
    });

    testWidgets('delay chips shift by a tenth of a second', (tester) async {
      final calls = await pumpPanel(tester, delaySeconds: .3);
      expect(find.text('+0.3 s'), findsOneWidget);

      await tester.tap(find.byKey(const Key('subtitle-delay-plus')));
      await tester.tap(find.byKey(const Key('subtitle-delay-minus')));

      expect(calls['delay'], [closeTo(.4, 1e-9), closeTo(.2, 1e-9)]);
    });
  });

  test('formatSubtitleDelay', () {
    expect(formatSubtitleDelay(0), '0.0 s');
    expect(formatSubtitleDelay(-0.04), '0.0 s');
    expect(formatSubtitleDelay(0.1), '+0.1 s');
    expect(formatSubtitleDelay(-1.2), '-1.2 s');
    expect(formatSubtitleDelay(0.30000000000000004), '+0.3 s');
    expect(formatSubtitleDelay(12), '+12.0 s');
  });
}
