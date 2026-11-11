import 'package:dhara/features/player/track_options.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';

void main() {
  group('audioOptions', () {
    test('drops media_kit\'s "auto" and "no" pseudo-tracks', () {
      final options = audioOptions(const [
        AudioTrack('auto', null, null),
        AudioTrack('no', null, null),
        AudioTrack('1', null, 'eng'),
      ]);

      expect(options.map((o) => o.id), ['1']);
    });

    test('is empty for a video without sound', () {
      expect(
        audioOptions(const [
          AudioTrack('auto', null, null),
          AudioTrack('no', null, null),
        ]),
        isEmpty,
      );
    });

    test('labels tracks with language, title, codec and channel layout', () {
      final options = audioOptions(const [
        AudioTrack('1', null, 'eng', codec: 'ac3', channelscount: 6),
        AudioTrack('2', 'Director commentary', 'eng', codec: 'aac'),
        AudioTrack('3', 'Hindi', 'hin', codec: 'eac3', channelscount: 2),
        AudioTrack('4', null, 'ben', codec: 'dts', channelscount: 8),
        AudioTrack('5', null, 'jpn', codec: 'opus', channelscount: 1),
      ]);

      expect(options.map((o) => o.label), [
        'English · AC3 5.1',
        'English · Director commentary · AAC',
        'Hindi · E-AC3 Stereo',
        'Bengali · DTS 7.1',
        'Japanese · Opus Mono',
      ]);
    });

    test('falls back to a numbered name when nothing is known', () {
      final options = audioOptions(const [
        AudioTrack('1', null, null),
        AudioTrack('2', '  ', 'und'),
        AudioTrack('3', null, 'xx', codec: 'unknown_codec'),
      ]);

      expect(options.map((o) => o.label), ['Track 1', 'Track 2', 'Track 3']);
    });

    test('keeps a title as plain text, whatever it contains', () {
      final options = audioOptions(const [
        AudioTrack('1', '<b>x</b>', null),
      ]);

      expect(options.single.label, '<b>x</b>');
    });
  });

  group('subtitleOptions', () {
    test('always starts with Off', () {
      expect(
        subtitleOptions(const [
          SubtitleTrack('auto', null, null),
          SubtitleTrack('no', null, null),
        ]),
        const [TrackOption(id: 'no', label: 'Off')],
      );
    });

    test('labels tracks with language, title and format', () {
      final options = subtitleOptions(const [
        SubtitleTrack('auto', null, null),
        SubtitleTrack('no', null, null),
        SubtitleTrack('1', null, 'eng', codec: 'subrip'),
        SubtitleTrack('2', 'Signs & Songs', 'eng', codec: 'ass'),
        SubtitleTrack('3', null, 'ben', codec: 'hdmv_pgs_subtitle'),
        SubtitleTrack('4', 'film.srt', 'auto', codec: 'subrip'),
      ]);

      expect(options.map((o) => o.label), [
        'Off',
        'English · SRT',
        'English · Signs & Songs · ASS',
        'Bengali · PGS',
        'film.srt · SRT',
      ]);
      expect(options.map((o) => o.id), ['no', '1', '2', '3', '4']);
    });
  });

  group('nextOption', () {
    const options = [
      TrackOption(id: 'no', label: 'Off'),
      TrackOption(id: '1', label: 'English'),
      TrackOption(id: '2', label: 'Bengali'),
    ];

    test('steps forward and wraps around to Off', () {
      expect(nextOption(options, 'no')?.id, '1');
      expect(nextOption(options, '1')?.id, '2');
      expect(nextOption(options, '2')?.id, 'no');
    });

    test('starts from the first option for an unknown id', () {
      expect(nextOption(options, '99')?.id, 'no');
    });

    test('returns null when there is nothing to switch to', () {
      expect(nextOption(const [TrackOption(id: 'no', label: 'Off')], 'no'),
          isNull);
      expect(nextOption(const [], 'no'), isNull);
    });
  });

  test('languageNameFor knows 2- and 3-letter codes, case-insensitively', () {
    expect(languageNameFor('eng'), 'English');
    expect(languageNameFor('EN'), 'English');
    expect(languageNameFor('ben'), 'Bengali');
    expect(languageNameFor('bn'), 'Bengali');
    expect(languageNameFor('fre'), 'French');
    expect(languageNameFor('fra'), 'French');
    expect(languageNameFor('und'), isNull);
    expect(languageNameFor(''), isNull);
    expect(languageNameFor(null), isNull);
  });
}
