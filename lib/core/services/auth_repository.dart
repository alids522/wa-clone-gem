import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/profile.dart';
import '../utils/app_error.dart';

class SignUpResult {
  const SignUpResult({required this.email, required this.username});

  final String email;
  final String username;
}

class AuthRepository {
  AuthRepository(this._client);

  final SupabaseClient _client;

  SupabaseClient get client => _client;

  Session? get session => _client.auth.currentSession;
  User? get user => _client.auth.currentUser;

  Future<void> signInWithPassword({
    required String identifier,
    required String password,
  }) async {
    final trimmed = identifier.trim();
    if (trimmed.contains('@')) {
      await _client.auth.signInWithPassword(
        email: trimmed.toLowerCase(),
        password: password,
      );
      return;
    }

    final response = await _client.functions.invoke(
      'login-identifier',
      body: {'identifier': trimmed.toLowerCase(), 'password': password},
    );
    final data = _asMap(response.data);
    final accessToken = data['access_token'] as String?;
    final refreshToken = data['refresh_token'] as String?;
    if (accessToken == null || refreshToken == null) {
      throw const AppError(
        'AUTH_FAILED',
        'Username atau password tidak sesuai.',
      );
    }
    await _client.auth.setSession(refreshToken);
  }

  Future<SignUpResult> signUp({
    required String inviteCode,
    required String username,
    required String email,
    required String password,
    required String displayName,
  }) async {
    final response = await _client.functions.invoke(
      'redeem-invite-register',
      body: {
        'invite_code': inviteCode.trim(),
        'username': username.trim().toLowerCase(),
        'email': email.trim().toLowerCase(),
        'password': password,
        'display_name': displayName.trim(),
      },
    );
    final data = _asMap(response.data);
    if (data['success'] == false) {
      throw AppError(
        data['code'] as String? ?? 'REGISTER_FAILED',
        data['message'] as String? ?? 'Pendaftaran gagal. Coba lagi.',
      );
    }

    await _client.auth.signInWithPassword(
      email: email.trim().toLowerCase(),
      password: password,
    );
    return SignUpResult(
      email: email.trim().toLowerCase(),
      username: username.trim().toLowerCase(),
    );
  }

  /// Pre-flight check for the sign-up form.
  ///
  /// Returns null when the check could not run (offline, function missing),
  /// so the form never blocks a valid registration on a transient failure.
  Future<bool?> usernameAvailable(String username) async {
    try {
      final response = await _client.functions.invoke(
        'username-availability',
        body: {'username': username},
      );
      final data = _asMap(response.data);
      final available = data['available'];
      return available is bool ? available : null;
    } catch (_) {
      return null;
    }
  }

  Future<Profile> loadAccount() async {
    try {
      final response = await _client.rpc('get_my_account');
      final map = _asMap(response);
      return Profile.fromMap(map);
    } on PostgrestException catch (error) {
      if (error.message.contains('PROFILE_MISSING')) {
        throw const AppError(
          'PROFILE_MISSING',
          'Profil akun belum selesai dibuat. Hubungi admin.',
          retryable: true,
          cause: null,
        );
      }
      rethrow;
    }
  }

  Future<void> signOut() async {
    try {
      await _client.auth.signOut(scope: SignOutScope.local);
    } on AuthException {
      // Local sign-out must still succeed when the network is down.
    }
  }

  Future<void> refreshSession() async {
    await _client.auth.refreshSession();
  }

  Stream<AuthState> get onAuthStateChange => _client.auth.onAuthStateChange;

  Map<String, dynamic> _asMap(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return value.cast<String, dynamic>();
    if (value is String && value.isNotEmpty) {
      return {'message': value};
    }
    return const {};
  }
}
