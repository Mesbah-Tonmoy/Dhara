import 'package:dhara/features/metadata/metadata_store.dart';
import 'package:dhara/features/metadata/release_name.dart';
import 'package:dhara/features/playback/copy_choice.dart';
import 'package:dhara/features/playback/play.dart';
import 'package:dhara/features/sources/source.dart';
import 'package:dhara/features/sources/source_store.dart';
import 'package:flutter_test/flutter_test.dart';

Source _source(String id, {SourceType type = SourceType.h5ai}) => Source(
  id: id,
  name: 'Server $id',
  type: type,
  category: SourceCategory.mixed,
  baseUrls: [Uri.parse('http://10.0.0.1/$id/')],
);

var _ids = 0;

TitleCopy _copy(
  String source, {
  int? height,
  int? size,
  int? season,
  int? episode,
  String? episodeName,
  ExtraKind? extra,
  String? url,
}) {
  final id = ++_ids;
  return TitleCopy(
    fileId: id,
    sourceId: source,
    name: 'file$id.mkv',
    path: 'Movies',
    url: Uri.parse(url ?? 'http://10.0.0.1/$source/file$id.mkv'),
    height: height,
    size: size,
    season: season,
    episode: episode,
    episodeName: episodeName,
    extra: extra,
  );
}

void main() {
  late SourceStore sources;

  /// Notes how the last test of [id] went.
  Future<void> tested(String id, {required bool reachable, int? ms}) =>
      sources.recordHealth({
        id: SourceHealth(
          checkedAt: DateTime(2026, 11, 15),
          reachable: reachable,
          readable: reachable,
          ping: ms == null ? null : Duration(milliseconds: ms),
        ),
      });

  setUp(() {
    sources = SourceStore(
      starter: [
        _source('fast'),
        _source('slow'),
        _source('down'),
        _source('new'),
        _source('emby', type: SourceType.emby),
      ],
    );
  });

  group('rankCopies', () {
    test('puts servers that answered first, then the sharpest picture, '
        'then the quicker server, then the larger file', () async {
      await tested('fast', reachable: true, ms: 8);
      await tested('slow', reachable: true, ms: 90);
      await tested('down', reachable: false);
      final offline4k = _copy('down', height: 2160);
      final untested = _copy('new', height: 2160);
      final slowHd = _copy('slow', height: 1080);
      final fastHd = _copy('fast', height: 1080, size: 100);
      final fastHdLarger = _copy('fast', height: 1080, size: 900);
      final fastSd = _copy('fast', height: 480);

      expect(
        rankCopies([
          offline4k,
          fastSd,
          slowHd,
          untested,
          fastHd,
          fastHdLarger,
        ], sources),
        [fastHdLarger, fastHd, slowHd, fastSd, untested, offline4k],
      );
    });

    test('puts what cannot be played last, however good', () async {
      await tested('emby', reachable: true, ms: 1);
      final needsSignIn = _copy('emby', height: 2160);
      final odd = _copy('fast', height: 2160, url: 'ftp://10.0.0.1/a.mkv');
      final plain = _copy('new', height: 480);

      expect(rankCopies([needsSignIn, odd, plain], sources).first, plain);
      expect(canPlayCopy(needsSignIn, sources), isFalse);
      expect(canPlayCopy(odd, sources), isFalse);
      expect(
        canPlayCopy(
          _copy('fast', url: 'http://user:pw@10.0.0.1/a.mkv'),
          sources,
        ),
        isFalse,
      );
    });

    test('tells how each server stood', () async {
      await tested('fast', reachable: true, ms: 8);
      await tested('down', reachable: false, ms: 5);

      expect(reachOf(_copy('fast'), sources), CopyReach.online);
      expect(reachOf(_copy('down'), sources), CopyReach.offline);
      expect(reachOf(_copy('new'), sources), CopyReach.unknown);
      expect(pingOf(_copy('fast'), sources), const Duration(milliseconds: 8));
      expect(pingOf(_copy('down'), sources), isNull);
      expect(sourceOf(_copy('fast'), sources)?.name, 'Server fast');
      expect(sourceOf(_copy('gone'), sources), isNull);
    });
  });

  group('bestCopy', () {
    test('is the first of the ranking that can be played', () async {
      await tested('fast', reachable: true, ms: 8);
      final trailer = _copy('fast', height: 2160, extra: ExtraKind.trailer);
      final film = _copy('fast', height: 720);

      expect(
        bestCopy([trailer, film, _copy('new', height: 1080)], sources),
        film,
      );
      expect(bestCopy([trailer, _copy('emby')], sources), isNull);
      expect(bestCopy(const [], sources), isNull);
    });
  });

  group('episodes', () {
    test('are grouped in order, seasons before what is numbered straight '
        'through', () {
      final copies = [
        _copy('fast', episode: 7),
        _copy('fast', season: 2, episode: 1),
        _copy('fast', season: 1, episode: 2),
        _copy('slow', season: 1, episode: 2),
        _copy('fast', season: 1, episode: 1),
        _copy('fast', season: 1, episode: 3, extra: ExtraKind.sample),
        _copy('fast'),
      ];

      final episodes = episodesIn(copies);

      expect(episodes.keys, [(1, 1), (1, 2), (2, 1), (null, 7)]);
      expect(episodes[(1, 2)], hasLength(2));
    });

    test('the queue is the chosen copy, then the episodes after it', () {
      final e1 = _copy('fast', season: 1, episode: 1);
      final e2 = _copy('slow', season: 1, episode: 2, height: 1080);
      final e2other = _copy('fast', season: 1, episode: 2, height: 2160);
      final e3 = _copy('fast', season: 1, episode: 3, height: 480);
      final e3better = _copy('new', season: 1, episode: 3, height: 1080);
      final e4 = _copy('emby', season: 1, episode: 4);
      final s2 = _copy('new', season: 2, episode: 1);
      final all = [s2, e4, e3better, e3, e2other, e2, e1];

      // From episode 2 on the slow server: that server where it has the
      // episode, the best copy where it has not, nothing that cannot play.
      expect(queueFrom(e2, all, sources), [e2, e3better, s2]);
      expect(queueFrom(e1, all, sources), [e1, e2other, e3, s2]);
      expect(queueFrom(s2, all, sources), [s2]);
      expect(queueFrom(e1, all, sources, limit: 2), [e1, e2other]);
    });

    test('a film, or a trailer, is played alone', () {
      final film = _copy('fast');
      final trailer = _copy(
        'fast',
        season: 1,
        episode: 1,
        extra: ExtraKind.trailer,
      );
      final all = [film, trailer, _copy('fast', season: 1, episode: 2)];

      expect(queueFrom(film, all, sources), [film]);
      expect(queueFrom(trailer, all, sources), [trailer]);
    });
  });

  group('labels', () {
    test('an episode is named by season and number', () {
      expect(episodeCode(1, 2), 'S1 · E2');
      expect(episodeCode(null, 12), 'Episode 12');
    });

    test('the player calls a copy by its title', () {
      expect(
        playLabel('Vivarium', _copy('fast'), year: 2019),
        'Vivarium (2019)',
      );
      expect(playLabel('Vivarium', _copy('fast')), 'Vivarium');
      expect(
        playLabel(
          'The Bay',
          _copy('fast', season: 1, episode: 2, episodeName: 'Second One'),
          year: 2019,
        ),
        'The Bay · S1 · E2 · Second One',
      );
      expect(
        playLabel('One Piece', _copy('fast', episode: 1071)),
        'One Piece · Episode 1071',
      );
    });
  });
}
