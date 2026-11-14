import 'package:dhara/core/secrets/secret_store.dart';
import 'package:dhara/features/metadata/tmdb_key.dart';
import 'package:flutter_test/flutter_test.dart';

/// Shaped like TMDB's, made up.
final _token = 'eyJhbGciOiJIUzI1NiJ9.${'a' * 120}.${'b' * 43}';
const _apiKey = '0123456789abcdef0123456789ABCDEF';

/// A secure storage that is out of order.
class _BrokenStore implements SecretStore {
  @override
  bool get keepsSecrets => true;

  @override
  Future<String?> read(String name) =>
      throw const SecretStoreException('broken');

  @override
  Future<void> write(String name, String value) =>
      throw const SecretStoreException('broken');

  @override
  Future<void> delete(String name) =>
      throw const SecretStoreException('broken');
}

void main() {
  test('tmdbKeyKindOf tells a token from an API key by their shape', () {
    expect(tmdbKeyKindOf(_token), TmdbKeyKind.accessToken);
    expect(tmdbKeyKindOf(_apiKey), TmdbKeyKind.apiKey);
    for (final text in [
      '',
      'hello',
      _apiKey.substring(1),
      '${_apiKey}0',
      _apiKey.replaceFirst('0', 'g'),
      'Bearer $_token',
      _token.replaceFirst('.', ''),
      '$_token.more',
      _token.replaceFirst('eyJ', 'abc'),
      'eyJ.a.b',
      '${_token}x' * 12,
      ' $_token',
      '$_token\n',
    ]) {
      expect(tmdbKeyKindOf(text), isNull, reason: text);
    }
  });

  group('TmdbKeyController', () {
    late MemorySecretStore store;
    late TmdbKeyController controller;
    late int changes;

    setUp(() {
      store = MemorySecretStore();
      controller = TmdbKeyController(store)..addListener(() => changes++);
      changes = 0;
    });

    tearDown(() => controller.dispose());

    test('starts without a key', () async {
      expect(controller.isLoaded, isFalse);

      await controller.load();

      expect(controller.isLoaded, isTrue);
      expect(controller.hasKey, isFalse);
      expect(controller.kind, isNull);
      expect(controller.unreadable, isFalse);
      expect(controller.keptAfterRestart, isFalse);
      expect(await controller.key(), isNull);
      expect(changes, 1);
    });

    test('finds a key saved earlier', () async {
      await store.write(TmdbKeyController.secretName, _apiKey);

      await controller.load();

      expect(controller.kind, TmdbKeyKind.apiKey);
      expect(await controller.key(), _apiKey);
    });

    test('saves what was entered, without the space around it', () async {
      await controller.load();

      expect(await controller.save('  $_token \n'), isNull);

      expect(controller.kind, TmdbKeyKind.accessToken);
      expect(await store.read('tmdb'), _token);
      expect(await controller.key(), _token);
      expect(changes, 2);
    });

    test('replaces a key with another', () async {
      await controller.load();
      await controller.save(_apiKey);

      expect(await controller.save(_token), isNull);

      expect(controller.kind, TmdbKeyKind.accessToken);
      expect(await controller.key(), _token);
    });

    test('refuses what is not a key and keeps the one it has', () async {
      await controller.load();
      await controller.save(_apiKey);
      changes = 0;

      expect(await controller.save('not a key'), TmdbKeyProblem.notAKey);
      expect(await controller.save(''), TmdbKeyProblem.notAKey);

      expect(await controller.key(), _apiKey);
      expect(changes, 0);
    });

    test('removes the key', () async {
      await controller.load();
      await controller.save(_apiKey);

      expect(await controller.remove(), isNull);

      expect(controller.hasKey, isFalse);
      expect(await store.read('tmdb'), isNull);
      expect(await controller.key(), isNull);
      // Removing nothing is fine too.
      expect(await controller.remove(), isNull);
    });

    test('treats a saved value of another shape as no key', () async {
      await store.write('tmdb', 'edited by hand');

      await controller.load();

      expect(controller.hasKey, isFalse);
      expect(await controller.key(), isNull);
    });

    test('notices a key that was removed behind its back', () async {
      await controller.load();
      await controller.save(_apiKey);
      changes = 0;

      await store.delete('tmdb');
      expect(await controller.key(), isNull);

      expect(controller.hasKey, isFalse);
      expect(changes, 1);
    });

    test('says so when the secure storage is out of order', () async {
      final broken = TmdbKeyController(_BrokenStore());
      addTearDown(broken.dispose);

      await broken.load();
      expect(broken.isLoaded, isTrue);
      expect(broken.unreadable, isTrue);
      expect(broken.hasKey, isFalse);
      expect(await broken.key(), isNull);

      expect(await broken.save(_token), TmdbKeyProblem.storage);
      expect(await broken.remove(), TmdbKeyProblem.storage);
      expect(broken.hasKey, isFalse);
    });
  });
}
