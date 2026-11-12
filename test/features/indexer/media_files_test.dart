import 'package:dhara/features/indexer/media_files.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('mediaKindOf', () {
    test('knows video files, whatever the case of the extension', () {
      for (final name in [
        'Tenet.2020.1080p.mkv',
        'movie.MP4',
        'clip.m4v',
        'old.avi',
        'trailer.mov',
        'web.WebM',
        'recording.ts',
        'disc.m2ts',
        'tape.mpg',
        'tape.mpeg',
        'show.wmv',
        'stream.flv',
      ]) {
        expect(mediaKindOf(name), MediaKind.video, reason: name);
      }
    });

    test('knows the subtitle files the player can load', () {
      for (final name in ['a.srt', 'a.en.ASS', 'a.ssa', 'a.vtt']) {
        expect(mediaKindOf(name), MediaKind.subtitle, reason: name);
      }
    });

    test('has no use for anything else', () {
      for (final name in [
        'setup.exe',
        'poster.jpg',
        'info.nfo',
        'movie.mkv.part',
        'movie.mkv.crdownload',
        'archive.rar',
        'disc.iso',
        'subs.sub',
        'subs.idx',
        'readme.txt',
        'page.html',
        'run.bat',
        'mkv',
        '.mkv',
        'no extension',
        'ends with dot.',
        '',
      ]) {
        expect(mediaKindOf(name), isNull, reason: name);
      }
    });
  });

  group('isSubtitleFolder', () {
    test('knows the usual names', () {
      for (final name in ['Subs', 'subs', 'SUB', 'Subtitle', 'Subtitles']) {
        expect(isSubtitleFolder(name), isTrue, reason: name);
      }
    });

    test('does not take other folders for one', () {
      for (final name in ['Season 1', 'Subway (2020)', 'Extras', '']) {
        expect(isSubtitleFolder(name), isFalse, reason: name);
      }
    });
  });

  group('matchSubtitles', () {
    test('pairs a subtitle with the video of the same name', () {
      expect(
        matchSubtitles(
          ['Inception.2010.mkv', 'Tenet.2020.mkv'],
          ['Tenet.2020.srt', 'Inception.2010.ass'],
        ),
        [1, 0],
      );
    });

    test('does not mind the case of the letters', () {
      expect(
        matchSubtitles(['TENET.2020.MKV', 'other.mkv'], ['tenet.2020.SRT']),
        [0],
      );
    });

    test('pairs a subtitle whose name continues the video name', () {
      expect(
        matchSubtitles(
          ['Tenet.2020.mkv', 'Inception.2010.mkv'],
          [
            'Tenet.2020.en.srt',
            'Tenet.2020.English.forced.srt',
            'Tenet.2020_bn.srt',
            'Tenet.2020-eng.srt',
            'Tenet.2020 (Bangla).srt',
            'Tenet.2020[SDH].srt',
          ],
        ),
        [0, 0, 0, 0, 0, 0],
      );
    });

    test('a name must continue at a separator', () {
      expect(
        matchSubtitles(['Alien.mkv', 'Up.mkv'], ['Aliens.srt', 'Upgrade.srt']),
        [null, null],
      );
    });

    test('the longest matching video name wins', () {
      expect(
        matchSubtitles(
          ['Movie.mkv', 'Movie.Part.2.mkv', 'Movie.Part.mkv'],
          ['Movie.Part.2.en.srt', 'Movie.Part.en.srt', 'Movie.en.srt'],
        ),
        [1, 2, 0],
      );
    });

    test('two videos with one name: the first gets the subtitle', () {
      expect(matchSubtitles(['a.mkv', 'a.mp4', 'b.mkv'], ['a.srt']), [0]);
    });

    test('pairs a shorter subtitle name with the one video it starts', () {
      expect(
        matchSubtitles(
          [
            'Show.S01E01.720p.WEB.mkv',
            'Show.S01E02.720p.WEB.mkv',
            'Show.S01E10.720p.WEB.mkv',
          ],
          ['Show.S01E02.srt', 'Show.S01E1.srt', 'Show.S01E10.srt'],
        ),
        [1, null, 2],
      );
    });

    test('a subtitle that starts several videos belongs to none', () {
      expect(
        matchSubtitles(
          ['Show.S01E01.mkv', 'Show.S01E02.mkv'],
          ['Show.srt', 'Show.S01.srt'],
        ),
        [null, null],
      );
    });

    test('next to a single video, any subtitle is its subtitle', () {
      expect(
        matchSubtitles(['Tenet.2020.mkv'], ['English.srt', '2_Bangla.ass']),
        [0, 0],
      );
    });

    test('with several videos, an unrelated subtitle belongs to none', () {
      expect(
        matchSubtitles(['a.mkv', 'b.mkv'], ['English.srt', 'c.srt']),
        [null, null],
      );
    });

    test('without videos there is nothing to belong to', () {
      expect(matchSubtitles([], ['a.srt', 'b.srt']), [null, null]);
      expect(matchSubtitles(['a.mkv'], []), isEmpty);
    });

    test('copes with odd names', () {
      expect(
        matchSubtitles(
          ['.hidden.mkv', 'no-dots', '...mkv'],
          ['.hidden.srt', '.srt', '-.srt'],
        ),
        [0, null, null],
      );
    });

    test('stays fast in a folder with thousands of files', () {
      final videos = [
        for (var i = 0; i < 10000; i++) 'Show.E${'$i'.padLeft(5, '0')}.HD.mkv',
      ];
      final subtitles = [
        for (var i = 0; i < 10000; i++) 'Show.E${'$i'.padLeft(5, '0')}.srt',
      ];
      final watch = Stopwatch()..start();

      final matches = matchSubtitles(videos, subtitles);

      expect(matches, [for (var i = 0; i < 10000; i++) i]);
      // Comparing every pair would take seconds.
      expect(watch.elapsedMilliseconds, lessThan(1000));
    });
  });
}
