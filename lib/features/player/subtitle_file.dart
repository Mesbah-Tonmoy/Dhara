import 'dart:io';

/// Extensions accepted for an external subtitle file the user picks.
const subtitleFileExtensions = <String>['srt', 'ass', 'ssa', 'vtt'];

/// Subtitle files are small text files; anything bigger is refused before it
/// reaches the player.
const maxSubtitleFileBytes = 20 * 1024 * 1024;

/// A subtitle file that passed [checkSubtitleFile].
class SubtitleFile {
  const SubtitleFile({required this.path, required this.name});

  /// Absolute path handed to the player.
  final String path;

  /// File name only, for display.
  final String name;
}

/// Thrown by [checkSubtitleFile]; [message] is safe to show to the user.
class SubtitleFileError implements Exception {
  const SubtitleFileError(this.message);

  final String message;

  @override
  String toString() => 'SubtitleFileError($message)';
}

/// Validates a user-picked subtitle file: whitelisted extension, an existing
/// regular file (not a folder, link target is resolved), and a sane size.
///
/// The file is only ever handed to the player as a subtitle; it is never
/// executed or opened by another program.
Future<SubtitleFile> checkSubtitleFile(String path) async {
  final name = path.split(RegExp(r'[\\/]')).last;
  final dot = name.lastIndexOf('.');
  final extension = dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
  if (!subtitleFileExtensions.contains(extension)) {
    throw const SubtitleFileError('Unsupported subtitle type');
  }

  final File file;
  final int size;
  try {
    final type = await FileSystemEntity.type(path);
    if (type != FileSystemEntityType.file) {
      throw const SubtitleFileError('Subtitle file not found');
    }
    file = File(path).absolute;
    size = await file.length();
  } on FileSystemException {
    throw const SubtitleFileError('Subtitle file could not be read');
  }

  if (size == 0) throw const SubtitleFileError('Subtitle file is empty');
  if (size > maxSubtitleFileBytes) {
    throw const SubtitleFileError('Subtitle file is too large');
  }
  return SubtitleFile(path: file.path, name: name);
}
