import 'package:dhara/core/settings/key_value_store.dart';
import 'package:dhara/features/sources/adapters/emby_adapter.dart';
import 'package:dhara/features/sources/device_id.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('makes up a valid id once and keeps it', () {
    final store = MemoryKeyValueStore();

    final first = loadOrCreateDeviceId(store);
    final second = loadOrCreateDeviceId(store);

    expect(first, matches(RegExp(r'^dhara-[0-9a-f]{16}$')));
    expect(isValidDeviceId(first), isTrue);
    expect(second, first);
  });

  test('different installations get different ids', () {
    final ids = {
      for (var i = 0; i < 20; i++) loadOrCreateDeviceId(MemoryKeyValueStore()),
    };

    expect(ids, hasLength(20));
  });

  test('replaces a saved id that could not go into a header', () {
    final store = MemoryKeyValueStore({'sources.deviceId': 'pc", Token="x'});

    final id = loadOrCreateDeviceId(store);

    expect(isValidDeviceId(id), isTrue);
    expect(store.getString('sources.deviceId'), id);
  });
}
