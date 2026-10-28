import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../models/message.dart';
import '../storage/local_database.dart';
import '../storage/secure_store.dart';
import '../utils/app_error.dart';
import 'signal_key_store.dart';

class DeviceConflictException implements Exception {
  const DeviceConflictException();
}

class IdentityChangedException implements Exception {
  const IdentityChangedException(this.peerId, this.fingerprint);

  final String peerId;
  final String fingerprint;
}

class DecryptionException implements Exception {
  const DecryptionException(this.reason);

  final String reason;
}

class CiphertextBundle {
  const CiphertextBundle({required this.ciphertext, required this.wireType});

  final String ciphertext;

  /// 2 = SignalMessage, 3 = PreKeySignalMessage.
  final int wireType;
}

/// Signal Protocol integration for 1:1 chats (single device per account).
///
/// The server only ever sees public keys and ciphertext. Private identity and
/// ratchet state stay in Keystore-backed storage / SQLCipher.
class E2eeService {
  E2eeService({
    required SupabaseClient client,
    required LocalDatabase db,
    required SecureStore secure,
  }) : _client = client,
       _db = db,
       _secure = secure,
       store = SignalKeyStore(db, secure);

  final SupabaseClient _client;
  final LocalDatabase _db;
  final SecureStore _secure;
  final SignalKeyStore store;

  static const _ownerKey = 'e2ee_owner';
  static const _preKeyCursorKey = 'e2ee_prekey_cursor';
  static const _initialPreKeys = 100;
  static const int _wireSignal = 2;
  static const int _wirePreKey = 3;

  String? _userId;
  bool _ready = false;

  bool get isReady => _ready;

  Future<void> initialize({
    required String userId,
    bool replaceExistingDevice = false,
  }) async {
    _userId = userId;
    final owner = await _db.getSetting(_ownerKey);
    if (owner != null && owner != userId) {
      await store.clearAll();
      await _secure.clearE2eeKeys();
      await _db.setSetting(_ownerKey, userId);
    }

    var pairSerialized = await _secure.readIdentityPair();
    var registrationId = await _secure.readRegistrationId();
    var deviceId = await _secure.readDeviceId();

    if (pairSerialized == null || registrationId == null || deviceId == null) {
      final pair = generateIdentityKeyPair();
      registrationId = generateRegistrationId(false);
      deviceId = const Uuid().v4();
      await store.saveIdentityPair(pair);
      await store.saveRegistrationId(registrationId);
      await _secure.writeDeviceId(deviceId);

      final signedPreKey = generateSignedPreKey(pair, 1);
      await store.storeSignedPreKey(1, signedPreKey);

      final preKeys = generatePreKeys(0, _initialPreKeys);
      for (final record in preKeys) {
        await store.storePreKey(record.id, record);
      }
      await _db.setSetting(_preKeyCursorKey, '$_initialPreKeys');
      pairSerialized = base64Encode(pair.serialize());
    }

    await _db.setSetting(_ownerKey, userId);
    await _registerDevice(
      deviceId: deviceId,
      replaceExisting: replaceExistingDevice,
    );
    _ready = true;
  }

  Future<void> _registerDevice({
    required String deviceId,
    required bool replaceExisting,
  }) async {
    final pair = await store.getIdentityKeyPair();
    final registrationId = await store.getLocalRegistrationId();
    final signedPreKey = await store.loadSignedPreKey(1);
    final preKeyIds = await store.storedPreKeyIds()
      ..sort();
    final preKeys = <Map<String, dynamic>>[];
    for (final id in preKeyIds) {
      final record = await store.loadPreKey(id);
      preKeys.add({
        'key_id': id,
        'public_key': base64Encode(record.getKeyPair().publicKey.serialize()),
      });
    }

    try {
      final response = await _client.rpc(
        'register_device_keys',
        params: {
          'p_device_id': deviceId,
          'p_identity_key': base64Encode(pair.getPublicKey().serialize()),
          'p_registration_id': registrationId,
          'p_signed_prekey': {
            'key_id': signedPreKey.id,
            'public_key': base64Encode(
              signedPreKey.getKeyPair().publicKey.serialize(),
            ),
            'signature': base64Encode(signedPreKey.signature),
          },
          'p_prekeys': preKeys,
          'p_replace': replaceExisting,
        },
      );
      final map = (response as Map).cast<String, dynamic>();
      final remaining =
          (map['prekey_count'] as num?)?.toInt() ?? preKeys.length;
      if (remaining < 20) {
        await _replenishPreKeys(20 - remaining);
      }
    } on PostgrestException catch (error) {
      if (error.message.contains('DEVICE_EXISTS')) {
        throw const DeviceConflictException();
      }
      rethrow;
    }
  }

  Future<void> _replenishPreKeys(int count) async {
    final cursor =
        int.tryParse(await _db.getSetting(_preKeyCursorKey) ?? '0') ?? 0;
    final records = generatePreKeys(cursor, count);
    for (final record in records) {
      await store.storePreKey(record.id, record);
    }
    await _db.setSetting(_preKeyCursorKey, '${cursor + count}');
    final deviceId = await _secure.readDeviceId();
    if (deviceId == null) return;
    await _client.rpc(
      'replenish_prekeys',
      params: {
        'p_device_id': deviceId,
        'p_prekeys': records
            .map(
              (record) => {
                'key_id': record.id,
                'public_key': base64Encode(
                  record.getKeyPair().publicKey.serialize(),
                ),
              },
            )
            .toList(),
      },
    );
  }

  SignalProtocolAddress _address(String peerId) =>
      SignalProtocolAddress(peerId, 1);

  Future<PreKeyBundle> _fetchBundle(
    String conversationId,
    String peerId,
  ) async {
    final response = await _client.rpc(
      'get_prekey_bundle',
      params: {'p_conversation_id': conversationId},
    );
    final map = (response as Map).cast<String, dynamic>();
    final identityKeyBase64 = map['identity_key'] as String;
    final identityKey = IdentityKey.fromBytes(
      Uint8List.fromList(base64Decode(identityKeyBase64)),
      0,
    );
    final fingerprint = _fingerprintOf(identityKey.serialize());
    final previous = await _db.getPeerFingerprint(peerId);
    final verified = await _db.isPeerVerified(peerId);
    if (previous != null && previous != fingerprint && !verified) {
      await _db.setPeerIdentityChanged(peerId, true);
      throw IdentityChangedException(peerId, fingerprint);
    }
    await _db.savePeerFingerprint(peerId, fingerprint);

    ECPublicKey? preKeyPublic;
    final preKeyId = (map['prekey_id'] as num?)?.toInt();
    final rawPreKey = map['prekey_public'] as String?;
    if (preKeyId != null && rawPreKey != null && rawPreKey.isNotEmpty) {
      preKeyPublic = Curve.decodePoint(
        Uint8List.fromList(base64Decode(rawPreKey)),
        0,
      );
    }

    return PreKeyBundle(
      (map['registration_id'] as num).toInt(),
      1,
      preKeyId,
      preKeyPublic,
      (map['signed_prekey_id'] as num).toInt(),
      Curve.decodePoint(
        Uint8List.fromList(base64Decode(map['signed_prekey_public'] as String)),
        0,
      ),
      Uint8List.fromList(
        base64Decode(map['signed_prekey_signature'] as String),
      ),
      identityKey,
    );
  }

  Future<void> _ensureSession(String conversationId, String peerId) async {
    final address = _address(peerId);

    // Cheap identity check that does not consume a one-time prekey.
    try {
      final response = await _client.rpc(
        'get_peer_identity',
        params: {'p_peer_id': peerId},
      );
      if (response is Map) {
        final identityKey = response['identity_key'] as String?;
        if (identityKey != null && identityKey.isNotEmpty) {
          final fingerprint = fingerprintFromBase64(identityKey);
          final previous = await _db.getPeerFingerprint(peerId);
          final verified = await _db.isPeerVerified(peerId);
          if (previous != null && previous != fingerprint && !verified) {
            await _db.setPeerIdentityChanged(peerId, true);
            await store.deleteAllSessions(peerId);
            throw IdentityChangedException(peerId, fingerprint);
          }
          if (previous == null) {
            await _db.savePeerFingerprint(peerId, fingerprint);
          }
        }
      }
    } on PostgrestException {
      // The bundle fetch below is still authoritative for new sessions.
    }

    if (await store.containsSession(address)) return;
    final bundle = await _fetchBundle(conversationId, peerId);
    final builder = SessionBuilder(store, store, store, store, address);
    await builder.processPreKeyBundle(bundle);
  }

  Future<CiphertextBundle> encrypt({
    required String conversationId,
    required String peerId,
    required MessageEnvelope envelope,
  }) async {
    if (_userId == null) {
      throw const AppError('E2EE_NOT_READY', 'Enkripsi belum siap.');
    }
    await _ensureSession(conversationId, peerId);
    final address = _address(peerId);
    final cipher = SessionCipher(store, store, store, store, address);
    final plaintext = Uint8List.fromList(utf8.encode(envelope.encode()));
    final message = await cipher.encrypt(plaintext);
    final type = message.getType();
    final prefix = type == CiphertextMessage.prekeyType ? 'p:' : 's:';
    return CiphertextBundle(
      ciphertext: '$prefix${base64Encode(message.serialize())}',
      wireType: type == CiphertextMessage.prekeyType
          ? _wirePreKey
          : _wireSignal,
    );
  }

  Future<MessageEnvelope> decrypt({
    required String senderId,
    required String ciphertext,
  }) async {
    if (ciphertext.length < 3 || !ciphertext.contains(':')) {
      throw const DecryptionException('Malformed ciphertext');
    }
    final isPreKey = ciphertext.startsWith('p:');
    final bytes = Uint8List.fromList(base64Decode(ciphertext.substring(2)));
    final address = _address(senderId);
    final cipher = SessionCipher(store, store, store, store, address);
    try {
      final plaintext = isPreKey
          ? await cipher.decrypt(PreKeySignalMessage(bytes))
          : await cipher.decryptFromSignal(SignalMessage.fromSerialized(bytes));
      return MessageEnvelope.decode(utf8.decode(plaintext));
    } on UntrustedIdentityException catch (error) {
      throw DecryptionException('Untrusted identity: $error');
    } catch (error) {
      throw DecryptionException(error.toString());
    }
  }

  Future<String?> myFingerprint() async {
    try {
      final pair = await store.getIdentityKeyPair();
      return _fingerprintOf(pair.getPublicKey().serialize());
    } catch (_) {
      return null;
    }
  }

  Future<String?> peerFingerprint(String peerId) async {
    final stored = await _db.getPeerFingerprint(peerId);
    if (stored != null) return stored;
    final identity = await store.getIdentity(_address(peerId));
    if (identity == null) return null;
    return _fingerprintOf(identity.serialize());
  }

  /// Deterministic safety number derived from both identity keys. Both parties
  /// sort the keys, so the value matches on each device.
  Future<String?> safetyNumber(String peerId) async {
    final mine = await myFingerprint();
    final theirs = await peerFingerprint(peerId);
    if (mine == null || theirs == null) return null;
    final keys = [mine, theirs]..sort();
    final digest = sha512.convert(utf8.encode(keys.join(':'))).bytes;
    final buffer = StringBuffer();
    final big = BigInt.parse(
      digest.map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
      radix: 16,
    );
    var value = big;
    final divisor = BigInt.from(100000);
    final groups = <String>[];
    for (var i = 0; i < 12; i++) {
      final group = value % divisor;
      groups.add(group.toInt().toString().padLeft(5, '0'));
      value = value ~/ divisor;
    }
    for (var i = 0; i < groups.length; i++) {
      buffer.write(groups[i]);
      if (i % 4 == 3 && i != groups.length - 1) buffer.write(' ');
    }
    return buffer.toString();
  }

  Future<bool> isVerified(String peerId) => _db.isPeerVerified(peerId);

  Future<bool> verifyPeer(String peerId) async {
    await _db.markPeerVerified(peerId);
    await _db.setPeerIdentityChanged(peerId, false);
    return true;
  }

  /// Human-readable fingerprint for a base64-encoded public identity key.
  String fingerprintFromBase64(String identityKey) {
    return _fingerprintOf(base64Decode(identityKey));
  }

  String _fingerprintOf(Uint8List keyBytes) {
    final digest = sha256.convert(keyBytes).bytes;
    final hex = digest.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    final groups = <String>[];
    for (var i = 0; i < hex.length; i += 8) {
      groups.add(hex.substring(i, i + 8));
    }
    return groups.join(' ');
  }

  Future<void> resetPeerSession(String peerId) async {
    await store.deleteSession(_address(peerId));
    await store.deleteAllSessions(peerId);
    await _db.setPeerIdentityChanged(peerId, false);
  }
}
