import 'dart:ui';

import 'package:dhara/features/player/widgets/player_controls_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records what the controls reported.
class _Calls {
  int back = 0;
  int togglePlay = 0;
  int toggleMute = 0;
  int skipBack = 0;
  int skipForward = 0;
  final seeks = <Duration>[];
  final volumes = <double>[];
  final volumeEnds = <double>[];
  final backSteps = <int>[];
  final forwardSteps = <int>[];
}

Future<_Calls> _pump(
  WidgetTester tester, {
  String title = 'Sample.mkv',
  bool playing = false,
  bool buffering = false,
  Duration position = const Duration(seconds: 65),
  Duration duration = const Duration(hours: 1),
  double volume = 80,
  bool muted = false,
  int seekBackSeconds = 10,
  int seekForwardSeconds = 30,
  _Calls? calls,
}) async {
  final recorded = calls ?? _Calls();
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        backgroundColor: Colors.black,
        body: PlayerControlsView(
          title: title,
          playing: playing,
          buffering: buffering,
          position: position,
          duration: duration,
          buffered: position,
          volume: volume,
          muted: muted,
          seekBackSeconds: seekBackSeconds,
          seekForwardSeconds: seekForwardSeconds,
          onBack: () => recorded.back++,
          onTogglePlay: () => recorded.togglePlay++,
          onSeek: recorded.seeks.add,
          onSkipBack: () => recorded.skipBack++,
          onSkipForward: () => recorded.skipForward++,
          onSeekBackChanged: recorded.backSteps.add,
          onSeekForwardChanged: recorded.forwardSteps.add,
          onVolumeChanged: recorded.volumes.add,
          onVolumeChangeEnd: recorded.volumeEnds.add,
          onToggleMute: () => recorded.toggleMute++,
        ),
      ),
    ),
  );
  return recorded;
}

/// Whether the bottom control bar is hidden (and ignoring the pointer).
bool _hidden(WidgetTester tester) {
  return tester
      .widget<IgnorePointer>(
        find
            .descendant(
              of: find.byKey(const Key('bottom-controls')),
              matching: find.byType(IgnorePointer),
            )
            .first,
      )
      .ignoring;
}

IconData _iconOf(WidgetTester tester, String key) {
  return tester
      .widget<Icon>(
        find.descendant(of: find.byKey(Key(key)), matching: find.byType(Icon)),
      )
      .icon!;
}

Future<TestGesture> _mouse(WidgetTester tester) async {
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: Offset.zero);
  addTearDown(mouse.removePointer);
  return mouse;
}

void main() {
  testWidgets('shows the title and the time', (tester) async {
    await _pump(tester);

    expect(find.text('Sample.mkv'), findsOneWidget);
    expect(find.text('1:05 / 1:00:00', findRichText: true), findsOneWidget);
  });

  testWidgets('shows server text literally, never as markup', (tester) async {
    await _pump(tester, title: '<b>x</b> & <script>alert(1)</script>.mkv');

    expect(
      find.text('<b>x</b> & <script>alert(1)</script>.mkv'),
      findsOneWidget,
    );
  });

  testWidgets('play/pause button reflects the state and reports taps',
      (tester) async {
    final calls = await _pump(tester);
    expect(_iconOf(tester, 'play-pause-button'), Icons.play_arrow_rounded);

    await tester.tap(find.byKey(const Key('play-pause-button')));
    expect(calls.togglePlay, 1);

    await _pump(tester, playing: true, calls: calls);
    expect(_iconOf(tester, 'play-pause-button'), Icons.pause_rounded);
  });

  testWidgets('clicking the picture toggles play/pause', (tester) async {
    final calls = await _pump(tester);

    await tester.tapAt(tester.getCenter(find.byType(PlayerControlsView)));

    expect(calls.togglePlay, 1);
  });

  testWidgets('back button reports back', (tester) async {
    final calls = await _pump(tester);

    await tester.tap(find.byKey(const Key('back-button')));

    expect(calls.back, 1);
    expect(calls.togglePlay, 0);
  });

  testWidgets('clicking the seek bar reports a seek, not a play toggle',
      (tester) async {
    final calls = await _pump(tester);

    await tester.tapAt(tester.getCenter(find.byKey(const Key('seek-fill'))) +
        const Offset(200, 0));

    expect(calls.seeks, hasLength(1));
    expect(calls.togglePlay, 0);
  });

  testWidgets('mute button reflects the state and reports taps',
      (tester) async {
    final calls = await _pump(tester);
    expect(_iconOf(tester, 'mute-button'), Icons.volume_up_rounded);

    await tester.tap(find.byKey(const Key('mute-button')));
    expect(calls.toggleMute, 1);

    await _pump(tester, muted: true, calls: calls);
    expect(_iconOf(tester, 'mute-button'), Icons.volume_off_rounded);

    await _pump(tester, volume: 20, calls: calls);
    expect(_iconOf(tester, 'mute-button'), Icons.volume_down_rounded);

    await _pump(tester, volume: 0, calls: calls);
    expect(_iconOf(tester, 'mute-button'), Icons.volume_off_rounded);
  });

  testWidgets('volume slider slides out on hover and reports changes',
      (tester) async {
    final calls = await _pump(tester);
    final mouse = await _mouse(tester);

    await mouse.moveTo(tester.getCenter(find.byKey(const Key('mute-button'))));
    await tester.pumpAndSettle();
    await tester
        .tapAt(tester.getCenter(find.byKey(const Key('volume-slider'))));
    await tester.pump();

    expect(calls.volumes, hasLength(1));
    expect(calls.volumes.single, closeTo(50, 10));
    expect(calls.volumeEnds, calls.volumes, reason: 'reported once at the end');
  });

  group('skip buttons', () {
    testWidgets('show the configured steps and report presses', (tester) async {
      final calls = await _pump(
        tester,
        seekBackSeconds: 15,
        seekForwardSeconds: 120,
      );

      expect(
        find.descendant(
          of: find.byKey(const Key('skip-back-button')),
          matching: find.text('15'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('skip-forward-button')),
          matching: find.text('120'),
        ),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('skip-back-button')));
      await tester.tap(find.byKey(const Key('skip-forward-button')));
      await tester.tap(find.byKey(const Key('skip-forward-button')));

      expect(calls.skipBack, 1);
      expect(calls.skipForward, 2);
      expect(calls.togglePlay, 0);
    });
  });

  group('seek-step panel', () {
    Future<void> open(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('seek-step-button')));
      await tester.pumpAndSettle();
    }

    testWidgets('opens from its button and reports new steps', (tester) async {
      final calls = await _pump(tester);
      expect(find.byKey(const Key('seek-step-panel')), findsNothing);

      await open(tester);
      expect(find.byKey(const Key('seek-step-panel')), findsOneWidget);

      await tester.tap(find.byKey(const Key('step-back-5')));
      await tester.tap(find.byKey(const Key('step-forward-90')));

      expect(calls.backSteps, [5]);
      expect(calls.forwardSteps, [90]);
    });

    testWidgets('the button closes it again', (tester) async {
      await _pump(tester);
      await open(tester);

      await tester.tap(find.byKey(const Key('seek-step-button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('seek-step-panel')), findsNothing);
    });

    testWidgets('a click on the picture closes it without toggling play',
        (tester) async {
      final calls = await _pump(tester);
      await open(tester);

      await tester.tapAt(const Offset(200, 200));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('seek-step-panel')), findsNothing);
      expect(calls.togglePlay, 0);

      await tester.tapAt(const Offset(200, 200));
      expect(calls.togglePlay, 1);
    });

    testWidgets('keeps the controls visible while open', (tester) async {
      final calls = await _pump(tester);
      await open(tester);
      await _pump(tester, playing: true, calls: calls);

      await tester.pump(const Duration(seconds: 10));
      expect(_hidden(tester), isFalse);

      await tester.tap(find.byKey(const Key('seek-step-button')));
      await tester.pump(const Duration(seconds: 4));
      expect(_hidden(tester), isTrue);
    });
  });

  testWidgets('shows a spinner while buffering', (tester) async {
    await _pump(tester);
    expect(find.byKey(const Key('buffering-indicator')), findsNothing);

    await _pump(tester, buffering: true);
    expect(find.byKey(const Key('buffering-indicator')), findsOneWidget);
  });

  group('auto-hide', () {
    testWidgets('hides after 3 s of playback without activity', (tester) async {
      await _pump(tester, playing: true);
      expect(_hidden(tester), isFalse);

      await tester.pump(const Duration(milliseconds: 2900));
      expect(_hidden(tester), isFalse);

      await tester.pump(const Duration(milliseconds: 200));
      expect(_hidden(tester), isTrue);
    });

    testWidgets('never hides while paused', (tester) async {
      await _pump(tester);

      await tester.pump(const Duration(seconds: 30));

      expect(_hidden(tester), isFalse);
    });

    testWidgets('mouse movement brings the controls back', (tester) async {
      await _pump(tester, playing: true);
      await tester.pump(const Duration(seconds: 4));
      expect(_hidden(tester), isTrue);

      final mouse = await _mouse(tester);
      await mouse.moveTo(tester.getCenter(find.byType(PlayerControlsView)));
      await tester.pump();
      expect(_hidden(tester), isFalse);

      await tester.pump(const Duration(seconds: 4));
      expect(_hidden(tester), isTrue);
    });

    testWidgets('stays visible while the mouse rests on the controls',
        (tester) async {
      await _pump(tester, playing: true);
      final mouse = await _mouse(tester);

      await mouse.moveTo(
        tester.getCenter(find.byKey(const Key('play-pause-button'))),
      );
      await tester.pump(const Duration(seconds: 10));
      expect(_hidden(tester), isFalse);

      await mouse.moveTo(tester.getCenter(find.byType(PlayerControlsView)));
      await tester.pump(const Duration(seconds: 4));
      expect(_hidden(tester), isTrue);
    });

    testWidgets('pausing shows the controls again', (tester) async {
      final calls = await _pump(tester, playing: true);
      await tester.pump(const Duration(seconds: 4));
      expect(_hidden(tester), isTrue);

      await _pump(tester, calls: calls);

      expect(_hidden(tester), isFalse);
    });

    testWidgets('a click on a hidden player still toggles play',
        (tester) async {
      final calls = await _pump(tester, playing: true);
      await tester.pump(const Duration(seconds: 4));

      await tester.tapAt(tester.getCenter(find.byType(PlayerControlsView)));
      await tester.pump();

      expect(calls.togglePlay, 1);
      expect(_hidden(tester), isFalse);
    });
  });
}
