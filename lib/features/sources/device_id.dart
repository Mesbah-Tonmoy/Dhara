import 'dart:async';
import 'dart:math';

import 'package:dhara/core/settings/key_value_store.dart';
import 'package:dhara/features/sources/adapters/emby_adapter.dart';

const _key = 'sources.deviceId';

/// The id this installation gives Emby/Jellyfin servers when it signs in.
///
/// Made up at random on first use and then kept, so a server sees one
/// device instead of a new one on every start. It says nothing about the
/// PC or its owner, and it is not a secret.
String loadOrCreateDeviceId(KeyValueStore store) {
  final saved = store.getString(_key);
  if (saved != null && isValidDeviceId(saved)) return saved;

  final random = Random.secure();
  final digits = [
    for (var i = 0; i < 16; i++) random.nextInt(16).toRadixString(16),
  ];
  final id = 'dhara-${digits.join()}';
  unawaited(store.setString(_key, id));
  return id;
}
