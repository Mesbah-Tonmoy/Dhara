import 'dart:convert';
import 'dart:io';

import 'package:dhara/features/update/update_notice.dart';
import 'package:dhara/features/update/update_signature.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/update_keys.dart';

final _askedAt = Uri.parse('https://files.example/download?id=notice');
const _sha = '9f86d081884c7d659a2feabbc5a48a55f6b3f1a2c1d4e7b8a9c0d1e2f3a4b5c6';

/// What a notice says, as the signing script writes it.
Map<String, Object?> _told({
  Object? version = '1.2.0',
  Object? installer = 'https://files.example/download?id=setup&confirm=t',
  Object? size = 50651234,
  Object? sha256 = _sha,
  Object? notes,
}) => {
  'version': version,
  'installer': installer,
  'size': size,
  'sha256': sha256,
  'notes': ?notes,
};

/// A notice around [told], with [signature] for its signature.
List<int> _notice(
  Object? told, {
  List<int> signature = const [1, 2, 3],
  Object? kind = 1,
}) => utf8.encode(
  jsonEncode({
    'dhara_update': kind,
    'signed': base64.encode(utf8.encode(jsonEncode(told))),
    'signature': base64.encode(signature),
  }),
);

/// Reads [bytes] with a stand-in for the signature check.
UpdateNoticeRead _read(List<int> bytes, {bool fits = true, Uri? askedAt}) =>
    readUpdateNotice(
      bytes,
      signed: (message, signature) => fits,
      askedAt: askedAt ?? _askedAt,
    );

void main() {
  group('a version', () {
    test('is three numbers', () {
      expect(AppVersion.parse('1.2.0'), const AppVersion(1, 2, 0));
      expect(AppVersion.parse('10.0.12').toString(), '10.0.12');
      for (final text in const [
        '',
        '1.2',
        '1.2.3.4',
        'v1.2.3',
        '1.2.3 ',
        '1.2.3+5',
        '1.2.x',
        '1..3',
        '-1.2.3',
        '1.2.3-beta',
        '123456.1.1',
      ]) {
        expect(AppVersion.parse(text), isNull, reason: text);
      }
    });

    test('is newer by its numbers, not by its letters', () {
      AppVersion v(String text) => AppVersion.parse(text)!;
      expect(v('1.2.0').isNewerThan(v('1.1.0')), isTrue);
      expect(v('1.10.0').isNewerThan(v('1.9.9')), isTrue);
      expect(v('2.0.0').isNewerThan(v('1.99.99')), isTrue);
      expect(v('1.1.1').isNewerThan(v('1.1.0')), isTrue);
      expect(v('1.1.0').isNewerThan(v('1.1.0')), isFalse);
      expect(v('1.0.9').isNewerThan(v('1.1.0')), isFalse);
      expect(v('01.1.0'), v('1.1.0'));
    });
  });

  group('a notice whose signature fits', () {
    test('is taken as what it says', () {
      final read = _read(_notice(_told(notes: 'Faster start.\nনতুন')));
      expect(read.problem, isNull);
      final notice = read.notice!;
      expect(notice.version, const AppVersion(1, 2, 0));
      expect(
        notice.installer,
        Uri.parse('https://files.example/download?id=setup&confirm=t'),
      );
      expect(notice.size, 50651234);
      expect(notice.sha256, _sha);
      expect(notice.notes, 'Faster start.\nনতুন');
    });

    test('needs no notes, and may say more than this version knows', () {
      expect(_read(_notice(_told())).notice!.notes, '');
      final read = _read(_notice({..._told(), 'min_windows': '10.0'}));
      expect(read.notice, isNotNull);
    });

    test('has its notes made plain text of a sensible length', () {
      final read = _read(
        _notice(
          _told(
            notes: '  One\r\nTwo\u0000\u0007\u001b[31m\u0085 ${'x' * 5000}',
          ),
        ),
      );
      final notes = read.notice!.notes;
      expect(notes, startsWith('One\nTwo   [31m  xxx'));
      expect(notes, hasLength(maxUpdateNotesLength));
    });

    test('is checked over the very bytes that were signed', () {
      final told = utf8.encode(
        '{ "version":"3.0.0",\n "installer" : '
        '"https://files.example/a", "size":7,"sha256":"$_sha"}',
      );
      List<int>? checked;
      List<int>? withSignature;
      final read = readUpdateNotice(
        utf8.encode(
          jsonEncode({
            'dhara_update': 1,
            'signed': base64.encode(told),
            'signature': base64.encode(const [9, 8, 7]),
          }),
        ),
        signed: (message, signature) {
          checked = message;
          withSignature = signature;
          return true;
        },
        askedAt: _askedAt,
      );
      expect(checked, told);
      expect(withSignature, const [9, 8, 7]);
      expect(read.notice!.version, const AppVersion(3, 0, 0));
    });
  });

  group('a notice is not usable', () {
    void refused(Object? told, String why, {Object? kind = 1}) {
      final read = _read(_notice(told, kind: kind));
      expect(read.notice, isNull, reason: why);
      expect(read.problem, UpdateNoticeProblem.notUsable, reason: why);
    }

    test('of a kind this version does not know', () {
      refused(_told(), 'kind 2', kind: 2);
      refused(_told(), 'kind 0', kind: 0);
    });

    test('if what is signed is not what a notice says', () {
      refused('1.2.0', 'a text');
      refused([_told()], 'a list');
      refused(const <String, Object?>{}, 'nothing');
      refused(_told()..remove('version'), 'no version');
      refused(_told()..remove('installer'), 'no installer');
      refused(_told()..remove('size'), 'no size');
      refused(_told()..remove('sha256'), 'no sha256');
    });

    test('with a version that is none', () {
      for (final version in const ['1.2', 'latest', '1.2.0-rc1', 120, null]) {
        refused(_told(version: version), '$version');
      }
    });

    test('with a size that is none or too large', () {
      for (final size in [0, -5, 12.5, '50651234', maxInstallerBytes + 1]) {
        refused(_told(size: size), '$size');
      }
      expect(_read(_notice(_told(size: maxInstallerBytes))).notice, isNotNull);
      expect(_read(_notice(_told(size: 1))).notice, isNotNull);
    });

    test('with a digest that is none', () {
      for (final sha256 in [
        '',
        _sha.substring(1),
        '${_sha}0',
        _sha.toUpperCase(),
        _sha.replaceFirst('9', 'g'),
        42,
      ]) {
        refused(_told(sha256: sha256), '$sha256');
      }
    });

    test('with notes that are no text', () {
      refused(_told(notes: 5), 'a number');
      refused(_told(notes: const ['a']), 'a list');
    });

    test('with an installer that is not on the host that was asked', () {
      for (final installer in [
        'https://other.example/download?id=setup',
        'https://files.example.evil.example/setup.exe',
        'https://evil.example/files.example/setup.exe',
        'https://files.example@evil.example/setup.exe',
        'https://files.example:8443/setup.exe',
        'http://files.example/setup.exe',
        'file:///C:/Windows/System32/calc.exe',
        r'C:\Users\Public\setup.exe',
        r'\\server\share\setup.exe',
        '//files.example/setup.exe',
        '/download?id=setup',
        'setup.exe',
        'ftp://files.example/setup.exe',
        'https://user:pass@files.example/setup.exe',
        'https://files.example/setup.exe#part',
        'https:///setup.exe',
        'https://files.example/${'a' * 2000}',
        '',
        7,
        null,
      ]) {
        refused(_told(installer: installer), '$installer');
      }
    });

    test('the host and the port count, not how they are written', () {
      final read = _read(
        _notice(_told(installer: 'HTTPS://FILES.example:443/Setup.exe')),
      );
      expect(read.notice!.installer.host, 'files.example');
      final onPort = _read(
        _notice(_told(installer: 'https://files.example:8443/setup.exe')),
        askedAt: Uri.parse('https://files.example:8443/notice'),
      );
      expect(onPort.notice, isNotNull);
    });
  });

  group('what is no notice', () {
    void notANotice(List<int> bytes, String why) {
      var asked = false;
      final read = readUpdateNotice(
        bytes,
        signed: (message, signature) {
          asked = true;
          return true;
        },
        askedAt: _askedAt,
      );
      expect(read.notice, isNull, reason: why);
      expect(read.problem, UpdateNoticeProblem.notANotice, reason: why);
      expect(asked, isFalse, reason: 'nothing of it goes to the check: $why');
    }

    test('is not taken, and nothing of it is checked', () {
      notANotice(const [], 'nothing');
      notANotice(utf8.encode('<!DOCTYPE html><html>Sign in</html>'), 'a page');
      notANotice(utf8.encode('[1, 2, 3]'), 'a list');
      notANotice(utf8.encode('"dhara_update"'), 'a text');
      notANotice(utf8.encode('{"dhara_update": 1'), 'cut off');
      notANotice(const [0xff, 0xfe, 0x7b, 0x7d], 'no UTF-8');
      notANotice(gzip.encode(_notice(_told())), 'packed');
      notANotice(utf8.encode(jsonEncode(_told())), 'unsigned content');
      notANotice(
        utf8.encode('{"dhara_update":"1","signed":"e30=","signature":"AQ=="}'),
        'the kind as a text',
      );
      notANotice(
        utf8.encode('{"dhara_update":1,"signed":"e30=","signature":5}'),
        'a signature that is no text',
      );
      notANotice(
        utf8.encode('{"dhara_update":1,"signed":"*","signature":"AQ=="}'),
        'no base64',
      );
      notANotice(
        utf8.encode('{"dhara_update":1,"signed":"","signature":"AQ=="}'),
        'nothing signed',
      );
    });

    test('nor is anything larger than a notice may be', () {
      final large = _notice(_told(notes: 'x' * maxUpdateNoticeBytes));
      expect(large.length, greaterThan(maxUpdateNoticeBytes));
      notANotice(large, 'too large');
    });
  });

  group('a notice whose signature does not fit', () {
    test('is refused whatever it says', () {
      final read = _read(_notice(_told()), fits: false);
      expect(read.notice, isNull);
      expect(read.problem, UpdateNoticeProblem.notSigned);
      // Also when what it says would not be usable anyway: the signature
      // is looked at first.
      expect(
        _read(_notice('nonsense'), fits: false).problem,
        UpdateNoticeProblem.notSigned,
      );
      expect(
        _read(_notice(_told(), kind: 99), fits: false).problem,
        UpdateNoticeProblem.notSigned,
      );
    });
  });

  group('a check that cannot be made', () {
    test('counts as a signature that does not fit', () {
      final read = readUpdateNotice(
        _notice(_told()),
        signed: (message, signature) => throw const CngException(0xC0000001),
        askedAt: _askedAt,
      );
      expect(read.notice, isNull);
      expect(read.problem, UpdateNoticeProblem.notSigned);
    });
  });

  group('with a real key (Windows)', () {
    late TestSigner signer;
    setUp(() => signer = TestSigner());
    tearDown(() => signer.close());

    List<int> signedNotice(TestSigner by, Map<String, Object?> told) {
      final message = utf8.encode(jsonEncode(told));
      return utf8.encode(
        jsonEncode({
          'dhara_update': 1,
          'signed': base64.encode(message),
          'signature': base64.encode(by.sign(message)),
        }),
      );
    }

    UpdateNoticeRead read(List<int> bytes, UpdateKey key) =>
        readUpdateNotice(bytes, signed: key.signed, askedAt: _askedAt);

    test('a notice signed with the key the app has is taken', () {
      final taken = read(signedNotice(signer, _told()), signer.key);
      expect(taken.notice!.version, const AppVersion(1, 2, 0));
    });

    test('one signed with another key is not', () {
      final other = TestSigner();
      addTearDown(other.close);
      final refused = read(signedNotice(other, _told()), signer.key);
      expect(refused.problem, UpdateNoticeProblem.notSigned);
    });

    test('nor one whose content was changed after it was signed', () {
      final outer =
          jsonDecode(utf8.decode(signedNotice(signer, _told())))
              as Map<String, Object?>;
      // The same notice, pointing at another file.
      final forged = utf8.encode(
        jsonEncode(_told(installer: 'https://files.example/download?id=other')),
      );
      final changed = utf8.encode(
        jsonEncode({...outer, 'signed': base64.encode(forged)}),
      );
      expect(read(changed, signer.key).problem, UpdateNoticeProblem.notSigned);
      // And one whose signature was cut out.
      final unsigned = utf8.encode(jsonEncode({...outer, 'signature': ''}));
      expect(read(unsigned, signer.key).problem, UpdateNoticeProblem.notSigned);
    });
  }, skip: Platform.isWindows ? false : 'Windows does the check');

  group('tool/sign-update.ps1 (Windows, PowerShell 7)', () {
    late Directory folder;
    String inFolder(String name) =>
        '${folder.path}${Platform.pathSeparator}$name';

    Future<ProcessResult> script(List<String> arguments) => Process.run(
      'pwsh',
      [
        '-NoLogo',
        '-NoProfile',
        '-NonInteractive',
        '-File',
        r'tool\sign-update.ps1',
        ...arguments,
      ],
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );

    setUp(() {
      folder = Directory.systemTemp.createTempSync('dhara-sign-');
    });
    // The key pair made for the test goes with the folder.
    tearDown(() => folder.deleteSync(recursive: true));

    test('makes a key pair, and a notice the app takes', () async {
      final made = await script(['-NewKey', inFolder('key')]);
      expect(made.exitCode, 0, reason: '${made.stdout}${made.stderr}');
      final privateFile = File(inFolder('key.private.pem'));
      final publicText = File(inFolder('key.public.txt')).readAsStringSync();
      final key = UpdateKey.from(publicText);
      expect(key, isNotNull, reason: 'the public half is what a build takes');
      // The private half is said nowhere but in its file.
      final privateBody = privateFile
          .readAsLinesSync()
          .where((line) => !line.startsWith('-----') && line.isNotEmpty)
          .join();
      expect(privateBody, isNotEmpty);
      expect('${made.stdout}${made.stderr}', isNot(contains(privateBody)));
      expect(
        '${made.stdout}${made.stderr}',
        isNot(contains(privateBody.substring(0, 24))),
      );

      final installer = File(inFolder('Dhara-Setup-9.9.9.exe'))
        ..writeAsBytesSync(List.generate(70001, (at) => (at * 7) % 256));
      final signed = await script([
        '-Installer',
        installer.path,
        '-InstallerLink',
        'https://drive.google.com/file/d/1AbCdEfGhIjKlMnOpQrStUv/view?usp=sharing',
        '-KeyFile',
        privateFile.path,
        '-Version',
        '9.9.9',
        '-Notes',
        'Faster start.',
        '-Out',
        inFolder('dhara-update.json'),
        // Nothing lies at that link; the check of it has its own test.
        '-NoCheck',
      ]);
      expect(signed.exitCode, 0, reason: '${signed.stdout}${signed.stderr}');
      expect('${signed.stdout}${signed.stderr}', isNot(contains(privateBody)));

      final bytes = File(inFolder('dhara-update.json')).readAsBytesSync();
      final read = readUpdateNotice(
        bytes,
        signed: key!.signed,
        // Where the app would have asked: the same place, another file.
        askedAt: Uri.parse(
          'https://drive.usercontent.google.com/download?id=notice',
        ),
      );
      expect(read.problem, isNull);
      final notice = read.notice!;
      expect(notice.version, const AppVersion(9, 9, 9));
      expect(
        notice.installer,
        Uri.parse(
          'https://drive.usercontent.google.com/download'
          '?id=1AbCdEfGhIjKlMnOpQrStUv&export=download&confirm=t',
        ),
      );
      expect(notice.size, 70001);
      expect(notice.sha256, hexOf(sha256Of(installer.readAsBytesSync())));
      expect(notice.notes, 'Faster start.');

      // Another key pair's public half does not take it.
      final other = TestSigner();
      addTearDown(other.close);
      expect(
        readUpdateNotice(
          bytes,
          signed: other.key.signed,
          askedAt: Uri.parse('https://drive.usercontent.google.com/x'),
        ).problem,
        UpdateNoticeProblem.notSigned,
      );
    });

    test('keeps a key out of the repository and never replaces one', () async {
      final inside = await script(['-NewKey', r'dist\update-key']);
      expect(inside.exitCode, 1);
      expect(inside.stdout, contains('outside this repository'));
      expect(File(r'dist\update-key.private.pem').existsSync(), isFalse);

      expect((await script(['-NewKey', inFolder('key')])).exitCode, 0);
      final before = File(inFolder('key.private.pem')).readAsStringSync();
      final again = await script(['-NewKey', inFolder('key')]);
      expect(again.exitCode, 1);
      expect(again.stdout, contains('is there already'));
      expect(File(inFolder('key.private.pem')).readAsStringSync(), before);
    });

    test('signs nothing it should not', () async {
      expect((await script(['-NewKey', inFolder('key')])).exitCode, 0);
      final installer = File(inFolder('setup.exe'))..writeAsBytesSync([1, 2]);
      Future<ProcessResult> sign({
        String link = 'https://files.example/setup.exe',
        String? keyFile,
        String version = '1.2.3',
        bool check = false,
      }) => script([
        '-Installer',
        installer.path,
        '-InstallerLink',
        link,
        '-KeyFile',
        keyFile ?? inFolder('key.private.pem'),
        '-Version',
        version,
        '-Out',
        inFolder('out.json'),
        if (!check) '-NoCheck',
      ]);

      for (final refused in [
        await sign(link: 'http://files.example/setup.exe'),
        await sign(link: 'https://drive.google.com/drive/folders/abc'),
        await sign(version: '1.2'),
        // The public half signs nothing.
        await sign(keyFile: inFolder('key.public.txt')),
      ]) {
        expect(refused.exitCode, 1, reason: '${refused.stdout}');
      }
      expect(File(inFolder('out.json')).existsSync(), isFalse);

      // Unless told not to, it first fetches what lies at the link, and
      // signs nothing if that is not the installer: here nothing answers
      // there at all (an address of this PC that nothing listens at).
      final unchecked = await sign(
        link: 'https://127.0.0.1:1/setup.exe',
        check: true,
      );
      expect(unchecked.exitCode, 1, reason: '${unchecked.stdout}');
      expect(unchecked.stdout, contains('could not be fetched'));
      expect(unchecked.stdout, contains('Nothing was signed'));
      expect(File(inFolder('out.json')).existsSync(), isFalse);

      expect((await sign()).exitCode, 0);
    });
  }, skip: _hasPwsh ? false : 'needs Windows with PowerShell 7');
}

/// Whether PowerShell 7 can be started on this PC.
final bool _hasPwsh = () {
  if (!Platform.isWindows) return false;
  try {
    return Process.runSync('pwsh', const ['-NoLogo', '-Version']).exitCode == 0;
  } on ProcessException {
    return false;
  }
}();
