import 'package:dhara/features/player/seek_math.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const duration = Duration(minutes: 10);

  Duration skip(Duration position, int seconds, {Duration total = duration}) {
    return skipTarget(position: position, duration: total, seconds: seconds);
  }

  test('skips forward and back by the given seconds', () {
    expect(
      skip(const Duration(minutes: 5), 30),
      const Duration(minutes: 5, seconds: 30),
    );
    expect(
      skip(const Duration(minutes: 5), -10),
      const Duration(minutes: 4, seconds: 50),
    );
  });

  test('never goes before the start', () {
    expect(skip(const Duration(seconds: 4), -10), Duration.zero);
    expect(skip(Duration.zero, -120), Duration.zero);
  });

  test('never goes past the end', () {
    expect(skip(const Duration(minutes: 9, seconds: 50), 30), duration);
    expect(skip(duration, 5), duration);
  });

  test('has no upper bound while the duration is unknown', () {
    expect(
      skip(const Duration(seconds: 20), 30, total: Duration.zero),
      const Duration(seconds: 50),
    );
    expect(
      skip(const Duration(seconds: 20), -30, total: Duration.zero),
      Duration.zero,
    );
  });

  group('skipCommand', () {
    const film = Duration(hours: 2);
    const at = Duration(minutes: 30);

    List<String> command(int seconds, {Duration from = at}) => skipCommand(
      from: from,
      target: skipTarget(position: from, duration: film, seconds: seconds),
      duration: film,
    );

    test('a short skip lands exactly on its target', () {
      expect(command(10), ['seek', '1810.000', 'absolute+exact']);
      expect(command(-5), ['seek', '1795.000', 'absolute+exact']);
      expect(command(15), ['seek', '1815.000', 'absolute+exact']);
    });

    test('a long skip goes to a keyframe, in its own direction', () {
      expect(command(30), ['seek', '30.000', 'relative+keyframes']);
      expect(command(-60), ['seek', '-60.000', 'relative+keyframes']);
      expect(command(120), ['seek', '120.000', 'relative+keyframes']);
      expect(command(16), ['seek', '16.000', 'relative+keyframes']);
    });

    test('a long skip cut short by the start or the end goes by what is '
        'left of it', () {
      // 8 s from the start, back 30: that is a skip of 8 s.
      expect(command(-30, from: const Duration(seconds: 8)), [
        'seek',
        '0.000',
        'absolute+exact',
      ]);
      // 20 s from the start, back 30: a skip of 20 s, to a keyframe.
      expect(command(-30, from: const Duration(seconds: 20)), [
        'seek',
        '-20.000',
        'relative+keyframes',
      ]);
    });

    test('near the end a forward skip is exact, a backward one is not', () {
      const late = Duration(hours: 1, minutes: 59);
      // To 1:59:40: there may be no keyframe after it.
      expect(command(40, from: late), ['seek', '7180.000', 'absolute+exact']);
      expect(command(-40, from: late), [
        'seek',
        '-40.000',
        'relative+keyframes',
      ]);
      // 30 s forward to a spot more than 30 s before the end: a keyframe.
      expect(command(30, from: const Duration(hours: 1, minutes: 58)), [
        'seek',
        '30.000',
        'relative+keyframes',
      ]);
    });

    test('while the duration is unknown the step alone decides', () {
      List<String> unknown(int seconds) => skipCommand(
        from: at,
        target: at + Duration(seconds: seconds),
        duration: Duration.zero,
      );
      expect(unknown(10).last, 'absolute+exact');
      expect(unknown(60), ['seek', '60.000', 'relative+keyframes']);
    });

    test('fractions of a second are kept', () {
      expect(
        skipCommand(
          from: const Duration(milliseconds: 61250),
          target: const Duration(milliseconds: 71250),
          duration: film,
        ),
        ['seek', '71.250', 'absolute+exact'],
      );
    });
  });

  test('a jump on the seek bar goes to the keyframe before the spot', () {
    expect(jumpCommand(const Duration(minutes: 42, milliseconds: 500)), [
      'seek',
      '2520.500',
      'absolute+keyframes',
    ]);
    expect(jumpCommand(Duration.zero), ['seek', '0.000', 'absolute+keyframes']);
  });
}
