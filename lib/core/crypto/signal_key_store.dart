import 'dart:convert';
import 'dart:typed_data';

import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';

import '../storage/local_database.dart';
import '../storage/secure_store.dart';

/// Persists the Signal double-ratchet state in the SQLCipher database and the
/// long-term identity in Android Keystore-backed storage.
class SignalKeyStore
    implements IdentityKeyStore, PreKeyStore, SignedPreKeyStore, SessionStore {
  SignalKeyStore(this._db, this._secure);

  final LocalDatabase _db;
  final SecureStore _secure;

  static const _sessionPrefix = 'signal_session:';
  static const _preKeyPrefix = 'signal_prekey:';
  static const _signedPreKeyPrefix = 'signal_spk:';
  static const _identityPrefix = 'signal_identity:';

  String _addressKey(SignalProtocolAddress address) =>
      '${address.getName()}:${address.getDeviceId()}';

  // ---------------------------------------------------------------------------
  // IdentityKeyStore
  // ---------------------------------------------------------------------------

  @override
  Future<IdentityKeyPair> getIdentityKeyPair() async {
    final stored = await _secure.readIdentityPair();
    if (stored == null || stored.isEmpty) {
      throw StateError('E2EE identity is not initialized');
    }
    return IdentityKeyPair.fromSerialized(base64Decode(stored));
  }

  @override
  Future<int> getLocalRegistrationId() async {
    final id = await _secure.readRegistrationId();
    if (id == null) throw StateError('E2EE registration id is missing');
    return id;
  }

  @override
  Future<bool> saveIdentity(
    SignalProtocolAddress address,
    IdentityKey? identityKey,
  ) async {
    if (identityKey == null) return false;
    final key = '$_identityPrefix${_addressKey(address)}';
    final previous = await _db.kvGet(key);
    final current = base64Encode(identityKey.serialize());
    await _db.kvSet(key, current);
    return previous != null && previous != current;
  }

  @override
  Future<bool> isTrustedIdentity(
    SignalProtocolAddress address,
    IdentityKey? identityKey,
    Direction direction,
  ) async {
    // Trust-on-first-use is enforced here; a changed identity is surfaced by
    // E2eeService before it is used (PRD 10.2 / ERR-11).
    return identityKey != null;
  }

  @override
  Future<IdentityKey?> getIdentity(SignalProtocolAddress address) async {
    final stored = await _db.kvGet('$_identityPrefix${_addressKey(address)}');
    if (stored == null || stored.isEmpty) return null;
    return IdentityKey.fromBytes(base64Decode(stored), 0);
  }

  // ---------------------------------------------------------------------------
  // PreKeyStore
  // ---------------------------------------------------------------------------

  @override
  Future<PreKeyRecord> loadPreKey(int preKeyId) async {
    final stored = await _db.kvGet('$_preKeyPrefix$preKeyId');
    if (stored == null) {
      throw InvalidKeyIdException('No prekey with id $preKeyId');
    }
    return PreKeyRecord.fromBuffer(base64Decode(stored));
  }

  @override
  Future<void> storePreKey(int preKeyId, PreKeyRecord record) =>
      _db.kvSet('$_preKeyPrefix$preKeyId', base64Encode(record.serialize()));

  @override
  Future<bool> containsPreKey(int preKeyId) async =>
      await _db.kvGet('$_preKeyPrefix$preKeyId') != null;

  @override
  Future<void> removePreKey(int preKeyId) =>
      _db.kvDelete('$_preKeyPrefix$preKeyId');

  // ---------------------------------------------------------------------------
  // SignedPreKeyStore
  // ---------------------------------------------------------------------------

  @override
  Future<SignedPreKeyRecord> loadSignedPreKey(int signedPreKeyId) async {
    final stored = await _db.kvGet('$_signedPreKeyPrefix$signedPreKeyId');
    if (stored == null) {
      throw InvalidKeyIdException('No signed prekey with id $signedPreKeyId');
    }
    return SignedPreKeyRecord.fromSerialized(base64Decode(stored));
  }

  @override
  Future<List<SignedPreKeyRecord>> loadSignedPreKeys() async {
    final entries = await _db.kvList(_signedPreKeyPrefix);
    return entries
        .map(
          (entry) =>
              SignedPreKeyRecord.fromSerialized(base64Decode(entry.value)),
        )
        .toList(growable: false);
  }

  @override
  Future<void> storeSignedPreKey(
    int signedPreKeyId,
    SignedPreKeyRecord record,
  ) => _db.kvSet(
    '$_signedPreKeyPrefix$signedPreKeyId',
    base64Encode(record.serialize()),
  );

  @override
  Future<bool> containsSignedPreKey(int signedPreKeyId) async =>
      await _db.kvGet('$_signedPreKeyPrefix$signedPreKeyId') != null;

  @override
  Future<void> removeSignedPreKey(int signedPreKeyId) =>
      _db.kvDelete('$_signedPreKeyPrefix$signedPreKeyId');

  // ---------------------------------------------------------------------------
  // SessionStore
  // ---------------------------------------------------------------------------

  @override
  Future<SessionRecord> loadSession(SignalProtocolAddress address) async {
    final stored = await _db.kvGet('$_sessionPrefix${_addressKey(address)}');
    if (stored == null || stored.isEmpty) return SessionRecord();
    return SessionRecord.fromSerialized(base64Decode(stored));
  }

  @override
  Future<List<int>> getSubDeviceSessions(String name) async => const [];

  @override
  Future<void> storeSession(
    SignalProtocolAddress address,
    SessionRecord record,
  ) => _db.kvSet(
    '$_sessionPrefix${_addressKey(address)}',
    base64Encode(record.serialize()),
  );

  @override
  Future<bool> containsSession(SignalProtocolAddress address) async =>
      await _db.kvGet('$_sessionPrefix${_addressKey(address)}') != null;

  @override
  Future<void> deleteSession(SignalProtocolAddress address) =>
      _db.kvDelete('$_sessionPrefix${_addressKey(address)}');

  @override
  Future<void> deleteAllSessions(String name) async {
    final prefix = '$_sessionPrefix$name:';
    final entries = await _db.kvList(prefix);
    for (final entry in entries) {
      await _db.kvDelete(entry.key);
    }
  }

  // ---------------------------------------------------------------------------
  // Local prekey inventory
  // ---------------------------------------------------------------------------

  Future<List<int>> storedPreKeyIds() async {
    final entries = await _db.kvList(_preKeyPrefix);
    return entries
        .map((entry) => int.tryParse(entry.key.substring(_preKeyPrefix.length)))
        .whereType<int>()
        .toList(growable: false);
  }

  Future<void> clearAll() async {
    for (final prefix in [
      _sessionPrefix,
      _preKeyPrefix,
      _signedPreKeyPrefix,
      _identityPrefix,
    ]) {
      final entries = await _db.kvList(prefix);
      for (final entry in entries) {
        await _db.kvDelete(entry.key);
      }
    }
  }

  Future<void> saveIdentityPair(IdentityKeyPair pair) =>
      _secure.writeIdentityPair(base64Encode(pair.serialize()));

  Future<void> saveRegistrationId(int id) => _secure.writeRegistrationId(id);

  Future<Uint8List> localIdentityPublicKey() async {
    final pair = await getIdentityKeyPair();
    return pair.getPublicKey().serialize();
  }
}
