import 'dart:io';

import 'package:dhara/core/secrets/secret_store.dart';
import 'package:dhara/core/secrets/windows_credential_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:win32/win32.dart';

void main() {
  test('isSecretName takes short lower-case names only', () {
    for (final name in ['tmdb', 'a', 'api-key_2.v1', 'x' * 64]) {
      expect(isSecretName(name), isTrue, reason: name);
    }
    for (final name in ['', 'TMDB', 'a b', 'a/b', r'a\b', 'x' * 65, 'ключ']) {
      expect(isSecretName(name), isFalse, reason: name);
    }
  });

  group('MemorySecretStore', () {
    test('keeps, replaces and removes secrets, for this run only', () async {
      final store = MemorySecretStore();
      expect(store.keepsSecrets, isFalse);
      expect(await store.read('tmdb'), isNull);

      await store.write('tmdb', 'first');
      await store.write('tmdb', 'second');
      await store.write('other', 'third');
      expect(await store.read('tmdb'), 'second');

      await store.delete('tmdb');
      await store.delete('tmdb');
      expect(await store.read('tmdb'), isNull);
      expect(await store.read('other'), 'third');
      expect(await MemorySecretStore().read('other'), isNull);
    });

    test('refuses a name that is not one', () {
      expect(
        () => MemorySecretStore().write('a/b', 'x'),
        throwsA(isA<SecretStoreException>()),
      );
    });
  });

  group('BuiltInSecretStore', () {
    const store = BuiltInSecretStore('tmdb', 'the key of the build');

    test('holds the one secret the build was made with', () async {
      expect(store.keepsSecrets, isTrue);
      expect(await store.read('tmdb'), 'the key of the build');
      expect(await store.read('other'), isNull);
    });

    test('cannot be written to or emptied', () async {
      await expectLater(
        store.write('tmdb', 'another'),
        throwsA(isA<SecretStoreException>()),
      );
      await expectLater(
        store.delete('tmdb'),
        throwsA(isA<SecretStoreException>()),
      );
      expect(await store.read('tmdb'), 'the key of the build');
      // What it says of itself never names the key.
      try {
        await store.write('tmdb', 'another');
      } on SecretStoreException catch (error) {
        expect('$error', isNot(contains('the key of the build')));
      }
    });
  });

  // Writes real entries to the Credential Manager of whoever runs the
  // tests, under a name of their own, and removes them again.
  group('WindowsCredentialStore', () {
    final store = WindowsCredentialStore(
      prefix: 'DharaTest-$pid-${DateTime.now().microsecondsSinceEpoch}',
    );

    tearDown(() async {
      await store.delete('tmdb');
      await store.delete('other');
    });

    test('keeps a secret, replaces it and removes it', () async {
      expect(store.keepsSecrets, isTrue);
      expect(await store.read('tmdb'), isNull);

      await store.write('tmdb', 'first secret');
      expect(await store.read('tmdb'), 'first secret');

      await store.write('tmdb', 'second');
      await store.write('other', 'third');
      expect(await store.read('tmdb'), 'second');
      expect(await store.read('other'), 'third');

      await store.delete('tmdb');
      expect(await store.read('tmdb'), isNull);
      expect(await store.read('other'), 'third');
      // Removing what is not there is not an error.
      await store.delete('tmdb');
    });

    test('is read by another store with the same prefix only', () async {
      await store.write('tmdb', 'kept by Windows');

      expect(
        await WindowsCredentialStore(prefix: store.prefix).read('tmdb'),
        'kept by Windows',
      );
      expect(
        await WindowsCredentialStore(prefix: '${store.prefix}x').read('tmdb'),
        isNull,
      );
    });

    test('keeps every character and the longest secret allowed', () async {
      const odd = 'eyJ.টোকেন.ключ 🔑 "quotes" \\ / \n end';
      await store.write('tmdb', odd);
      expect(await store.read('tmdb'), odd);

      final long = 'k' * maxSecretBytes;
      await store.write('tmdb', long);
      expect(await store.read('tmdb'), long);
    });

    test('refuses what it cannot keep, without saying the secret', () async {
      await store.write('tmdb', 'stays');
      final tooLong = 'SECRET' * 400;

      for (final write in [
        () => store.write('tmdb', ''),
        () => store.write('tmdb', tooLong),
        () => store.write('a/b', 'x'),
        () => store.write('', 'x'),
      ]) {
        await expectLater(
          write,
          throwsA(
            isA<SecretStoreException>().having(
              (error) => '$error',
              'text',
              isNot(contains('SECRET')),
            ),
          ),
        );
      }
      expect(() => store.read('A B'), throwsA(isA<SecretStoreException>()));
      expect(() => store.delete('../x'), throwsA(isA<SecretStoreException>()));
      expect(await store.read('tmdb'), 'stays');
    });
  }, skip: Platform.isWindows ? null : 'Windows only');

  group('withErrorCode', () {
    const done = Win32Result(value: true, error: ERROR_SUCCESS);
    const notFound = Win32Result(value: false, error: ERROR_NOT_FOUND);
    // The call failed, and the reason was wiped before it could be read.
    const lost = Win32Result(value: false, error: ERROR_SUCCESS);

    (Win32Result<bool>, int) run(List<Win32Result<bool>> answers) {
      var calls = 0;
      final result = withErrorCode(() => answers[calls++]);
      return (result, calls);
    }

    test('makes a call that works, or fails with a reason, once', () {
      expect(run([done, lost]), (done, 1));
      expect(run([notFound, done]), (notFound, 1));
    });

    test('makes a call again whose reason for failing was lost', () {
      expect(run([lost, notFound]), (notFound, 2));
      expect(run([lost, lost, done]), (done, 3));
    });

    test('gives up after three calls', () {
      expect(run([lost, lost, lost, done]), (lost, 3));
    });
  });
}
