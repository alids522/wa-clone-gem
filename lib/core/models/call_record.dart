enum CallType { voice, video }

enum CallDirection { incoming, outgoing }

enum CallStatus {
  ringing,
  connecting,
  connected,
  declined,
  missed,
  noAnswer,
  failed,
  ended,
  busy,
}

extension CallStatusX on CallStatus {
  String get wire {
    switch (this) {
      case CallStatus.noAnswer:
        return 'no_answer';
      default:
        return name;
    }
  }

  static CallStatus fromWire(String? value) {
    switch (value) {
      case 'no_answer':
        return CallStatus.noAnswer;
      case 'incoming':
        return CallStatus.ringing;
      case 'calling':
        return CallStatus.connecting;
      case 'reconnecting':
        return CallStatus.connecting;
      default:
        return CallStatus.values.firstWhere(
          (e) => e.name == value,
          orElse: () => CallStatus.ended,
        );
    }
  }
}

class CallRecord {
  const CallRecord({
    required this.id,
    required this.peerId,
    required this.peerName,
    required this.peerUsername,
    this.peerAvatarPath,
    required this.type,
    required this.direction,
    required this.status,
    required this.startedAt,
    this.endedAt,
    this.duration = Duration.zero,
  });

  final String id;
  final String peerId;
  final String peerName;
  final String peerUsername;
  final String? peerAvatarPath;
  final CallType type;
  final CallDirection direction;
  final CallStatus status;
  final DateTime startedAt;
  final DateTime? endedAt;
  final Duration duration;

  bool get isMissed =>
      status == CallStatus.missed ||
      status == CallStatus.declined ||
      status == CallStatus.noAnswer;

  Map<String, dynamic> toLocalMap() => {
    'id': id,
    'peer_id': peerId,
    'peer_name': peerName,
    'peer_username': peerUsername,
    'peer_avatar_path': peerAvatarPath,
    'type': type.name,
    'direction': direction.name,
    'status': status.wire,
    'started_at': startedAt.toUtc().toIso8601String(),
    'ended_at': endedAt?.toUtc().toIso8601String(),
    'duration_seconds': duration.inSeconds,
  };

  factory CallRecord.fromLocalMap(Map<String, Object?> map) {
    return CallRecord(
      id: map['id'] as String,
      peerId: map['peer_id'] as String,
      peerName: map['peer_name'] as String? ?? '',
      peerUsername: map['peer_username'] as String? ?? '',
      peerAvatarPath: map['peer_avatar_path'] as String?,
      type: map['type'] == 'video' ? CallType.video : CallType.voice,
      direction: map['direction'] == 'outgoing'
          ? CallDirection.outgoing
          : CallDirection.incoming,
      status: CallStatusX.fromWire(map['status'] as String?),
      startedAt:
          DateTime.tryParse(map['started_at'] as String? ?? '')?.toLocal() ??
          DateTime.now(),
      endedAt: DateTime.tryParse(map['ended_at'] as String? ?? '')?.toLocal(),
      duration: Duration(
        seconds: (map['duration_seconds'] as num?)?.toInt() ?? 0,
      ),
    );
  }

  factory CallRecord.fromServerMap(
    Map<String, dynamic> map, {
    required String currentUserId,
    required String peerId,
    required String peerName,
    String peerUsername = '',
    String? peerAvatarPath,
  }) {
    final started =
        DateTime.tryParse(map['started_at'] as String? ?? '')?.toLocal() ??
        DateTime.now();
    final ended = DateTime.tryParse(
      map['ended_at'] as String? ?? '',
    )?.toLocal();
    return CallRecord(
      id: map['id'] as String,
      peerId: peerId,
      peerName: peerName,
      peerUsername: peerUsername,
      peerAvatarPath: peerAvatarPath,
      type: map['call_type'] == 'video' ? CallType.video : CallType.voice,
      direction: map['initiator_id'] == currentUserId
          ? CallDirection.outgoing
          : CallDirection.incoming,
      status: CallStatusX.fromWire(map['status'] as String?),
      startedAt: started,
      endedAt: ended,
      duration: ended == null ? Duration.zero : ended.difference(started),
    );
  }
}
