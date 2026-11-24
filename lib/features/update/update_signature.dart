/// The check an update rests on: SHA-256, and ECDSA signatures over the
/// curve P-256, both done by Windows itself (CNG, `bcrypt.dll`).
///
/// Dart's own libraries have neither, and Windows has both built in, so no
/// package is added for it and no arithmetic of this kind is written here.
/// Only call this on Windows.
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

/// The length of a SHA-256 digest, of one coordinate of a P-256 point and
/// of one half of a signature, in bytes.
const _wordBytes = 32;

/// The public half of the key that signs updates: a point of the curve
/// P-256, as its X and Y coordinates (32 bytes each, big-endian).
///
/// It is given to a production build when it is made. It is no secret: it
/// can only say whether a signature fits, not make one.
class UpdateKey {
  UpdateKey._(this._point);

  /// The key out of what a build was given (`DHARA_UPDATE_KEY`): the 64
  /// bytes of X and Y in base64. `null` if it is anything else.
  static UpdateKey? from(String value) {
    final text = value.trim();
    // 64 bytes in base64 are 88 characters, the last of them one "=".
    if (!RegExp(r'^[A-Za-z0-9+/]{86}[A-Za-z0-9+/=]{2}$').hasMatch(text)) {
      return null;
    }
    final Uint8List point;
    try {
      point = base64.decode(text);
    } on FormatException {
      return null;
    }
    return point.length == 2 * _wordBytes ? UpdateKey._(point) : null;
  }

  final Uint8List _point;

  /// Whether [signature] was made over [message] with the private half of
  /// this key: an ECDSA signature over the SHA-256 of the message, as the
  /// two numbers r and s, 32 bytes each (the form .NET's `SignData` and
  /// Web Crypto write). Anything else is no signature.
  ///
  /// Throws a [CngException] only if Windows cannot do the check at all.
  bool signed(List<int> message, List<int> signature) {
    if (signature.length != 2 * _wordBytes) return false;
    final digest = sha256Of(message);
    return using((arena) {
      final algorithm = _Algorithm.open('ECDSA_P256', arena);
      try {
        // BCRYPT_ECCKEY_BLOB: which key it is ("ECS1", a public P-256
        // key), how long a coordinate is, then X and Y.
        const header = 8;
        final blob = arena<Uint8>(header + _point.length);
        final bytes = blob.asTypedList(header + _point.length);
        ByteData.sublistView(bytes)
          ..setUint32(0, 0x31534345, Endian.little)
          ..setUint32(4, _wordBytes, Endian.little);
        bytes.setAll(header, _point);
        final key = arena<IntPtr>();
        final imported = _importKeyPair(
          algorithm.handle,
          0,
          'ECCPUBLICBLOB'.toNativeUtf16(allocator: arena),
          key,
          blob,
          bytes.length,
          0,
        );
        // Sixty-four bytes that are no point of the curve.
        if (imported != 0) return false;
        try {
          final hashed = arena<Uint8>(digest.length)
            ..asTypedList(digest.length).setAll(0, digest);
          final given = arena<Uint8>(signature.length)
            ..asTypedList(signature.length).setAll(0, signature);
          // Zero and nothing else says that the signature fits.
          return _verifySignature(
                key.value,
                nullptr,
                hashed,
                digest.length,
                given,
                signature.length,
                0,
              ) ==
              0;
        } finally {
          _destroyKey(key.value);
        }
      } finally {
        algorithm.close();
      }
    });
  }
}

/// The SHA-256 of [bytes].
Uint8List sha256Of(List<int> bytes) => (Sha256()..add(bytes)).finish();

/// SHA-256 of something that comes piece by piece, such as a file that is
/// too large to hold in memory: [add] every piece in order, then [finish].
class Sha256 {
  Sha256() {
    using((arena) {
      final algorithm = _Algorithm.open('SHA256', arena);
      try {
        final hash = arena<IntPtr>();
        _check(_createHash(algorithm.handle, hash, nullptr, 0, nullptr, 0, 0));
        _hash = hash.value;
      } finally {
        // The hash keeps what it needs of the algorithm.
        algorithm.close();
      }
    });
  }

  /// The most that is handed to Windows in one call.
  static const _piece = 1024 * 1024;

  int? _hash;

  /// Takes the next [bytes] into the digest.
  void add(List<int> bytes) {
    final hash = _hash;
    if (hash == null) throw StateError('This digest is finished.');
    if (bytes.isEmpty) return;
    final buffer = malloc<Uint8>(bytes.length < _piece ? bytes.length : _piece);
    try {
      for (var at = 0; at < bytes.length; at += _piece) {
        final length = bytes.length - at < _piece ? bytes.length - at : _piece;
        buffer.asTypedList(length).setRange(0, length, bytes, at);
        _check(_hashData(hash, buffer, length, 0));
      }
    } finally {
      malloc.free(buffer);
    }
  }

  /// The digest of everything that was added: 32 bytes. Ends this object.
  Uint8List finish() {
    final hash = _hash;
    if (hash == null) throw StateError('This digest is finished.');
    return using((arena) {
      final out = arena<Uint8>(_wordBytes);
      try {
        _check(_finishHash(hash, out, _wordBytes, 0));
        return Uint8List.fromList(out.asTypedList(_wordBytes));
      } finally {
        close();
      }
    });
  }

  /// Gives up a digest that will not be finished.
  void close() {
    final hash = _hash;
    _hash = null;
    if (hash != null) _destroyHash(hash);
  }
}

/// A digest as the lower-case hexadecimal text it is usually written as.
String hexOf(List<int> bytes) =>
    [for (final byte in bytes) byte.toRadixString(16).padLeft(2, '0')].join();

/// Windows could not do what was asked of its cryptography. Says which
/// status it gave, and nothing of what was being checked.
class CngException implements Exception {
  const CngException(this.status);

  /// The NTSTATUS of the call that failed.
  final int status;

  @override
  String toString() =>
      'CngException(0x${status.toUnsigned(32).toRadixString(16)})';
}

void _check(int status) {
  if (status != 0) throw CngException(status);
}

/// One of Windows' algorithms, opened for as long as it is used.
class _Algorithm {
  _Algorithm._(this.handle);

  factory _Algorithm.open(String name, Arena arena) {
    final handle = arena<IntPtr>();
    _check(
      _openAlgorithmProvider(
        handle,
        name.toNativeUtf16(allocator: arena),
        nullptr,
        0,
      ),
    );
    return _Algorithm._(handle.value);
  }

  final int handle;

  void close() => _closeAlgorithmProvider(handle, 0);
}

// The functions of bcrypt.dll that are used, and no other. The library is
// part of Windows and is loaded by its name from the system's own folder
// (it is one of the "known DLLs", which are never looked for beside the
// program).
final _bcrypt = DynamicLibrary.open('bcrypt.dll');

final _openAlgorithmProvider = _bcrypt
    .lookupFunction<
      Int32 Function(Pointer<IntPtr>, Pointer<Utf16>, Pointer<Utf16>, Uint32),
      int Function(Pointer<IntPtr>, Pointer<Utf16>, Pointer<Utf16>, int)
    >('BCryptOpenAlgorithmProvider');

final _closeAlgorithmProvider = _bcrypt
    .lookupFunction<Int32 Function(IntPtr, Uint32), int Function(int, int)>(
      'BCryptCloseAlgorithmProvider',
    );

final _createHash = _bcrypt
    .lookupFunction<
      Int32 Function(
        IntPtr,
        Pointer<IntPtr>,
        Pointer<Uint8>,
        Uint32,
        Pointer<Uint8>,
        Uint32,
        Uint32,
      ),
      int Function(
        int,
        Pointer<IntPtr>,
        Pointer<Uint8>,
        int,
        Pointer<Uint8>,
        int,
        int,
      )
    >('BCryptCreateHash');

final _hashData = _bcrypt
    .lookupFunction<
      Int32 Function(IntPtr, Pointer<Uint8>, Uint32, Uint32),
      int Function(int, Pointer<Uint8>, int, int)
    >('BCryptHashData');

final _finishHash = _bcrypt
    .lookupFunction<
      Int32 Function(IntPtr, Pointer<Uint8>, Uint32, Uint32),
      int Function(int, Pointer<Uint8>, int, int)
    >('BCryptFinishHash');

final _destroyHash = _bcrypt
    .lookupFunction<Int32 Function(IntPtr), int Function(int)>(
      'BCryptDestroyHash',
    );

final _importKeyPair = _bcrypt
    .lookupFunction<
      Int32 Function(
        IntPtr,
        IntPtr,
        Pointer<Utf16>,
        Pointer<IntPtr>,
        Pointer<Uint8>,
        Uint32,
        Uint32,
      ),
      int Function(
        int,
        int,
        Pointer<Utf16>,
        Pointer<IntPtr>,
        Pointer<Uint8>,
        int,
        int,
      )
    >('BCryptImportKeyPair');

final _verifySignature = _bcrypt
    .lookupFunction<
      Int32 Function(
        IntPtr,
        Pointer<Void>,
        Pointer<Uint8>,
        Uint32,
        Pointer<Uint8>,
        Uint32,
        Uint32,
      ),
      int Function(
        int,
        Pointer<Void>,
        Pointer<Uint8>,
        int,
        Pointer<Uint8>,
        int,
        int,
      )
    >('BCryptVerifySignature');

final _destroyKey = _bcrypt
    .lookupFunction<Int32 Function(IntPtr), int Function(int)>(
      'BCryptDestroyKey',
    );
