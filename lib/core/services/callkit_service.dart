import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Native ringing UI for calls that arrive while Adoetz Chat is not on screen.
///
/// Call pushes are sent data-only so Android hands them to the background
/// isolate, which raises a full-screen CallKit notification with Terima/Tolak.
/// Accepting launches the app; the call id is then handed to the UI through
/// [accepted] so it can join the same call the callee just answered.
class CallkitService {
  CallkitService({required SupabaseClient client}) : _client = client;

  final SupabaseClient _client;
  final StreamController<String> _accepted =
      StreamController<String>.broadcast();
  final List<String> _pending = <String>[];
  final Set<String> _seen = <String>{};
  StreamSubscription<CallEvent?>? _events;
  bool _started = false;

  /// Calls answered on the native CallKit screen.
  Stream<String> get accepted => _accepted.stream;

  /// An accept that arrived before the UI was listening (cold start).
  String? takePending() {
    if (_pending.isEmpty) return null;
    return _pending.removeAt(0);
  }

  Future<void> start() async {
    if (_started) return;
    _started = true;
    _events = FlutterCallkitIncoming.onEvent.listen(_onEvent);
    try {
      // Android 14+ only grants full-screen intents to approved calling apps.
      await FlutterCallkitIncoming.requestFullIntentPermission();
    } catch (error) {
      debugPrint('CallKit full-screen permission unavailable: $error');
    }
    try {
      // The app can be launched by the CallKit screen itself; the accepted
      // call is then only visible through the plugin's stored call list.
      final active = await FlutterCallkitIncoming.activeCalls();
      for (final raw in active ?? const <dynamic>[]) {
        if (raw is! Map) continue;
        if (raw['isAccepted'] != true) continue;
        final id = _callIdOf(raw);
        if (id != null) _emit(id);
      }
    } catch (error) {
      debugPrint('CallKit active calls unavailable: $error');
    }
  }

  void _onEvent(CallEvent? event) {
    if (event == null) return;
    switch (event.event) {
      case Event.actionCallAccept:
        {
          final id = _callIdOf(event.body);
          if (id != null) _emit(id);
        }
        break;
      case Event.actionCallDecline:
        {
          final id = _callIdOf(event.body);
          if (id != null) unawaited(_decline(id));
        }
        break;
      case Event.actionCallTimeout:
      case Event.actionCallEnded:
      case Event.actionCallConnected:
      case Event.actionCallCallback:
      case Event.actionCallIncoming:
      case Event.actionCallStart:
      case Event.actionCallToggleHold:
      case Event.actionCallToggleMute:
      case Event.actionCallToggleDmtf:
      case Event.actionCallToggleGroup:
      case Event.actionCallToggleAudioSession:
      case Event.actionCallCustom:
      case Event.actionDidUpdateDevicePushTokenVoip:
        break;
    }
  }

  void _emit(String id) {
    if (!_seen.add(id)) return;
    if (_accepted.hasListener) {
      _accepted.add(id);
    } else {
      _pending.add(id);
    }
  }

  Future<void> _decline(String callId) async {
    try {
      await _client.rpc(
        'call_action',
        params: {'p_call_id': callId, 'p_action': 'decline'},
      );
    } catch (_) {
      // The call may already have expired; nothing else to do.
    }
  }

  static String? _callIdOf(dynamic body) {
    if (body is! Map) return null;
    final id = body['id'];
    if (id is String && id.isNotEmpty) return id;
    final extra = body['extra'];
    if (extra is Map) {
      final fromExtra = extra['call_id'];
      if (fromExtra is String && fromExtra.isNotEmpty) return fromExtra;
    }
    return null;
  }

  /// Raises the native ringing screen. Safe to call from the FCM background
  /// isolate: it touches no UI and returns once the notification is posted.
  static Future<void> showIncoming({
    required String callId,
    required String callerName,
    required bool video,
  }) async {
    final params = CallKitParams(
      id: callId,
      nameCaller: callerName,
      appName: 'Adoetz Chat',
      handle: video ? 'Panggilan video' : 'Panggilan suara',
      type: video ? 1 : 0,
      // Matches the 45s ring window the server allows for the call.
      duration: 45000,
      textAccept: 'Terima',
      textDecline: 'Tolak',
      extra: <String, dynamic>{
        'call_id': callId,
        'kind': video ? 'video' : 'voice',
      },
      android: const AndroidParams(
        ringtonePath: 'system_ringtone_default',
        isShowLogo: false,
        isShowFullLockedScreen: true,
        incomingCallNotificationChannelName: 'Panggilan',
        missedCallNotificationChannelName: 'Panggilan',
      ),
      ios: const IOSParams(
        iconName: 'AppIcon',
        handleType: 'generic',
        supportsVideo: true,
        audioSessionActive: true,
        configureAudioSession: true,
      ),
    );
    await FlutterCallkitIncoming.showCallkitIncoming(params);
  }

  /// Clears the native call UI once the in-app call is over.
  static Future<void> end(String callId) async {
    try {
      await FlutterCallkitIncoming.endCall(callId);
    } catch (error) {
      debugPrint('CallKit end failed: $error');
    }
  }

  Future<void> dispose() async {
    await _events?.cancel();
    await _accepted.close();
  }
}
