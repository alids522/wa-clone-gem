import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/app_error.dart';

enum CallKind {
  voice,
  video;

  String get wire => name;

  static CallKind fromWire(String? value) =>
      value == 'video' ? CallKind.video : CallKind.voice;

  String get label =>
      this == CallKind.video ? 'Panggilan video' : 'Panggilan suara';
}

class CallRecord {
  const CallRecord({
    required this.id,
    required this.initiatorId,
    required this.receiverId,
    required this.kind,
    required this.status,
    required this.createdAt,
    this.startedAt,
    this.endedAt,
  });

  final String id;
  final String initiatorId;
  final String receiverId;
  final CallKind kind;
  final String status;
  final DateTime createdAt;
  final DateTime? startedAt;
  final DateTime? endedAt;

  bool get isRinging => status == 'ringing';

  bool isOutgoingFor(String? userId) => initiatorId == userId;

  String peerIdFor(String? userId) =>
      initiatorId == userId ? receiverId : initiatorId;

  Duration get duration {
    final start = startedAt;
    final end = endedAt ?? DateTime.now();
    if (start == null) return Duration.zero;
    final value = end.difference(start);
    return value.isNegative ? Duration.zero : value;
  }

  factory CallRecord.fromMap(Map<String, dynamic> map) {
    DateTime? date(Object? value) => value is String && value.isNotEmpty
        ? DateTime.tryParse(value)?.toLocal()
        : null;
    return CallRecord(
      id: map['id'] as String,
      initiatorId: map['initiator_id'] as String,
      receiverId: map['receiver_id'] as String,
      kind: CallKind.fromWire(map['kind'] as String?),
      status: map['status'] as String? ?? 'ringing',
      createdAt: date(map['created_at']) ?? DateTime.now(),
      startedAt: date(map['started_at']),
      endedAt: date(map['ended_at']),
    );
  }
}

class CallRepository {
  CallRepository(this._client);

  final SupabaseClient _client;

  Future<CallRecord> initiate({
    required String receiverId,
    required CallKind kind,
  }) async {
    try {
      final response = await _client.rpc(
        'initiate_call',
        params: {'p_receiver_id': receiverId, 'p_kind': kind.wire},
      );
      return CallRecord.fromMap((response as Map).cast<String, dynamic>());
    } catch (error) {
      throw mapError(error);
    }
  }

  Future<CallRecord> action(String callId, String action) async {
    try {
      final response = await _client.rpc(
        'call_action',
        params: {'p_call_id': callId, 'p_action': action},
      );
      return CallRecord.fromMap((response as Map).cast<String, dynamic>());
    } catch (error) {
      throw mapError(error);
    }
  }

  Future<CallRecord?> fetch(String callId) async {
    try {
      final row = await _client
          .from('calls')
          .select()
          .eq('id', callId)
          .maybeSingle();
      return row == null ? null : CallRecord.fromMap(row);
    } catch (_) {
      return null;
    }
  }

  Future<List<CallRecord>> history({int limit = 80}) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return const [];
    try {
      final rows = await _client
          .from('calls')
          .select()
          .or('initiator_id.eq.$userId,receiver_id.eq.$userId')
          .order('created_at', ascending: false)
          .limit(limit);
      return rows
          .map(
            (raw) => CallRecord.fromMap((raw as Map).cast<String, dynamic>()),
          )
          .toList(growable: false);
    } catch (error) {
      throw mapError(error);
    }
  }
}
