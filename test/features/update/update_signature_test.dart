@TestOn('windows')
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:dhara/features/update/update_signature.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/update_keys.dart';

Uint8List _hex(String text) => Uint8List.fromList([
  for (var at = 0; at < text.length; at += 2)
    int.parse(text.substring(at, at + 2), radix: 16),
]);

void main() {
  group('SHA-256', () {
    // The digests the standard itself gives (FIPS 180-4).
    test('of nothing and of "abc"', () {
      expect(
        hexOf(sha256Of(const [])),
        'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
      );
      expect(
        hexOf(sha256Of(ascii.encode('abc'))),
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
      );
    });

    test('of a million letters, whatever the pieces they come in', () {
      const expected =
          'cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0';
      final million = Uint8List(1000000)..fillRange(0, 1000000, 0x61);
      expect(hexOf(sha256Of(million)), expected);

      final pieces = Sha256();
      for (var at = 0; at < million.length; at += 77777) {
        final end = at + 77777 < million.length ? at + 77777 : million.length;
        pieces.add(Uint8List.sublistView(million, at, end));
      }
      expect(hexOf(pieces.finish()), expected);
    });

    test('of more than is handed over in one call', () {
      final bytes = Uint8List(3 * 1024 * 1024 + 5);
      for (var at = 0; at < bytes.length; at++) {
        bytes[at] = at * 31 + (at >> 8);
      }
      final whole = sha256Of(bytes);
      final halves = Sha256()
        ..add(Uint8List.sublistView(bytes, 0, 1500000))
        ..add(Uint8List.sublistView(bytes, 1500000));
      expect(halves.finish(), whole);
    });

    test('a digest that is finished takes nothing more', () {
      final digest = Sha256()..add(const [1, 2, 3]);
      digest.finish();
      expect(() => digest.add(const [4]), throwsStateError);
      expect(digest.finish, throwsStateError);
      // Closing it again does no harm.
      digest.close();
    });
  });

  group('the key a build was given', () {
    test('is 64 bytes in base64 and nothing else', () {
      final signer = TestSigner();
      addTearDown(signer.close);
      expect(UpdateKey.from(signer.publicKey), isNotNull);
      expect(UpdateKey.from('  ${signer.publicKey}\n'), isNotNull);

      for (final value in [
        '',
        'not a key',
        base64.encode(List.filled(63, 7)),
        base64.encode(List.filled(65, 7)),
        base64.encode(List.filled(32, 7)),
        // A private key in the form the signing script keeps it.
        '-----BEGIN PRIVATE KEY-----',
        '${signer.publicKey}=',
        signer.publicKey.replaceFirst(RegExp('.'), '*'),
      ]) {
        expect(UpdateKey.from(value), isNull, reason: value);
      }
    });

    test('bytes that are no point of the curve sign nothing', () {
      final key = UpdateKey.from(base64.encode(List.filled(64, 7)))!;
      expect(key.signed(const [1, 2, 3], List.filled(64, 1)), isFalse);
    });
  });

  group('a signature', () {
    // Published ones (RFC 6979, A.2.5: P-256 with SHA-256), so the check
    // is held against something this PC did not make.
    final published = UpdateKey.from(
      base64.encode(
        _hex(
          '60fed4ba255a9d31c961eb74c6356d68c049b8923b61fa6ce669622e60f29fb6'
          '7903fe1008b8bc99a41ae9e95628bc64f2f1b20c2d7e9f5177a3c294d4462299',
        ),
      ),
    )!;
    final ofSample = _hex(
      'efd48b2aacb6a8fd1140dd9cd45e81d69d2c877b56aaf991c34d0ea84eaf3716'
      'f7cb1c942d657c41d436c7a1b6e29f65f3e900dbb9aff4064dc4ab2f843acda8',
    );
    final ofTest = _hex(
      'f1abb023518351cd71d881567b1ea663ed3efcf6c5132b354f28d3b0b7d38367'
      '019f4113742a2b14bd25926b49c649155f267e60d3814b4c0cc84250e46f0083',
    );

    test('that was published fits its message and no other', () {
      expect(published.signed(ascii.encode('sample'), ofSample), isTrue);
      expect(published.signed(ascii.encode('test'), ofTest), isTrue);
      expect(published.signed(ascii.encode('sample'), ofTest), isFalse);
      expect(published.signed(ascii.encode('Sample'), ofSample), isFalse);
    });

    test('made here fits, and fits no other key', () {
      final signer = TestSigner();
      final other = TestSigner();
      addTearDown(signer.close);
      addTearDown(other.close);
      final message = utf8.encode('{"version":"1.2.0"}');
      final signature = signer.sign(message);

      expect(signature, hasLength(64));
      expect(signer.key.signed(message, signature), isTrue);
      expect(other.key.signed(message, signature), isFalse);
      expect(published.signed(message, signature), isFalse);
    });

    test('does not fit once a single bit is another', () {
      final signer = TestSigner();
      addTearDown(signer.close);
      final message = Uint8List.fromList(List.generate(4000, (at) => at % 251));
      final signature = signer.sign(message);
      expect(signer.key.signed(message, signature), isTrue);

      for (final at in const [0, 1999, 3999]) {
        final changed = Uint8List.fromList(message)..[at] ^= 0x01;
        expect(signer.key.signed(changed, signature), isFalse, reason: '$at');
      }
      for (final at in const [0, 31, 32, 63]) {
        final changed = Uint8List.fromList(signature)..[at] ^= 0x80;
        expect(signer.key.signed(message, changed), isFalse, reason: '$at');
      }
      // A byte more or less of the message.
      expect(signer.key.signed([...message, 0], signature), isFalse);
      expect(signer.key.signed(message.sublist(0, 3999), signature), isFalse);
    });

    test('of another length or shape is none', () {
      final signer = TestSigner();
      addTearDown(signer.close);
      final message = ascii.encode('an update notice');
      final signature = signer.sign(message);

      expect(signer.key.signed(message, const []), isFalse);
      expect(signer.key.signed(message, signature.sublist(0, 63)), isFalse);
      expect(signer.key.signed(message, [...signature, 0]), isFalse);
      expect(signer.key.signed(message, List.filled(64, 0)), isFalse);
      expect(signer.key.signed(message, List.filled(64, 0xff)), isFalse);
      // The same two numbers, the other way round.
      expect(
        signer.key.signed(message, [
          ...signature.sublist(32),
          ...signature.sublist(0, 32),
        ]),
        isFalse,
      );
    });
  });
}
