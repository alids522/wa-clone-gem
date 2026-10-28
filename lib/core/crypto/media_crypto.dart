import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as digest;
import 'package:cryptography/cryptography.dart';

/// Result of encrypting an attachment. `key` is base64 AES-256 material and is
/// only ever shared inside the E2EE message envelope, never with the server.
class EncryptedMedia {
  const EncryptedMedia({
    required this.bytes,
    required this.key,
    required this.nonce,
    required this.sha256,
    required this.plainSize,
  });

  final Uint8List bytes;
  final String key;
  final String nonce;
  final String sha256;
  final int plainSize;
}

/// Chunked AES-256-GCM for attachments.
///
/// Container format:
///   "ADZ1" | ( nonce[12] | len[4 big endian] | ciphertext[len] )*
/// Each 512 KiB plaintext chunk is sealed with a fresh random nonce. The key
/// travels only inside the encrypted message envelope.
class MediaCrypto {
  MediaCrypto({int chunkSize = 512 * 1024}) : _chunkSize = chunkSize;

  final int _chunkSize;
  final AesGcm _algorithm = AesGcm.with256bits();
  final Random _random = Random.secure();

  static const _magic = [0x41, 0x44, 0x5A, 0x31]; // "ADZ1"

  Future<EncryptedMedia> encrypt(Uint8List plaintext) async {
    final key = await _algorithm.newSecretKey();
    final keyBytes = await key.extractBytes();
    final output = BytesBuilder(copy: false)..add(_magic);

    for (var offset = 0; offset < plaintext.length; offset += _chunkSize) {
      final end = min(offset + _chunkSize, plaintext.length);
      final chunk = plaintext.sublist(offset, end);
      final nonce = _randomBytes(12);
      final box = await _algorithm.encrypt(chunk, secretKey: key, nonce: nonce);
      final sealed = Uint8List.fromList([...box.cipherText, ...box.mac.bytes]);
      output
        ..add(nonce)
        ..add(_uint32(sealed.length))
        ..add(sealed);
    }

    return EncryptedMedia(
      bytes: output.takeBytes(),
      key: base64Encode(keyBytes),
      nonce: base64Encode(_randomBytes(12)),
      sha256: digest.sha256.convert(plaintext).toString(),
      plainSize: plaintext.length,
    );
  }

  Future<Uint8List> decrypt({
    required Uint8List ciphertext,
    required String key,
    String? expectedSha256,
  }) async {
    if (ciphertext.length < 8) {
      throw const MediaCryptoException('Berkas terenkripsi tidak valid.');
    }
    for (var i = 0; i < _magic.length; i++) {
      if (ciphertext[i] != _magic[i]) {
        throw const MediaCryptoException('Format berkas tidak dikenal.');
      }
    }
    final secretKey = SecretKey(base64Decode(key));
    final out = BytesBuilder(copy: false);
    var offset = _magic.length;
    while (offset < ciphertext.length) {
      if (offset + 16 > ciphertext.length) {
        throw const MediaCryptoException('Berkas terenkripsi terpotong.');
      }
      final nonce = ciphertext.sublist(offset, offset + 12);
      final length = ByteData.sublistView(
        ciphertext,
        offset + 12,
        offset + 16,
      ).getUint32(0, Endian.big);
      offset += 16;
      if (length < 16 || offset + length > ciphertext.length) {
        throw const MediaCryptoException('Berkas terenkripsi korup.');
      }
      final sealed = ciphertext.sublist(offset, offset + length);
      final box = SecretBox(
        sealed.sublist(0, sealed.length - 16),
        nonce: nonce,
        mac: Mac(sealed.sublist(sealed.length - 16)),
      );
      final clear = await _algorithm.decrypt(box, secretKey: secretKey);
      out.add(clear);
      offset += length;
    }
    final plain = out.takeBytes();
    if (expectedSha256 != null &&
        digest.sha256.convert(plain).toString() != expectedSha256) {
      throw const MediaCryptoException(
        'Berkas gagal diverifikasi (checksum tidak cocok).',
      );
    }
    return plain;
  }

  Uint8List _randomBytes(int length) {
    return Uint8List.fromList(
      List<int>.generate(length, (_) => _random.nextInt(256)),
    );
  }

  Uint8List _uint32(int value) {
    final data = ByteData(4)..setUint32(0, value, Endian.big);
    return data.buffer.asUint8List();
  }
}

class MediaCryptoException implements Exception {
  const MediaCryptoException(this.message);

  final String message;
}
