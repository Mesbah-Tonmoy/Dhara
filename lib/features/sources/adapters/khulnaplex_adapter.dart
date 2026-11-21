import 'package:dhara/core/net/safe_http_client.dart';
import 'package:dhara/features/indexer/media_files.dart';
import 'package:dhara/features/sources/adapters/source_adapter.dart';
import 'package:html/dom.dart';
import 'package:html/parser.dart' as html;

/// Whether [document] is a page of a Khulnaplex site: its menu leads to
/// `movies.php` and `series.php`, and it runs the site's one script.
bool isKhulnaplex(Document document) =>
    document.querySelector('a[href="movies.php"]') != null &&
    document.querySelector('a[href="series.php"]') != null &&
    document.querySelector('script[src^="assets/js/script.js"]') != null;

/// Reads Khulnaplex (khulnaplex.net), a website of its own kind: films and
/// shows as cards on numbered pages, and a page for every film and every
/// episode that names the one video file it plays.
///
/// The site has no folders, so the adapter makes them up:
///
/// - the base URL holds "Movies" (`movies.php`) and "TV Shows"
///   (`series.php`);
/// - each of the two holds a folder for every card of every page of its
///   list (`?page=N`): a film ("Ghaati (2025)", `watch.php?id=13&type=movie`)
///   or a show (`watch.php?id=1&type=series`);
/// - a film's folder holds its one file. A show's folder holds a folder
///   for each episode ("S01E02"), and that the episode's one file.
///
/// A video's address is the only thing taken from a page, and only if it
/// lies on the site itself and ends like a video; everything else (a
/// film's number, a season, an episode) is a number the adapter puts into
/// an address of its own making.
///
/// Every film and every episode costs a request, which the site's folders
/// (they cannot be listed) would have saved. A film's page does not change,
/// so a film's and an episode's folder carry one fixed date: the crawler
/// then reads each only once, and again on a full crawl. A show's folder
/// carries none and is read every time, for new episodes.
///
/// A file is named for the library to read, from what its page says: "Ghaati
/// (2025) 1080p.mkv", "Genie, Make a Wish (2025) S01E02 1080p.mp4". The picture
/// size and the ending are those of the real file.
class KhulnaplexAdapter implements SourceAdapter {
  KhulnaplexAdapter(this._client, {required Uri baseUrl}) : _root = baseUrl;

  /// The most pages of a list one reading follows (the films had 63 on
  /// 2026-11-21).
  static const maxPages = 400;

  /// The date of a folder that never changes; see the class comment.
  static final unchanging = DateTime(2000);

  final SafeHttpClient _client;
  final Uri _root;

  @override
  Future<List<RemoteEntry>> list(Uri folder) async {
    if (folder.host != _root.host || folder.port != _root.port) {
      throw const SourceReadException('This is not a folder of the site.');
    }
    if (folder == _root) {
      return [
        RemoteEntry(name: 'Movies', url: _page('movies.php'), isFolder: true),
        RemoteEntry(name: 'TV Shows', url: _page('series.php'), isFolder: true),
      ];
    }
    if (folder == _page('movies.php')) return _titles('movies.php', 'movie');
    if (folder == _page('series.php')) return _titles('series.php', 'series');

    final asked = folder.queryParameters;
    final id = _number(asked['id'], 999999999);
    if (folder.path == _page('watch.php').path && id != null) {
      final season = _number(asked['season'], 999);
      final episode = _number(asked['episode'], 9999);
      if (folder == _watch(id, 'movie')) return _film(id);
      if (folder == _watch(id, 'series')) return _show(id);
      if (season != null &&
          episode != null &&
          folder == _watch(id, 'series', season, episode)) {
        return _episode(id, season, episode);
      }
    }
    throw const SourceReadException('This is not a folder of the site.');
  }

  /// Every card of every page of the list on [file], as a folder.
  Future<List<RemoteEntry>> _titles(String file, String kind) async {
    final opens = kind == 'movie' ? 'openMovie' : 'openSeries';
    final titles = <RemoteEntry>[];
    final seen = <int>{};
    for (var page = 1; page <= maxPages; page++) {
      final document = await _get(
        _page(file).replace(queryParameters: {'page': '$page'}),
      );
      var fresh = 0;
      for (final card in document.querySelectorAll('.movie-card[onclick]')) {
        // "openMovie(1357)".
        final call = _opens.firstMatch(card.attributes['onclick']!.trim());
        final id = call == null || call[1] != opens
            ? null
            : int.parse(call[2]!);
        final title = _clean(card.querySelector('h3')?.text ?? '');
        if (id == null || title.isEmpty || !seen.add(id)) continue;
        fresh++;
        final year = _year(card.querySelector('.year')?.text);
        titles.add(
          RemoteEntry(
            // "Name (Year)" is how a film's or a show's folder is usually
            // named on disk.
            name: '$title${year == null ? '' : ' ($year)'}',
            url: _watch(id, kind),
            isFolder: true,
            modified: kind == 'movie' ? unchanging : null,
          ),
        );
        if (titles.length >= maxEntriesPerFolder) return titles;
      }
      // Past its last page the site shows no cards, or the same again.
      if (fresh == 0) break;
    }
    return titles;
  }

  Future<List<RemoteEntry>> _film(int id) async {
    final document = await _get(_watch(id, 'movie'));
    final video = _videoOf(document);
    final title = _titleOf(document);
    if (video == null || title == null) return const [];
    final year = _year(
      document.querySelector('.video-meta .fa-calendar')?.parent?.text,
    );
    return [
      RemoteEntry(
        name:
            '$title${year == null ? '' : ' ($year)'}'
            '${_sharpness(video)}.${_ending(video)}',
        url: video,
        isFolder: false,
      ),
    ];
  }

  /// A folder for every episode the show's page links to.
  Future<List<RemoteEntry>> _show(int id) async {
    final document = await _get(_watch(id, 'series'));
    final episodes = <RemoteEntry>[];
    final seen = <(int, int)>{};
    for (final link in document.querySelectorAll(
      '.episode-item a.play-episode-btn[href]',
    )) {
      final asked = Uri.tryParse(link.attributes['href']!)?.queryParameters;
      if (asked == null || asked['type'] != 'series') continue;
      if (_number(asked['id'], 999999999) != id) continue;
      final season = _number(asked['season'], 999);
      final episode = _number(asked['episode'], 9999);
      if (season == null || episode == null) continue;
      if (!seen.add((season, episode))) continue;
      episodes.add(
        RemoteEntry(
          name: _numbered(season, episode),
          url: _watch(id, 'series', season, episode),
          isFolder: true,
          modified: unchanging,
        ),
      );
      if (episodes.length >= maxEntriesPerFolder) break;
    }
    return episodes;
  }

  Future<List<RemoteEntry>> _episode(int id, int season, int episode) async {
    final document = await _get(_watch(id, 'series', season, episode));
    final video = _videoOf(document);
    final title = _titleOf(document);
    if (video == null || title == null) return const [];
    // "Season 1, Episode 2": asked for an episode it does not have, the
    // site may show another one.
    final shown = _shownEpisode.firstMatch(
      document.querySelector('.video-meta .fa-tv')?.parent?.text ?? '',
    );
    if (shown != null &&
        (int.parse(shown[1]!) != season || int.parse(shown[2]!) != episode)) {
      return const [];
    }
    final year = _year(
      document.querySelector('.video-meta .fa-calendar')?.parent?.text,
    );
    return [
      RemoteEntry(
        name:
            '$title${year == null ? '' : ' ($year)'} '
            '${_numbered(season, episode)}'
            '${_sharpness(video)}.${_ending(video)}',
        url: video,
        isFolder: false,
      ),
    ];
  }

  /// A page of the site, parsed. A redirect to another host is refused by
  /// the client, and one to another page of the site (the front page, for
  /// a film that is gone) is not the page that was asked for.
  Future<Document> _get(Uri url) async {
    final response = await _client.get(url, maxBytes: maxListingBytes);
    if (!response.isOk) {
      throw SourceReadException(
        'The server answered ${response.statusCode}.',
        statusCode: response.statusCode,
      );
    }
    if (response.url.host != url.host || response.url.path != url.path) {
      throw const SourceReadException(
        'The server sent a different page than the one asked for.',
      );
    }
    return html.parse(response.body);
  }

  /// Where the video of a film's or an episode's page lies, if the page
  /// names one that may be used: a file of this site, of a kind the player
  /// opens, named plainly (no query, no way up out of a folder).
  Uri? _videoOf(Document document) {
    for (final source in document.querySelectorAll('video source[src]')) {
      final Uri url;
      try {
        url = _page('watch.php').resolve(source.attributes['src']!.trim());
      } on FormatException {
        continue;
      }
      if (url.scheme != _root.scheme ||
          url.host != _root.host ||
          url.port != _root.port ||
          url.userInfo.isNotEmpty ||
          url.hasQuery ||
          url.hasFragment) {
        continue;
      }
      final List<String> parts;
      try {
        parts = url.pathSegments;
      } on FormatException {
        continue;
      }
      if (parts.isEmpty || parts.any((part) => part == '..' || part == '.')) {
        continue;
      }
      if (mediaKindOf(parts.last) != MediaKind.video) continue;
      return url;
    }
    return null;
  }

  Uri _page(String file) => _root.resolve(file);

  Uri _watch(int id, String kind, [int? season, int? episode]) =>
      _page('watch.php').replace(
        queryParameters: {
          'id': '$id',
          'type': kind,
          if (season != null) 'season': '$season',
          if (episode != null) 'episode': '$episode',
        },
      );

  static String? _titleOf(Document document) {
    final title = _clean(document.querySelector('.video-info h1')?.text ?? '');
    return title.isEmpty ? null : title;
  }

  /// " 1080p" if the name of the file at [video] says so, or nothing.
  static String _sharpness(Uri video) {
    final height = _height.firstMatch(video.pathSegments.last)?[1];
    return height == null ? '' : ' ${height}p';
  }

  static String _ending(Uri video) {
    final name = video.pathSegments.last;
    return name.substring(name.lastIndexOf('.') + 1).toLowerCase();
  }

  static String _numbered(int season, int episode) =>
      'S${'$season'.padLeft(2, '0')}E${'$episode'.padLeft(2, '0')}';

  /// [text] as a whole number from 0 to [max], written plainly.
  static int? _number(String? text, int max) {
    if (text == null || !_digits.hasMatch(text)) return null;
    final number = int.parse(text);
    return number <= max ? number : null;
  }

  static int? _year(String? text) {
    final year = int.tryParse(text?.trim() ?? '');
    return year != null && year >= 1880 && year <= 2200 ? year : null;
  }

  /// Text of the site made safe to be part of a file name: one line, not
  /// too long, and without the signs that part folders.
  static String _clean(String text) => cleanServerText(
    text.replaceAll(_pathSigns, ' ').replaceAll(_spaces, ' '),
    150,
  );

  static final _opens = RegExp(r'^(openMovie|openSeries)\((\d{1,9})\);?$');
  static final _digits = RegExp(r'^\d{1,9}$');
  static final _height = RegExp(r'(2160|1440|1080|720|576|480|360)[pP]');
  static final _shownEpisode = RegExp(
    r'Season\s+(\d{1,3}),\s*Episode\s+(\d{1,4})',
  );
  static final _pathSigns = RegExp(r'[/\\]');
  static final _spaces = RegExp(r'\s+');
}
