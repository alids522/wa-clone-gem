import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/env.dart';

enum RealtimeKind {
  messageCreated,
  messageUpdated,
  receiptCreated,
  callChanged,
  reactionChanged,
}

class RealtimeEvent {
  const RealtimeEvent(this.kind, this.record);

  final RealtimeKind kind;
  final Map<String, dynamic> record;

  String? get conversationId => record['conversation_id'] as String?;
}

/// A single RLS-scoped channel that wakes local sync when durable rows change.
/// History always comes from PostgreSQL, never from the event payload alone.
class RealtimeService {
  RealtimeService(this._client);

  final SupabaseClient _client;
  final StreamController<RealtimeEvent> _events =
      StreamController<RealtimeEvent>.broadcast();

  RealtimeChannel? _channel;
  bool _started = false;

  Stream<RealtimeEvent> get events => _events.stream;

  void start() {
    if (_started) return;
    _started = true;
    _subscribe();
  }

  void _subscribe() {
    _channel = _client
        .channel('adoetz:inbox')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: Env.dbSchema,
          table: 'messages',
          callback: (payload) =>
              _emit(RealtimeKind.messageCreated, payload.newRecord),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: Env.dbSchema,
          table: 'messages',
          callback: (payload) =>
              _emit(RealtimeKind.messageUpdated, payload.newRecord),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: Env.dbSchema,
          table: 'message_receipts',
          callback: (payload) =>
              _emit(RealtimeKind.receiptCreated, payload.newRecord),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: Env.dbSchema,
          table: 'calls',
          callback: (payload) =>
              _emit(RealtimeKind.callChanged, payload.newRecord),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: Env.dbSchema,
          table: 'message_reactions',
          callback: (payload) =>
              _emit(RealtimeKind.reactionChanged, payload.newRecord),
        )
        .subscribe((status, error) {
          if (status == RealtimeSubscribeStatus.channelError) {
            _started = false;
            Timer(const Duration(seconds: 5), () {
              if (!_started) {
                _started = true;
                _subscribe();
              }
            });
          }
        });
  }

  void _emit(RealtimeKind kind, Map<String, dynamic> record) {
    if (!_events.isClosed) _events.add(RealtimeEvent(kind, record));
  }

  Future<void> stop() async {
    _started = false;
    final channel = _channel;
    _channel = null;
    if (channel != null) {
      await _client.removeChannel(channel);
    }
  }

  Future<void> dispose() async {
    await stop();
    await _events.close();
  }
}
