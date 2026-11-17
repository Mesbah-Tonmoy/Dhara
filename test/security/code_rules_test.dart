import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Rules of BRIEF section 7 that can be read off the source: each test
/// fails when code that breaks one is added, and names the file and line.
///
/// They look at the code as text, so they prove that something is absent,
/// not that what is there behaves. What the code does is checked by the
/// tests next to it (`safe_http_client_test.dart`, `secure_player_test.dart`
/// and the others listed in `docs/security-review.md`).
void main() {
  final lib = _dartFiles('lib');
  final runner = [
    for (final file in Directory('windows/runner').listSync(recursive: true))
      if (file is File && RegExp(r'\.(cpp|h|rc|manifest)$').hasMatch(file.path))
        _Source(_slashes(file.path), file.readAsLinesSync()),
  ];

  test('there is code to look at', () {
    expect(lib.length, greaterThan(100));
    expect(runner.length, greaterThan(5));
  });

  group('network', () {
    test('only SafeHttpClient opens a connection', () {
      expect(
        _hits(lib, RegExp(r'\bHttpClient\(')).map((hit) => hit.file).toSet(),
        {'lib/core/net/safe_http_client.dart'},
      );
      expect(
        _hits(
          lib,
          RegExp(
            r'\b(RawSocket|SecureSocket|RawSecureSocket|ServerSocket|'
            r'RawServerSocket|RawDatagramSocket|WebSocket|HttpServer)\b|'
            r'\bSocket\.(connect|startConnect)\b|'
            r'''['"](package:http/|package:dio/|dart:html|dart:js)''',
          ),
        ),
        isEmpty,
      );
    });

    test('no certificate check is switched off and no proxy is read', () {
      expect(
        _hits(
          lib,
          RegExp(
            r'badCertificateCallback|SecurityContext\(|findProxy|'
            r'Platform\.environment|HttpOverrides',
          ),
        ),
        isEmpty,
      );
    });

    test('no address of another scheme is written into the code', () {
      expect(
        _hits(
          lib,
          RegExp(
            r'''Uri\.file\(|Uri\.directory\(|['"](file|ftp|smb|data|'''
            r'''javascript|rtmp|rtsp|udp|edl|memory|av|lavf)://?''',
          ),
        ),
        isEmpty,
      );
    });

    test('the only hosts named in the code are TMDB and AniList', () {
      final named = <String>{
        for (final hit in _hits(
          lib,
          RegExp(
            r'''['"/]((?:[a-z0-9-]+\.)+(?:org|co|com|net|io|app|dev|tv|me|'''
            r'''xyz|info|bd))['"/:]''',
          ),
        ))
          hit.match.group(1)!,
      };
      expect(named, {
        'api.themoviedb.org',
        'image.tmdb.org',
        'graphql.anilist.co',
        's4.anilist.co',
      });
    });
  });

  group('untrusted input', () {
    test('nothing renders a page or runs a script', () {
      expect(
        _hits(
          lib,
          RegExp(
            r'webview|WebView|HtmlElementView|InAppBrowser|dart:ui_web|'
            r'dart:js_interop|package:flutter_html|package:url_launcher|'
            r'launchUrl|dart:mirrors|Isolate\.spawnUri',
          ),
        ),
        isEmpty,
      );
    });

    test('nothing starts a program or opens a file with one', () {
      expect(
        _hits(
          lib,
          RegExp(
            r'\bProcess\.(run|runSync|start|killPid)\b|ShellExecute|'
            r'CreateProcess|WinExec|OpenFile\.open|package:process',
          ),
        ),
        isEmpty,
      );
    });

    test(
      'server pages are parsed by package:html only where they are read',
      () {
        expect(
          _hits(
            lib,
            RegExp(r'''['"]package:html/'''),
          ).map((h) => h.file).toSet(),
          {
            'lib/features/sources/adapters/directory_listing_adapter.dart',
            'lib/features/sources/adapters/h5ai_adapter.dart',
            'lib/features/sources/adapters/listing_parser.dart',
            'lib/features/sources/portal_links.dart',
            'lib/features/sources/source_tester.dart',
          },
        );
      },
    );
  });

  group('database', () {
    // What may be spliced into the text of a statement: parts written in
    // the code itself. Everything that comes from a server, a file name or
    // the user goes in as a `?` parameter.
    final allowed = [
      RegExp(r'^_placeholders\(\w+(\.\w+)?( \+ 1)?\)$'),
      RegExp(r"^List\.filled\(\w+\.length, '\?'\)\.join\(', '\)$"),
      RegExp(
        r'^(_columns|_shown|HomeStore\.cardColumns|HomeStore\.shownOnly|'
        r'onSources|rated|from|order|pageCacheKb)$',
      ),
      RegExp(r"^where\.join\(' AND '\)$"),
      RegExp(
        r'^(only == null|withOverview|whateverItsState|countOnly|'
        r'minHeight == null) \? ',
      ),
    ];
    final statement = RegExp(
      r'''['"].*\b(SELECT|INSERT|UPDATE|DELETE|WHERE|FROM|ORDER BY|'''
      r'''GROUP BY|VALUES|MATCH|LIMIT|AND|OR|IN|JOIN|SET|PRAGMA|CREATE|'''
      r'''DROP|ALTER)\b''',
    );
    final spliced = RegExp(r'\$\{([^}]*)\}|\$([A-Za-z_][\w.]*)');

    test('no statement is put together from anything but code', () {
      final stores = lib.where(
        (file) => file.lines.any(
          (line) => RegExp(r'\b(select|execute|prepare)\(').hasMatch(line),
        ),
      );
      expect(stores.length, greaterThan(8));
      final strangers = <String>[];
      for (final file in stores) {
        for (final (index, line) in file.lines.indexed) {
          if (!statement.hasMatch(line)) continue;
          // What stands inside `${...}` is judged as a whole.
          final outside = line.replaceAll(RegExp(r'\$\{[^}]*\}'), '');
          final parts = [
            for (final match in RegExp(r'\$\{([^}]*)\}').allMatches(line))
              match[1]!,
            for (final match in spliced.allMatches(outside))
              if (match[2] != null) match[2]!,
          ];
          for (final part in parts) {
            if (!allowed.any((pattern) => pattern.hasMatch(part))) {
              strangers.add('${file.path}:${index + 1}: $part');
            }
          }
        }
      }
      expect(
        strangers,
        isEmpty,
        reason:
            'Give the value to the statement as a parameter (?). If it is '
            'text written in the code, add it to the list above.',
      );
    });
  });

  group('player', () {
    test('a player is only made where it is hardened', () {
      expect(_hits(lib, RegExp(r'\bPlayer\(')).map((hit) => hit.file).toSet(), {
        'lib/features/player/secure_player.dart',
      });
    });

    test('no mpv command that runs or loads something is used', () {
      expect(
        _hits(
          lib,
          RegExp(
            r'''['"](run|subprocess|load-script|loadlist|script-message|'''
            r'''script-message-to|script-binding|load-config-file|'''
            r'''screenshot-to-file|dump-cache|write-watch-later-config|'''
            r'''ab-loop-dump-cache)['"]''',
          ),
        ),
        isEmpty,
      );
    });
  });

  group('files', () {
    test('only these files reach the file system', () {
      expect(
        _hits(lib, RegExp(r'''['"]dart:io['"]''')).map((h) => h.file).toSet(),
        {
          'lib/core/db/library_isolate.dart',
          'lib/core/images/image_store.dart',
          'lib/core/images/remote_image.dart',
          'lib/core/net/safe_http_client.dart',
          'lib/features/metadata/anilist_client.dart',
          'lib/features/metadata/tmdb_client.dart',
          'lib/features/player/subtitle_file.dart',
          'lib/features/sources/source_store.dart',
          'lib/features/sources/source_test_controller.dart',
          'lib/features/sources/ui/server_discovery_screen.dart',
          'lib/features/sources/ui/source_list_files.dart',
          'lib/main.dart',
        },
        reason:
            'A new file that imports dart:io can read and write files: look '
            'at what it does with names that come from a server, then add '
            'it here.',
      );
    });

    test('native code is called for the TMDB key only', () {
      expect(
        _hits(
          lib,
          RegExp(r'''['"](dart:ffi|package:ffi/|package:win32/)'''),
        ).map((hit) => hit.file).toSet(),
        {'lib/core/secrets/windows_credential_store.dart'},
      );
    });
  });

  group('privacy', () {
    test('nothing is logged, printed or reported', () {
      expect(
        _hits(
          lib,
          RegExp(
            r'\bprint\(|\bdebugPrint\(|debugPrintStack|dart:developer|'
            r'\bstdout\b|\bstderr\b|'
            r'package:[a-z_]*(logging|logger|sentry|firebase|crashlytics|'
            r'analytics|telemetry)',
          ),
        ),
        isEmpty,
      );
    });
  });

  group('the data folder', () {
    test('keeps its name: it is the company and product name of the '
        'program', () {
      // path_provider reads the two from the program's version resource,
      // so "%APPDATA%\com.dhara\dhara" follows them. A new name would
      // leave the library, the settings and the sources of an installed
      // app behind.
      final resource = runner
          .singleWhere((file) => file.path.endsWith('Runner.rc'))
          .lines
          .join('\n');
      expect(resource, contains('VALUE "CompanyName", "com.dhara"'));
      expect(resource, contains('VALUE "ProductName", "dhara"'));
    });
  });

  group('least privilege (Windows runner)', () {
    test('the app runs as the user who started it', () {
      final manifest = runner.singleWhere(
        (file) => file.path.endsWith('runner.exe.manifest'),
      );
      // The manifest asks for nothing, so the linker writes its default
      // into the program: asInvoker, no uiAccess.
      expect(
        manifest.lines.join('\n'),
        isNot(
          anyOf(
            contains('requireAdministrator'),
            contains('highestAvailable'),
            contains('uiAccess="true"'),
          ),
        ),
      );

      // Where a build exists, read what the program really carries.
      for (final build in const ['Release', 'Profile', 'Debug']) {
        final exe = File('build/windows/x64/runner/$build/dhara.exe');
        if (!exe.existsSync()) continue;
        final levels = RegExp(r'requestedExecutionLevel\s+level="([^"]*)"')
            .allMatches(String.fromCharCodes(exe.readAsBytesSync()))
            .map((match) => match[1])
            .toSet();
        expect(levels, {'asInvoker'}, reason: '$build build');
      }
    });

    test('the runner writes no registry key, starts nothing and installs no '
        'service', () {
      expect(
        _hits(
          runner,
          RegExp(
            r'RegSetValue|RegCreateKey|RegSetKeyValue|CreateService|'
            r'OpenSCManager|ShellExecute|WinExec|CreateProcess|'
            r'URLDownloadToFile|WinHttp|InternetOpen|schtasks|'
            r'CurrentVersion\\\\Run',
          ),
        ),
        isEmpty,
      );
    });
  });

  group('least privilege (installer)', () {
    final script = [
      for (final line in File('installer/dhara.iss').readAsLinesSync())
        if (!line.trimLeft().startsWith(';')) line,
    ].join('\n');

    test('installs for the user who runs it, and cannot ask for more', () {
      expect(script, contains('PrivilegesRequired=lowest'));
      expect(script, isNot(contains('PrivilegesRequiredOverridesAllowed')));
      expect(script, contains(r'DefaultDirName={autopf}\'));
      // Places only an administrator can write to.
      expect(
        RegExp(
          r'\{(commonpf|commonpf32|commonpf64|commoncf|win|sys|sysnative|'
          r'commonappdata|commonprograms|commonstartmenu|commondesktop|'
          r'commonstartup)\}',
          caseSensitive: false,
        ).allMatches(script),
        isEmpty,
      );
    });

    test('adds no service, start-up entry, task, registry key or download', () {
      expect(
        RegExp(
          r'^\[(Registry|INI|Code|UninstallRun)\]|'
          r'\{(userstartup|commonstartup|autostartup)\}|'
          r'CurrentVersion\\Run|schtasks|sc\.exe|\bsc create\b|'
          r'https?://|DownloadTemporaryFile|runascurrentuser|runasoriginaluser',
          caseSensitive: false,
          multiLine: true,
        ).allMatches(script).map((match) => match[0]),
        isEmpty,
      );
    });

    test('runs nothing but the app itself, and only when asked', () {
      final run = script.split('[Run]').last;
      final entries = [
        for (final line in run.split('\n'))
          if (line.startsWith('Filename:')) line,
      ];
      expect(entries, hasLength(1));
      expect(entries.single, contains(r'Filename: "{app}\dhara.exe"'));
      expect(entries.single, contains('postinstall'));
      expect(entries.single, contains('skipifsilent'));
    });
  });

  group('supply chain', () {
    final pubspec = File('pubspec.yaml').readAsLinesSync();

    Map<String, String> section(String name) {
      final entries = <String, String>{};
      var inside = false;
      for (final line in pubspec) {
        if (RegExp(r'^\S').hasMatch(line)) inside = line.startsWith('$name:');
        final entry = RegExp(r'^  ([a-z0-9_]+):\s*(.*)$').firstMatch(line);
        if (inside && entry != null) entries[entry[1]!] = entry[2]!.trim();
      }
      return entries;
    }

    test('the packages are the ones that were looked at', () {
      expect(section('dependencies').keys.toSet(), {
        'ffi',
        'file_selector',
        'flutter',
        'html',
        'media_kit',
        'media_kit_libs_windows_video',
        'media_kit_video',
        'path_provider_platform_interface',
        'shared_preferences',
        'sqlite3',
        'win32',
      });
      expect(section('dev_dependencies').keys.toSet(), {
        'flutter_test',
        'flutter_lints',
      });
    });

    test('every package is pinned to one version', () {
      final all = {...section('dependencies'), ...section('dev_dependencies')};
      for (final MapEntry(key: name, value: version) in all.entries) {
        if (name == 'flutter' || name == 'flutter_test') continue;
        expect(
          version,
          matches(RegExp(r'^\d+\.\d+\.\d+(\+\d+)?$')),
          reason: '$name must name one exact version',
        );
      }
      expect(
        pubspec.where((line) => RegExp(r'^\s+(git|path|url):').hasMatch(line)),
        isEmpty,
        reason: 'packages come from pub.dev only',
      );
    });

    test('the lock file names a checksum for every package from pub.dev', () {
      final lock = File('pubspec.lock').readAsStringSync();
      final hosted = RegExp(r'source: hosted').allMatches(lock).length;
      final hashed = RegExp(
        r'sha256: "?[0-9a-f]{64}"?',
      ).allMatches(lock).length;
      expect(hosted, greaterThan(20));
      expect(hashed, hosted);
      expect(lock, isNot(contains('source: git')));
    });
  });
}

/// One source file, without its comment lines.
class _Source {
  _Source(this.path, List<String> raw)
    : lines = [
        for (final line in raw)
          RegExp(r'^\s*(//|\*|/\*|<!--)').hasMatch(line) ? '' : line,
      ];

  final String path;
  final List<String> lines;
}

class _Hit {
  const _Hit(this.file, this.line, this.match);

  final String file;
  final int line;
  final RegExpMatch match;

  @override
  String toString() => '$file:$line: ${match.input.trim()}';
}

String _slashes(String path) => path.replaceAll(r'\', '/');

List<_Source> _dartFiles(String folder) => [
  for (final file in Directory(folder).listSync(recursive: true))
    if (file is File && file.path.endsWith('.dart'))
      _Source(_slashes(file.path), file.readAsLinesSync()),
];

List<_Hit> _hits(List<_Source> files, RegExp pattern) => [
  for (final file in files)
    for (final (index, line) in file.lines.indexed)
      for (final match in pattern.allMatches(line))
        _Hit(file.path, index + 1, match),
];
