import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../crypto/e2ee_service.dart';
import '../models/conversation.dart';
import '../models/profile.dart';
import '../utils/app_error.dart';
import 'media_service.dart';

class UserPreferences {
  const UserPreferences({
    this.theme = 'system',
    this.readReceipts = true,
    this.typingIndicators = true,
    this.notificationPrivacy = 'sender',
  });

  final String theme;
  final bool readReceipts;
  final bool typingIndicators;
  final String notificationPrivacy;

  UserPreferences copyWith({
    String? theme,
    bool? readReceipts,
    bool? typingIndicators,
    String? notificationPrivacy,
  }) {
    return UserPreferences(
      theme: theme ?? this.theme,
      readReceipts: readReceipts ?? this.readReceipts,
      typingIndicators: typingIndicators ?? this.typingIndicators,
      notificationPrivacy: notificationPrivacy ?? this.notificationPrivacy,
    );
  }

  factory UserPreferences.fromMap(Map<String, dynamic> map) {
    return UserPreferences(
      theme: map['theme'] as String? ?? 'system',
      readReceipts: map['read_receipts'] as bool? ?? true,
      typingIndicators: map['typing_indicators'] as bool? ?? true,
      notificationPrivacy: map['notification_privacy'] as String? ?? 'sender',
    );
  }
}

class ProfileRepository {
  ProfileRepository({
    required SupabaseClient client,
    required MediaService media,
    required E2eeService e2ee,
  }) : _client = client,
       _media = media,
       _e2ee = e2ee;

  final SupabaseClient _client;
  final MediaService _media;
  final E2eeService _e2ee;

  Future<Profile> updateProfile({
    String? displayName,
    String? bio,
    bool? discoverable,
  }) async {
    final updates = <String, dynamic>{
      if (displayName != null) 'display_name': displayName.trim(),
      if (bio != null) 'bio': bio.trim().isEmpty ? null : bio.trim(),
      if (discoverable != null) 'discoverable': discoverable,
    };
    if (updates.isEmpty) {
      final response = await _client.rpc('get_my_account');
      return Profile.fromMap((response as Map).cast<String, dynamic>());
    }
    try {
      await _client
          .from('profiles')
          .update(updates)
          .eq('user_id', _client.auth.currentUser!.id);
    } catch (error) {
      throw mapError(error);
    }
    final response = await _client.rpc('get_my_account');
    return Profile.fromMap((response as Map).cast<String, dynamic>());
  }

  Future<Profile> changeAvatar(Uint8List bytes, String mime) async {
    final userId = _client.auth.currentUser!.id;
    final path = await _media.uploadAvatar(
      userId: userId,
      bytes: bytes,
      mime: mime,
    );
    await _client
        .from('profiles')
        .update({'avatar_path': path})
        .eq('user_id', userId);
    final response = await _client.rpc('get_my_account');
    return Profile.fromMap((response as Map).cast<String, dynamic>());
  }

  Future<String?> avatarUrl(String? path) => _media.avatarUrl(path);

  Future<PeerProfile> peerProfile(String userId) async {
    try {
      final response = await _client.rpc(
        'get_peer_profile',
        params: {'p_peer_id': userId},
      );
      final map = (response as Map).cast<String, dynamic>();
      String? fingerprint;
      try {
        final identity = await _client.rpc(
          'get_peer_identity',
          params: {'p_peer_id': userId},
        );
        if (identity is Map) {
          final key = identity['identity_key'] as String?;
          if (key != null && key.isNotEmpty) {
            fingerprint = _e2ee.fingerprintFromBase64(key);
          }
        }
      } catch (_) {}
      final stored = await _e2ee.peerFingerprint(userId);
      return PeerProfile.fromMap({
        ...map,
        'identity_fingerprint': stored ?? fingerprint,
        'identity_changed': false,
      });
    } catch (error) {
      throw mapError(error);
    }
  }

  Future<List<PeerProfile>> searchUsers(String query) async {
    try {
      final response = await _client.rpc(
        'search_users',
        params: {'p_query': query},
      );
      final list = (response as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(PeerProfile.fromMap)
          .toList(growable: false);
      return list;
    } catch (error) {
      throw mapError(error);
    }
  }

  Future<UserPreferences> loadPreferences() async {
    final rows = await _client
        .from('user_preferences')
        .select()
        .eq('user_id', _client.auth.currentUser!.id)
        .limit(1);
    if (rows.isEmpty) return const UserPreferences();
    return UserPreferences.fromMap(rows.first);
  }

  Future<UserPreferences> savePreferences(UserPreferences preferences) async {
    try {
      await _client.from('user_preferences').upsert({
        'user_id': _client.auth.currentUser!.id,
        'theme': preferences.theme,
        'read_receipts': preferences.readReceipts,
        'typing_indicators': preferences.typingIndicators,
        'notification_privacy': preferences.notificationPrivacy,
      });
      return preferences;
    } catch (error) {
      throw mapError(error);
    }
  }

  Future<void> blockUser(String userId) async {
    try {
      await _client.rpc('block_user', params: {'p_user_id': userId});
    } catch (error) {
      throw mapError(error);
    }
  }

  Future<void> unblockUser(String userId) async {
    try {
      await _client.rpc('unblock_user', params: {'p_user_id': userId});
    } catch (error) {
      throw mapError(error);
    }
  }

  Future<bool> isBlocked(String userId) async {
    try {
      final rows = await _client
          .from('blocked_users')
          .select('blocked_id')
          .eq('blocker_id', _client.auth.currentUser!.id)
          .eq('blocked_id', userId)
          .limit(1);
      return rows.isNotEmpty;
    } catch (_) {
      return false;
    }
  }
}
