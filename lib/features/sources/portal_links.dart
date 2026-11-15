import 'package:dhara/core/net/media_url.dart';
import 'package:dhara/features/sources/adapters/source_adapter.dart';
import 'package:dhara/features/sources/source.dart';
import 'package:flutter/foundation.dart';
import 'package:html/dom.dart';

/// A link on a web page that leads to another server.
///
/// Both parts are server-controlled text: shown as plain text only, and
/// the address is never asked for unless the user makes it a source.
@immutable
class PortalLink {
  const PortalLink(this.url, this.label);

  /// Where it leads, tidied: no query, no fragment, a path that ends in
  /// "/" where it names a folder.
  final Uri url;

  /// What the page calls it ("Media Live Movies"), or its host.
  final String label;

  @override
  bool operator ==(Object other) =>
      other is PortalLink && other.url == url && other.label == label;

  @override
  int get hashCode => Object.hash(url, label);

  @override
  String toString() => 'PortalLink($label, $url)';
}

/// The other servers the page [document] (read from [page]) points to: its
/// links to `http`/`https` addresses on another host, the first for each
/// host, in the order of the page.
///
/// Some entries of a server list are no media servers but an operator's
/// front page: a few pictures, each a link to one of its servers. There is
/// nothing on such a page to put in a library; what it is good for is
/// saying where the servers are. Nothing here follows a link.
List<PortalLink> portalLinks(Document document, Uri page, {int limit = 12}) {
  final links = <PortalLink>[];
  final seen = <String>{};
  for (final anchor in document.querySelectorAll('a[href]')) {
    if (links.length >= limit) break;
    final target = Uri.tryParse(anchor.attributes['href']!.trim());
    if (target == null ||
        !allowedUrlSchemes.contains(target.scheme) ||
        target.host.isEmpty ||
        target.userInfo.isNotEmpty) {
      continue;
    }
    final host = target.host.toLowerCase();
    if (host == page.host.toLowerCase()) continue;
    if (!seen.add('$host:${target.port}')) continue;

    var path = target.path.replaceAll(RegExp('/{2,}'), '/');
    if (path.isEmpty) path = '/';
    // A folder is written with its "/"; a page (index.php) is left alone.
    if (!path.endsWith('/') && !path.split('/').last.contains('.')) {
      path = '$path/';
    }
    final text = anchor.text.replaceAll(RegExp(r'\s+'), ' ').trim();
    final picture = anchor.querySelector('img[alt]')?.attributes['alt'] ?? '';
    final label = cleanServerText(text.isNotEmpty ? text : picture, 50);
    links.add(
      PortalLink(
        Uri(
          scheme: target.scheme,
          host: host,
          port: target.hasPort ? target.port : null,
          path: path,
        ),
        label.isEmpty ? host : label,
      ),
    );
  }
  return links;
}

/// The sources among [sources] that [link] leads to: those with an address
/// on its host, and those whose operator's front page is on it.
List<Source> sourcesBehind(PortalLink link, Iterable<Source> sources) => [
  for (final source in sources)
    if (source.baseUrls.any((url) => url.host.toLowerCase() == link.url.host) ||
        source.portalUrl?.host.toLowerCase() == link.url.host)
      source,
];
