enum AccountRole { user, admin }

enum AccountStatus { active, suspended, deleted }

AccountStatus accountStatusFromWire(String? value) {
  switch (value) {
    case 'suspended':
      return AccountStatus.suspended;
    case 'deleted':
      return AccountStatus.deleted;
    default:
      return AccountStatus.active;
  }
}

AccountRole accountRoleFromWire(String? value) =>
    value == 'admin' ? AccountRole.admin : AccountRole.user;

class Profile {
  const Profile({
    required this.userId,
    required this.username,
    required this.displayName,
    this.avatarPath,
    this.bio = '',
    this.discoverable = true,
    this.role = AccountRole.user,
    this.status = AccountStatus.active,
    this.createdAt,
    this.email,
    this.lastSignInAt,
  });

  final String userId;
  final String username;
  final String displayName;
  final String? avatarPath;
  final String bio;
  final bool discoverable;
  final AccountRole role;
  final AccountStatus status;
  final DateTime? createdAt;
  final String? email;
  final DateTime? lastSignInAt;

  bool get isAdmin => role == AccountRole.admin;
  bool get isActive => status == AccountStatus.active;

  String get label => displayName.trim().isEmpty ? '@$username' : displayName;

  Profile copyWith({
    String? username,
    String? displayName,
    String? avatarPath,
    String? bio,
    bool? discoverable,
    AccountRole? role,
    AccountStatus? status,
    String? email,
    DateTime? lastSignInAt,
  }) {
    return Profile(
      userId: userId,
      username: username ?? this.username,
      displayName: displayName ?? this.displayName,
      avatarPath: avatarPath ?? this.avatarPath,
      bio: bio ?? this.bio,
      discoverable: discoverable ?? this.discoverable,
      role: role ?? this.role,
      status: status ?? this.status,
      createdAt: createdAt,
      email: email ?? this.email,
      lastSignInAt: lastSignInAt ?? this.lastSignInAt,
    );
  }

  factory Profile.fromMap(Map<String, dynamic> map) {
    return Profile(
      userId: map['user_id'] as String,
      username: map['username'] as String? ?? '',
      displayName: map['display_name'] as String? ?? '',
      avatarPath: map['avatar_path'] as String?,
      bio: map['bio'] as String? ?? '',
      discoverable: map['discoverable'] as bool? ?? true,
      role: _roleFrom(map['role'] as String?),
      status: _statusFrom(map['status'] as String?),
      createdAt: _date(map['created_at']),
      email: map['email'] as String?,
      lastSignInAt: _date(map['last_sign_in_at']),
    );
  }

  static AccountRole _roleFrom(String? value) =>
      value == 'admin' ? AccountRole.admin : AccountRole.user;

  static AccountStatus _statusFrom(String? value) {
    switch (value) {
      case 'suspended':
        return AccountStatus.suspended;
      case 'deleted':
        return AccountStatus.deleted;
      default:
        return AccountStatus.active;
    }
  }

  static DateTime? _date(Object? value) {
    if (value is! String || value.isEmpty) return null;
    return DateTime.tryParse(value);
  }
}
