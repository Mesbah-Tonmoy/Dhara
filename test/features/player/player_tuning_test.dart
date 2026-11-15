import 'package:dhara/core/settings/key_value_store.dart';
import 'package:dhara/core/settings/settings_controller.dart';
import 'package:dhara/features/player/player_tuning.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const megabyte = 1024 * 1024;

  test('the buffer is split: three quarters ahead, a quarter behind', () {
    const tuning = PlayerTuning();
    expect(tuning.bufferMegabytes, 150);
    expect(tuning.forwardBytes + tuning.backBytes, 150 * megabyte);
    expect(tuning.forwardBytes, 3 * tuning.backBytes);

    for (final size in [50, 100, 250, 500]) {
      final other = PlayerTuning(bufferMegabytes: size);
      expect(other.forwardBytes + other.backBytes, size * megabyte);
      expect(other.backBytes, greaterThan(0));
    }
  });

  test('the options are the ones the brief asks for', () {
    final options = const PlayerTuning().mpvOptions;
    expect(options['hwdec'], 'auto-safe');
    expect(options['cache'], 'yes');
    // Nothing of a video is written to disk.
    expect(options['cache-on-disk'], 'no');
    expect(options['demuxer-max-bytes'], '${150 * megabyte ~/ 4 * 3}');
    expect(options['demuxer-max-back-bytes'], '${150 * megabyte ~/ 4}');
    expect(options['demuxer-seekable-cache'], 'yes');
    expect(options['network-timeout'], '5');
    expect(options['hr-seek-framedrop'], 'yes');
  });

  test('hardware decoding can be turned off', () {
    const tuning = PlayerTuning(hardwareDecoding: false);
    expect(tuning.hwdec, 'no');
    expect(tuning.mpvOptions['hwdec'], 'no');
  });

  test('follows the settings', () {
    final settings = SettingsController(MemoryKeyValueStore());
    expect(PlayerTuning.of(settings).bufferMegabytes, 150);
    expect(PlayerTuning.of(settings).hardwareDecoding, isTrue);

    settings
      ..setBufferMegabytes(400)
      ..setHardwareDecoding(false);
    final tuning = PlayerTuning.of(settings);
    expect(tuning.forwardBytes + tuning.backBytes, 400 * megabyte);
    expect(tuning.mpvOptions['hwdec'], 'no');
  });

  test('the buffer has limits', () {
    expect(() => PlayerTuning(bufferMegabytes: 49), throwsAssertionError);
    expect(() => PlayerTuning(bufferMegabytes: 501), throwsAssertionError);
  });

  test('a value read back counts as set when text or number agree', () {
    expect(sameMpvValue('yes', 'yes'), isTrue);
    expect(sameMpvValue('5', '5.000000'), isTrue);
    expect(sameMpvValue('117964800', '117964800'), isTrue);
    expect(sameMpvValue('auto-safe', 'auto'), isFalse);
    expect(sameMpvValue('no', ''), isFalse);
    expect(sameMpvValue('5', '60.000000'), isFalse);
  });
}
