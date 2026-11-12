import 'package:dhara/core/net/safe_http_client.dart';
import 'package:dhara/features/sources/adapters/directory_listing_adapter.dart';
import 'package:dhara/features/sources/adapters/source_adapter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;

import '../../../support/local_server.dart';

List<RemoteEntry> _parse(String file, String folder) =>
    parseDirectoryListing(fixture('listings/$file'), Uri.parse(folder));

void main() {
  group('real pages', () {
    test('Apache table of folders (ICC FTP)', () {
      const folder = 'http://10.16.100.202/ftps10/iccftps10sasd9/Movies/';

      final entries = _parse('apache_table_folders.html', folder);

      expect(entries, hasLength(19));
      expect(entries.every((entry) => entry.isFolder), isTrue);
      expect(entries.every((entry) => entry.size == null), isTrue);
      expect(
        entries.first,
        RemoteEntry(
          name: '3D',
          url: Uri.parse('${folder}3D/'),
          isFolder: true,
          modified: DateTime(2024, 1, 6, 17, 46),
        ),
      );
      expect(entries.map((entry) => entry.name), contains('Bangla (BD)'));
      expect(
        entries.last.url.toString(),
        '${folder}South%20Indian/',
      );
    });

    test('Apache table with a file and its size (ICC FTP)', () {
      const folder =
          'http://10.16.100.202/ftps10/iccftps10sasd9/Movies/3D/Animated/';

      final entries = _parse('apache_table_file.html', folder);

      expect(entries, [
        RemoteEntry(
          name: 'The LEGO Batman Movie (2017) 1080p 3D HSBS BluRay.mp4',
          url: Uri.parse(
            '${folder}The%20LEGO%20Batman%20Movie%20(2017)%201080p%203D%20'
            'HSBS%20BluRay.mp4',
          ),
          isFolder: false,
          size: 1717986918,
          modified: DateTime(2024, 1, 6, 17, 46),
        ),
      ]);
    });

    test('Apache 2.2 table with named months (Xplex)', () {
      final entries = _parse(
        'apache_table_named_months.html',
        'http://172.27.27.124/s1d1/',
      );

      final first = entries.first;
      expect(first.name, 'Hindi-2021');
      expect(first.modified, DateTime(2022, 8, 1, 15, 54));
      expect(entries.map((entry) => entry.name), contains('lost+found'));
      expect(entries.every((entry) => entry.isFolder), isTrue);
      expect(entries.every((entry) => entry.modified != null), isTrue);
    });

    test('IIS page with links only (ICC FTP)', () {
      const folder = 'http://10.16.100.241/ftps3d1/Documentary/English/';

      final entries = _parse('iis_links_only.html', folder);

      expect(entries, [
        RemoteEntry(
          name: 'Above Majestic (2018) 1080p WEBDL.mkv',
          url: Uri.parse(
            '${folder}Above%20Majestic%20(2018)%201080p%20WEBDL.mkv',
          ),
          isFolder: false,
        ),
        RemoteEntry(
          name: 'Gascoigne (2015) 720p BluRay.mp4',
          url: Uri.parse('${folder}Gascoigne%20(2015)%20720p%20BluRay.mp4'),
          isFolder: false,
        ),
        RemoteEntry(
          name: 'Ice on Fire (2019)',
          url: Uri.parse('${folder}Ice%20on%20Fire%20(2019)/'),
          isFolder: true,
        ),
        RemoteEntry(
          name: 'Never Again Is Now (2019)',
          url: Uri.parse('${folder}Never%20Again%20Is%20Now%20(2019)/'),
          isFolder: true,
        ),
      ]);
    });

    test('h5ai pages are readable too, through their plain table', () {
      final entries = _parse(
        'h5ai_root.html',
        'http://172.16.50.7/DHAKA-FLIX-7/',
      );

      expect(entries.map((entry) => entry.name), [
        '3D Movies',
        'English Movies',
        'Foreign Language Movies',
        'Kolkata Bangla Movies',
      ]);
    });
  });

  group('hand-written pages in documented formats', () {
    test('nginx autoindex', () {
      const folder =
          'http://10.0.0.7/media/Series/Harbor%20Lights/Season%2001/';

      final entries = _parse('nginx_autoindex.html', folder);

      expect(entries, [
        RemoteEntry(
          name: 'Extras',
          url: Uri.parse('${folder}Extras/'),
          isFolder: true,
          modified: DateTime(2024, 3, 4, 21, 17),
        ),
        RemoteEntry(
          name: 'Harbor.Lights.S01E01.1080p.WEB-DL.x264.mkv',
          url: Uri.parse('${folder}Harbor.Lights.S01E01.1080p.WEB-DL.x264.mkv'),
          isFolder: false,
          size: 1503238553,
          modified: DateTime(2024, 3, 4, 21, 9),
        ),
        RemoteEntry(
          name: 'Harbor.Lights.S01E01.srt',
          url: Uri.parse('${folder}Harbor.Lights.S01E01.srt'),
          isFolder: false,
          size: 48211,
          modified: DateTime(2024, 3, 4, 21, 9),
        ),
        RemoteEntry(
          name: 'Harbor.Lights.S01E02.1080p.WEB-DL.x264.mkv',
          url: Uri.parse('${folder}Harbor.Lights.S01E02.1080p.WEB-DL.x264.mkv'),
          isFolder: false,
          size: 1498765432,
          modified: DateTime(2024, 3, 11, 20, 58),
        ),
        RemoteEntry(
          name: 'বাংলা নাম.mp4',
          url: Uri.parse(
            '$folder%E0%A6%AC%E0%A6%BE%E0%A6%82%E0%A6%B2%E0%A6%BE%20'
            '%E0%A6%A8%E0%A6%BE%E0%A6%AE.mp4',
          ),
          isFolder: false,
          size: 73400320,
          modified: DateTime(2024, 3, 12, 8),
        ),
      ]);
    });

    test('IIS with dates and sizes before each link', () {
      const folder = 'http://10.0.0.5/Movies/';

      final entries = _parse('iis_with_details.html', folder);

      expect(entries, [
        RemoteEntry(
          name: 'Paper Kites (2021)',
          url: Uri.parse('${folder}Paper%20Kites%20(2021)/'),
          isFolder: true,
          modified: DateTime(2023, 1, 12, 10, 20),
        ),
        RemoteEntry(
          name: 'Quiet River (2019) 720p.mkv',
          url: Uri.parse('${folder}Quiet%20River%20(2019)%20720p.mkv'),
          isFolder: false,
          size: 2147483648,
          modified: DateTime(2024, 11, 3, 21, 5),
        ),
        RemoteEntry(
          name: 'web.config',
          url: Uri.parse('${folder}web.config'),
          isFolder: false,
          size: 168,
          modified: DateTime(2024, 12, 31),
        ),
      ]);
    });

    test('Apache without tables', () {
      const folder = 'http://10.0.0.9/anime/Glass%20Orchard/';

      final entries = _parse('apache_plain.html', folder);

      expect(entries, [
        RemoteEntry(
          name: 'Season 2',
          url: Uri.parse('${folder}Season%202/'),
          isFolder: true,
          modified: DateTime(2023, 5, 2, 9, 41),
        ),
        RemoteEntry(
          name: 'Glass.Orchard.E01.mkv',
          url: Uri.parse('${folder}Glass.Orchard.E01.mkv'),
          isFolder: false,
          size: 356 * 1024 * 1024,
          modified: DateTime(2023, 4, 11, 18, 30),
        ),
        RemoteEntry(
          name: 'Glass.Orchard.E01.ass',
          url: Uri.parse('${folder}Glass.Orchard.E01.ass'),
          isFolder: false,
          size: 41 * 1024,
          modified: DateTime(2023, 4, 11, 18, 30),
        ),
      ]);
    });
  });

  group('untrusted pages', () {
    final folder = Uri.parse('http://10.0.0.5/Movies/');

    test('an ordinary website is refused, not crawled', () {
      expect(
        () => _parse('not_a_listing.html', 'http://10.0.0.5/'),
        throwsA(isA<SourceReadException>()),
      );
      expect(
        isDirectoryListing(html.parse(fixture('listings/not_a_listing.html'))),
        isFalse,
      );
    });

    test('only links into the folder survive', () {
      const page = '''
<html><head><title>Index of /Movies/</title></head><body><pre>
<a href="../">../</a>
<a href="good.mkv">good.mkv</a>
<a href="good.mkv">good.mkv again</a>
<a href="http://evil.example/Movies/steal.mkv">steal.mkv</a>
<a href="file:///C:/Windows/win.ini">win.ini</a>
<a href="..%2F..%2Fsecret.mkv">secret.mkv</a>
<a href="/Other/far.mkv">far.mkv</a>
<a href="javascript:alert(1)">click</a>
<a>no href</a>
</pre></body></html>''';

      final entries = parseDirectoryListing(page, folder);

      expect(entries.map((entry) => entry.url.toString()), [
        'http://10.0.0.5/Movies/good.mkv',
      ]);
    });

    test('markup in a name stays text', () {
      const page = '<title>Index of /Movies/</title>'
          '<a href="%3Cscript%3Ealert(1)%3C%2Fscript%3E.mkv">x</a>';

      // "%2F" hides a slash, so this one is dropped altogether...
      expect(parseDirectoryListing(page, folder), isEmpty);

      // ...and without it the name is kept as plain characters.
      const harmless = '<title>Index of /Movies/</title>'
          '<a href="%3Cb%3Ebold%3Cb%3E.mkv">x</a>';
      expect(
        parseDirectoryListing(harmless, folder).single.name,
        '<b>bold<b>.mkv',
      );
    });

    test('a huge folder is cut off at the entry limit', () {
      final page = StringBuffer('<title>Index of /Movies/</title><pre>');
      for (var i = 0; i < maxEntriesPerFolder + 50; i++) {
        page.write('<a href="f$i.mkv">f$i.mkv</a> 04-Mar-2024 21:09 1\n');
      }
      page.write('</pre>');

      final entries = parseDirectoryListing(page.toString(), folder);

      expect(entries, hasLength(maxEntriesPerFolder));
      expect(entries.last.size, 1);
    });
  });

  group('over HTTP', () {
    late LocalServer server;
    late SafeHttpClient client;
    late DirectoryListingAdapter adapter;

    setUp(() async {
      server = await LocalServer.start();
      client = server.client();
      adapter = DirectoryListingAdapter(client);
    });

    tearDown(() async {
      client.close();
      await server.close();
    });

    test('lists a folder and can go one level deeper', () async {
      server
        ..serve('/s1d1/', fixture('listings/apache_table_named_months.html'))
        ..serve('/s1d1/Hindi-2021/', fixture('listings/nginx_autoindex.html'));

      final root = await adapter.list(server.url('/s1d1/'));
      final deeper = await adapter.list(root.first.url);

      expect(root.first.url, server.url('/s1d1/Hindi-2021/'));
      expect(deeper, hasLength(5));
      expect(deeper[1].url.path, startsWith('/s1d1/Hindi-2021/Harbor.Lights'));
    });

    test('follows the usual redirect to the folder with a slash', () async {
      server
        ..redirect('/s1d1', '/s1d1/')
        ..serve('/s1d1/', fixture('listings/apache_table_named_months.html'));

      final entries = await adapter.list(server.url('/s1d1'));

      expect(entries.first.url, server.url('/s1d1/Hindi-2021/'));
    });

    test('refuses a redirect to some other page', () async {
      server
        ..redirect('/s1d1/', '/login/')
        ..serve('/login/', fixture('listings/apache_table_named_months.html'));

      await expectLater(
        adapter.list(server.url('/s1d1/')),
        throwsA(isA<SourceReadException>()),
      );
    });

    test('reports an error status', () async {
      server.serve('/secret/', 'Forbidden', status: 403);

      await expectLater(
        adapter.list(server.url('/secret/')),
        throwsA(
          isA<SourceReadException>()
              .having((e) => e.message, 'message', contains('403')),
        ),
      );
    });

    test('lets network failures through as SafeHttpException', () async {
      final url = server.url('/s1d1/');
      await server.close();

      await expectLater(adapter.list(url), throwsA(isA<SafeHttpException>()));
    });
  });
}
