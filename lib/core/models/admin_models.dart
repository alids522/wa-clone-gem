import 'profile.dart';

class AdminDashboardStats {
  const AdminDashboardStats({
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
  final List<AuditLogEntry> recentActions;

  factory AdminDashboardStats.fromMap(Map<String, dynamic> map) {
    return AdminDashboardStats(
      totalUsers: (map['total_users'] as num?)?.toInt() ?? 0,
      activeUsers: (map['active_users'] as num?)?.toInt() ?? 0,
      suspendedUsers: (map['suspended_users'] as num?)?.toInt() ?? 0,
      pendingInvites: (map['pending_invites'] as num?)?.toInt() ?? 0,
      activeInvites: (map['active_invites'] as num?)?.toInt() ?? 0,
      recentActions: (map['recent_actions'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(AuditLogEntry.fromMap)
          .toList(growable: false),
    );
  }
}

class AdminUser {
  const AdminUser({
    required this.profile,
    required this.status,
    this.createdAt,
    this.lastSignInAt,
    this.deviceCount = 0,
  });

  final Profile profile;
  final AccountStatus status;
  final DateTime? createdAt;
  final DateTime? lastSignInAt;
  final int deviceCount;

  bool get isSuspended => status == AccountStatus.suspended;

  factory AdminUser.fromMap(Map<String, dynamic> map) {
    return AdminUser(
      profile: Profile.fromMap(map),
      status: accountStatusFromWire(map['status'] as String?),
      createdAt: _date(map['created_at']),
      lastSignInAt: _date(map['last_sign_in_at']),
      deviceCount: (map['device_count'] as num?)?.toInt() ?? 0,
    );
  }

  static DateTime? _date(Object? value) {
    if (value is! String || value.isEmpty) return null;
    return DateTime.tryParse(value)?.toLocal();
  }
}

class AdminUserPage {
  const AdminUserPage({
    required this.users,
    required this.total,
    required this.hasMore,
  });

  final List<AdminUser> users;
  final int total;
  final bool hasMore;

  factory AdminUserPage.fromMap(Map<String, dynamic> map) {
    return AdminUserPage(
      users: (map['users'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(AdminUser.fromMap)
          .toList(growable: false),
      total: (map['total'] as num?)?.toInt() ?? 0,
      hasMore: map['has_more'] as bool? ?? false,
    );
  }
}

class Invitation {
  const Invitation({
    required this.id,
    required this.status,
    required this.maxUses,
    required this.usedCount,
    required this.expiresAt,
    required this.createdAt,
    this.label,
    this.intendedFor,
    this.rawCode,
  });

  final String id;
  final String status;
  final int maxUses;
  final int usedCount;
  final DateTime expiresAt;
  final DateTime createdAt;
  final String? label;
  final String? intendedFor;

  /// Only present in the creation response; server stores SHA-256 only.
  final String? rawCode;

  bool get isExpired => expiresAt.isBefore(DateTime.now());
  bool get isExhausted => usedCount >= maxUses;
  bool get isActive => status == 'active' && !isExpired && !isExhausted;

  String get statusLabel {
    if (status == 'revoked') return 'Dicabut';
    if (isExpired) return 'Kedaluwarsa';
    if (isExhausted) return 'Sudah dipakai';
    return 'Aktif';
  }

  factory Invitation.fromMap(Map<String, dynamic> map) {
    return Invitation(
      id: map['id'] as String,
      status: map['status'] as String? ?? 'active',
      maxUses: (map['max_uses'] as num?)?.toInt() ?? 1,
      usedCount: (map['used_count'] as num?)?.toInt() ?? 0,
      expiresAt:
          DateTime.tryParse(map['expires_at'] as String? ?? '')?.toLocal() ??
          DateTime.now(),
      createdAt:
          DateTime.tryParse(map['created_at'] as String? ?? '')?.toLocal() ??
          DateTime.now(),
      label: map['label'] as String?,
      intendedFor: map['intended_for'] as String?,
      rawCode: map['raw_code'] as String?,
    );
  }
}

class AuditLogEntry {
  const AuditLogEntry({
    required this.id,
    required this.action,
    required this.createdAt,
    this.actorId,
    this.actorUsername,
    this.targetId,
    this.targetUsername,
    this.reason,
    this.result = 'success',
    this.requestId,
  });

  final String id;
  final String action;
  final DateTime createdAt;
  final String? actorId;
  final String? actorUsername;
  final String? targetId;
  final String? targetUsername;
  final String? reason;
  final String result;
  final String? requestId;

  bool get isFailure => result != 'success';

  factory AuditLogEntry.fromMap(Map<String, dynamic> map) {
    return AuditLogEntry(
      id: map['id'] as String,
      action: map['action'] as String? ?? 'unknown',
      createdAt:
          DateTime.tryParse(map['created_at'] as String? ?? '')?.toLocal() ??
          DateTime.now(),
      actorId: map['actor_id'] as String?,
      actorUsername: map['actor_username'] as String?,
      targetId: map['target_id'] as String?,
      targetUsername: map['target_username'] as String?,
      reason: map['reason'] as String?,
      result: map['result'] as String? ?? 'success',
      requestId: map['request_id'] as String?,
    );
  }
}
