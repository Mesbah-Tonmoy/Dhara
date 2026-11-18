import 'package:dhara/features/player/secure_player.dart';
import 'package:flutter_test/flutter_test.dart';

/// Read-back values of a correctly hardened player.
Map<String, String> hardenedValues() => {
      'config': 'no',
      'ytdl': 'no',
      'load-scripts': 'no',
      'osc': 'no',
      'curl-enabled': 'no',
      'load-unsafe-playlists': 'no',
      'autoload-files': 'no',
      'sub-auto': 'no',
      'audio-file-auto': 'no',
      'cover-art-auto': 'no',
      'stream-lavf-o':
          'protocol_whitelist=http,https,tcp,tls,crypto,max_redirects=0',
      'demuxer-lavf-o': 'protocol_whitelist=http,https,tcp,tls,crypto',
    };

void main() {
  test('protocol whitelist is exactly the one from the brief', () {
    expect(allowedPlayerProtocols, ['http', 'https', 'tcp', 'tls', 'crypto']);
  });

  test('hardened options cover the must-haves from the brief', () {
    expect(hardenedMpvOptions['ytdl'], 'no');
    expect(hardenedMpvOptions['load-scripts'], 'no');
    expect(hardenedMpvOptions['osc'], 'no');
    expect(hardenedMpvOptions['curl-enabled'], 'no');
    expect(hardenedMpvOptions['load-unsafe-playlists'], 'no');
    expect(
      hardenedMpvOptions['stream-lavf-o'],
      'protocol_whitelist=[http,https,tcp,tls,crypto],max_redirects=0',
    );
    expect(
      hardenedMpvOptions['demuxer-lavf-o'],
      'protocol_whitelist=[http,https,tcp,tls,crypto]',
    );
    // `config` cannot be set after init; it must still be verified.
    expect(requiredMpvValues['config'], {'no'});
  });

  test('every option that is set is also verified', () {
    expect(requiredMpvValues.keys, containsAll(hardenedMpvOptions.keys));
  });

  group('findHardeningViolations', () {
    test('accepts a fully hardened player', () {
      expect(findHardeningViolations(hardenedValues()), isEmpty);
    });

    test('accepts a libmpv build without the ytdl option', () {
      expect(
        findHardeningViolations(hardenedValues()..['ytdl'] = ''),
        isEmpty,
      );
    });

    const unsafe = <String, String>{
      'config': 'yes',
      'ytdl': 'yes',
      'load-scripts': 'yes',
      'osc': 'yes',
      'curl-enabled': 'yes',
      'load-unsafe-playlists': 'yes',
      'autoload-files': 'yes',
      'sub-auto': 'exact',
      'audio-file-auto': 'fuzzy',
      'cover-art-auto': 'exact',
      'stream-lavf-o': '',
      'demuxer-lavf-o':
          'allowed_extensions=ALL,protocol_whitelist=http,https,tcp,tls,crypto,file',
    };

    for (final entry in unsafe.entries) {
      test('flags ${entry.key} = "${entry.value}"', () {
        final violations = findHardeningViolations(
          hardenedValues()..[entry.key] = entry.value,
        );
        expect(violations, hasLength(1));
        expect(violations.single, startsWith(entry.key));
      });
    }

    test('flags an option that was never read back', () {
      final violations = findHardeningViolations(
        hardenedValues()..remove('load-scripts'),
      );
      expect(violations, ['load-scripts was not checked']);
    });

    test('an empty value only passes for what a build may not have', () {
      // The yt-dlp hook and mpv's on-screen controls (builds without Lua),
      // and the libcurl stream (builds without libcurl).
      const mayBeAbsent = {'ytdl', 'osc', 'curl-enabled'};
      final actual = {for (final name in requiredMpvValues.keys) name: ''};
      final violations = findHardeningViolations(actual);
      expect(
        violations,
        hasLength(requiredMpvValues.length - mayBeAbsent.length),
      );
      for (final name in mayBeAbsent) {
        expect(violations.any((v) => v.startsWith('$name ')), isFalse);
      }
    });

    test('a script of mpv\'s own must be off, whatever it is called', () {
      expect(isScriptSwitch('load-stats-overlay'), isTrue);
      expect(isScriptSwitch('load-something-new'), isTrue);
      expect(isScriptSwitch('ytdl'), isFalse);
      expect(
        findHardeningViolations(
          hardenedValues()
            ..['load-stats-overlay'] = 'no'
            ..['load-something-new'] = 'no',
        ),
        isEmpty,
      );
      for (final left in ['yes', 'auto', '']) {
        expect(
          findHardeningViolations(
            hardenedValues()..['load-something-new'] = left,
          ),
          ['load-something-new is "$left"'],
        );
      }
    });
  });
}
