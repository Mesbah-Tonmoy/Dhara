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
      final options = audioOptions(const [AudioTrack('1', '<b>x</b>', null)]);

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
      expect(
        nextOption(const [TrackOption(id: 'no', label: 'Off')], 'no'),
        isNull,
      );
      expect(nextOption(const [], 'no'), isNull);
    });
  });

  group('sound the player cannot decode', () {
    // The bundled libmpv has no Dolby TrueHD decoder (checked 2026-11-16).
    const decoders = {'ac3', 'eac3', 'dts', 'aac'};
    const film = [
      AudioTrack('auto', null, null),
      AudioTrack('no', null, null),
      AudioTrack('1', 'TrueHD Atmos 7.1', 'eng', codec: 'truehd'),
      AudioTrack('2', null, 'hin', codec: 'eac3', channelscount: 6),
      AudioTrack('3', 'Compatibility', 'eng', codec: 'ac3', channelscount: 6),
    ];

    test('decodableCodecs reads libmpv\'s decoder list', () {
      expect(
        decodableCodecs(
          '[{"codec":"ac3","driver":"ac3","description":"ATSC A/52A"},'
          '{"codec":"DTS","driver":"dca"},{"driver":"odd"},7]',
        ),
        {'ac3', 'dts'},
      );
      for (final unreadable in ['', 'no', '{"codec":"ac3"}', '[1,2']) {
        expect(decodableCodecs(unreadable), isEmpty, reason: unreadable);
      }
    });

    test('a track without a decoder says so in the list', () {
      final labels = audioOptions(film, decoders: decoders).map((o) => o.label);
      expect(labels, [
        'English · TrueHD Atmos 7.1 · TrueHD · cannot be played',
        'Hindi · E-AC3 5.1',
        'English · Compatibility · AC3 5.1',
      ]);
      // Without a decoder list nothing is ruled out.
      expect(
        audioOptions(film).first.label,
        'English · TrueHD Atmos 7.1 · TrueHD',
      );
    });

    test('another track in the same language is played instead', () {
      // libmpv keeps the track selected, or gives up on it: both count.
      expect(audioFallback(film, '1', decoders)?.id, '3');
      expect(audioFallback(film, offId, decoders)?.id, '3');
    });

    test('without one in that language, the first that can be played', () {
      const tracks = [
        AudioTrack('1', null, 'eng', codec: 'truehd'),
        AudioTrack('2', null, 'hin', codec: 'eac3'),
        AudioTrack('3', null, 'ben', codec: 'aac'),
      ];
      expect(audioFallback(tracks, '1', decoders)?.id, '2');
    });

    test('a track that can be played is left alone', () {
      expect(audioFallback(film, '2', decoders), isNull);
      expect(audioFallback(film, '3', decoders), isNull);
      // Not known what can be decoded: nothing is changed.
      expect(audioFallback(film, '1', const {}), isNull);
      // A codec libmpv does not name counts as playable.
      expect(
        audioFallback(const [AudioTrack('1', null, 'eng')], '1', decoders),
        isNull,
      );
    });

    test('there is nothing to switch to when no track can be played', () {
      const tracks = [
        AudioTrack('1', null, 'eng', codec: 'truehd'),
        AudioTrack('2', null, 'eng', codec: 'mlp'),
      ];
      expect(audioFallback(tracks, '1', decoders), isNull);
      expect(canDecode(tracks.first, decoders), isFalse);
      expect(audioFormatName(tracks.first), 'TrueHD');
      expect(audioFormatName(tracks.last), 'MLP');
    });

    test('libmpv\'s complaint about a sound decoder is recognised', () {
      expect(
        undecodableAudioCodec(
          "Failed to initialize a decoder for codec 'truehd'.",
        ),
        'truehd',
      );
      expect(
        undecodableAudioCodec(
          "Failed to initialize a decoder for codec 'mlp'.",
        ),
        'mlp',
      );
      // A picture that cannot be decoded stays an error.
      expect(
        undecodableAudioCodec(
          "Failed to initialize a decoder for codec 'hevc'.",
        ),
        isNull,
      );
      expect(undecodableAudioCodec('tcp: connection refused'), isNull);
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
