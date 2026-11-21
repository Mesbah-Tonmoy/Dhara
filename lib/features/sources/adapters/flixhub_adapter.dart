import 'dart:convert';

import 'package:dhara/core/net/safe_http_client.dart';
import 'package:dhara/features/sources/adapters/source_adapter.dart';
import 'package:html/dom.dart';
import 'package:html/parser.dart' as html;

/// Whether [document] is a page of a FlixHub site: its navigation bar is
/// on every page.
bool isFlixHub(Document document) =>
    document.getElementById('flixhubNavbar') != null;

/// Reads FlixHub (flixhub.net), a website of its own kind: films and shows
/// as cards on pages, every video one address of the site.
///
/// The site has no folders, so the adapter makes them up:
///
/// - the base URL holds "Movies" and "TV Shows";
/// - "Movies" (`/movies`) holds every film as one file. The site hands its
///   list out a page at a time, as JSON with a piece of HTML in it
///   (`/movies?page=N`, what its own "Load more" asks for); the adapter
///   reads the pages one after another;
/// - "TV Shows" (`/tv-shows`) holds a folder for each show, and a show's
///   page (`/watch/series/<name>`) every episode as one file.
///
/// Nothing on a page says where to fetch from. Of a card only the name in
/// its link is used (`perfect-liars`), and only if it is letters, digits
/// and dashes; the addresses of the video (`/stream/movie/<name>`,
/// `/stream/episode/<name>`) and of a show's page are put together here,
/// on the site the source names. So a page cannot send the app elsewhere.
///
/// A file gets a name of the kind a file server would have, for the
/// library to read: "Perfect Liars (2026) 1080p.mp4", "Reacher S01E02
/// First Dance.mkv". The site does not say what kind of file a video is
/// until it is fetched (both mp4 and mkv were seen), so the endings are a
/// guess; the player does not go by them.
class FlixHubAdapter implements SourceAdapter {
  FlixHubAdapter(this._client, {required Uri baseUrl})
    : _root = baseUrl.resolve('/');

  /// The most pages of the film list one reading follows (the site had 68
  /// on 2026-11-21).
  static const maxPages = 400;

  final SafeHttpClient _client;
  final Uri _root;

  @override
  Future<List<RemoteEntry>> list(Uri folder) async {
    if (folder.host != _root.host || folder.port != _root.port) {
      throw const SourceReadException('This is not a folder of the site.');
    }
    return switch (folder.pathSegments.where((s) => s.isNotEmpty).toList()) {
      [] => [
        RemoteEntry(
          name: 'Movies',
          url: _root.resolve('movies'),
          isFolder: true,
        ),
        RemoteEntry(
          name: 'TV Shows',
          url: _root.resolve('tv-shows'),
          isFolder: true,
        ),
      ],
      ['movies'] => await _films(),
      ['tv-shows'] => await _shows(),
      ['watch', 'series', final name] when _name.hasMatch(name) =>
        await _episodes(name),
      _ => throw const SourceReadException('This is not a folder of the site.'),
    };
  }

  Future<List<RemoteEntry>> _films() async {
    final films = <RemoteEntry>[];
    final seen = <String>{};
    for (var page = 1; page <= maxPages; page++) {
      final response = await _get(
        _root.replace(path: '/movies', queryParameters: {'page': '$page'}),
        // What the site's own script sends, to get the list and not the
        // whole page around it.
        headers: const {
          'X-Requested-With': 'XMLHttpRequest',
          'Accept': 'application/json',
        },
      );
      final Object? answer;
      try {
        answer = jsonDecode(response.body);
      } on FormatException {
        throw const SourceReadException('The list of films is not readable.');
      }
      final cards = answer is Map<String, dynamic> ? answer['html'] : null;
      if (answer is! Map<String, dynamic> || cards is! String) {
        throw const SourceReadException('The list of films is not readable.');
      }
      for (final card
          in html
              .parseFragment(cards)
              .querySelectorAll('article[data-card-type="movie"]')) {
        final name = _nameIn(card, 'movie');
        final title = _titleOf(card);
        if (name == null || title == null || !seen.add(name)) continue;
        final year = _yearOf(card);
        final sharp =
            _heights[card.querySelector('.badge-quality')?.text.trim()];
        films.add(
          RemoteEntry(
            name:
                '$title${year == null ? '' : ' ($year)'}'
                '${sharp == null ? '' : ' ${sharp}p'}.mp4',
            url: _root.resolve('stream/movie/$name'),
            isFolder: false,
          ),
        );
        if (films.length >= maxEntriesPerFolder) return films;
      }
      // The site says which page comes next; anything else ends the list.
      if (answer['has_more'] != true || answer['next_page'] != page + 1) break;
    }
    return films;
  }

  Future<List<RemoteEntry>> _shows() async {
    final page = html.parse((await _get(_root.resolve('tv-shows'))).body);
    final shows = <RemoteEntry>[];
    final seen = <String>{};
    for (final card in page.querySelectorAll(
      'article[data-card-type="series"]',
    )) {
      final name = _nameIn(card, 'series');
      final title = _titleOf(card);
      if (name == null || title == null || !seen.add(name)) continue;
      final year = _yearOf(card);
      shows.add(
        RemoteEntry(
          // "Name (Year)" is how a show's folder is usually named on disk.
          name: '$title${year == null ? '' : ' ($year)'}',
          url: _root.resolve('watch/series/$name'),
          isFolder: true,
        ),
      );
      if (shows.length >= maxEntriesPerFolder) break;
    }
    return shows;
  }

  Future<List<RemoteEntry>> _episodes(String show) async {
    final page = html.parse(
      (await _get(_root.resolve('watch/series/$show'))).body,
    );
    final heading = page.querySelector('h1.movie-title')?.text ?? '';
    final title = _clean(heading).isEmpty ? show : _clean(heading);
    final episodes = <RemoteEntry>[];
    final seen = <String>{};
    for (final card in page.querySelectorAll(
      'article.player-sidebar-card[data-season-number]',
    )) {
      final name = _nameIn(card, 'episode');
      final season = int.tryParse(card.attributes['data-season-number'] ?? '');
      if (name == null || season == null || season < 0 || season > 999) {
        continue;
      }
      // "E2 — First Dance".
      final label = _clean(
        card.querySelector('.player-sidebar-card-title')?.text ?? '',
      );
      final numbered = _episodeLabel.firstMatch(label);
      if (numbered == null || !seen.add(name)) continue;
      final number = numbered[1]!.padLeft(2, '0');
      final called = numbered[2]!.trim();
      episodes.add(
        RemoteEntry(
          name:
              '$title S${'$season'.padLeft(2, '0')}E$number'
              '${called.isEmpty ? '' : ' $called'}.mkv',
          url: _root.resolve('stream/episode/$name'),
          isFolder: false,
        ),
      );
      if (episodes.length >= maxEntriesPerFolder) break;
    }
    return episodes;
  }

  /// A page of the site itself: a redirect to another host is refused by
  /// the client, and one to another page of the site (the sign-in page,
  /// say) is not the page that was asked for.
  Future<SafeHttpResponse> _get(
    Uri url, {
    Map<String, String> headers = const {},
  }) async {
    final response = await _client.get(
      url,
      headers: headers,
      maxBytes: maxListingBytes,
    );
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
    return response;
  }

  /// The name a card's link gives a film, show or episode
  /// (`/watch/<kind>/<name>`), if it is one the adapter will use.
  static String? _nameIn(Element card, String kind) {
    for (final link in [
      card.attributes['data-watch-url'],
      for (final anchor in card.querySelectorAll('a[href]'))
        anchor.attributes['href'],
    ]) {
      final url = link == null ? null : Uri.tryParse(link);
      if (url == null) continue;
      final parts = url.pathSegments;
      if (parts.length == 3 &&
          parts[0] == 'watch' &&
          parts[1] == kind &&
          _name.hasMatch(parts[2])) {
        return parts[2];
      }
    }
    return null;
  }

  static String? _titleOf(Element card) {
    final title = _clean(
      card.querySelector('a[aria-label]')?.attributes['aria-label'] ??
          card.querySelector('.movie-title')?.text ??
          '',
    );
    return title.isEmpty ? null : title;
  }

  static int? _yearOf(Element card) {
    for (final text in [
      card.parent?.attributes['data-year'],
      for (final part in card.querySelectorAll('.movie-card-meta span'))
        part.text,
    ]) {
      final year = int.tryParse(text?.trim() ?? '');
      if (year != null && year >= 1880 && year <= 2200) return year;
    }
    return null;
  }

  /// Text of the site made safe to be part of a file name: one line, not
  /// too long, and without the signs that part folders.
  static String _clean(String text) => cleanServerText(
    text.replaceAll(_pathSigns, ' ').replaceAll(_spaces, ' '),
    150,
  );

  static final _name = RegExp(r'^[a-z0-9][a-z0-9-]{0,149}$');
  static final _episodeLabel = RegExp(r'^E(\d{1,4})\b\s*[—–-]?\s*(.*)$');
  static final _pathSigns = RegExp(r'[/\\]');
  static final _spaces = RegExp(r'\s+');

  /// What the site's badge on a film says of its picture.
  static const _heights = {'4K': 2160, 'FHD': 1080, 'HD': 720, 'SD': 480};
}
