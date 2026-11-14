import 'dart:convert';
import 'dart:ffi';

import 'package:dhara/core/secrets/secret_store.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:win32/win32.dart';

/// Keeps secrets in Windows Credential Manager, as "generic credentials"
/// of the signed-in user. Windows encrypts them with that user's sign-in;
/// they are listed (without their content) under Control Panel, Credential
/// Manager, Windows Credentials.
///
/// Only call this on Windows.
class WindowsCredentialStore implements SecretStore {
  const WindowsCredentialStore({this.prefix = 'Dhara'});

  /// What the names of this app's credentials start with: the one called
  /// `tmdb` is listed as "Dhara/tmdb".
  final String prefix;

  @override
  bool get keepsSecrets => true;

  @override
  Future<String?> read(String name) async {
    final target = _target(name);
    return using((arena) {
      final found = arena<Pointer<CREDENTIAL>>();
      final result = withErrorCode(
        () => CredRead(arena.pcwstr(target), CRED_TYPE_GENERIC, found),
      );
      if (!result.value) {
        if (result.error == ERROR_NOT_FOUND) return null;
        throw _failure('read', result.error);
      }
      try {
        final credential = found.value.ref;
        final size = credential.CredentialBlobSize;
        if (size == 0 || credential.CredentialBlob == nullptr) return null;
        return utf8.decode(
          credential.CredentialBlob.asTypedList(size),
          allowMalformed: true,
        );
      } finally {
        CredFree(found.value);
      }
    });
  }

  @override
  Future<void> write(String name, String value) async {
    final target = _target(name);
    final bytes = utf8.encode(value);
    if (bytes.isEmpty || bytes.length > maxSecretBytes) {
      throw const SecretStoreException(
        'A secret must be between 1 and $maxSecretBytes bytes long.',
      );
    }
    using((arena) {
      final blob = arena<Uint8>(bytes.length);
      final copy = blob.asTypedList(bytes.length)..setAll(0, bytes);
      final credential = arena<CREDENTIAL>();
      credential.ref
        ..Type = CRED_TYPE_GENERIC
        ..TargetName = PWSTR(arena.pcwstr(target))
        ..UserName = PWSTR(arena.pcwstr(prefix))
        ..CredentialBlobSize = bytes.length
        ..CredentialBlob = blob
        // Stays on this PC, for this user, across restarts.
        ..Persist = CRED_PERSIST_LOCAL_MACHINE;
      final result = withErrorCode(() => CredWrite(credential, 0));
      // Windows has its own copy now; this one is not left lying in freed
      // memory.
      copy.fillRange(0, copy.length, 0);
      if (!result.value) throw _failure('keep', result.error);
    });
  }

  @override
  Future<void> delete(String name) async {
    final target = _target(name);
    using((arena) {
      final result = withErrorCode(
        () => CredDelete(arena.pcwstr(target), CRED_TYPE_GENERIC),
      );
      if (!result.value && result.error != ERROR_NOT_FOUND) {
        throw _failure('remove', result.error);
      }
    });
  }

  String _target(String name) {
    if (!isSecretName(name)) {
      throw const SecretStoreException('That is not a name for a secret.');
    }
    return '$prefix/$name';
  }

  static SecretStoreException _failure(String action, int error) =>
      SecretStoreException(
        'Windows Credential Manager could not $action the secret '
        '(error $error).',
      );
}

/// Makes a call to Windows that says, when it fails, why.
///
/// The reason is fetched by a second call (`GetLastError`), and now and
/// then something else on the thread gets in between and wipes it: the call
/// has failed, yet the reason reads "no error". Reading, writing and
/// removing a credential can all be done again without harm, so such a
/// call is made again, up to [tries] times in all.
@visibleForTesting
Win32Result<bool> withErrorCode(
  Win32Result<bool> Function() call, {
  int tries = 3,
}) {
  var result = call();
  for (var made = 1; made < tries; made++) {
    if (result.value || result.error != ERROR_SUCCESS) break;
    result = call();
  }
  return result;
}
