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
