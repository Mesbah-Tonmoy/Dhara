import 'dart:io';

import 'package:dhara/features/sources/source_list.dart';
import 'package:file_selector/file_selector.dart';

const _jsonFiles = XTypeGroup(label: 'Source list', extensions: ['json']);

/// Reads and writes source-list files, always at a place the user picks in
/// the system's own file dialog. Nothing is opened or run, only read as
/// text or written as text.
class SourceListFiles {
  const SourceListFiles();

  /// Lets the user pick a source list and returns its text, or `null` if
  /// they cancel. Throws a [SourceFormatException] for a file that is too
  /// large or is not text.
  Future<String?> pickAndRead() async {
    final file = await openFile(acceptedTypeGroups: const [_jsonFiles]);
    if (file == null) return null;
    try {
      // Checked before reading, so a huge file is never loaded.
      if (await file.length() > maxSourceListLength) {
        throw const SourceFormatException('The file is too large.');
      }
      return await file.readAsString();
    } on FileSystemException {
      throw const SourceFormatException(
        'The file could not be read as text.',
      );
    }
  }

  /// Lets the user pick where to save [json] and returns the chosen path,
  /// or `null` if they cancel. Throws a [FileSystemException] if writing
  /// fails.
  Future<String?> save(String json) async {
    final location = await getSaveLocation(
      suggestedName: 'dhara-sources.json',
      acceptedTypeGroups: const [_jsonFiles],
    );
    if (location == null) return null;
    await File(location.path).writeAsString(json);
    return location.path;
  }
}
