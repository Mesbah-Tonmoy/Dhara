import 'package:dhara/features/player/playback_progress.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('isResumable', () {
    const movie = Duration(hours: 2);

    test('is true in the middle of a video', () {
      expect(isResumable(const Duration(minutes: 40), movie), isTrue);
      expect(isResumable(const Duration(seconds: 10), movie), isTrue);
    });

    test('is false in the first ten seconds of a long video', () {
      expect(isResumable(Duration.zero, movie), isFalse);
      expect(isResumable(const Duration(seconds: 9), movie), isFalse);
    });

    test('is false in the last 5% (credits)', () {
      expect(isResumable(const Duration(minutes: 113), movie), isTrue);
      expect(isResumable(const Duration(minutes: 114), movie), isFalse);
      expect(isResumable(movie, movie), isFalse);
    });

    test('what is past resuming at the end counts as watched', () {
      expect(isWatched(const Duration(minutes: 113), movie), isFalse);
      expect(isWatched(const Duration(minutes: 114), movie), isTrue);
      expect(isWatched(movie, movie), isTrue);
      // The first moments cannot be resumed either, but are not the end.
      expect(isWatched(const Duration(seconds: 3), movie), isFalse);
      expect(isWatched(Duration.zero, Duration.zero), isFalse);
    });

    test('uses 5% instead of ten seconds for short clips', () {
      const clip = Duration(seconds: 60);
      expect(isResumable(const Duration(seconds: 2), clip), isFalse);
      expect(isResumable(const Duration(seconds: 3), clip), isTrue);
      expect(isResumable(const Duration(seconds: 56), clip), isTrue);
      expect(isResumable(const Duration(seconds: 57), clip), isFalse);
    });

    test('is false while the duration is unknown', () {
      expect(isResumable(const Duration(minutes: 5), Duration.zero), isFalse);
    });
  });

  group('upNextSecondsLeft', () {
    const duration = Duration(minutes: 20);

    test('is null until the last 15 seconds', () {
      expect(upNextSecondsLeft(Duration.zero, duration), isNull);
      expect(
        upNextSecondsLeft(const Duration(minutes: 19, seconds: 44), duration),
        isNull,
      );
    });

    test('counts down the remaining seconds, rounding up', () {
      expect(
        upNextSecondsLeft(const Duration(minutes: 19, seconds: 45), duration),
        15,
      );
      expect(
        upNextSecondsLeft(
          const Duration(minutes: 19, seconds: 50, milliseconds: 400),
          duration,
        ),
        10,
      );
      expect(
        upNextSecondsLeft(
          const Duration(minutes: 19, seconds: 59, milliseconds: 900),
          duration,
        ),
        1,
      );
    });

    test('is null at and after the end, and for an unknown duration', () {
      expect(upNextSecondsLeft(duration, duration), isNull);
      expect(
        upNextSecondsLeft(const Duration(minutes: 21), duration),
        isNull,
      );
      expect(upNextSecondsLeft(Duration.zero, Duration.zero), isNull);
    });
  });
}
