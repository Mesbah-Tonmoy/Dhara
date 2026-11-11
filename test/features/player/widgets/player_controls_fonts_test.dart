// Lays the player controls out in the real bundled fonts (widget tests use a
// placeholder font otherwise), so a font change that makes a row overflow is
// caught here. Any overflow fails the test.
import 'dart:io';
import 'dart:ui';

import 'package:dhara/features/player/track_options.dart';
import 'package:dhara/features/player/widgets/player_controls_view.dart';
import 'package:dhara/theme/theme.dart';
import 'package:dhara/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _loadFont(String family, String path) {
  final loader = FontLoader(family)
    ..addFont(Future.value(ByteData.sublistView(File(path).readAsBytesSync())));
  return loader.load();
}

Widget buildControls() {
  return MaterialApp(
    theme: buildDharaTheme(),
    home: Scaffold(
      backgroundColor: Colors.black,
      body: PlayerControlsView(
        title: '[Group] A Fairly Long Series Title S05 - E01 1080p HEVC.mkv',
        playing: false,
        buffering: false,
        position: const Duration(hours: 1, minutes: 48, seconds: 52),
        duration: const Duration(hours: 2, minutes: 8, seconds: 8),
        buffered: const Duration(hours: 1, minutes: 50),
        volume: 80,
        muted: false,
        seekBackSeconds: 120,
        seekForwardSeconds: 600,
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
        audioOptions: const [
          TrackOption(id: '1', label: 'Japanese · E-AC3 5.1'),
          TrackOption(id: '2', label: 'English · Director commentary · AAC'),
        ],
        selectedAudioId: '1',
        onAudioSelected: (_) {},
        subtitleOptions: const [
          TrackOption(id: 'no', label: 'Off'),
          TrackOption(id: '1', label: 'English · Signs & Songs · ASS'),
          TrackOption(id: '2', label: 'Bengali · SRT'),
        ],
        selectedSubtitleId: '1',
        onSubtitleSelected: (_) {},
        onLoadSubtitle: () {},
        subtitleScalePercent: 200,
        onSubtitleScaleChanged: (_) {},
        subtitleDelay: -12.3,
        onSubtitleDelayChanged: (_) {},
        speed: 1.25,
        onSpeedChanged: (_) {},
        fullscreen: false,
        onToggleFullscreen: () {},
        hasNext: true,
        onPlayNext: () {},
        upNext: const UpNext(
          title: '[Group] A Fairly Long Series Title S05 - E02 1080p HEVC.mkv',
          secondsLeft: 15,
        ),
        onCancelNext: () {},
        resumedFrom: const Duration(hours: 1, minutes: 2, seconds: 3),
        onStartOver: () {},
      ),
    ),
  );
}

/// Font families of all text currently on screen (icons excluded).
Set<String?> _familiesOnScreen(WidgetTester tester) {
  return {
    for (final text in tester.widgetList<RichText>(find.byType(RichText)))
      text.text.style?.fontFamily,
    for (final field
        in tester.widgetList<EditableText>(find.byType(EditableText)))
      field.style.fontFamily,
  }..remove('MaterialIcons');
}

void main() {
  setUpAll(() async {
    await _loadFont(DharaFonts.ui, 'assets/fonts/Inter/Inter-Variable.ttf');
    await _loadFont(
      DharaFonts.display,
      'assets/fonts/PlusJakartaSans/PlusJakartaSans-Variable.ttf',
    );
  });

  for (final size in const [Size(1280, 720), Size(1040, 600)]) {
    testWidgets(
        'controls and every panel fit at ${size.width.toInt()}x'
        '${size.height.toInt()} in the bundled fonts', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(buildControls());
      await tester.pumpAndSettle();

      for (final button in [
        'speed-button',
        'audio-button',
        'subtitles-button',
        'seek-step-button',
      ]) {
        await tester.tap(find.byKey(Key(button)));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: button);
        // No text may fall back to a system font.
        expect(
          _familiesOnScreen(tester),
          {DharaFonts.ui, DharaFonts.display},
          reason: button,
        );
      }

      // The volume slider slides out on hover and takes extra room.
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(
        tester.getCenter(find.byKey(const Key('mute-button'))),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'volume slider');
    });
  }
}
