import 'dart:io';

import 'package:dhara/core/app_info.dart';
import 'package:dhara/core/settings/key_value_store.dart';
import 'package:dhara/features/settings/ui/settings_screen.dart';
import 'package:dhara/theme/scale.dart';
import 'package:dhara/widgets/chips.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/test_app.dart';

final _page = find.byKey(const Key('settings'));

Future<void> _boot(WidgetTester tester, KeyValueStore store) async {
  tester.view
    ..physicalSize = const Size(1280, 720)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(testApp(settings: store).app);
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('rail-settings')));
  await tester.pumpAndSettle();
}

/// Brings [target] into view and clicks it.
Future<void> _tap(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

bool _on(WidgetTester tester, String key) =>
    tester.widget<DharaSwitch>(find.byKey(Key(key))).value;

void main() {
  testWidgets('shows its parts, and only settings that do something', (
    tester,
  ) async {
    await _boot(tester, MemoryKeyValueStore());

    expect(find.byType(SettingsScreen), findsOneWidget);
    for (final group in SettingsGroup.values) {
      expect(
        find.byKey(Key('settings-group-${group.name}'), skipOffstage: false),
        findsOneWidget,
      );
    }
    // Not built yet, so not offered.
    for (final absent in ['Preferred quality', 'Default subtitles']) {
      expect(find.textContaining(absent, skipOffstage: false), findsNothing);
    }
  });

  testWidgets('shows what was saved before', (tester) async {
    await _boot(
      tester,
      MemoryKeyValueStore({
        'player.seekBackSeconds': 15,
        'player.autoplayNext': 0,
        'player.subtitleScalePercent': 130,
        'look.rotateFeatured': 0,
        'look.reduceMotion': 1,
      }),
    );

    expect(_on(tester, 'set-autoplay'), isFalse);
    expect(_on(tester, 'set-rotate'), isFalse);
    expect(_on(tester, 'set-reduce-motion'), isTrue);
    expect(
      tester.widget<Text>(find.byKey(const Key('set-subtitle-value'))).data,
      '130%',
    );
  });

  testWidgets('a seek step is picked from the presets or typed in, each '
      'direction by itself', (tester) async {
    final store = MemoryKeyValueStore();
    await _boot(tester, store);

    await _tap(tester, find.byKey(const Key('step-back-5')));
    expect(store.getInt('player.seekBackSeconds'), 5);
    expect(store.getInt('player.seekForwardSeconds'), isNull);

    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('step-forward-custom')),
        matching: find.byType(TextField),
      ),
      '45',
    );
    await tester.pumpAndSettle();
    expect(store.getInt('player.seekForwardSeconds'), 45);
    expect(store.getInt('player.seekBackSeconds'), 5);
  });

  testWidgets('the switches and the subtitle size are saved as they change', (
    tester,
  ) async {
    final store = MemoryKeyValueStore();
    await _boot(tester, store);

    await _tap(tester, find.byKey(const Key('set-autoplay')));
    expect(_on(tester, 'set-autoplay'), isFalse);
    expect(store.getInt('player.autoplayNext'), 0);

    await _tap(tester, find.byKey(const Key('set-subtitle-more')));
    await _tap(tester, find.byKey(const Key('set-subtitle-more')));
    await _tap(tester, find.byKey(const Key('set-subtitle-less')));
    expect(store.getInt('player.subtitleScalePercent'), 110);
    expect(
      tester.widget<Text>(find.byKey(const Key('set-subtitle-value'))).data,
      '110%',
    );

    await _tap(tester, find.byKey(const Key('set-rotate')));
    expect(store.getInt('look.rotateFeatured'), 0);
    await _tap(tester, find.byKey(const Key('set-rotate')));
    expect(store.getInt('look.rotateFeatured'), 1);
  });

  testWidgets('buffer size and hardware decoding are saved as they change', (
    tester,
  ) async {
    final store = MemoryKeyValueStore({'player.bufferMegabytes': 450});
    await _boot(tester, store);
    String shown() =>
        tester.widget<Text>(find.byKey(const Key('set-buffer-value'))).data!;
    expect(shown(), '450 MB');
    expect(_on(tester, 'set-hwdec'), isTrue);

    await _tap(tester, find.byKey(const Key('set-buffer-more')));
    expect(shown(), '500 MB');
    expect(store.getInt('player.bufferMegabytes'), 500);
    // At the top of the range there is no more.
    await _tap(tester, find.byKey(const Key('set-buffer-more')));
    expect(shown(), '500 MB');

    await _tap(tester, find.byKey(const Key('set-buffer-less')));
    await _tap(tester, find.byKey(const Key('set-buffer-less')));
    expect(shown(), '400 MB');
    expect(store.getInt('player.bufferMegabytes'), 400);

    await _tap(tester, find.byKey(const Key('set-hwdec')));
    expect(_on(tester, 'set-hwdec'), isFalse);
    expect(store.getInt('player.hardwareDecoding'), 0);
  });

  testWidgets('Interface size draws the whole app larger or smaller at once', (
    tester,
  ) async {
    final store = MemoryKeyValueStore();
    await _boot(tester, store);
    double scale() => DharaScale.of(tester.element(_page));
    expect(scale(), 1);

    await _tap(
      tester,
      find.descendant(
        of: find.byKey(const Key('set-interface-size')),
        matching: find.text('125%'),
      ),
    );
    expect(scale(), 1.25);
    expect(store.getInt('look.interfaceScalePercent'), 125);

    await _tap(
      tester,
      find.descendant(
        of: find.byKey(const Key('set-interface-size')),
        matching: find.text('90%'),
      ),
    );
    expect(scale(), closeTo(.9, 1e-9));
  });

  testWidgets('Reduce motion switches animations off for every page', (
    tester,
  ) async {
    final store = MemoryKeyValueStore();
    await _boot(tester, store);
    bool still() => MediaQuery.disableAnimationsOf(tester.element(_page));
    expect(still(), isFalse);

    await _tap(tester, find.byKey(const Key('set-reduce-motion')));

    expect(still(), isTrue);
    expect(store.getInt('look.reduceMotion'), 1);
  });

  testWidgets('clearing the history asks first', (tester) async {
    await _boot(tester, MemoryKeyValueStore());

    await _tap(tester, find.byKey(const Key('set-clear-history')));
    expect(find.text('Clear the history?'), findsOneWidget);

    await tester.tap(find.byKey(const Key('history-clear-cancel')));
    await tester.pumpAndSettle();
    expect(find.text('Clear the history?'), findsNothing);
    expect(find.text('History cleared.'), findsNothing);

    await _tap(tester, find.byKey(const Key('set-clear-history')));
    await tester.tap(find.byKey(const Key('history-clear-confirm')));
    await tester.pumpAndSettle();
    expect(find.text('History cleared.'), findsOneWidget);
    // Let the message go, so that no timer is left behind.
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
  });

  testWidgets('the list on the left brings a part into view', (tester) async {
    await _boot(tester, MemoryKeyValueStore());
    final about = find.byKey(const Key('settings-group-about'));
    final view = tester.getRect(find.byKey(const Key('settings-scroll')));
    expect(tester.getRect(about).top, greaterThan(view.bottom));

    await tester.tap(find.byKey(const Key('settings-nav-about')));
    await tester.pumpAndSettle();

    expect(tester.getRect(about).bottom, lessThanOrEqualTo(view.bottom + 1));
  });

  testWidgets('Tab walks the list on the left first, then the settings', (
    tester,
  ) async {
    await _boot(tester, MemoryKeyValueStore());

    /// The key of what holds the keyboard, or of what it is part of.
    String? focused() {
      final context = FocusManager.instance.primaryFocus?.context;
      String? found;
      context?.visitAncestorElements((element) {
        final key = element.widget.key;
        if (key is! ValueKey<String>) return true;
        found = key.value;
        return false;
      });
      return found;
    }

    final order = <String?>[];
    for (var i = 0; i < SettingsGroup.values.length + 1; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      order.add(focused());
    }

    expect(order, [
      for (final group in SettingsGroup.values) 'settings-nav-${group.name}',
      'step-back-5',
    ]);
  });

  testWidgets('lists the keys that do something', (tester) async {
    await _boot(tester, MemoryKeyValueStore());
    final keys = find.byKey(const Key('settings-group-keyboard'));
    await tester.ensureVisible(keys);
    await tester.pumpAndSettle();

    for (final key in ['Ctrl K', 'PgDn', 'Esc', 'Ctrl O', 'Space']) {
      expect(
        find.descendant(of: keys, matching: find.text(key)),
        findsOneWidget,
        reason: key,
      );
    }
  });

  test('says the version that pubspec.yaml has', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final version = RegExp(
      r'^version:\s*([0-9.]+)',
      multiLine: true,
    ).firstMatch(pubspec)!.group(1);

    expect(dharaVersion, version);
  });
}
