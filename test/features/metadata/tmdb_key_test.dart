import 'dart:async';
import 'dart:io';

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

  test('the key a production build carries is there, and stays', () async {
    final controller = TmdbKeyController(
      const BuiltInSecretStore(TmdbKeyController.secretName, _apiKey),
      check: (_, _) async => TmdbKeyCheck.accepted,
    );
    await controller.load();

    expect(controller.hasKey, isTrue);
    expect(controller.kind, TmdbKeyKind.apiKey);
    expect(controller.keptAfterRestart, isTrue);
    expect(await controller.key(), _apiKey);
    // Nobody can replace or remove it.
    expect(await controller.save(_token), TmdbKeyProblem.storage);
    expect(await controller.remove(), TmdbKeyProblem.storage);
    expect(await controller.key(), _apiKey);
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

    group('test', () {
      late List<(String, TmdbKeyKind)> asked;
      late TmdbKeyCheck answer;

      TmdbKeyController checking({TmdbKeyChecker? check}) {
        final made = TmdbKeyController(
          store,
          check:
              check ??
              (key, kind) async {
                asked.add((key, kind));
                return answer;
              },
        );
        addTearDown(made.dispose);
        return made;
      }

      setUp(() {
        asked = [];
        answer = TmdbKeyCheck.accepted;
      });

      test('asks TMDB about the saved key and keeps the answer', () async {
        final keys = checking();
        await keys.load();
        await keys.save(_token);
        expect(keys.lastCheck, isNull);

        final states = <bool>[];
        keys.addListener(() => states.add(keys.isChecking));
        expect(await keys.test(), TmdbKeyCheck.accepted);

        expect(asked, [(_token, TmdbKeyKind.accessToken)]);
        expect(keys.lastCheck, TmdbKeyCheck.accepted);
        expect(keys.isChecking, isFalse);
        expect(states, [true, false]);

        answer = TmdbKeyCheck.refused;
        expect(await keys.test(), TmdbKeyCheck.refused);
        expect(keys.lastCheck, TmdbKeyCheck.refused);
      });

      test('has nothing to ask without a key', () async {
        final keys = checking();
        await keys.load();

        expect(await keys.test(), isNull);

        expect(asked, isEmpty);
        expect(keys.lastCheck, isNull);
        expect(keys.isChecking, isFalse);
      });

      test('counts a check that breaks down as not reached', () async {
        final keys = checking(
          check: (key, kind) => throw const SocketException('offline'),
        );
        await keys.load();
        await keys.save(_apiKey);

        expect(await keys.test(), TmdbKeyCheck.unreachable);
        expect(keys.lastCheck, TmdbKeyCheck.unreachable);
      });

      test('forgets the answer when the key changes or goes', () async {
        final keys = checking();
        await keys.load();
        await keys.save(_token);
        await keys.test();

        await keys.save(_apiKey);
        expect(keys.lastCheck, isNull);

        await keys.test();
        await keys.remove();
        expect(keys.lastCheck, isNull);
      });

      test('drops an answer that is about a key since replaced', () async {
        final slow = Completer<TmdbKeyCheck>();
        final keys = checking(check: (key, kind) => slow.future);
        await keys.load();
        await keys.save(_token);

        final old = keys.test();
        await pumpEventQueue();
        expect(keys.isChecking, isTrue);
        await keys.save(_apiKey);
        expect(keys.isChecking, isFalse);
        slow.complete(TmdbKeyCheck.refused);
        await old;

        expect(keys.lastCheck, isNull);
        expect(keys.isChecking, isFalse);
      });
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
