import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../storage/secure_store.dart';

@pragma('vm:entry-point')
Future<void> firebaseBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
  } catch (_) {}
  await PushService.showBackgroundNotification(message);
}

class PushService {
  PushService({required SupabaseClient client, required SecureStore secure})
    : _client = client,
      _secure = secure;

  final SupabaseClient _client;
  final SecureStore _secure;
  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();
  final StreamController<PushRoute> _routes =
      StreamController<PushRoute>.broadcast();

  bool _available = false;
  String? _token;
  StreamSubscription<RemoteMessage>? _foregroundSub;
  StreamSubscription<RemoteMessage>? _openedSub;
  StreamSubscription<String>? _tokenSub;

  Stream<PushRoute> get routes => _routes.stream;
  bool get available => _available;

  static const _messagesChannel = AndroidNotificationChannel(
    'messages',
    'Pesan',
    description: 'Notifikasi pesan baru Adoetz Chat',
    importance: Importance.high,
  );

  static const _callsChannel = AndroidNotificationChannel(
    'calls',
    'Panggilan',
    description: 'Notifikasi panggilan masuk',
    importance: Importance.max,
  );

  Future<void> initialize() async {
    try {
      await Firebase.initializeApp();
      _available = true;
    } catch (error) {
      debugPrint('Firebase unavailable: $error');
      _available = false;
    }

    const initSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );
    await _local.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload == null || payload.isEmpty) return;
        try {
          _routes.add(PushRoute.fromJson(jsonDecode(payload)));
        } catch (_) {}
      },
    );

    final android = _local
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await android?.createNotificationChannel(_messagesChannel);
    await android?.createNotificationChannel(_callsChannel);

    if (!_available) return;

    FirebaseMessaging.onBackgroundMessage(firebaseBackgroundHandler);
    _foregroundSub = FirebaseMessaging.onMessage.listen(_onForeground);
    _openedSub = FirebaseMessaging.onMessageOpenedApp.listen((message) {
      final route = PushRoute.fromData(message.data);
      if (route != null) _routes.add(route);
    });
    _tokenSub = FirebaseMessaging.instance.onTokenRefresh.listen((token) {
      _token = token;
      _registerToken(token);
    });

    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) {
      final route = PushRoute.fromData(initial.data);
      if (route != null) _routes.add(route);
    }
  }

  Future<void> requestPermission() async {
    if (!_available) return;
    await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    await FirebaseMessaging.instance
        .setForegroundNotificationPresentationOptions(
          alert: false,
          badge: false,
          sound: false,
        );
  }

  Future<void> onSignedIn() async {
    if (!_available) return;
    await requestPermission();
    try {
      _token = await FirebaseMessaging.instance.getToken();
      if (_token != null) await _registerToken(_token!);
    } catch (error) {
      debugPrint('FCM token unavailable: $error');
    }
  }

  Future<void> _registerToken(String token) async {
    final deviceId = await _secure.readDeviceId();
    try {
      await _client.rpc(
        'register_push_token',
        params: {'p_token': token, 'p_device_id': deviceId},
      );
    } catch (error) {
      debugPrint('Push token registration failed: $error');
    }
  }

  Future<void> onSignedOut() async {
    final token = _token;
    if (token == null) return;
    try {
      await _client.rpc('unregister_push_token', params: {'p_token': token});
    } catch (_) {}
    try {
      await FirebaseMessaging.instance.deleteToken();
    } catch (_) {}
    _token = null;
  }

  Future<void> _onForeground(RemoteMessage message) async {
    final route = PushRoute.fromData(message.data);
    if (route == null) return;
    final notification = message.notification;
    await _local.show(
      route.hashCode,
      notification?.title ?? _titleFor(route),
      notification?.body ?? _bodyFor(route),
      NotificationDetails(
        android: AndroidNotificationDetails(
          route.kind == PushRouteKind.call ? 'calls' : 'messages',
          route.kind == PushRouteKind.call ? 'Panggilan' : 'Pesan',
          channelDescription: 'Adoetz Chat',
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      payload: jsonEncode(route.toJson()),
    );
  }

  String _titleFor(PushRoute route) =>
      route.kind == PushRouteKind.call ? 'Panggilan masuk' : 'Pesan baru';

  String _bodyFor(PushRoute route) => route.kind == PushRouteKind.call
      ? 'Ketuk untuk membuka Adoetz Chat'
      : 'Buka aplikasi untuk membaca pesan.';

  static Future<void> showBackgroundNotification(RemoteMessage message) async {
    final route = PushRoute.fromData(message.data);
    if (route == null) return;
    final plugin = FlutterLocalNotificationsPlugin();
    const initSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );
    await plugin.initialize(initSettings);
    const channel = AndroidNotificationChannel(
      'messages',
      'Pesan',
      importance: Importance.high,
    );
    await plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(channel);
    await plugin.show(
      route.hashCode,
      message.notification?.title ?? 'Pesan baru',
      message.notification?.body ?? 'Buka Adoetz Chat untuk membaca.',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'messages',
          'Pesan',
          channelDescription: 'Adoetz Chat',
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      payload: jsonEncode(route.toJson()),
    );
  }

  Future<void> dispose() async {
    await _foregroundSub?.cancel();
    await _openedSub?.cancel();
    await _tokenSub?.cancel();
    await _routes.close();
  }
}

enum PushRouteKind { message, call }

class PushRoute {
  const PushRoute({
    required this.kind,
    this.conversationId,
    this.messageId,
    this.callId,
  });

  final PushRouteKind kind;
  final String? conversationId;
  final String? messageId;
  final String? callId;

  static PushRoute? fromData(Map<String, dynamic> data) {
    final type = data['type'] as String?;
    if (type == 'call') {
      final callId = data['call_id'] as String?;
      if (callId == null) return null;
      return PushRoute(kind: PushRouteKind.call, callId: callId);
    }
    final conversationId = data['conversation_id'] as String?;
    if (conversationId == null) return null;
    return PushRoute(
      kind: PushRouteKind.message,
      conversationId: conversationId,
      messageId: data['message_id'] as String?,
    );
  }

  static PushRoute fromJson(Map<String, dynamic> json) => PushRoute(
    kind: json['kind'] == 'call' ? PushRouteKind.call : PushRouteKind.message,
    conversationId: json['conversation_id'] as String?,
    messageId: json['message_id'] as String?,
    callId: json['call_id'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'kind': kind == PushRouteKind.call ? 'call' : 'message',
    'conversation_id': conversationId,
    'message_id': messageId,
    'call_id': callId,
  };
}
