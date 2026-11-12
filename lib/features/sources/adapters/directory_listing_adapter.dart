import 'package:dhara/core/net/safe_http_client.dart';
import 'package:dhara/features/sources/adapters/listing_parser.dart';
import 'package:dhara/features/sources/adapters/source_adapter.dart';
import 'package:html/dom.dart';
import 'package:html/parser.dart' as html;

/// Reads the plain folder pages web servers generate themselves: Apache
/// (`mod_autoindex`, with or without tables), nginx (`autoindex`) and IIS
/// (directory browsing).
class DirectoryListingAdapter implements SourceAdapter {
  const DirectoryListingAdapter(this._client);

  final SafeHttpClient _client;

  @override
  Future<List<RemoteEntry>> list(Uri folder) async {
    final page = await fetchFolderPage(_client, folder);
    return parseDirectoryListing(page.body, page.url);
  }
}

/// The entries of a folder page fetched from [folder].
///
/// Throws a [SourceReadException] if [pageHtml] is not a folder listing, so
/// an ordinary website is never crawled through its links.
List<RemoteEntry> parseDirectoryListing(String pageHtml, Uri folder) {
  final document = html.parse(pageHtml);
  if (!isDirectoryListing(document)) {
    throw const SourceReadException('The page is not a folder listing.');
  }
  return entriesFromLinks(document.querySelectorAll('a[href]'), folder);
}

/// Whether [document] looks like a server-generated folder page: an
/// "Index of" title (Apache, nginx) or a link to the parent folder.
bool isDirectoryListing(Document document) {
  final title = document.querySelector('title')?.text.trim().toLowerCase();
  if (title != null && title.startsWith('index of ')) return true;

  for (final link in document.querySelectorAll('a[href]')) {
    final text = link.text.trim();
    if (link.attributes['href'] == '../' ||
        text == 'Parent Directory' ||
        text == '[To Parent Directory]') {
      return true;
    }
  }
  return false;
}
