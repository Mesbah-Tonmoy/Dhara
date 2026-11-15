import 'package:dhara/features/player/stall_watch.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const second = Duration(seconds: 1);

  /// Ticks once a second from [from] to [to] (inclusive) with the same
  /// state, and returns what was reported, with the second it came at.
  List<(int, Trouble)> run(
    StallWatch watch, {
    required int from,
    required int to,
    bool opened = true,
    bool playing = true,
    bool completed = false,
    Duration Function(int second)? position,
  }) => [
    for (var at = from; at <= to; at++)
      if (watch.tick(
            now: second * at,
            opened: opened,
            playing: playing,
            completed: completed,
            position: position?.call(at) ?? const Duration(minutes: 5),
          )
          case final trouble?)
        (at, trouble),
  ];

  test('a video that never opens is noticed after ten seconds, once', () {
    final watch = StallWatch()..restart(Duration.zero);

    expect(run(watch, from: 1, to: 30, opened: false), [
      (10, Trouble.notOpening),
    ]);
  });

  test('one that opens in time is left alone', () {
    final watch = StallWatch()..restart(Duration.zero);

    expect(run(watch, from: 1, to: 6, opened: false), isEmpty);
    expect(run(watch, from: 7, to: 60, position: (at) => second * at), isEmpty);
  });

  test('a position that stands still while it should play is noticed '
      'after ten seconds', () {
    final watch = StallWatch()..restart(Duration.zero);
    expect(run(watch, from: 1, to: 20, position: (at) => second * at), isEmpty);

    // From second 21 on nothing arrives: the first second it is seen
    // standing still is 22.
    expect(run(watch, from: 21, to: 60), [(32, Trouble.notLoading)]);
  });

  test('a short wait that ends is nothing', () {
    final watch = StallWatch()..restart(Duration.zero);

    expect(run(watch, from: 1, to: 8), isEmpty);
    expect(run(watch, from: 9, to: 12, position: (at) => second * at), isEmpty);
    // The next wait is counted from its own beginning.
    expect(run(watch, from: 13, to: 21), isEmpty);
    expect(run(watch, from: 22, to: 30), [(24, Trouble.notLoading)]);
  });

  test('a video at its end is not in trouble', () {
    final watch = StallWatch()..restart(Duration.zero);

    expect(run(watch, from: 1, to: 120, completed: true), isEmpty);
  });

  test('a position that moves is no trouble', () {
    final watch = StallWatch()..restart(Duration.zero);

    expect(run(watch, from: 1, to: 60, position: (at) => second * at), isEmpty);
  });

  test('a video the user paused is never in trouble', () {
    final watch = StallWatch()..restart(Duration.zero);

    expect(run(watch, from: 1, to: 120, playing: false), isEmpty);
    // Played again, and nothing comes: counted from then.
    expect(run(watch, from: 121, to: 140), [(131, Trouble.notLoading)]);
  });

  test('nothing is watched while idle, and a restart begins afresh', () {
    final watch = StallWatch();
    expect(run(watch, from: 1, to: 60, opened: false), isEmpty);

    watch.restart(second * 60);
    expect(run(watch, from: 61, to: 80, opened: false), [
      (70, Trouble.notOpening),
    ]);

    // The next copy gets its own ten seconds, and is reported again.
    watch.restart(second * 80);
    expect(run(watch, from: 81, to: 100, opened: false), [
      (90, Trouble.notOpening),
    ]);

    watch.idle();
    expect(run(watch, from: 101, to: 200, opened: false), isEmpty);
  });

  test('other limits can be set', () {
    final watch = StallWatch(openTimeout: second * 3, waitTimeout: second * 2)
      ..restart(Duration.zero);

    expect(run(watch, from: 1, to: 9, opened: false), [
      (3, Trouble.notOpening),
    ]);
    watch.restart(second * 10);
    expect(run(watch, from: 11, to: 20), [(14, Trouble.notLoading)]);
  });

  test('an end far from the end is a server that broke off', () {
    const film = Duration(hours: 2);

    expect(endedEarly(const Duration(minutes: 40), film), isTrue);
    // The last 5% count as the end.
    expect(endedEarly(const Duration(hours: 1, minutes: 55), film), isFalse);
    expect(endedEarly(film, film), isFalse);
    // A short clip: only what is more than a few seconds short.
    const clip = Duration(seconds: 12);
    expect(endedEarly(const Duration(seconds: 5), clip), isTrue);
    expect(endedEarly(const Duration(seconds: 10), clip), isFalse);
    expect(endedEarly(const Duration(seconds: 5), Duration.zero), isFalse);
  });

  test('every kind of trouble has words for the player', () {
    for (final trouble in Trouble.values) {
      expect(trouble.message, endsWith('.'));
    }
  });
}
