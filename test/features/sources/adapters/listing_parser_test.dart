import 'package:dhara/features/sources/adapters/listing_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('childEntry', () {
    final folder = Uri.parse('http://10.0.0.5/Movies/English%20Movies/');

    test('reads a file and a folder directly inside the folder', () {
      final file = childEntry(folder, 'Quiet%20River%20(2019).mkv')!;
      final sub = childEntry(folder, 'Paper%20Kites%20(2021)/')!;

      expect(file.name, 'Quiet River (2019).mkv');
      expect(file.isFolder, isFalse);
      expect(
        file.url.toString(),
        'http://10.0.0.5/Movies/English%20Movies/Quiet%20River%20(2019).mkv',
      );
      expect(sub.name, 'Paper Kites (2021)');
      expect(sub.isFolder, isTrue);
      expect(sub.url.path, endsWith('/Paper%20Kites%20(2021)/'));
    });

    test('accepts absolute paths and full URLs of the same folder', () {
      expect(
        childEntry(folder, '/Movies/English%20Movies/a.mkv')?.name,
        'a.mkv',
      );
      expect(
        childEntry(folder, 'http://10.0.0.5/Movies/English%20Movies/a.mkv')
            ?.name,
        'a.mkv',
      );
    });

    test('matches the folder even when the server escapes it differently',
        () {
      // h5ai escapes "(" and ")"; a hand-typed base URL does not.
      final typed = Uri.parse('http://10.0.0.5/Movies (HD)/');

      expect(childEntry(typed, '/Movies%20%28HD%29/a.mkv')?.name, 'a.mkv');
    });

    test('works when the folder URL lacks its final slash', () {
      final bare = Uri.parse('http://10.0.0.5/Movies');

      expect(childEntry(bare, '/Movies/a.mkv')?.name, 'a.mkv');
    });

    test('keeps names with unusual but harmless characters', () {
      expect(childEntry(folder, 'lost+found/')?.name, 'lost+found');
      expect(
        childEntry(folder, '%E0%A6%AC%E0%A6%BE%E0%A6%82%E0%A6%B2%E0%A6%BE.mp4')
            ?.name,
        'বাংলা.mp4',
      );
      expect(childEntry(folder, 'What%3F%20%231.mkv')?.name, 'What? #1.mkv');
      // Not valid UTF-8 (a Latin-1 "é"): the raw text is kept.
      expect(childEntry(folder, 'Am%E9lie.mkv')?.name, 'Am%E9lie.mkv');
    });

    test('ignores the parent, the folder itself and sort links', () {
      for (final href in [
        '..',
        '../',
        '/',
        '/Movies/',
        '.',
        './',
        '',
        '?C=N;O=D',
        '?C=M;O=A',
        '#top',
        '/Movies/English%20Movies/',
      ]) {
        expect(childEntry(folder, href), isNull, reason: '"$href"');
      }
    });

    test('ignores links that leave the folder', () {
      for (final href in [
        'sub/file.mkv',
        '../Other/file.mkv',
        '/Other/file.mkv',
        '/Movies/English%20Movies%20Extra/file.mkv',
        'http://10.0.0.6/Movies/English%20Movies/file.mkv',
        'https://10.0.0.5/Movies/English%20Movies/file.mkv',
        'http://10.0.0.5:8080/Movies/English%20Movies/file.mkv',
        '//evil.example/Movies/English%20Movies/file.mkv',
      ]) {
        expect(childEntry(folder, href), isNull, reason: href);
      }
    });

    test('ignores other schemes and unparsable links', () {
      for (final href in [
        'file:///C:/Windows/win.ini',
        'javascript:alert(1)',
        'mailto:admin@example.net',
        'ftp://10.0.0.5/Movies/English%20Movies/file.mkv',
        'http://[broken',
      ]) {
        expect(childEntry(folder, href), isNull, reason: href);
      }
    });

    test('ignores names that hide a path separator or control character',
        () {
      for (final href in [
        '..%2F..%2Fetc%2Fpasswd',
        'a%2Fb.mkv',
        'a%5Cb.mkv',
        '%2E%2E/',
        '%2e%2e%2f',
        'a%00.mkv',
        'a%0Ab.mkv',
        'file.mkv?download=1',
        'file.mkv#t=10',
      ]) {
        expect(childEntry(folder, href), isNull, reason: href);
      }
    });
  });

  group('parseListingSize', () {
    test('reads plain byte counts', () {
      expect(parseListingSize('1503238553'), 1503238553);
      expect(parseListingSize('  168 '), 168);
      expect(parseListingSize('0'), 0);
    });

    test('reads rounded sizes in powers of 1024', () {
      expect(parseListingSize('4.0K'), 4096);
      expect(parseListingSize('356M'), 356 * 1024 * 1024);
      expect(parseListingSize('1.6G'), 1717986918);
      expect(parseListingSize('2T'), 2 * 1024 * 1024 * 1024 * 1024);
      expect(parseListingSize('1,5M'), 1572864);
    });

    test('reads sizes with a unit word, as h5ai prints them', () {
      expect(parseListingSize('88 KB'), 88 * 1024);
      expect(parseListingSize('1762038 KB'), 1762038 * 1024);
      expect(parseListingSize('12 MiB'), 12 * 1024 * 1024);
      expect(parseListingSize('512 B'), 512);
    });

    test('returns null for anything that is not a size', () {
      for (final text in ['', '-', '  - ', '<dir>', '\u00A0', 'big', '1.2.3G']) {
        expect(parseListingSize(text), isNull, reason: '"$text"');
      }
      expect(parseListingSize('2024-01-06 17:46'), isNull);
    });
  });

  group('parseListingDate', () {
    test('reads the formats listings use', () {
      expect(parseListingDate('2024-01-06 17:46  '), DateTime(2024, 1, 6, 17, 46));
      expect(parseListingDate('2019-08-29 18:11'), DateTime(2019, 8, 29, 18, 11));
      expect(parseListingDate('01-Aug-2022 15:54'), DateTime(2022, 8, 1, 15, 54));
      expect(parseListingDate('11-dec-2025 02:05'), DateTime(2025, 12, 11, 2, 5));
    });

    test('reads IIS dates, month first, with AM and PM', () {
      expect(
        parseListingDate(' 11/3/2024  9:05 PM   2147483648 '),
        DateTime(2024, 11, 3, 21, 5),
      );
      expect(parseListingDate('1/12/2023 10:20 AM <dir>'), DateTime(2023, 1, 12, 10, 20));
      expect(parseListingDate('12/31/2024 12:00 AM'), DateTime(2024, 12, 31));
      expect(parseListingDate('12/31/2024 12:30 PM'), DateTime(2024, 12, 31, 12, 30));
    });

    test('reads the date even when the size follows it', () {
      expect(
        parseListingDate('   04-Mar-2024 21:09          1503238553\r\n'),
        DateTime(2024, 3, 4, 21, 9),
      );
    });

    test('returns null for anything else', () {
      for (final text in [
        '',
        '-',
        '\u00A0',
        'yesterday',
        '2024-13-01 10:00',
        '2024-01-32 10:00',
        '2024-01-06 24:00',
        '2024-01-06 10:60',
        '01-Foo-2022 15:54',
        '31/12/2024 10:00 AM',
        '1503238553',
      ]) {
        expect(parseListingDate(text), isNull, reason: '"$text"');
      }
    });
  });
}
