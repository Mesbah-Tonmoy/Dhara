import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:dhara/features/update/update_signature.dart';
import 'package:ffi/ffi.dart';

/// A key pair for signing updates in a test: made by Windows when the test
/// asks for it, kept in memory only, and gone when it is closed. No test
/// reads a key from a file, and none is ever written.
///
/// Only on Windows.
class TestSigner {
  TestSigner() {
    using((arena) {
      final algorithm = arena<IntPtr>();
      _check(
        _open(
          algorithm,
          'ECDSA_P256'.toNativeUtf16(allocator: arena),
          nullptr,
          0,
        ),
      );
      final key = arena<IntPtr>();
      _check(_generate(algorithm.value, key, 256, 0));
      _check(_finalize(key.value, 0));
      _algorithm = algorithm.value;
      _key = key.value;

      // The public half, as Windows writes it: eight bytes that say what
      // it is, then X and Y.
      final blob = arena<Uint8>(72);
      final written = arena<Uint32>();
      _check(
        _export(
          key.value,
          0,
          'ECCPUBLICBLOB'.toNativeUtf16(allocator: arena),
          blob,
          72,
          written,
          0,
        ),
      );
      publicKey = base64.encode(blob.asTypedList(72).sublist(8));
    });
  }

  late final int _algorithm;
  late final int _key;

  /// The public half, as a build is given it (`DHARA_UPDATE_KEY`).
  late final String publicKey;

  /// The same, as the app uses it.
  UpdateKey get key => UpdateKey.from(publicKey)!;

  /// The signature of [message]: r and s, 32 bytes each.
  Uint8List sign(List<int> message) {
    final digest = sha256Of(message);
    return using((arena) {
      final hashed = arena<Uint8>(32)..asTypedList(32).setAll(0, digest);
      final signature = arena<Uint8>(64);
      final written = arena<Uint32>();
      _check(_sign(_key, nullptr, hashed, 32, signature, 64, written, 0));
      return Uint8List.fromList(signature.asTypedList(written.value));
    });
  }

  void close() {
    _destroyKey(_key);
    _close(_algorithm, 0);
  }
}

void _check(int status) {
  if (status != 0) {
    throw StateError(
      'bcrypt.dll: 0x${status.toUnsigned(32).toRadixString(16)}',
    );
  }
}

final _bcrypt = DynamicLibrary.open('bcrypt.dll');

final _open = _bcrypt
    .lookupFunction<
      Int32 Function(Pointer<IntPtr>, Pointer<Utf16>, Pointer<Utf16>, Uint32),
      int Function(Pointer<IntPtr>, Pointer<Utf16>, Pointer<Utf16>, int)
    >('BCryptOpenAlgorithmProvider');

final _close = _bcrypt
    .lookupFunction<Int32 Function(IntPtr, Uint32), int Function(int, int)>(
      'BCryptCloseAlgorithmProvider',
    );

final _generate = _bcrypt
    .lookupFunction<
      Int32 Function(IntPtr, Pointer<IntPtr>, Uint32, Uint32),
      int Function(int, Pointer<IntPtr>, int, int)
    >('BCryptGenerateKeyPair');

final _finalize = _bcrypt
    .lookupFunction<Int32 Function(IntPtr, Uint32), int Function(int, int)>(
      'BCryptFinalizeKeyPair',
    );

final _export = _bcrypt
    .lookupFunction<
      Int32 Function(
        IntPtr,
        IntPtr,
        Pointer<Utf16>,
        Pointer<Uint8>,
        Uint32,
        Pointer<Uint32>,
        Uint32,
      ),
      int Function(
        int,
        int,
        Pointer<Utf16>,
        Pointer<Uint8>,
        int,
        Pointer<Uint32>,
        int,
      )
    >('BCryptExportKey');

final _sign = _bcrypt
    .lookupFunction<
      Int32 Function(
        IntPtr,
        Pointer<Void>,
        Pointer<Uint8>,
        Uint32,
        Pointer<Uint8>,
        Uint32,
        Pointer<Uint32>,
        Uint32,
      ),
      int Function(
        int,
        Pointer<Void>,
        Pointer<Uint8>,
        int,
        Pointer<Uint8>,
        int,
        Pointer<Uint32>,
        int,
      )
    >('BCryptSignHash');

final _destroyKey = _bcrypt
    .lookupFunction<Int32 Function(IntPtr), int Function(int)>(
      'BCryptDestroyKey',
    );
