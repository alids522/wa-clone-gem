import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/adoetz_app.dart';
import '../../app/providers.dart';
import '../../core/models/conversation.dart';
import '../../core/services/call_repository.dart';
import '../../core/services/callkit_service.dart';
import '../../core/services/realtime_service.dart';
import '../../core/ui/app_widgets.dart';
import '../../core/utils/app_error.dart';
import 'active_call_screen.dart';
import 'incoming_call_card.dart';

/// Watches durable `calls` changes and offers an in-app incoming-call UI.
///
/// Rendered above the MaterialApp navigator so a ringing call is visible from
/// any screen.
class IncomingCallOverlay extends ConsumerStatefulWidget {
  const IncomingCallOverlay({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<IncomingCallOverlay> createState() =>
      _IncomingCallOverlayState();
}

class _IncomingCallOverlayState extends ConsumerState<IncomingCallOverlay> {
  StreamSubscription<RealtimeEvent>? _subscription;
  StreamSubscription<String>? _acceptedSub;
  CallRecord? _incoming;
  PeerProfile? _peer;
  bool _busy = false;
  Timer? _expiry;
  final Set<String> _handled = <String>{};

  @override
  void initState() {
    super.initState();
    final deps = ref.read(depsProvider);
    _subscription = deps.realtime.events.listen(_onEvent);
    _acceptedSub = deps.push.acceptedCalls.listen(_joinAccepted);
    // An accept can happen before this widget listens (the app may cold start
    // straight into the answered call), so drain what the service buffered.
    final pending = deps.push.takePendingAcceptedCall();
    if (pending != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _joinAccepted(pending));
    }
  }

  @override
  void dispose() {
    _expiry?.cancel();
    _subscription?.cancel();
    _acceptedSub?.cancel();
    super.dispose();
  }

  /// Joins a call the user answered on the native CallKit screen.
  Future<void> _joinAccepted(String callId) async {
    if (_busy || _handled.contains(callId)) return;
    final deps = ref.read(depsProvider);
    final me = deps.client.auth.currentUser?.id;
    if (me == null) return;
    final record = await deps.calls.fetch(callId);
    if (record == null || record.receiverId != me) return;
    if (record.status != 'ringing' &&
        record.status != 'connecting' &&
        record.status != 'active') {
      return;
    }
    _handled.add(callId);
    _dismiss();
    if (mounted) setState(() => _busy = true);
    try {
      final call = record.status == 'ringing'
          ? await deps.calls.action(record.id, 'accept')
          : record;
      final peer = await deps.profiles.peerProfile(record.initiatorId);
      final navigator = AdoetzApp.navigatorKey.currentState;
      if (navigator == null) return;
      await navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => ActiveCallScreen(
            call: call,
            peerTitle: peer.title,
            peerAvatarPath: peer.avatarPath,
            outgoing: false,
            video: call.kind == CallKind.video,
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        showAppSnack(context, mapError(error).message, error: true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _onEvent(RealtimeEvent event) {
    if (event.kind != RealtimeKind.callChanged) return;
    final record = event.record;
    final me = ref.read(depsProvider).client.auth.currentUser?.id;
    if (me == null) return;
    final status = record['status'] as String?;
    final id = record['id'] as String?;
    if (id == null) return;

    if (status == 'ringing' && record['receiver_id'] == me) {
      if (_handled.contains(id) || _incoming?.id == id) return;
      _show(CallRecord.fromMap(record));
      return;
    }

    if (_incoming?.id == id &&
        status != null &&
        status != 'ringing' &&
        status != 'connecting' &&
        status != 'active') {
      _dismiss(markHandled: true);
    }
  }

  Future<void> _show(CallRecord record) async {
    _expiry?.cancel();
    setState(() {
      _incoming = record;
      _peer = null;
    });
    HapticFeedback.heavyImpact();
    _expiry = Timer(const Duration(seconds: 45), () {
      if (mounted && _incoming?.id == record.id) _dismiss(markHandled: true);
    });
    try {
      final peer = await ref
          .read(depsProvider)
          .profiles
          .peerProfile(record.initiatorId);
      if (mounted && _incoming?.id == record.id) setState(() => _peer = peer);
    } catch (_) {}
  }

  void _dismiss({bool markHandled = false}) {
    final id = _incoming?.id;
    if (markHandled && id != null) _handled.add(id);
    _expiry?.cancel();
    if (mounted) {
      setState(() {
        _incoming = null;
        _peer = null;
      });
    }
  }

  Future<void> _accept() async {
    final record = _incoming;
    if (record == null || _busy) return;
    setState(() => _busy = true);
    try {
      final accepted = await ref
          .read(depsProvider)
          .calls
          .action(record.id, 'accept');
      _dismiss(markHandled: true);
      // If the native screen was ringing too, clear it now that this screen
      // has taken over.
      await CallkitService.end(record.id);
      final navigator = AdoetzApp.navigatorKey.currentState;
      if (navigator == null) return;
      final peer = _peer;
      await navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => ActiveCallScreen(
            call: accepted,
            peerTitle: peer?.title ?? 'Panggilan masuk',
            peerAvatarPath: peer?.avatarPath,
            outgoing: false,
            video: accepted.kind == CallKind.video,
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        showAppSnack(context, mapError(error).message, error: true);
        _dismiss(markHandled: true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _decline() async {
    final record = _incoming;
    if (record == null) return;
    _dismiss(markHandled: true);
    try {
      await ref.read(depsProvider).calls.action(record.id, 'decline');
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final incoming = _incoming;
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (incoming != null)
          IncomingCallCard(
            record: incoming,
            peer: _peer,
            busy: _busy,
            onAccept: _accept,
            onDecline: _decline,
          ),
      ],
    );
  }
}

