import 'package:dhara/core/net/safe_http_client.dart';
import 'package:dhara/features/sources/adapters/h5ai_adapter.dart';
import 'package:dhara/features/sources/adapters/source_adapter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;

import '../../../support/local_server.dart';

List<RemoteEntry> _parse(String file, String folder) =>
    parseH5aiListing(fixture('listings/$file'), Uri.parse(folder));

void main() {
  group('real pages', () {
    test('DhakaFlix 7 root: folders with dates', () {
      const folder = 'http://172.16.50.7/DHAKA-FLIX-7/';

      final entries = _parse('h5ai_root.html', folder);

      expect(entries, [
        RemoteEntry(
          name: '3D Movies',
          url: Uri.parse('${folder}3D%20Movies/'),
          isFolder: true,
          modified: DateTime(2022, 8, 27, 13, 3),
        ),
        RemoteEntry(
          name: 'English Movies',
          url: Uri.parse('${folder}English%20Movies/'),
          isFolder: true,
          modified: DateTime(2026, 1, 13, 0, 19),
        ),
        RemoteEntry(
          name: 'Foreign Language Movies',
          url: Uri.parse('${folder}Foreign%20Language%20Movies/'),
          isFolder: true,
          modified: DateTime(2022, 8, 27, 13, 4),
        ),
        RemoteEntry(
          name: 'Kolkata Bangla Movies',
          url: Uri.parse('${folder}Kolkata%20Bangla%20Movies/'),
          isFolder: true,
          modified: DateTime(2024, 4, 17, 21, 30),
        ),
      ]);
    });

    test('DhakaFlix 7 movie folder: files with sizes', () {
      const folder = 'http://172.16.50.7/DHAKA-FLIX-7/3D%20Movies/'
          '300-Rise%20of%20an%20Empire%20%282014%29%201080p%20%5B3D%5D/';

      final entries = _parse('h5ai_files.html', folder);

      expect(entries, [
        RemoteEntry(
          name: '300.Rise.of.an.Empire.2014.1080p.3D.HSBS.BluRay.x264.YIFY.mp4',
          url: Uri.parse(
            '${folder}300.Rise.of.an.Empire.2014.1080p.3D.HSBS.BluRay.x264.'
            'YIFY.mp4',
          ),
          isFolder: false,
          size: 1762038 * 1024,
          modified: DateTime(2019, 8, 29, 18, 11),
        ),
        RemoteEntry(
          name: 'a14a.jpg',
          url: Uri.parse('${folder}a14a.jpg'),
          isFolder: false,
          size: 88 * 1024,
          modified: DateTime(2019, 8, 29, 18, 11),
        ),
      ]);
    });

    test('CircleFTP (h5ai 0.29.2): a name with "&"', () {
      const folder = 'http://index2.circleftp.net/FILE/';

      final entries = _parse('h5ai_0_29_2.html', folder);

      expect(entries.map((entry) => entry.name), [
        'English & Foreign Dubbed Movies',
        'English Movies',
      ]);
      expect(
        entries.first.url.toString(),
        '${folder}English%20%26%20Foreign%20Dubbed%20Movies/',
      );
    });

    test('are recognised as h5ai even when the footer is re-branded', () {
      for (final file in ['h5ai_root.html', 'h5ai_0_29_2.html']) {
        expect(isH5ai(html.parse(fixture('listings/$file'))), isTrue);
      }
    });
  });

  group('untrusted pages', () {
    final folder = Uri.parse('http://10.0.0.5/files/');

    test('pages that are not h5ai are refused', () {
      for (final file in [
        'apache_table_folders.html',
        'nginx_autoindex.html',
        'iis_links_only.html',
        'not_a_listing.html',
      ]) {
        expect(isH5ai(html.parse(fixture('listings/$file'))), isFalse);
        expect(
          () => parseH5aiListing(fixture('listings/$file'), folder),
          throwsA(isA<SourceReadException>()),
          reason: file,
        );
      }
    });

    test('an h5ai page without the plain table is reported', () {
      const page = '<title>index - powered by h5ai v0.30.0</title>'
          '<script src="/_h5ai/public/js/scripts.js"></script>'
          '<body id="root"></body>';

      expect(
        () => parseH5aiListing(page, folder),
        throwsA(
          isA<SourceReadException>()
              .having((e) => e.message, 'message', contains('plain file')),
        ),
      );
    });

    test('only links in the table, and only into the folder, count', () {
      const page = '''
<title>index - powered by h5ai v0.29.0</title>
<a href="outside-table.mkv">outside-table.mkv</a>
<div id="fallback"><table>
<tr><td class="fb-n"><a href="..">Parent Directory</a></td><td class="fb-d"></td><td class="fb-s"></td></tr>
<tr><td class="fb-n"><a href="/files/good.mkv">good.mkv</a></td><td class="fb-d">2024-01-06 17:46</td><td class="fb-s">2048 KB</td></tr>
<tr><td class="fb-n"><a href="/elsewhere/far.mkv">far.mkv</a></td><td class="fb-d"></td><td class="fb-s">1 KB</td></tr>
<tr><td class="fb-n"><a href="http://evil.example/files/steal.mkv">steal.mkv</a></td><td class="fb-d"></td><td class="fb-s">1 KB</td></tr>
<tr><td class="fb-i"><a href="/files/in-icon-cell.mkv">x</a></td></tr>
</table></div>''';

      final entries = parseH5aiListing(page, folder);

      expect(entries, [
        RemoteEntry(
          name: 'good.mkv',
          url: Uri.parse('http://10.0.0.5/files/good.mkv'),
          isFolder: false,
          size: 2048 * 1024,
          modified: DateTime(2024, 1, 6, 17, 46),
        ),
      ]);
    });
  });

  group('over HTTP', () {
    late LocalServer server;
    late SafeHttpClient client;

    setUp(() async {
      server = await LocalServer.start();
      client = server.client();
    });

    tearDown(() async {
      client.close();
      await server.close();
    });

    test('lists the root, then a folder from it', () async {
      server
        ..serve('/DHAKA-FLIX-7/', fixture('listings/h5ai_root.html'))
        ..serve(
          '/DHAKA-FLIX-7/3D%20Movies/',
          fixture('listings/h5ai_0_29_2.html'),
        );
      final adapter = H5aiAdapter(client);

      final root = await adapter.list(server.url('/DHAKA-FLIX-7/'));

      expect(root.first.url, server.url('/DHAKA-FLIX-7/3D%20Movies/'));
      // The second page belongs to another folder ("/FILE/"), so none of
      // its links is inside the folder that was asked for.
      expect(await adapter.list(root.first.url), isEmpty);
    });

    test('reports an error status', () async {
      final adapter = H5aiAdapter(client);

      await expectLater(
        adapter.list(server.url('/gone/')),
        throwsA(
          isA<SourceReadException>()
              .having((e) => e.message, 'message', contains('404')),
        ),
      );
    });
  });
}
