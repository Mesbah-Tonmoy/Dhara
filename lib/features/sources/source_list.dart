import 'dart:convert';

import 'package:dhara/core/net/media_url.dart';
import 'package:dhara/features/sources/source.dart';

/// Version of the source-list JSON this app reads and writes. The format is
/// documented in `assets/sources/README.md`.
const sourceListSchemaVersion = 1;

// A list can be imported from anywhere, so it is untrusted input: every size
// is capped and every field is checked.
const maxSourceListLength = 2 * 1024 * 1024;
const maxSources = 2000;
const maxBaseUrlsPerSource = 64;
const _maxUrlLength = 2048;

/// Why a source or a source list was rejected.
class SourceFormatException implements Exception {
  const SourceFormatException(this.message);

  /// A plain-English reason that names the field, e.g.
  /// `sources[3].baseUrls[0]: must be an http or https URL.`
  /// It never quotes text from the rejected list.
  final String message;

  @override
  String toString() => 'SourceFormatException: $message';
}

/// Reads a source list from JSON [text]. One bad entry rejects the whole
/// list, so a list is never half applied.
///
/// Throws a [SourceFormatException] that says what is wrong.
List<Source> parseSourceList(String text) =>
    sourcesFromJson(decodeSourceListJson(text));

/// The first half of [parseSourceList]: size check and JSON decoding.
Map<String, dynamic> decodeSourceListJson(String text) {
  if (text.length > maxSourceListLength) {
    throw const SourceFormatException('The list is too large.');
  }
  final Object? root;
  try {
    root = jsonDecode(text);
  } on FormatException {
    throw const SourceFormatException('The file is not valid JSON.');
  }
  if (root is! Map<String, dynamic>) {
    throw const SourceFormatException('The list must be a JSON object.');
  }
  return root;
}

/// The second half of [parseSourceList]: checks the envelope and every
/// source. Keys this version does not know are ignored.
List<Source> sourcesFromJson(Map<String, dynamic> root) {
  final version = root['schemaVersion'];
  if (version is! int || version < 1) {
    throw const SourceFormatException(
      '"schemaVersion" is missing or is not a version number.',
    );
  }
  if (version > sourceListSchemaVersion) {
    throw SourceFormatException(
      'The list uses schema version $version, but this app only reads up '
      'to version $sourceListSchemaVersion.',
    );
  }
  final items = root['sources'];
  if (items is! List) {
    throw const SourceFormatException('"sources" must be a list.');
  }
  if (items.length > maxSources) {
    throw const SourceFormatException(
      'The list has more than $maxSources sources.',
    );
  }

  final sources = <Source>[];
  final ids = <String>{};
  for (final (index, item) in items.indexed) {
    final source = sourceFromJson(item, at: 'sources[$index]');
    if (!ids.add(source.id)) {
      throw SourceFormatException(
        'sources[$index].id: another source already uses this id.',
      );
    }
    sources.add(source);
  }
  return sources;
}

/// The list envelope for [sources], ready for `jsonEncode`.
Map<String, Object?> sourcesToJson(Iterable<Source> sources) => {
      'schemaVersion': sourceListSchemaVersion,
      'sources': [for (final source in sources) source.toJson()],
    };

/// Reads and checks one source. [at] names it in error messages.
///
/// Also the way to check a [Source] built in code: a source that survives
/// `sourceFromJson(source.toJson())` can always be saved and loaded again.
Source sourceFromJson(Object? json, {String at = 'source'}) {
  if (json is! Map<String, dynamic>) {
    throw SourceFormatException('$at: must be a JSON object.');
  }

  final id = _requiredText(json, 'id', at, maxLength: 64);
  if (!_idPattern.hasMatch(id)) {
    throw SourceFormatException(
      '$at.id: use lower-case letters, digits and "-" only.',
    );
  }

  final rawUrls = json['baseUrls'];
  if (rawUrls is! List || rawUrls.isEmpty) {
    throw SourceFormatException('$at.baseUrls: list at least one URL.');
  }
  if (rawUrls.length > maxBaseUrlsPerSource) {
    throw SourceFormatException(
      '$at.baseUrls: more than $maxBaseUrlsPerSource URLs.',
    );
  }
  final baseUrls = <Uri>[];
  for (final (index, raw) in rawUrls.indexed) {
    final url = _folderUrl(raw, '$at.baseUrls[$index]');
    if (!baseUrls.contains(url)) baseUrls.add(url);
  }

  final portal = json['portalUrl'];
  return Source(
    id: id,
    name: _requiredText(json, 'name', at, maxLength: 80),
    provider: _optionalText(json, 'provider', at, maxLength: 80),
    isp: _optionalText(json, 'isp', at, maxLength: 80),
    type: _oneOf(json['type'], _typesByName, '$at.type'),
    category: _oneOf(
      json['category'],
      SourceCategory.values.asNameMap(),
      '$at.category',
    ),
    baseUrls: List.unmodifiable(baseUrls),
    portalUrl: portal == null ? null : _webUrl(portal, '$at.portalUrl'),
    notes: _optionalText(
      json,
      'notes',
      at,
      maxLength: 1000,
      multiline: true,
    ),
  );
}

final _idPattern = RegExp(r'^[a-z0-9]+(-[a-z0-9]+)*$');
final _typesByName = {
  for (final type in SourceType.values) type.jsonName: type,
};

// Control characters; the multi-line variant lets tab, LF and CR through.
final _controlChars = RegExp(r'[\x00-\x1F\x7F]');
final _controlCharsMultiline = RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]');

String _requiredText(
  Map<String, dynamic> json,
  String key,
  String at, {
  required int maxLength,
}) {
  final text = _optionalText(json, key, at, maxLength: maxLength);
  if (text == null) throw SourceFormatException('$at.$key: is missing.');
  return text;
}

/// Trimmed text, or `null` when the key is absent, `null` or blank.
String? _optionalText(
  Map<String, dynamic> json,
  String key,
  String at, {
  required int maxLength,
  bool multiline = false,
}) {
  final value = json[key];
  if (value == null) return null;
  if (value is! String) throw SourceFormatException('$at.$key: must be text.');

  final text = value.trim();
  if (text.isEmpty) return null;
  if (text.length > maxLength) {
    throw SourceFormatException(
      '$at.$key: longer than $maxLength characters.',
    );
  }
  if (text.contains(multiline ? _controlCharsMultiline : _controlChars)) {
    throw SourceFormatException('$at.$key: contains control characters.');
  }
  return text;
}

T _oneOf<T>(Object? value, Map<String, T> options, String at) {
  final match = options[value];
  if (match == null) {
    throw SourceFormatException(
      '$at: must be one of ${options.keys.join(', ')}.',
    );
  }
  return match;
}

/// An absolute http(s) URL without credentials. Passwords never belong in a
/// source list: it is saved as plain text and can be exported.
Uri _webUrl(Object? value, String at) {
  final url = value is String && value.length <= _maxUrlLength
      ? parseMediaUrl(value)
      : null;
  if (url == null) {
    throw SourceFormatException('$at: must be an http or https URL.');
  }
  if (url.userInfo.isNotEmpty) {
    throw SourceFormatException(
      '$at: must not contain a user name or password.',
    );
  }
  return url;
}

/// A [_webUrl] that names a folder: no query or fragment, and a path that
/// ends in "/" (added when missing).
Uri _folderUrl(Object? value, String at) {
  final url = _webUrl(value, at);
  if (url.hasQuery || url.hasFragment) {
    throw SourceFormatException('$at: must not contain "?" or "#".');
  }
  return url.path.endsWith('/') ? url : url.replace(path: '${url.path}/');
}
