// Runs against the front page of FTPmedia (`http://10.1.1.1/`), saved
// unchanged on 2026-11-16: see test/fixtures/listings/README.md.
import 'package:dhara/features/sources/portal_links.dart';
import 'package:dhara/features/sources/source.dart';
import 'package:dhara/features/sources/source_tester.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;

import '../../support/local_server.dart';

List<PortalLink> _links(String page, {String from = 'http://10.1.1.1/'}) =>
    portalLinks(html.parse(page), Uri.parse(from));

Source _source(String id, String url, {String? portal}) => Source(
  id: id,
  name: 'Server $id',
  type: SourceType.h5ai,
  category: SourceCategory.movies,
  baseUrls: [Uri.parse(url)],
  portalUrl: portal == null ? null : Uri.parse(portal),
);

void main() {
  test('a real front page: the servers it points to, by what it calls '
      'them', () {
    final links = _links(fixture('listings/ftpmedia_portal.html'));

    expect(links, [
      PortalLink(Uri.parse('http://10.50.50.51/'), 'Media Live Movies'),
      // Written "http://172.16.50.4//" on the page.
      PortalLink(Uri.parse('http://172.16.50.4/'), 'Download'),
      PortalLink(Uri.parse('http://172.16.15.5/'), 'Streming LIVE.....'),
      PortalLink(Uri.parse('http://172.16.14.3/'), 'LIVE'),
      PortalLink(Uri.parse('http://172.16.14.1/'), 'OTT Live.....'),
    ]);
    // Its link to itself is no other server.
    expect(links.map((link) => link.url.host), isNot(contains('10.1.1.1')));
  });

  test('only web addresses on other hosts count, once per host', () {
    final links = _links('''
      <a href="/movies/">Here</a>
      <a href="movies.html">Here too</a>
      <a href="http://10.1.1.1/tv/">Same host</a>
      <a href="HTTP://Media.Example.Net/Films">Films</a>
      <a href="http://media.example.net/series/">Series, same host</a>
      <a href="http://media.example.net:8096/">Another port</a>
      <a href="https://files.example.net/index.php?dir=a#top">Files</a>
      <a href="ftp://files.example.org/">FTP</a>
      <a href="file:///C:/Windows/win.ini">File</a>
      <a href="javascript:alert(1)">Script</a>
      <a href="http://user:pw@secret.example.net/">With a password</a>
      <a href="mailto:someone@example.net">Mail</a>
      <a href="http://">Nothing</a>
      <a>No address</a>
    ''');

    expect(links, [
      PortalLink(Uri.parse('http://media.example.net/Films/'), 'Films'),
      PortalLink(Uri.parse('http://media.example.net:8096/'), 'Another port'),
      PortalLink(Uri.parse('https://files.example.net/index.php'), 'Files'),
    ]);
  });

  test('a link goes by its text, its picture, or its host', () {
    final links = _links('''
      <a href="http://a.example.net/">  Two
         lines  </a>
      <a href="http://b.example.net/"><img src="b.jpg" alt="Live TV"></a>
      <a href="http://c.example.net/"><img src="c.jpg"></a>
      <a href="http://d.example.net/">${'x' * 80}</a>
      <a href="http://e.example.net/">A\u0007bell</a>
    ''');

    expect(links.map((link) => link.label), [
      'Two lines',
      'Live TV',
      'c.example.net',
      'x' * 50,
      'A bell',
    ]);
  });

  test('a page of a hundred links gives the first dozen', () {
    final page = [
      for (var i = 0; i < 100; i++) '<a href="http://h$i.example.net/">$i</a>',
    ].join();

    expect(_links(page), hasLength(12));
    expect(_links(page, from: 'http://h0.example.net/').first.label, '1');
  });

  test('a link leads to the sources on its host, and to those whose front '
      'page it is', () {
    final sources = [
      _source('flix7', 'http://172.16.50.7/F7/', portal: 'http://172.16.50.4/'),
      _source(
        'flix12',
        'http://172.16.50.12/F12/',
        portal: 'http://172.16.50.4/',
      ),
      _source('movies', 'http://10.50.50.51/movies/'),
      _source('other', 'http://10.9.9.9/'),
    ];
    PortalLink to(String url) => PortalLink(Uri.parse(url), 'x');

    expect(sourcesBehind(to('http://172.16.50.4/'), sources).map((s) => s.id), [
      'flix7',
      'flix12',
    ]);
    expect(sourcesBehind(to('http://10.50.50.51/'), sources).map((s) => s.id), [
      'movies',
    ]);
    expect(sourcesBehind(to('http://172.16.14.1/'), sources), isEmpty);
  });

  test('the tester names the servers a website links to, and asks none of '
      'them', () async {
    final server = await LocalServer.start();
    addTearDown(server.close);
    server.serve('/', fixture('listings/ftpmedia_portal.html'));
    final portal = Source(
      id: 'ftpmedia',
      name: 'FTPmedia',
      type: SourceType.customSite,
      category: SourceCategory.mixed,
      baseUrls: [server.url('/')],
    );

    final result = await SourceTester(
      deviceId: 'dhara-test',
    ).testAll([portal]).single;
    final url = result.urls.single;

    expect(url.reachable, isTrue);
    expect(url.detectedType, SourceType.customSite);
    expect(url.readable, isFalse);
    // (Its title goes on in Bangla.)
    expect(url.sample.single, startsWith('FTPmedia.net | '));
    // From 127.0.0.1 the page's link to 10.1.1.1 is another host as well.
    expect(url.links.map((link) => link.url.host), [
      '10.1.1.1',
      '10.50.50.51',
      '172.16.50.4',
      '172.16.15.5',
      '172.16.14.3',
      '172.16.14.1',
    ]);
    // Only the tested server itself was asked (its page, and whether it is
    // a media server).
    expect(server.requests.map((request) => request.headers.host).toSet(), {
      '127.0.0.1',
    });
  });

  test('a server that lists files has no such links', () async {
    final server = await LocalServer.start();
    addTearDown(server.close);
    server.serve('/', fixture('listings/h5ai_root.html'));
    final source = _source('h5ai', '${server.url('/')}');

    final result = await SourceTester(
      deviceId: 'dhara-test',
    ).testAll([source]).single;

    expect(result.urls.single.detectedType, SourceType.h5ai);
    expect(result.urls.single.links, isEmpty);
  });
}
