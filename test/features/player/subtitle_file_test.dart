import 'dart:io';

import 'package:dhara/features/player/subtitle_file.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('dhara_subs_'));
  tearDown(() => dir.deleteSync(recursive: true));

  String write(String name, {String content = '1\n00:00:00,000 --> x\nhi\n'}) {
    final file = File('${dir.path}${Platform.pathSeparator}$name')
      ..writeAsStringSync(content);
    return file.path;
  }

  Matcher refuses(String message) {
    return throwsA(
      isA<SubtitleFileError>().having((e) => e.message, 'message', message),
    );
  }

  test('accepts the whitelisted subtitle types', () async {
    for (final name in ['a.srt', 'b.ass', 'c.ssa', 'd.vtt', 'UPPER.SRT']) {
      final file = await checkSubtitleFile(write(name));
      expect(file.name, name);
      expect(File(file.path).existsSync(), isTrue);
      expect(File(file.path).isAbsolute, isTrue);
    }
  });

  test('keeps spaces and brackets in the file name', () async {
    final file = await checkSubtitleFile(write('My Film (2021) [1080p].srt'));

    expect(file.name, 'My Film (2021) [1080p].srt');
  });

  test('refuses other file types, including look-alikes', () async {
    for (final name in [
      'movie.mkv',
      'run.exe',
      'script.srt.bat',
      'notes.txt',
      'noextension',
      '.srt.lnk',
    ]) {
      await expectLater(
        checkSubtitleFile(write(name)),
        refuses('Unsupported subtitle type'),
        reason: name,
      );
    }
  });

  test('refuses a missing file', () async {
    await expectLater(
      checkSubtitleFile('${dir.path}${Platform.pathSeparator}missing.srt'),
      refuses('Subtitle file not found'),
    );
  });

  test('refuses a folder named like a subtitle', () async {
    final folder = Directory('${dir.path}${Platform.pathSeparator}folder.srt')
      ..createSync();

    await expectLater(
      checkSubtitleFile(folder.path),
      refuses('Subtitle file not found'),
    );
  });

  test('refuses an empty file', () async {
    await expectLater(
      checkSubtitleFile(write('empty.srt', content: '')),
      refuses('Subtitle file is empty'),
    );
  });

  test('refuses a file over the size limit', () async {
    final path = write('huge.srt');
    final handle = File(path).openSync(mode: FileMode.write);
    handle.truncateSync(maxSubtitleFileBytes + 1);
    handle.closeSync();

    await expectLater(
      checkSubtitleFile(path),
      refuses('Subtitle file is too large'),
    );
  });
}
