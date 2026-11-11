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
}
