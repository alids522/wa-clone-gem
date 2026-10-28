import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/app_error.dart';

DateTime? _date(Object? value) => value is String && value.isNotEmpty
    ? DateTime.tryParse(value)?.toLocal()
    : null;

class AdminStats {
  const AdminStats({
    required this.totalUsers,
    required this.activeUsers,
    required this.suspendedUsers,
    required this.pendingInvites,
    required this.activeInvites,
    required this.recentActions,
  });

  final int totalUsers;
  final int activeUsers;
  final int suspendedUsers;
  final int pendingInvites;
  final int activeInvites;
  final List<AdminAuditEntry> recentActions;

  factory AdminStats.fromMap(Map<String, dynamic> map) {
    int count(String key) => (map[key] as num?)?.toInt() ?? 0;
    return AdminStats(
      totalUsers: count('total_users'),
      activeUsers: count('active_users'),
      suspendedUsers: count('suspended_users'),
      pendingInvites: count('pending_invites'),
      activeInvites: count('active_invites'),
      recentActions: ((map['recent_actions'] as List<dynamic>?) ?? const [])
          .whereType<Map>()
          .map((raw) => AdminAuditEntry.fromMap(raw.cast<String, dynamic>()))
          .toList(growable: false),
    );
  }
}

class AdminUserSummary {
  const AdminUserSummary({
    required this.userId,
    required this.username,
    required this.displayName,
    required this.role,
    required this.status,
    this.avatarPath,
    this.email,
    this.createdAt,
    this.lastSignInAt,
    this.deviceCount = 0,
  });

  final String userId;
  final String username;
  final String displayName;
  final String role;
  final String status;
  final String? avatarPath;
  final String? email;
  final DateTime? createdAt;
  final DateTime? lastSignInAt;
  final int deviceCount;

  String get label => displayName.trim().isEmpty ? '@$username' : displayName;

  bool get isAdmin => role == 'admin';
  bool get isSuspended => status == 'suspended';

  factory AdminUserSummary.fromMap(Map<String, dynamic> map) {
    return AdminUserSummary(
      userId: map['user_id'] as String,
      username: map['username'] as String? ?? '',
      displayName: map['display_name'] as String? ?? '',
      role: map['role'] as String? ?? 'user',
      status: map['status'] as String? ?? 'active',
      avatarPath: map['avatar_path'] as String?,
      email: map['email'] as String?,
      createdAt: _date(map['created_at']),
      lastSignInAt: _date(map['last_sign_in_at']),
      deviceCount: (map['device_count'] as num?)?.toInt() ?? 0,
    );
  }
}

class AdminUserPage {
  const AdminUserPage({
    required this.users,
    required this.total,
    required this.hasMore,
  });

  final List<AdminUserSummary> users;
  final int total;
  final bool hasMore;
}

class AdminUserDetail {
  const AdminUserDetail({
    required this.summary,
    required this.bio,
    required this.discoverable,
    required this.devices,
    this.suspendedAt,
    this.reasonCode,
  });

  final AdminUserSummary summary;
  final String bio;
  final bool discoverable;
  final List<Map<String, dynamic>> devices;
  final DateTime? suspendedAt;
  final String? reasonCode;

  factory AdminUserDetail.fromMap(Map<String, dynamic> map) {
    return AdminUserDetail(
      summary: AdminUserSummary.fromMap(map),
      bio: map['bio'] as String? ?? '',
      discoverable: map['discoverable'] as bool? ?? true,
      devices: ((map['devices'] as List<dynamic>?) ?? const [])
          .whereType<Map>()
          .map((raw) => raw.cast<String, dynamic>())
          .toList(growable: false),
      suspendedAt: _date(map['suspended_at']),
      reasonCode: map['reason_code'] as String?,
    );
  }
}

class Invitation {
  const Invitation({
    required this.id,
    required this.status,
    required this.maxUses,
    required this.usedCount,
    required this.createdAt,
    this.expiresAt,
    this.label,
    this.intendedFor,
    this.createdByUsername,
  });

  final String id;
  final String status;
  final int maxUses;
  final int usedCount;
  final DateTime createdAt;
  final DateTime? expiresAt;
  final String? label;
  final String? intendedFor;
  final String? createdByUsername;

  bool get isActive => status == 'active';
  bool get isExhausted => usedCount >= maxUses;
  bool get isExpired =>
      expiresAt != null && expiresAt!.isBefore(DateTime.now());

  String get stateLabel {
    if (!isActive) return status == 'revoked' ? 'Dicabut' : status;
    if (isExpired) return 'Kedaluwarsa';
    if (isExhausted) return 'Habis';
    return 'Aktif';
  }

  factory Invitation.fromMap(Map<String, dynamic> map) {
    return Invitation(
      id: map['id'] as String,
      status: map['status'] as String? ?? 'active',
      maxUses: (map['max_uses'] as num?)?.toInt() ?? 1,
      usedCount: (map['used_count'] as num?)?.toInt() ?? 0,
      createdAt: _date(map['created_at']) ?? DateTime.now(),
      expiresAt: _date(map['expires_at']),
      label: map['label'] as String?,
      intendedFor: map['intended_for'] as String?,
      createdByUsername: map['created_by_username'] as String?,
    );
  }
}

class AdminAuditEntry {
  const AdminAuditEntry({
    required this.id,
    required this.action,
    required this.result,
    required this.createdAt,
    this.reason,
    this.actorUsername,
    this.targetUsername,
  });

  final int id;
  final String action;
  final String result;
  final DateTime createdAt;
  final String? reason;
  final String? actorUsername;
  final String? targetUsername;

  factory AdminAuditEntry.fromMap(Map<String, dynamic> map) {
    return AdminAuditEntry(
      id: (map['id'] as num?)?.toInt() ?? 0,
      action: map['action'] as String? ?? 'unknown',
      result: map['result'] as String? ?? 'success',
      createdAt: _date(map['created_at']) ?? DateTime.now(),
      reason: map['reason'] as String?,
      actorUsername: map['actor_username'] as String?,
      targetUsername: map['target_username'] as String?,
    );
  }
}

class CreatedInvitation {
  const CreatedInvitation({required this.id, required this.rawCode});

  final String id;
  final String rawCode;
}

class AdminReport {
  const AdminReport({
    required this.id,
    required this.reportedUserId,
    required this.reason,
    required this.status,
    required this.createdAt,
    this.reporterUsername,
    this.reportedUsername,
    this.reportedDisplayName,
    this.details,
    this.sharedContent,
    this.resolutionNote,
    this.reviewedAt,
  });

  final String id;
  final String reportedUserId;
  final String reason;
  final String status;
  final DateTime createdAt;
  final String? reporterUsername;
  final String? reportedUsername;
  final String? reportedDisplayName;
  final String? details;
  final String? sharedContent;
  final String? resolutionNote;
  final DateTime? reviewedAt;

  String get targetLabel {
    final name = reportedDisplayName?.trim() ?? '';
    if (name.isNotEmpty) return name;
    final username = reportedUsername?.trim() ?? '';
    return username.isEmpty ? reportedUserId : '@$username';
  }

  factory AdminReport.fromMap(Map<String, dynamic> map) {
    return AdminReport(
      id: map['id'] as String,
      reportedUserId: map['reported_user_id'] as String,
      reason: map['reason'] as String? ?? 'other',
      status: map['status'] as String? ?? 'open',
      createdAt: _date(map['created_at']) ?? DateTime.now(),
      reporterUsername: map['reporter_username'] as String?,
      reportedUsername: map['reported_username'] as String?,
      reportedDisplayName: map['reported_display_name'] as String?,
      details: map['details'] as String?,
      sharedContent: map['shared_content'] as String?,
      resolutionNote: map['resolution_note'] as String?,
      reviewedAt: _date(map['reviewed_at']),
    );
  }
}

/// Thin wrapper over the admin SECURITY DEFINER RPCs. Authorisation is
/// enforced server-side by `public.is_admin()` on every call.
class AdminRepository {
  AdminRepository(this._client);

  final SupabaseClient _client;

  Future<AdminStats> stats() async {
    try {
      final response = await _client.rpc('admin_dashboard_stats');
      return AdminStats.fromMap((response as Map).cast<String, dynamic>());
    } catch (error) {
      throw mapError(error);
    }
  }

  Future<AdminUserPage> listUsers({
    String? query,
    String? role,
    String? status,
    int limit = 20,
    int offset = 0,
  }) async {
    try {
      final response = await _client.rpc(
        'admin_list_users',
        params: {
          'p_query': (query ?? '').trim().isEmpty ? null : query!.trim(),
          'p_role': role,
          'p_status': status,
          'p_limit': limit,
          'p_offset': offset,
        },
      );
      final map = (response as Map).cast<String, dynamic>();
      return AdminUserPage(
        users: ((map['users'] as List<dynamic>?) ?? const [])
            .whereType<Map>()
            .map((raw) => AdminUserSummary.fromMap(raw.cast<String, dynamic>()))
            .toList(growable: false),
        total: (map['total'] as num?)?.toInt() ?? 0,
        hasMore: map['has_more'] as bool? ?? false,
      );
    } catch (error) {
      throw mapError(error);
    }
  }

  Future<AdminUserDetail> user(String userId) async {
    try {
      final response = await _client.rpc(
        'admin_get_user',
        params: {'p_user_id': userId},
      );
      return AdminUserDetail.fromMap((response as Map).cast<String, dynamic>());
    } catch (error) {
      throw mapError(error);
    }
  }

  Future<void> setRole(String userId, String role, String? reason) async {
    try {
      await _client.rpc(
        'admin_set_user_role',
        params: {'p_target_id': userId, 'p_role': role, 'p_reason': reason},
      );
    } catch (error) {
      throw mapError(error);
    }
  }

  Future<void> setStatus(String userId, String status, String reason) async {
    try {
      await _client.rpc(
        'admin_set_user_status',
        params: {'p_target_id': userId, 'p_status': status, 'p_reason': reason},
      );
    } catch (error) {
      throw mapError(error);
    }
  }

  Future<List<Invitation>> invitations({String? status}) async {
    try {
      final response = await _client.rpc(
        'admin_list_invitations',
        params: {'p_status': status},
      );
      return ((response as List<dynamic>?) ?? const [])
          .whereType<Map>()
          .map((raw) => Invitation.fromMap(raw.cast<String, dynamic>()))
          .toList(growable: false);
    } catch (error) {
      throw mapError(error);
    }
  }

  Future<CreatedInvitation> createInvitation({
    String? label,
    int maxUses = 1,
    DateTime? expiresAt,
    String? intendedFor,
  }) async {
    try {
      final response = await _client.rpc(
        'admin_create_invitation',
        params: {
          'p_label': label,
          'p_max_uses': maxUses,
          'p_expires_at': expiresAt?.toUtc().toIso8601String(),
          'p_intended_for': intendedFor,
        },
      );
      final map = (response as Map).cast<String, dynamic>();
      return CreatedInvitation(
        id: map['id'] as String,
        rawCode: map['raw_code'] as String,
      );
    } catch (error) {
      throw mapError(error);
    }
  }

  Future<void> revokeInvitation(String id, String reason) async {
    try {
      await _client.rpc(
        'admin_revoke_invitation',
        params: {'p_invitation_id': id, 'p_reason': reason},
      );
    } catch (error) {
      throw mapError(error);
    }
  }

  Future<List<AdminReport>> reports({
    String? status,
    int limit = 50,
    int offset = 0,
  }) async {
    try {
      final response = await _client.rpc(
        'admin_list_reports',
        params: {'p_status': status, 'p_limit': limit, 'p_offset': offset},
      );
      return ((response as List<dynamic>?) ?? const [])
          .whereType<Map>()
          .map((raw) => AdminReport.fromMap(raw.cast<String, dynamic>()))
          .toList(growable: false);
    } catch (error) {
      throw mapError(error);
    }
  }

  Future<void> updateReport({
    required String reportId,
    required String status,
    String? note,
  }) async {
    try {
      await _client.rpc(
        'admin_update_report',
        params: {'p_report_id': reportId, 'p_status': status, 'p_note': note},
      );
    } catch (error) {
      throw mapError(error);
    }
  }

  Future<List<AdminAuditEntry>> auditLogs({
    int limit = 50,
    int offset = 0,
    String? action,
    String? query,
  }) async {
    try {
      final response = await _client.rpc(
        'admin_list_audit_logs',
        params: {
          'p_limit': limit,
          'p_offset': offset,
          'p_action': action,
          'p_query': (query ?? '').trim().isEmpty ? null : query!.trim(),
        },
      );
      return ((response as List<dynamic>?) ?? const [])
          .whereType<Map>()
          .map((raw) => AdminAuditEntry.fromMap(raw.cast<String, dynamic>()))
          .toList(growable: false);
    } catch (error) {
      throw mapError(error);
    }
  }
}
