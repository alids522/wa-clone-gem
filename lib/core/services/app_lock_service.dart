import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../storage/secure_store.dart';

/// App Lock: a salted, iterated SHA-256 PIN hash kept in the Android Keystore
/// backed secure store, plus an optional biometric gate via `local_auth`.
///
/// The PIN never leaves the device and is never written to preferences or
/// logs. Only the enabled flags and the auto-lock timeout are stored in
/// [SharedPreferences] because they are not secrets.
class AppLockService {
  AppLockService({
    required SecureStore secure,
    required SharedPreferences prefs,
    LocalAuthentication? auth,
  }) : _secure = secure,
       _prefs = prefs,
       _auth = auth ?? LocalAuthentication();

  final SecureStore _secure;
  final SharedPreferences _prefs;
  final LocalAuthentication _auth;

  static const _enabledKey = 'app_lock_enabled_v1';
  static const _biometricKey = 'app_lock_biometric_v1';
  static const _timeoutKey = 'app_lock_timeout_seconds_v1';
  static const _failedKey = 'app_lock_failed_v1';
  static const _cooldownKey = 'app_lock_cooldown_v1';

  static const _hashIterations = 24000;
  static const _maxAttempts = 5;
  static const _cooldownPenalty = Duration(seconds: 30);

  static const pinLength = 4;

  bool get enabled => _prefs.getBool(_enabledKey) ?? false;

  bool get biometricsEnabled => _prefs.getBool(_biometricKey) ?? false;

  /// How long the app may stay in the background before it locks again.
  Duration get lockTimeout =>
      Duration(seconds: _prefs.getInt(_timeoutKey) ?? 30);

  Future<void> setLockTimeout(Duration value) =>
      _prefs.setInt(_timeoutKey, value.inSeconds);

  /// False until [load] has run on a cold start.
  bool get hasPin => (_cachedPinHash ?? '').isNotEmpty;

  String? _cachedPinHash;

  /// Loads the stored hash once so verification does not touch the Keystore on
  /// every keypad tap.
  Future<void> load() async {
    final stored = await _secure.readPinHash();
    _cachedPinHash = (stored == null || stored.isEmpty) ? null : stored;
  }

  Future<void> setPin(String pin) async {
    final salt = List<int>.generate(16, (_) => Random.secure().nextInt(256));
    final hash = _derive(pin, salt);
    final encoded = '${base64Encode(salt)}:${base64Encode(hash)}';
    await _secure.writePinHash(encoded);
    _cachedPinHash = encoded;
    await _resetFailures();
  }

  Future<bool> verifyPin(String pin) async {
    if (_cooldownRemaining > Duration.zero) return false;
    final stored = _cachedPinHash ?? await _secure.readPinHash();
    _cachedPinHash = stored;
    if (stored == null) return false;
    final parts = stored.split(':');
    if (parts.length != 2) return false;
    final salt = base64Decode(parts[0]);
    final expected = parts[1];
    final candidate = base64Encode(_derive(pin, salt));
    // Constant-time comparison keeps timing from leaking the hash prefix.
    if (!_constantTimeEquals(candidate, expected)) {
      await _recordFailure();
      return false;
    }
    await _resetFailures();
    return true;
  }

  Duration get _cooldownRemaining {
    final until = _prefs.getInt(_cooldownKey) ?? 0;
    if (until == 0) return Duration.zero;
    final remaining = DateTime.fromMillisecondsSinceEpoch(
      until,
    ).difference(DateTime.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  Future<void> _recordFailure() async {
    final failures = (_prefs.getInt(_failedKey) ?? 0) + 1;
    await _prefs.setInt(_failedKey, failures);
    if (failures >= _maxAttempts) {
      await _prefs.setInt(
        _cooldownKey,
        DateTime.now().add(_cooldownPenalty).millisecondsSinceEpoch,
      );
      await _prefs.setInt(_failedKey, 0);
    }
  }

  Future<void> _resetFailures() async {
    await _prefs.remove(_failedKey);
    await _prefs.remove(_cooldownKey);
  }

  String? get cooldownMessage {
    final remaining = _cooldownRemaining;
    if (remaining == Duration.zero) return null;
    return 'Terlalu banyak percobaan. Coba lagi dalam '
        '${remaining.inSeconds + 1} detik.';
  }

  Future<void> enable() async {
    await _prefs.setBool(_enabledKey, true);
  }

  Future<void> disable() async {
    await _prefs.setBool(_enabledKey, false);
    await _prefs.setBool(_biometricKey, false);
    await _secure.writePinHash('');
    _cachedPinHash = null;
    await _resetFailures();
  }

  Future<void> setBiometricsEnabled(bool value) =>
      _prefs.setBool(_biometricKey, value);

  Future<bool> get canUseBiometrics async {
    try {
      if (!await _auth.isDeviceSupported()) return false;
      final available = await _auth.getAvailableBiometrics();
      return available.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Shows the OS biometric prompt. Returns true only on a successful scan.
  Future<bool> authenticateBiometrically() async {
    try {
      return await _auth.authenticate(
        localizedReason: 'Buka Adoetz Chat',
        options: const AuthenticationOptions(
          biometricOnly: false,
          stickyAuth: true,
          useErrorDialogs: true,
        ),
      );
    } catch (_) {
      return false;
    }
  }

  static List<int> _derive(String pin, List<int> salt) {
    var block = <int>[...salt, ...utf8.encode(pin)];
    for (var i = 0; i < _hashIterations; i++) {
      block = sha256.convert(block).bytes;
    }
    return block;
  }

  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }
}
