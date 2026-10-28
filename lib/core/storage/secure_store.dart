import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Android Keystore-backed storage for the database passphrase and the E2EE
/// identity. Nothing here is backed up to the cloud by the app.
class SecureStore {
  SecureStore({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(encryptedSharedPreferences: true),
          );

  final FlutterSecureStorage _storage;

  static const _dbPasswordKey = 'db_password_v1';
  static const _identityPairKey = 'e2ee_identity_pair_v1';
  static const _registrationIdKey = 'e2ee_registration_id_v1';
  static const _deviceIdKey = 'e2ee_device_id_v1';
  static const _appPinKey = 'app_pin_hash_v1';

  Future<String> databasePassword() async {
    final existing = await _storage.read(key: _dbPasswordKey);
    if (existing != null && existing.isNotEmpty) return existing;
    final random = Random.secure();
    final bytes = Uint8List.fromList(
      List<int>.generate(32, (_) => random.nextInt(256)),
    );
    final value = base64UrlEncode(bytes);
    await _storage.write(key: _dbPasswordKey, value: value);
    return value;
  }

  Future<String?> readIdentityPair() => _storage.read(key: _identityPairKey);

  Future<void> writeIdentityPair(String value) =>
      _storage.write(key: _identityPairKey, value: value);

  Future<int?> readRegistrationId() async {
    final value = await _storage.read(key: _registrationIdKey);
    return value == null ? null : int.tryParse(value);
  }

  Future<void> writeRegistrationId(int value) =>
      _storage.write(key: _registrationIdKey, value: '$value');

  Future<String?> readDeviceId() => _storage.read(key: _deviceIdKey);

  Future<void> writeDeviceId(String value) =>
      _storage.write(key: _deviceIdKey, value: value);

  Future<String?> readPinHash() => _storage.read(key: _appPinKey);

  Future<void> writePinHash(String value) =>
      _storage.write(key: _appPinKey, value: value);

  Future<void> clearE2eeKeys() async {
    await _storage.delete(key: _identityPairKey);
    await _storage.delete(key: _registrationIdKey);
    await _storage.delete(key: _deviceIdKey);
  }

  Future<void> clearAll() async {
    await _storage.deleteAll();
  }
}
