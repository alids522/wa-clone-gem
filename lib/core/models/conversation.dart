import 'message.dart';

class ConversationSummary {
  const ConversationSummary({
    required this.id,
    required this.peerId,
    required this.peerUsername,
    required this.peerDisplayName,
    this.peerAvatarPath,
    this.lastMessageId,
    this.lastMessageSenderId,
    this.lastMessageCiphertext,
    this.lastMessageProtocolVersion = 3,
    this.lastMessageKind = MessageKind.text,
    this.lastMessageAt,
    this.lastMessagePreview,
    this.unreadCount = 0,
    this.pinned = false,
    this.muted = false,
    this.peerIdentityChanged = false,
  });

  final String id;
  final String peerId;
  final String peerUsername;
  final String peerDisplayName;
  final String? peerAvatarPath;
  final String? lastMessageId;
  final String? lastMessageSenderId;
  final String? lastMessageCiphertext;
  final int lastMessageProtocolVersion;
  final MessageKind lastMessageKind;
  final DateTime? lastMessageAt;
  final String? lastMessagePreview;
  final int unreadCount;
  final bool pinned;
  final bool muted;
  final bool peerIdentityChanged;

  String get title =>
      peerDisplayName.trim().isEmpty ? '@$peerUsername' : peerDisplayName;

  String get subtitle {
    if (lastMessagePreview != null && lastMessagePreview!.isNotEmpty) {
      return lastMessagePreview!;
    }
    if (lastMessageId == null) return 'Mulai percakapan';
    return lastMessageKind.fallbackPreview;
  }

  ConversationSummary copyWith({
    String? lastMessageId,
    String? lastMessageSenderId,
    String? lastMessageCiphertext,
    int? lastMessageProtocolVersion,
    MessageKind? lastMessageKind,
    DateTime? lastMessageAt,
    String? lastMessagePreview,
    int? unreadCount,
    bool? pinned,
    bool? muted,
    bool? peerIdentityChanged,
  }) {
    return ConversationSummary(
      id: id,
      peerId: peerId,
      peerUsername: peerUsername,
      peerDisplayName: peerDisplayName,
      peerAvatarPath: peerAvatarPath,
      lastMessageId: lastMessageId ?? this.lastMessageId,
      lastMessageSenderId: lastMessageSenderId ?? this.lastMessageSenderId,
      lastMessageCiphertext:
          lastMessageCiphertext ?? this.lastMessageCiphertext,
      lastMessageProtocolVersion:
          lastMessageProtocolVersion ?? this.lastMessageProtocolVersion,
      lastMessageKind: lastMessageKind ?? this.lastMessageKind,
      lastMessageAt: lastMessageAt ?? this.lastMessageAt,
      lastMessagePreview: lastMessagePreview ?? this.lastMessagePreview,
      unreadCount: unreadCount ?? this.unreadCount,
      pinned: pinned ?? this.pinned,
      muted: muted ?? this.muted,
      peerIdentityChanged: peerIdentityChanged ?? this.peerIdentityChanged,
    );
  }

  factory ConversationSummary.fromMap(Map<String, dynamic> map) {
    return ConversationSummary(
      id: map['conversation_id'] as String,
      peerId: map['peer_id'] as String,
      peerUsername: map['peer_username'] as String? ?? '',
      peerDisplayName: map['peer_display_name'] as String? ?? '',
      peerAvatarPath: map['peer_avatar_path'] as String?,
      lastMessageId: map['last_message_id'] as String?,
      lastMessageSenderId: map['last_message_sender_id'] as String?,
      lastMessageCiphertext: map['last_message_ciphertext'] as String?,
      lastMessageProtocolVersion:
          (map['last_message_protocol_version'] as num?)?.toInt() ?? 3,
      lastMessageKind: MessageKindX.fromWire(
        map['last_message_type'] as String?,
      ),
      lastMessageAt: _date(map['last_message_at']),
      lastMessagePreview: map['last_message_preview'] as String?,
      unreadCount: (map['unread_count'] as num?)?.toInt() ?? 0,
      pinned: map['pinned'] as bool? ?? false,
      muted: map['muted'] as bool? ?? false,
      peerIdentityChanged: map['peer_identity_changed'] as bool? ?? false,
    );
  }

  static DateTime? _date(Object? value) {
    if (value is! String || value.isEmpty) return null;
    return DateTime.tryParse(value)?.toLocal();
  }
}

class PeerProfile {
  const PeerProfile({
    required this.userId,
    required this.username,
    required this.displayName,
    this.avatarPath,
    this.bio = '',
    this.discoverable = true,
    this.identityFingerprint,
    this.identityChanged = false,
  });

  final String userId;
  final String username;
  final String displayName;
  final String? avatarPath;
  final String bio;
  final bool discoverable;
  final String? identityFingerprint;
  final bool identityChanged;

  String get title => displayName.trim().isEmpty ? '@$username' : displayName;

  factory PeerProfile.fromMap(Map<String, dynamic> map) {
    return PeerProfile(
      userId: map['user_id'] as String,
      username: map['username'] as String? ?? '',
      displayName: map['display_name'] as String? ?? '',
      avatarPath: map['avatar_path'] as String?,
      bio: map['bio'] as String? ?? '',
      discoverable: map['discoverable'] as bool? ?? true,
      identityFingerprint: map['identity_fingerprint'] as String?,
      identityChanged: map['identity_changed'] as bool? ?? false,
    );
  }
}
