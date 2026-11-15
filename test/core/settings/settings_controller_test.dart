import 'package:dhara/core/settings/key_value_store.dart';
import 'package:dhara/core/settings/settings_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('starts with the defaults from the approved prototype', () {
    final settings = SettingsController(MemoryKeyValueStore());

    expect(settings.seekBackSeconds, 10);
    expect(settings.seekForwardSeconds, 30);
    expect(settings.volume, 100);
  });

  test('autoplay and the rotating banner start on, Reduce motion off, the '
      'interface at its own size', () {
    final settings = SettingsController(MemoryKeyValueStore());

    expect(settings.autoplayNext, isTrue);
    expect(settings.rotateFeatured, isTrue);
    expect(settings.reduceMotion, isFalse);
    expect(settings.interfaceScalePercent, 100);
  });

  test('the preferred quality starts at the sharpest, and is saved', () {
    final store = MemoryKeyValueStore();
    final settings = SettingsController(store);
    expect(settings.preferredQuality, PreferredQuality.best);

    var changes = 0;
    settings
      ..addListener(() => changes++)
      ..setPreferredQuality(PreferredQuality.fullHd)
      ..setPreferredQuality(PreferredQuality.fullHd);
    expect(changes, 1);
    expect(store.getInt('player.preferredQualityHeight'), 1080);
    expect(SettingsController(store).preferredQuality, PreferredQuality.fullHd);

    settings.setPreferredQuality(PreferredQuality.best);
    expect(store.getInt('player.preferredQualityHeight'), 0);
    expect(SettingsController(store).preferredQuality, PreferredQuality.best);

    // A height that is none of the choices is not trusted.
    expect(
      SettingsController(
        MemoryKeyValueStore({'player.preferredQualityHeight': 1234}),
      ).preferredQuality,
      PreferredQuality.best,
    );
    expect(PreferredQuality.values.map((quality) => quality.label), [
      'Auto (best)',
      '4K',
      '1080p',
      '720p',
    ]);
  });

  test('the buffer starts at 150 MB with hardware decoding on', () {
    final settings = SettingsController(MemoryKeyValueStore());

    expect(settings.bufferMegabytes, 150);
    expect(settings.hardwareDecoding, isTrue);
  });

  test('saves the buffer size and hardware decoding', () {
    final store = MemoryKeyValueStore();
    var changes = 0;
    SettingsController(store)
      ..addListener(() => changes++)
      ..setBufferMegabytes(300)
      ..setHardwareDecoding(false)
      // The same again changes nothing.
      ..setBufferMegabytes(300);

    expect(changes, 2);
    expect(store.getInt('player.bufferMegabytes'), 300);
    expect(store.getInt('player.hardwareDecoding'), 0);
    final next = SettingsController(store);
    expect(next.bufferMegabytes, 300);
    expect(next.hardwareDecoding, isFalse);
  });

  test('the buffer keeps to 50–500 MB in steps of 50', () {
    final settings = SettingsController(MemoryKeyValueStore())
      ..setBufferMegabytes(10);
    expect(settings.bufferMegabytes, 50);
    settings.setBufferMegabytes(9000);
    expect(settings.bufferMegabytes, 500);
    settings.setBufferMegabytes(230);
    expect(settings.bufferMegabytes, 250);

    // A saved value outside the range is not trusted.
    for (final stored in [0, 49, 501, -150]) {
      final odd = SettingsController(
        MemoryKeyValueStore({
          'player.bufferMegabytes': stored,
          'player.hardwareDecoding': 5,
        }),
      );
      expect(odd.bufferMegabytes, 150, reason: '$stored');
      expect(odd.hardwareDecoding, isTrue);
    }
  });

  test('saves the switches and the interface size', () {
    final store = MemoryKeyValueStore();
    var changes = 0;
    SettingsController(store)
      ..addListener(() => changes++)
      ..setAutoplayNext(false)
      ..setRotateFeatured(false)
      ..setReduceMotion(true)
      ..setInterfaceScalePercent(125)
      // The same again changes nothing.
      ..setReduceMotion(true);

    expect(changes, 4);
    final next = SettingsController(store);
    expect(next.autoplayNext, isFalse);
    expect(next.rotateFeatured, isFalse);
    expect(next.reduceMotion, isTrue);
    expect(next.interfaceScalePercent, 125);
  });

  test('an interface size that is not offered is not taken, set or saved', () {
    final settings = SettingsController(MemoryKeyValueStore())
      ..setInterfaceScalePercent(300);
    expect(settings.interfaceScalePercent, 100);

    final odd = SettingsController(
      MemoryKeyValueStore({
        'look.interfaceScalePercent': 1000,
        'player.autoplayNext': 7,
        'look.reduceMotion': -1,
      }),
    );
    expect(odd.interfaceScalePercent, 100);
    expect(odd.autoplayNext, isTrue);
    expect(odd.reduceMotion, isFalse);
  });

  test('offers the presets from the brief', () {
    expect(SettingsController.seekStepPresets, [5, 10, 15, 30, 60, 90, 120]);
  });

  test('loads saved values', () {
    final settings = SettingsController(
      MemoryKeyValueStore({
        'player.seekBackSeconds': 5,
        'player.seekForwardSeconds': 45,
        'player.volume': 62.5,
      }),
    );

    expect(settings.seekBackSeconds, 5);
    expect(settings.seekForwardSeconds, 45);
    expect(settings.volume, 62.5);
  });

  test('saves changes so the next start sees them', () {
    final store = MemoryKeyValueStore();
    SettingsController(store)
      ..setSeekBackSeconds(15)
      ..setSeekForwardSeconds(90)
      ..setVolume(40);

    final next = SettingsController(store);
    expect(next.seekBackSeconds, 15);
    expect(next.seekForwardSeconds, 90);
    expect(next.volume, 40);
  });

  test('back and forward steps are independent', () {
    final settings = SettingsController(MemoryKeyValueStore())
      ..setSeekBackSeconds(120);

    expect(settings.seekBackSeconds, 120);
    expect(settings.seekForwardSeconds, 30);
  });

  test('clamps out-of-range values', () {
    final settings = SettingsController(MemoryKeyValueStore())
      ..setSeekBackSeconds(0)
      ..setSeekForwardSeconds(100000)
      ..setVolume(250);

    expect(settings.seekBackSeconds, 1);
    expect(settings.seekForwardSeconds, 600);
    expect(settings.volume, 100);

    settings.setVolume(-5);
    expect(settings.volume, 0);
  });

  test('falls back to defaults for corrupt or wrongly typed stored values', () {
    final settings = SettingsController(
      MemoryKeyValueStore({
        'player.seekBackSeconds': -3,
        'player.seekForwardSeconds': 'thirty',
        'player.volume': 9000.0,
      }),
    );

    expect(settings.seekBackSeconds, 10);
    expect(settings.seekForwardSeconds, 30);
    expect(settings.volume, 100);
  });

  group('subtitle size', () {
    test('defaults to 100% and is saved', () {
      final store = MemoryKeyValueStore();
      final settings = SettingsController(store);
      expect(settings.subtitleScalePercent, 100);

      settings.setSubtitleScalePercent(150);

      expect(SettingsController(store).subtitleScalePercent, 150);
    });

    test('stays within 50–200% in steps of 10', () {
      final settings = SettingsController(MemoryKeyValueStore())
        ..setSubtitleScalePercent(10);
      expect(settings.subtitleScalePercent, 50);

      settings.setSubtitleScalePercent(999);
      expect(settings.subtitleScalePercent, 200);

      settings.setSubtitleScalePercent(134);
      expect(settings.subtitleScalePercent, 130);

      settings.setSubtitleScalePercent(136);
      expect(settings.subtitleScalePercent, 140);
    });

    test('ignores a stored value outside the range', () {
      final settings = SettingsController(
        MemoryKeyValueStore({'player.subtitleScalePercent': 5000}),
      );

      expect(settings.subtitleScalePercent, 100);
    });
  });

  test('notifies listeners only when a value really changes', () {
    final settings = SettingsController(MemoryKeyValueStore());
    var notifications = 0;
    settings.addListener(() => notifications++);

    settings.setSeekBackSeconds(10); // unchanged
    expect(notifications, 0);

    settings.setSeekBackSeconds(15);
    settings.setSeekForwardSeconds(60);
    settings.setVolume(80);
    expect(notifications, 3);

    settings.setSeekForwardSeconds(60); // unchanged
    expect(notifications, 3);
  });
}
