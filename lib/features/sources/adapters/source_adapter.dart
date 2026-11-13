import 'package:dhara/core/net/safe_http_client.dart';
import 'package:flutter/foundation.dart';

/// Size limit for one folder page. Big folders make big pages, so this is
/// above the HTTP client's default.
const maxListingBytes = 8 * 1024 * 1024;

/// A folder page with more entries than this is cut off here.
const maxEntriesPerFolder = 20000;

/// One file or folder found inside a folder of a source.
@immutable
class RemoteEntry {
  const RemoteEntry({
    required this.name,
    required this.url,
    required this.isFolder,
    this.size,
    this.modified,
  });

  /// The file or folder name. Server-controlled text: show it only through
  /// a plain `Text` widget, and never use it as a local path as it is.
  final String name;

  /// For a folder: what to pass to [SourceAdapter.list] to look inside.
  /// For a file: where it can be fetched.
  final Uri url;
  final bool isFolder;

  /// Size in bytes if the server says. Often rounded ("1.6G").
  final int? size;

  /// Last change, read as local time.
  final DateTime? modified;

  @override
  bool operator ==(Object other) =>
      other is RemoteEntry &&
      other.name == name &&
      other.url == url &&
      other.isFolder == isFolder &&
      other.size == size &&
      other.modified == modified;

  @override
  int get hashCode => Object.hash(name, url, isFolder, size, modified);

  @override
  String toString() =>
      'RemoteEntry(${isFolder ? 'folder' : 'file'} "$name", $url, '
      'size: $size, modified: $modified)';
}

/// The server answered, but not with something the adapter can use.
class SourceReadException implements Exception {
  const SourceReadException(this.message, {this.statusCode});

  /// Plain English, safe to show; never quotes the server's answer.
  final String message;

  /// The HTTP status the server answered with, if that is what went wrong.
  /// It tells a busy server (503) from a folder that is gone (404).
  final int? statusCode;

  @override
  String toString() => 'SourceReadException: $message';
}

/// Reads the folders of one kind of server. Every server type has one
/// implementation; the rest of the app only sees this.
abstract interface class SourceAdapter {
  /// The files and folders directly inside [folder], in server order.
  ///
  /// Start with one of the source's base URLs, then pass the `url` of a
  /// folder entry to go deeper. An adapter only returns entries below the
  /// folder it was asked for, so a server cannot steer the app elsewhere.
  ///
  /// Throws a [SourceReadException] if the answer is not usable, or a
  /// [SafeHttpException] if the request was refused or did not finish.
  Future<List<RemoteEntry>> list(Uri folder);
}

/// Fetches the page of [folder] for an HTML-listing adapter.
///
/// A redirect is accepted only if it leads to the same folder on the same
/// host (typically `/dir` to `/dir/`, or http to https).
Future<SafeHttpResponse> fetchFolderPage(
  SafeHttpClient client,
  Uri folder,
) async {
  final response = await client.get(folder, maxBytes: maxListingBytes);
  if (!response.isOk) {
    throw SourceReadException(
      'The server answered ${response.statusCode}.',
      statusCode: response.statusCode,
    );
  }
  if (response.url.host != folder.host ||
      _asFolder(response.url.path) != _asFolder(folder.path)) {
    throw const SourceReadException(
      'The server sent a different page than the folder asked for.',
    );
  }
  return response;
}

String _asFolder(String path) => path.endsWith('/') ? path : '$path/';

/// Server text made safe to keep and show: control characters become
/// spaces (so it stays on one line) and it is cut to [maxLength].
String cleanServerText(String text, int maxLength) {
  final clean = text.replaceAll(_controlChars, ' ').trim();
  return clean.length <= maxLength ? clean : clean.substring(0, maxLength);
}

final _controlChars = RegExp(r'[\x00-\x1F\x7F]');
