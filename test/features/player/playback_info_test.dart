import 'package:dhara/features/player/playback_info.dart';
import 'package:flutter_test/flutter_test.dart';

/// What the bundled libmpv answered while it played a short VP9 video from
/// a local web server (2026-11-16).
const _real = <String, String>{
  'width': '1920',
  'height': '1080',
  'video-format': 'vp9',
  'estimated-vf-fps': '24.012523',
  'hwdec-current': 'd3d11va-copy',
  'audio-codec-name': '',
  'audio-params/channel-count': '',
  'demuxer-cache-state':
      '{"cache-end":11.845000,"reader-pts":2.168000,'
      '"cache-duration":9.677000,"eof":true,"underrun":false,"idle":true,'
      '"total-bytes":1965680,"fw-bytes":1573312,"raw-input-rate":800921,'
      '"seekable-ranges":[{"start":0.000000,"end":11.845000}]}',
  'frame-drop-count': '0',
  'decoder-frame-drop-count': '0',
};

void main() {
  test('reads what libmpv answers', () {
    final info = PlaybackInfo.fromMpv(_real);

    expect(info.width, 1920);
    expect(info.height, 1080);
    expect(info.videoFormat, 'vp9');
    expect(info.framesPerSecond, closeTo(24.01, .01));
    expect(info.hardwareDecoder, 'd3d11va-copy');
    expect(info.softwareDecoding, isFalse);
    expect(info.audioFormat, isNull);
    expect(info.bufferedAhead, const Duration(milliseconds: 9677));
    expect(info.bufferedBytes, 1573312);
    expect(info.bytesPerSecond, 800921);
    expect(info.droppedFrames, 0);
  });

  test('the lines say it in plain words', () {
    final info = PlaybackInfo.fromMpv(
      {
        ..._real,
        'audio-codec-name': 'eac3',
        'audio-params/channel-count': '6',
        'frame-drop-count': '3',
        'decoder-frame-drop-count': '2',
      },
      server: 'DhakaFlix 7 (172.16.50.7)',
      serverAnswered: const Duration(milliseconds: 38),
      startedIn: const Duration(milliseconds: 1240),
    );

    expect(info.rows, [
      ('Server', 'DhakaFlix 7 (172.16.50.7)'),
      ('Server answered in', '38 ms'),
      ('Started in', '1.2 s'),
      ('Picture', '1920×1080 · vp9 · 24 fps'),
      ('Decoding', 'Graphics card (d3d11va-copy)'),
      ('Sound', 'eac3 · 6 channels'),
      ('Buffer', '9.7 s ahead · 1.5 MB'),
      ('Server speed', '0.8 MB/s'),
      ('Dropped frames', '5'),
    ]);
  });

  test('says when the processor decodes', () {
    final info = PlaybackInfo.fromMpv({..._real, 'hwdec-current': 'no'});
    expect(info.hardwareDecoder, isNull);
    expect(info.softwareDecoding, isTrue);
    expect(info.rows, contains(('Decoding', 'Processor (software)')));
  });

  test('before a video is open nothing is claimed', () {
    final info = PlaybackInfo.fromMpv({
      for (final name in playbackInfoProperties) name: '',
    });
    expect(info.rows, isEmpty);
    expect(PlaybackInfo.fromMpv(const {}).rows, isEmpty);
  });

  test('an answer in another shape is left out, not trusted', () {
    for (final cache in ['not json', '[1,2]', '{"fw-bytes":"many"}', '7']) {
      final info = PlaybackInfo.fromMpv({
        'demuxer-cache-state': cache,
        'width': 'wide',
      });
      expect(info.bufferedBytes, isNull, reason: cache);
      expect(info.bufferedAhead, isNull, reason: cache);
      expect(info.width, isNull);
    }
  });

  test('texts from the file are cut and cleaned', () {
    final info = PlaybackInfo.fromMpv({
      'video-format': 'h264\n<b>bold</b>\u0007${'x' * 80}',
    });
    final format = info.videoFormat!;
    expect(format.length, 41);
    expect(format, startsWith('h264 <b>bold</b> x'));
    expect(format, isNot(contains('\n')));
  });

  test('options libmpv did not take are named', () {
    const info = PlaybackInfo(notTaken: ['cache-on-disk', 'hwdec']);
    expect(info.rows, [('Options not taken', 'cache-on-disk, hwdec')]);
  });

  test('megabytes have one decimal', () {
    expect(formatMegabytes(0), '0.0 MB');
    expect(formatMegabytes(64 * 1024 * 1024), '64.0 MB');
    expect(formatMegabytes(1573312), '1.5 MB');
  });
}
