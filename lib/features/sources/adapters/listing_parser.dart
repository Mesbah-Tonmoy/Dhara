// Shared by the adapters that read HTML folder pages. The HTML is parsed
// with a real parser (package:html) and only ever inspected, never rendered
// or run; the regular expressions here read short text cells, not markup.
import 'package:dhara/features/sources/adapters/source_adapter.dart';
import 'package:html/dom.dart';

/// Turns the links of a folder page into entries: every link that points
/// directly into [folder], with the size and date written next to it.
List<RemoteEntry> entriesFromLinks(Iterable<Element> links, Uri folder) {
  final entries = <RemoteEntry>[];
  final seen = <Uri>{};
  final positions = _SiblingPositions();
  for (final link in links) {
    if (entries.length >= maxEntriesPerFolder) break;
    final href = link.attributes['href'];
    if (href == null) continue;

    final child = childEntry(folder, href);
    if (child == null || !seen.add(child.url)) continue;
    final details = _detailsOf(link, positions);
    entries.add(
      RemoteEntry(
        name: child.name,
        url: child.url,
        isFolder: child.isFolder,
        // A folder's "size" is the size of its directory record, if anything.
        size: child.isFolder ? null : details.size,
        modified: details.modified,
      ),
    );
  }
  return entries;
}

/// The entry [href] stands for, if it points directly into [folder].
///
/// Returns `null` for everything else: the parent link, sort links
/// (`?C=N;O=D`), links to other hosts or schemes, links that skip a level,
/// and names that hide a path separator. This is what keeps a hostile or
/// broken page from sending the app outside the folder it asked for.
RemoteEntry? childEntry(Uri folder, String href) {
  final Uri target;
  try {
    target = folder.resolve(href.trim());
  } on FormatException {
    return null;
  }
  if (target.scheme != folder.scheme ||
      target.host != folder.host ||
      target.port != folder.port ||
      target.hasQuery ||
      target.hasFragment) {
    return null;
  }

  final parent = _segments(folder.path);
  final path = _segments(target.path);
  if (parent == null || path == null || path.length != parent.length + 1) {
    return null;
  }
  for (var i = 0; i < parent.length; i++) {
    if (path[i] != parent[i]) return null;
  }
  final name = path.last;
  if (name == '.' || name == '..') return null;

  return RemoteEntry(
    name: name,
    url: target,
    isFolder: target.path.endsWith('/'),
  );
}

/// The decoded segments of [path], or `null` if one of them hides a path
/// separator or a control character behind percent-encoding.
List<String>? _segments(String path) {
  final segments = <String>[];
  for (final raw in path.split('/')) {
    if (raw.isEmpty) continue;
    final segment = _decode(raw);
    if (segment.contains(_unsafeInName)) return null;
    segments.add(segment);
  }
  return segments;
}

final _unsafeInName = RegExp(r'[/\\\x00-\x1F\x7F]');

String _decode(String segment) {
  try {
    return Uri.decodeComponent(segment);
  } on FormatException {
    // Escapes that are not UTF-8 (legacy encodings): keep the raw text.
    return segment;
  } on ArgumentError {
    return segment;
  }
}

/// Reads a size as servers print it: `1234567`, `1.6G`, `4.0K`, `88 KB`.
/// Units are powers of 1024. Returns `null` for `-`, blanks and anything
/// else.
int? parseListingSize(String text) {
  final match = _sizePattern.firstMatch(text.trim());
  if (match == null) return null;
  final number = double.tryParse(match[1]!.replaceFirst(',', '.'));
  if (number == null) return null;
  const factors = {
    '': 1,
    'k': 1024,
    'm': 1024 * 1024,
    'g': 1024 * 1024 * 1024,
    't': 1024 * 1024 * 1024 * 1024,
  };
  return (number * factors[match[2]!.toLowerCase()]!).round();
}

final _sizePattern = RegExp(
  r'^(\d+(?:[.,]\d+)?)\s*([kmgt]?)(?:i?b)?$',
  caseSensitive: false,
);

/// Reads the date at the start of [text], in the formats listings use:
/// `2024-01-06 17:46` (Apache, h5ai), `01-Aug-2022 15:54` (Apache, nginx)
/// and `11/3/2024 9:05 PM` (IIS, month first). Anything else is `null`.
DateTime? parseListingDate(String text) {
  final clean = text.trim().replaceAll(_whitespace, ' ');

  var match = _isoDate.firstMatch(clean);
  if (match != null) {
    return _date(match[1]!, match[2]!, match[3]!, match[4]!, match[5]!);
  }
  match = _namedMonthDate.firstMatch(clean);
  if (match != null) {
    final month = _months.indexOf(match[2]!.toLowerCase()) + 1;
    return _date(match[3]!, '$month', match[1]!, match[4]!, match[5]!);
  }
  match = _usDate.firstMatch(clean);
  if (match != null) {
    final isPm = match[6]!.toLowerCase() == 'pm';
    final hour = int.parse(match[4]!) % 12 + (isPm ? 12 : 0);
    return _date(match[3]!, match[1]!, match[2]!, '$hour', match[5]!);
  }
  return null;
}

final _whitespace = RegExp(r'\s+');
final _isoDate = RegExp(r'^(\d{4})-(\d{2})-(\d{2})[ T](\d{1,2}):(\d{2})');
final _namedMonthDate =
    RegExp(r'^(\d{1,2})-([A-Za-z]{3})-(\d{4}) (\d{1,2}):(\d{2})');
final _usDate = RegExp(
  r'^(\d{1,2})/(\d{1,2})/(\d{4}) (\d{1,2}):(\d{2}) ?([AP]M)',
  caseSensitive: false,
);
const _months = [
  'jan', 'feb', 'mar', 'apr', 'may', 'jun', //
  'jul', 'aug', 'sep', 'oct', 'nov', 'dec',
];

DateTime? _date(
  String year,
  String month,
  String day,
  String hour,
  String minute,
) {
  final y = int.parse(year);
  final m = int.parse(month);
  final d = int.parse(day);
  final h = int.parse(hour);
  final min = int.parse(minute);
  // DateTime would silently roll "month 13" over into the next year.
  if (m < 1 || m > 12 || d < 1 || d > 31 || h > 23 || min > 59) return null;
  return DateTime(y, m, d, h, min);
}

typedef _Details = ({int? size, DateTime? modified});

/// The size and date printed next to [link].
///
/// - In a table (Apache, h5ai): the other cells of the link's row.
/// - Otherwise the text right after the link (nginx, Apache without
///   tables), or right before it when nothing follows (IIS).
_Details _detailsOf(Element link, _SiblingPositions positions) {
  final row = _ancestor(link, 'tr');
  if (row != null) {
    int? size;
    DateTime? modified;
    for (final cell in row.children) {
      if (cell.contains(link)) continue;
      size ??= parseListingSize(cell.text);
      modified ??= parseListingDate(cell.text);
    }
    return (size: size, modified: modified);
  }

  var text = positions.textBeside(link, offset: 1);
  if (text.trim().isEmpty) text = positions.textBeside(link, offset: -1);
  final words = text.trim().split(_whitespace);
  return (size: parseListingSize(words.last), modified: parseListingDate(text));
}

Element? _ancestor(Element element, String localName) {
  for (var node = element.parent; node != null; node = node.parent) {
    if (node.localName == localName) return node;
  }
  return null;
}

/// Finds the text node next to an element. A plain listing can hold
/// thousands of links under one parent, so each parent's children are
/// numbered once instead of being searched for every link.
class _SiblingPositions {
  final _byParent = <Node, Map<Node, int>>{};

  String textBeside(Element element, {required int offset}) {
    final parent = element.parentNode;
    if (parent == null) return '';
    final positions = _byParent[parent] ??= {
      for (final (index, node) in parent.nodes.indexed) node: index,
    };
    final index = positions[element]! + offset;
    if (index < 0 || index >= parent.nodes.length) return '';
    final node = parent.nodes[index];
    return node is Text ? node.text : '';
  }
}
