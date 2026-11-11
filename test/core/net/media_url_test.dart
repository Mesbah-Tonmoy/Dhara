import 'package:dhara/core/net/media_url.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseMediaUrl accepts', () {
    test('plain http and https URLs', () {
      expect(
        parseMediaUrl('http://media.example.net/movies/a.mkv').toString(),
        'http://media.example.net/movies/a.mkv',
      );
      expect(parseMediaUrl('https://example.org/v.mp4')?.scheme, 'https');
    });

    test('surrounding whitespace and upper-case scheme', () {
      final uri = parseMediaUrl('  HTTP://Example.NET/a.mkv \n');
      expect(uri?.scheme, 'http');
      expect(uri?.host, 'example.net');
    });

    test('private IP ranges and custom ports (common on BDIX)', () {
      expect(
          parseMediaUrl('http://10.16.100.244/a.mkv')?.host, '10.16.100.244');
      expect(parseMediaUrl('http://172.16.50.4:8096/x')?.port, 8096);
      expect(parseMediaUrl('http://192.168.1.2/x'), isNotNull);
    });

    test('spaces and brackets in the path, percent-encoding them', () {
      final uri =
          parseMediaUrl('http://h.example/Movies/My Film (2021) [1080p].mkv');
      expect(uri, isNotNull);
      expect(uri.toString(), isNot(contains(' ')));
      expect(uri!.pathSegments.last, 'My Film (2021) [1080p].mkv');
    });
  });

  group('parseMediaUrl rejects', () {
    const rejected = <String>[
      '',
      '   ',
      'file:///C:/Windows/win.ini',
      r'C:\Videos\a.mkv',
      r'\\server\share\a.mkv',
      '/movies/a.mkv',
      'movies/a.mkv',
      'media.example.net/a.mkv',
      'ftp://media.example.net/a.mkv',
      'smb://media.example.net/a.mkv',
      'rtmp://media.example.net/live',
      'data:video/mp4;base64,AAAA',
      'javascript:alert(1)',
      'edl://http://a/b.mkv',
      'memory://#EXTM3U',
      'lavf://http://a/b.mkv',
      'ytdl://abc',
      'av://lavfi:testsrc',
      'http://',
      'http:///a.mkv',
      'http:a.mkv',
    ];

    for (final input in rejected) {
      test('"$input"', () => expect(parseMediaUrl(input), isNull));
    }
  });
}
