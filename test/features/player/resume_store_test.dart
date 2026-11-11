import 'dart:convert';

import 'package:dhara/core/settings/key_value_store.dart';
import 'package:dhara/features/player/resume_store.dart';
import 'package:flutter_test/flutter_test.dart';

const _key = 'player.resumePositions';
const _movie = Duration(hours: 2);

Uri _url(String name) => Uri.parse('http://10.16.100.244/movies/$name');

void main() {
  test('remembers a position and survives a restart', () {
    final store = MemoryKeyValueStore();
    ResumeStore(store).save(
      _url('a.mkv'),
      position: const Duration(minutes: 42, seconds: 7),
      duration: _movie,
    );

    expect(
      ResumeStore(store).positionFor(_url('a.mkv')),
      const Duration(minutes: 42, seconds: 7),
    );
  });

  test('has nothing for a video never played', () {
    expect(
        ResumeStore(MemoryKeyValueStore()).positionFor(_url('a.mkv')), isNull);
  });

  test('keeps videos apart', () {
    final resume = ResumeStore(MemoryKeyValueStore())
      ..save(_url('a.mkv'),
          position: const Duration(minutes: 5), duration: _movie)
      ..save(_url('b.mkv'),
          position: const Duration(minutes: 9), duration: _movie);

    expect(resume.positionFor(_url('a.mkv')), const Duration(minutes: 5));
    expect(resume.positionFor(_url('b.mkv')), const Duration(minutes: 9));
  });

  test('ignores the URL fragment but not the query', () {
    final resume = ResumeStore(MemoryKeyValueStore())
      ..save(
        Uri.parse('http://h.example/a.mkv?v=1#t=5'),
        position: const Duration(minutes: 5),
        duration: _movie,
      );

    expect(
      resume.positionFor(Uri.parse('http://h.example/a.mkv?v=1')),
      const Duration(minutes: 5),
    );
    expect(resume.positionFor(Uri.parse('http://h.example/a.mkv?v=2')), isNull);
  });

  test('forgets a video that is stopped near the start or in the credits', () {
    final resume = ResumeStore(MemoryKeyValueStore())
      ..save(_url('a.mkv'),
          position: const Duration(minutes: 5), duration: _movie)
      ..save(_url('a.mkv'),
          position: const Duration(seconds: 3), duration: _movie);
    expect(resume.positionFor(_url('a.mkv')), isNull);

    resume
      ..save(_url('a.mkv'),
          position: const Duration(minutes: 5), duration: _movie)
      ..save(_url('a.mkv'),
          position: const Duration(minutes: 118), duration: _movie);
    expect(resume.positionFor(_url('a.mkv')), isNull);
  });

  test('does not touch anything while the duration is unknown', () {
    final resume = ResumeStore(MemoryKeyValueStore())
      ..save(_url('a.mkv'),
          position: const Duration(minutes: 5), duration: _movie)
      ..save(_url('a.mkv'), position: Duration.zero, duration: Duration.zero);

    expect(resume.positionFor(_url('a.mkv')), const Duration(minutes: 5));
  });

  test('clear forgets a video', () {
    final store = MemoryKeyValueStore();
    final resume = ResumeStore(store)
      ..save(_url('a.mkv'),
          position: const Duration(minutes: 5), duration: _movie)
      ..clear(_url('a.mkv'));

    expect(resume.positionFor(_url('a.mkv')), isNull);
    expect(ResumeStore(store).positionFor(_url('a.mkv')), isNull);
  });

  test('keeps only the most recently watched videos', () {
    final store = MemoryKeyValueStore();
    final resume = ResumeStore(store);
    for (var i = 0; i < ResumeStore.maxEntries + 5; i++) {
      resume.save(
        _url('$i.mkv'),
        position: const Duration(minutes: 5),
        duration: _movie,
      );
    }
    // Watching an old one again makes it recent.
    resume.save(
      _url('5.mkv'),
      position: const Duration(minutes: 6),
      duration: _movie,
    );
    resume.save(
      _url('new.mkv'),
      position: const Duration(minutes: 5),
      duration: _movie,
    );

    expect(resume.positionFor(_url('0.mkv')), isNull);
    expect(resume.positionFor(_url('4.mkv')), isNull);
    expect(resume.positionFor(_url('6.mkv')), isNull);
    expect(resume.positionFor(_url('5.mkv')), const Duration(minutes: 6));
    expect(resume.positionFor(_url('new.mkv')), isNotNull);

    final saved = jsonDecode(store.getString(_key)!) as List<Object?>;
    expect(saved, hasLength(ResumeStore.maxEntries));
  });

  group('damaged storage', () {
    ResumeStore load(Object value) =>
        ResumeStore(MemoryKeyValueStore({_key: value}));

    test('is ignored when it is not JSON, or not a list', () {
      expect(load('not json').positionFor(_url('a.mkv')), isNull);
      expect(load('{"a": 1}').positionFor(_url('a.mkv')), isNull);
      expect(load(42).positionFor(_url('a.mkv')), isNull);
    });

    test('skips malformed rows and keeps the good ones', () {
      final resume = load(
        jsonEncode([
          'nonsense',
          ['http://10.16.100.244/movies/short-row.mkv', 5],
          ['http://10.16.100.244/movies/text.mkv', 'five', 100],
          ['http://10.16.100.244/movies/negative.mkv', -5, 100],
          ['http://10.16.100.244/movies/past-end.mkv', 500, 100],
          [42, 5, 100],
          ['http://10.16.100.244/movies/good.mkv', 60000, 7200000],
        ]),
      );

      for (final name in ['short-row', 'text', 'negative', 'past-end']) {
        expect(resume.positionFor(_url('$name.mkv')), isNull, reason: name);
      }
      expect(resume.positionFor(_url('good.mkv')), const Duration(minutes: 1));
    });
  });
}
