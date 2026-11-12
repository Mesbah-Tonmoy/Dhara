import 'package:dhara/core/net/safe_http_client.dart';
import 'package:dhara/features/sources/adapters/listing_parser.dart';
import 'package:dhara/features/sources/adapters/source_adapter.dart';
import 'package:html/dom.dart';
import 'package:html/parser.dart' as html;

/// Reads h5ai file indexes (DhakaFlix, CircleFTP and others).
///
/// h5ai draws its list with JavaScript, but every page also carries the
/// same list as a plain table (`#fallback`) for browsers without it. That
/// table is what this reads, so no script is ever run.
class H5aiAdapter implements SourceAdapter {
  const H5aiAdapter(this._client);

  final SafeHttpClient _client;

  @override
  Future<List<RemoteEntry>> list(Uri folder) async {
    final page = await fetchFolderPage(_client, folder);
    return parseH5aiListing(page.body, page.url);
  }
}

/// The entries of an h5ai page fetched from [folder].
///
/// Throws a [SourceReadException] if [pageHtml] is not an h5ai index or
/// has no plain table.
List<RemoteEntry> parseH5aiListing(String pageHtml, Uri folder) {
  final document = html.parse(pageHtml);
  if (!isH5ai(document)) {
    throw const SourceReadException('The page is not an h5ai index.');
  }
  final table = document.querySelector('#fallback table');
  if (table == null) {
    throw const SourceReadException(
      'This h5ai index has no plain file table to read.',
    );
  }
  // Sizes come as whole "KB", so they are rounded to 1024 bytes.
  return entriesFromLinks(table.querySelectorAll('td.fb-n a[href]'), folder);
}

/// Whether [document] is an h5ai index page: it loads h5ai's script, or
/// says so in its title (operators often re-brand the visible footer).
bool isH5ai(Document document) {
  for (final script in document.querySelectorAll('script[src]')) {
    if (script.attributes['src']!.contains('_h5ai/')) return true;
  }
  final title = document.querySelector('title')?.text.toLowerCase() ?? '';
  return title.contains('powered by h5ai');
}
