import 'dart:ui';

import 'package:dhara/core/window/window_controller.dart';
import 'package:dhara/features/player/track_options.dart';
import 'package:dhara/features/player/widgets/player_controls_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/test_app.dart';

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
  int loadSubtitle = 0;
  final audioIds = <String>[];
  final subtitleIds = <String>[];
  final subtitleScales = <int>[];
  final subtitleDelays = <double>[];
  final speeds = <double>[];
  int toggleFullscreen = 0;
  int playNext = 0;
  int cancelNext = 0;
  int startOver = 0;
}

const _audio = [
  TrackOption(id: '1', label: 'English · AC3 5.1'),
  TrackOption(id: '2', label: 'Hindi · AAC Stereo'),
];

const _subtitles = [
  TrackOption(id: 'no', label: 'Off'),
  TrackOption(id: '1', label: 'English · SRT'),
  TrackOption(id: '2', label: 'Bengali · ASS'),
];

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
  List<TrackOption> audioOptions = _audio,
  String selectedAudioId = '1',
  List<TrackOption> subtitleOptions = _subtitles,
  String selectedSubtitleId = 'no',
  PlayerNotice? notice,
  double speed = 1,
  bool fullscreen = false,
  bool hasNext = false,
  UpNext? upNext,
  Duration? resumedFrom,
  _Calls? calls,
  WindowController? window,
}) async {
  final recorded = calls ?? _Calls();
  Widget inWindow(Widget app) =>
      window == null ? app : WindowScope(controller: window, child: app);
  await tester.pumpWidget(
    inWindow(MaterialApp(
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
          audioOptions: audioOptions,
          selectedAudioId: selectedAudioId,
          onAudioSelected: recorded.audioIds.add,
          subtitleOptions: subtitleOptions,
          selectedSubtitleId: selectedSubtitleId,
          onSubtitleSelected: recorded.subtitleIds.add,
          onLoadSubtitle: () => recorded.loadSubtitle++,
          subtitleScalePercent: 100,
          onSubtitleScaleChanged: recorded.subtitleScales.add,
          subtitleDelay: 0,
          onSubtitleDelayChanged: recorded.subtitleDelays.add,
          speed: speed,
          onSpeedChanged: recorded.speeds.add,
          fullscreen: fullscreen,
          onToggleFullscreen: () => recorded.toggleFullscreen++,
          hasNext: hasNext,
          onPlayNext: () => recorded.playNext++,
          upNext: upNext,
          onCancelNext: () => recorded.cancelNext++,
          resumedFrom: resumedFrom,
          onStartOver: () => recorded.startOver++,
          notice: notice,
        ),
      ),
    )),
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

    testWidgets('reports when the control bars appear and disappear',
        (tester) async {
      final shown = <bool>[];
      Future<void> pump({required bool playing}) {
        return tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: PlayerControlsView(
                title: 't',
                playing: playing,
                buffering: false,
                position: Duration.zero,
                duration: const Duration(minutes: 1),
                buffered: Duration.zero,
                volume: 100,
                muted: false,
                seekBackSeconds: 10,
                seekForwardSeconds: 30,
                onBack: () {},
                onTogglePlay: () {},
                onSeek: (_) {},
                onSkipBack: () {},
                onSkipForward: () {},
                onSeekBackChanged: (_) {},
                onSeekForwardChanged: (_) {},
                onVolumeChanged: (_) {},
                onVolumeChangeEnd: (_) {},
                onToggleMute: () {},
                audioOptions: const [],
                selectedAudioId: 'no',
                onAudioSelected: (_) {},
                subtitleOptions: _subtitles,
                selectedSubtitleId: 'no',
                onSubtitleSelected: (_) {},
                onLoadSubtitle: () {},
                subtitleScalePercent: 100,
                onSubtitleScaleChanged: (_) {},
                subtitleDelay: 0,
                onSubtitleDelayChanged: (_) {},
                speed: 1,
                onSpeedChanged: (_) {},
                fullscreen: false,
                onToggleFullscreen: () {},
                hasNext: false,
                onPlayNext: () {},
                upNext: null,
                onCancelNext: () {},
                resumedFrom: null,
                onStartOver: () {},
                onControlsShownChanged: shown.add,
              ),
            ),
          ),
        );
      }

      await pump(playing: true);
      await tester.pump();
      expect(shown, [true], reason: 'initial state');

      await tester.pump(const Duration(seconds: 4));
      await tester.pump();
      expect(shown, [true, false]);

      await pump(playing: false);
      await tester.pump();
      expect(shown, [true, false, true]);
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

  group('audio and subtitle panels', () {
    Future<void> tapButton(WidgetTester tester, String key) async {
      await tester.tap(find.byKey(Key(key)));
      await tester.pumpAndSettle();
    }

    testWidgets('audio panel lists the tracks and reports a choice',
        (tester) async {
      final calls = await _pump(tester);

      await tapButton(tester, 'audio-button');
      expect(find.byKey(const Key('audio-panel')), findsOneWidget);
      expect(find.text('English · AC3 5.1'), findsOneWidget);

      await tester.tap(find.byKey(const Key('audio-option-2')));
      expect(calls.audioIds, ['2']);
    });

    testWidgets('subtitle panel reports track, file, size and delay actions',
        (tester) async {
      final calls = await _pump(tester);

      await tapButton(tester, 'subtitles-button');
      expect(find.byKey(const Key('subtitles-panel')), findsOneWidget);

      await tester.tap(find.byKey(const Key('subtitle-option-2')));
      await tester.tap(find.byKey(const Key('load-subtitle')));
      await tester.tap(find.byKey(const Key('subtitle-delay-plus')));
      await tester.tap(find.byKey(const Key('subtitle-delay-minus')));

      expect(calls.subtitleIds, ['2']);
      expect(calls.loadSubtitle, 1);
      expect(calls.subtitleDelays, [closeTo(.1, 1e-9), closeTo(-.1, 1e-9)]);
    });

    testWidgets('only one panel is open at a time', (tester) async {
      await _pump(tester);

      await tapButton(tester, 'audio-button');
      await tapButton(tester, 'subtitles-button');
      expect(find.byKey(const Key('audio-panel')), findsNothing);
      expect(find.byKey(const Key('subtitles-panel')), findsOneWidget);

      await tapButton(tester, 'seek-step-button');
      expect(find.byKey(const Key('subtitles-panel')), findsNothing);
      expect(find.byKey(const Key('seek-step-panel')), findsOneWidget);

      await tapButton(tester, 'seek-step-button');
      expect(find.byKey(const Key('seek-step-panel')), findsNothing);
    });

    testWidgets('a new notice is flashed on screen', (tester) async {
      final calls = await _pump(tester);

      await _pump(
        tester,
        notice: const PlayerNotice('Subtitles: film.srt'),
        calls: calls,
      );
      await tester.pump();

      expect(find.text('Subtitles: film.srt'), findsOneWidget);
      expect(
        tester.widget<AnimatedOpacity>(find.byKey(const Key('osd'))).opacity,
        1,
      );
    });
  });

  group('speed', () {
    testWidgets('button shows the current speed', (tester) async {
      await _pump(tester);
      expect(
        find.descendant(
          of: find.byKey(const Key('speed-button')),
          matching: find.text('1×'),
        ),
        findsOneWidget,
      );

      await _pump(tester, speed: 1.5);
      expect(
        find.descendant(
          of: find.byKey(const Key('speed-button')),
          matching: find.text('1.5×'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('panel lists the speeds and reports a choice', (tester) async {
      final calls = await _pump(tester);

      await tester.tap(find.byKey(const Key('speed-button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('speed-panel')), findsOneWidget);
      expect(find.text('Normal'), findsOneWidget);

      await tester.tap(find.byKey(const Key('speed-option-1.25')));
      await tester.tap(find.byKey(const Key('speed-option-0.5')));

      expect(calls.speeds, [1.25, 0.5]);
    });
  });

  group('fullscreen', () {
    testWidgets('button reflects the state and reports presses',
        (tester) async {
      final calls = await _pump(tester);
      expect(_iconOf(tester, 'fullscreen-button'), Icons.fullscreen_rounded);

      await tester.tap(find.byKey(const Key('fullscreen-button')));
      expect(calls.toggleFullscreen, 1);

      await _pump(tester, fullscreen: true, calls: calls);
      expect(
        _iconOf(tester, 'fullscreen-button'),
        Icons.fullscreen_exit_rounded,
      );
    });

    testWidgets('F toggles fullscreen, once per press', (tester) async {
      final calls = await _pump(tester);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyF);
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.keyF);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyF);

      expect(calls.toggleFullscreen, 1);
    });

    testWidgets('a double-click toggles fullscreen and leaves play as it was',
        (tester) async {
      final calls = await _pump(tester);
      const point = Offset(300, 250);

      await tester.tapAt(point);
      await tester.pump(const Duration(milliseconds: 120));
      await tester.tapAt(point);

      expect(calls.toggleFullscreen, 1);
      expect(calls.togglePlay, 2, reason: 'paused, then resumed');
    });

    testWidgets('two slow clicks are two play/pause toggles', (tester) async {
      final calls = await _pump(tester);
      const point = Offset(300, 250);

      await tester.tapAt(point);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tapAt(point);

      expect(calls.toggleFullscreen, 0);
      expect(calls.togglePlay, 2);
    });

    testWidgets('Esc leaves fullscreen before leaving the player',
        (tester) async {
      final calls = await _pump(tester, fullscreen: true);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      expect(calls.toggleFullscreen, 1);
      expect(calls.back, 0);

      await _pump(tester, calls: calls);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      expect(calls.back, 1);
    });
  });

  group('next video', () {
    testWidgets('no next button or N shortcut at the end of the queue',
        (tester) async {
      final calls = await _pump(tester);

      expect(find.byKey(const Key('next-button')), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
      expect(calls.playNext, 0);
    });

    testWidgets('next button and N play the next video', (tester) async {
      final calls = await _pump(tester, hasNext: true);

      await tester.tap(find.byKey(const Key('next-button')));
      await tester.sendKeyEvent(LogicalKeyboardKey.keyN);

      expect(calls.playNext, 2);
    });

    testWidgets('up-next card shows the countdown and the title',
        (tester) async {
      await _pump(tester, hasNext: true);
      expect(find.byKey(const Key('up-next-card')), findsNothing);

      await _pump(
        tester,
        hasNext: true,
        upNext: const UpNext(title: 'Show S01E02 <b>.mkv', secondsLeft: 12),
      );

      expect(find.text('UP NEXT IN 12 S'), findsOneWidget);
      expect(find.text('Show S01E02 <b>.mkv'), findsOneWidget);
    });

    testWidgets('Play now and Cancel are reported', (tester) async {
      final calls = await _pump(
        tester,
        hasNext: true,
        upNext: const UpNext(title: 'Next.mkv', secondsLeft: 9),
      );

      await tester.tap(find.byKey(const Key('up-next-play-now')));
      await tester.tap(find.byKey(const Key('up-next-cancel')));

      expect(calls.playNext, 1);
      expect(calls.cancelNext, 1);
      expect(calls.togglePlay, 0);
    });

    testWidgets('the card stays visible while the controls are hidden',
        (tester) async {
      await _pump(
        tester,
        playing: true,
        hasNext: true,
        upNext: const UpNext(title: 'Next.mkv', secondsLeft: 9),
      );
      await tester.pump(const Duration(seconds: 4));

      expect(_hidden(tester), isTrue);
      expect(find.byKey(const Key('up-next-card')), findsOneWidget);
    });
  });

  group('resume', () {
    testWidgets('shows where playback resumed from, with Start over',
        (tester) async {
      final calls = await _pump(tester);
      expect(find.byKey(const Key('resume-pill')), findsNothing);

      await _pump(
        tester,
        resumedFrom: const Duration(minutes: 42, seconds: 7),
        calls: calls,
      );
      expect(
        find.text('Resumed from 42:07', findRichText: true),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('start-over-button')));
      expect(calls.startOver, 1);
      expect(calls.togglePlay, 0);
    });
  });

  group('keyboard shortcuts', () {
    double osdOpacity(WidgetTester tester) {
      return tester
          .widget<AnimatedOpacity>(find.byKey(const Key('osd')))
          .opacity;
    }

    testWidgets('Space toggles play/pause, once per press', (tester) async {
      final calls = await _pump(tester);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.space);
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.space);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.space);

      expect(calls.togglePlay, 1);
    });

    testWidgets('← and → skip, and repeat while held', (tester) async {
      final calls = await _pump(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      expect(calls.skipBack, 1);
      expect(calls.skipForward, 0);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
      expect(calls.skipForward, 3);
      expect(calls.skipBack, 1);
    });

    testWidgets('skips show the step on screen for a moment', (tester) async {
      await _pump(tester, seekBackSeconds: 15, seekForwardSeconds: 90);
      expect(osdOpacity(tester), 0);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(find.text('+ 90 s'), findsOneWidget);
      expect(osdOpacity(tester), 1);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(find.text('− 15 s'), findsOneWidget);

      await tester.pump(const Duration(seconds: 1));
      expect(osdOpacity(tester), 0);
    });

    testWidgets('↑ and ↓ change the volume in steps of 5 and save it',
        (tester) async {
      final calls = await _pump(tester, volume: 80);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(calls.volumes, [85]);
      expect(calls.volumeEnds, [85]);
      expect(find.text('Volume 85%'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      expect(calls.volumes, [85, 75]);
    });

    testWidgets('volume keys stay within 0–100', (tester) async {
      final calls = await _pump(tester, volume: 98);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      expect(calls.volumes.last, 100);

      await _pump(tester, volume: 3, calls: calls);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      expect(calls.volumes.last, 0);
    });

    testWidgets('↑ while muted starts again from silence', (tester) async {
      final calls = await _pump(tester, volume: 80, muted: true);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);

      expect(calls.volumes, [5]);
    });

    testWidgets('M toggles mute', (tester) async {
      final calls = await _pump(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
      await tester.pump();

      expect(calls.toggleMute, 1);
      expect(find.text('Muted'), findsOneWidget);
    });

    testWidgets('Esc leaves the player', (tester) async {
      final calls = await _pump(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);

      expect(calls.back, 1);
    });

    testWidgets('Esc closes an open panel first', (tester) async {
      final calls = await _pump(tester);
      await tester.tap(find.byKey(const Key('seek-step-button')));
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('seek-step-panel')), findsNothing);
      expect(calls.back, 0);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      expect(calls.back, 1);
    });

    testWidgets('keys belong to the custom-step field while typing in it',
        (tester) async {
      final calls = await _pump(tester);
      await tester.tap(find.byKey(const Key('seek-step-button')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byKey(const Key('step-back-custom')),
          matching: find.byType(TextField),
        ),
      );
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      expect(calls.togglePlay, 0);
      expect(calls.toggleMute, 0);
      expect(calls.volumes, isEmpty);

      // First Esc leaves the field, and the shortcuts work again.
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(find.byKey(const Key('seek-step-panel')), findsOneWidget);
      expect(calls.back, 0);

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      expect(calls.togglePlay, 1);
    });

    testWidgets('Enter in the custom-step field returns to the shortcuts',
        (tester) async {
      final calls = await _pump(tester);
      await tester.tap(find.byKey(const Key('seek-step-button')));
      await tester.pumpAndSettle();
      final field = find.descendant(
        of: find.byKey(const Key('step-forward-custom')),
        matching: find.byType(TextField),
      );
      await tester.tap(field);
      await tester.pump();
      await tester.enterText(field, '45');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      expect(calls.forwardSteps, [45]);

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      expect(calls.togglePlay, 1);
    });

    testWidgets('Space still means play/pause after clicking another button',
        (tester) async {
      final calls = await _pump(tester);

      await tester.tap(find.byKey(const Key('mute-button')));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);

      expect(calls.toggleMute, 1);
      expect(calls.togglePlay, 1);
    });

    testWidgets('Ctrl/Alt combinations are left alone', (tester) async {
      final calls = await _pump(tester);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);

      expect(calls.toggleMute, 0);
      expect(calls.skipForward, 0);
    });

    testWidgets('S steps through the subtitle tracks and back to Off',
        (tester) async {
      final calls = await _pump(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
      await tester.pump();
      expect(calls.subtitleIds, ['1']);
      expect(find.text('Subtitles: English · SRT'), findsOneWidget);

      await _pump(tester, selectedSubtitleId: '2', calls: calls);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
      await tester.pump();
      expect(calls.subtitleIds, ['1', 'no']);
      expect(find.text('Subtitles: Off'), findsOneWidget);
    });

    testWidgets('S says so when the video has no subtitles', (tester) async {
      final calls = await _pump(
        tester,
        subtitleOptions: const [TrackOption(id: 'no', label: 'Off')],
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
      await tester.pump();

      expect(calls.subtitleIds, isEmpty);
      expect(find.text('No subtitles'), findsOneWidget);
    });

    testWidgets('a key press brings hidden controls back', (tester) async {
      await _pump(tester, playing: true);
      await tester.pump(const Duration(seconds: 4));
      expect(_hidden(tester), isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();

      expect(_hidden(tester), isFalse);
    });
  });

  group('with the app\'s own window frame', () {
    testWidgets('the top strip carries the window buttons and moves the '
        'window', (tester) async {
      final window = FakeWindow();
      await _pump(tester, window: window);
      final top = find.byKey(const Key('top-controls'));

      expect(
        find.descendant(
          of: top,
          matching: find.byKey(const Key('window-close')),
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('window-minimize')));
      expect(window.calls, ['minimize']);

      // Between the title and the window buttons.
      final strip = tester.getRect(top);
      await tester.dragFrom(
        Offset(strip.center.dx, strip.top + 20),
        const Offset(40, 30),
      );
      expect(window.calls, ['minimize', 'drag']);
      await tester.pump(const Duration(milliseconds: 500));
    });

    testWidgets('a click on the top strip does not pause the video', (
      tester,
    ) async {
      final window = FakeWindow();
      final calls = await _pump(tester, playing: true, window: window);
      final strip = tester.getRect(find.byKey(const Key('top-controls')));

      await tester.tapAt(Offset(strip.center.dx, strip.top + 20));
      await tester.pump(const Duration(milliseconds: 500));

      expect(calls.togglePlay, 0);
    });

    testWidgets('in fullscreen, and with the system\'s title bar, there are '
        'no window buttons', (tester) async {
      await _pump(tester, window: FakeWindow(isFullscreen: true));
      expect(find.byKey(const Key('window-close')), findsNothing);

      await _pump(tester);
      expect(find.byKey(const Key('window-close')), findsNothing);
    });
  });
}
