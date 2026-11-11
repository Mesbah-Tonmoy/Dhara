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

  group('parseMediaUrls', () {
    test('reads one URL per line, in order', () {
      final result = parseMediaUrls(
        'http://h.example/e01.mkv\r\nhttp://h.example/e02.mkv\nhttp://h.example/e03.mkv',
      );

      expect(result.isValid, isTrue);
      expect(result.urls.map((u) => u.pathSegments.last), [
        'e01.mkv',
        'e02.mkv',
        'e03.mkv',
      ]);
    });

    test('ignores blank lines and surrounding spaces', () {
      final result = parseMediaUrls(
        '\n  http://h.example/a.mkv  \n\n   \nhttp://h.example/b.mkv\n',
      );

      expect(result.urls, hasLength(2));
    });

    test('a single URL is a list of one', () {
      expect(parseMediaUrls('http://h.example/a.mkv').urls, hasLength(1));
    });

    test('one bad line rejects everything and is reported by number', () {
      final result = parseMediaUrls(
        'http://h.example/a.mkv\n\nfile:///C:/secret.txt\nhttp://h.example/b.mkv',
      );

      expect(result.isValid, isFalse);
      expect(result.invalidLine, 3);
      expect(result.urls, isEmpty);
    });

    test('empty input is not valid', () {
      expect(parseMediaUrls('').isValid, isFalse);
      expect(parseMediaUrls(' \n \n').isValid, isFalse);
      expect(parseMediaUrls('').invalidLine, isNull);
    });
  });

  group('mediaTitleFromUrl', () {
    String title(String url) => mediaTitleFromUrl(parseMediaUrl(url)!);

    test('uses the decoded file name', () {
      expect(
        title('http://h.example/Movies/My%20Film%20(2021)%20%5B1080p%5D.mkv'),
        'My Film (2021) [1080p].mkv',
      );
      expect(title('http://h.example/a/b/c.mp4?token=1#x'), 'c.mp4');
    });

    test('decodes non-ASCII names', () {
      expect(
        title(
            'http://h.example/%E0%A6%AC%E0%A6%BE%E0%A6%82%E0%A6%B2%E0%A6%BE.mkv'),
        'বাংলা.mkv',
      );
    });

    test('ignores a trailing slash and falls back to the host', () {
      expect(title('http://h.example/Movies/Film/'), 'Film');
      expect(title('http://h.example/'), 'h.example');
      expect(title('http://10.16.100.244'), '10.16.100.244');
    });

    test('keeps the raw text when escapes are not valid UTF-8', () {
      expect(title('http://h.example/%FF%FE.mkv'), '%FF%FE.mkv');
    });

    test('never treats an encoded slash as a path separator', () {
      expect(title('http://h.example/a%2F..%2Fb.mkv'), 'a/../b.mkv');
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
