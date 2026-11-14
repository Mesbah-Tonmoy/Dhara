import 'package:dhara/core/db/library_db.dart';
import 'package:dhara/features/history/history_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late LibraryDb library;
  late HistoryStore store;
  late DateTime clock;

  setUp(() {
    library = LibraryDb.inMemory();
    clock = DateTime(2026, 11, 15, 21);
    store = HistoryStore(library, now: () => clock);
  });

  tearDown(() => library.close());

  void watch(String name, {int minutes = 30, bool finished = false}) {
    clock = clock.add(const Duration(minutes: 1));
    store.record(
      'http://a.test/$name',
      positionMs: Duration(minutes: minutes).inMilliseconds,
      durationMs: const Duration(hours: 2).inMilliseconds,
      finished: finished,
    );
  }

  List<String> names() => [
    for (final video in store.entries()) video.url.split('/').last,
  ];

  test('lists what was watched, the latest first', () {
    watch('a.mkv');
    watch('b.mkv', minutes: 45);

    final [latest, earlier] = store.entries();
    expect(latest.url, 'http://a.test/b.mkv');
    expect(latest.watchedAt, DateTime(2026, 11, 15, 21, 2));
    expect(latest.position, const Duration(minutes: 45));
    expect(latest.duration, const Duration(hours: 2));
    expect(latest.finished, isFalse);
    expect(earlier.url, 'http://a.test/a.mkv');
    expect(store.count(), 2);
  });

  test('a video is in it once: watching it again moves it up', () {
    watch('a.mkv');
    watch('b.mkv');
    watch('a.mkv', minutes: 50);

    expect(names(), ['a.mkv', 'b.mkv']);
    expect(store.entries().first.position, const Duration(minutes: 50));
  });

  test('a video watched to the end is kept as finished, all of it', () {
    watch('a.mkv', minutes: 117, finished: true);

    final video = store.entries().single;
    expect(video.finished, isTrue);
    expect(video.position, video.duration);

    // Started again later: it is under way once more.
    watch('a.mkv', minutes: 3);
    expect(store.entries().single.finished, isFalse);
    expect(store.entries().single.position, const Duration(minutes: 3));
  });

  test('takes a time other than now', () {
    store.record(
      'http://a.test/a.mkv',
      positionMs: 1000,
      durationMs: 5000,
      finished: false,
      at: DateTime(2026, 1, 2).millisecondsSinceEpoch,
    );

    expect(store.entries().single.watchedAt, DateTime(2026, 1, 2));
  });

  test('is read a page at a time', () {
    for (var i = 0; i < 7; i++) {
      watch('$i.mkv');
    }

    expect(
      [for (final v in store.entries(limit: 3)) v.url.split('/').last],
      ['6.mkv', '5.mkv', '4.mkv'],
    );
    expect(
      [
        for (final v in store.entries(limit: 3, offset: 6))
          v.url.split('/').last,
      ],
      ['0.mkv'],
    );
  });

  test('removes one video, or all of them', () {
    watch('a.mkv');
    watch('b.mkv');

    store.remove('http://a.test/a.mkv');
    expect(names(), ['b.mkv']);

    store.clear();
    expect(names(), isEmpty);
    expect(store.count(), 0);
  });

  test('keeps only the most recently watched videos', () {
    for (var i = 0; i < 12; i++) {
      watch('$i.mkv');
    }

    expect(store.trim(keep: 10), 2);
    expect(store.count(), 10);
    expect(names().last, '2.mkv');
    expect(store.trim(keep: 10), 0);
  });

  test('takes a URL as it is, whatever it holds', () {
    const odd = "http://a.test/it's'; DROP TABLE watch_history; --.mkv";
    store.record(odd, positionMs: 1, durationMs: 2, finished: false);

    expect(store.entries().single.url, odd);
    store.remove(odd);
    expect(store.count(), 0);
  });
}
