import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/adoetz_app.dart';
import '../../app/providers.dart';
import '../../app/theme/app_tokens.dart';
import '../../core/models/conversation.dart';
import '../../core/services/call_repository.dart';
import '../../core/services/realtime_service.dart';
import '../../core/ui/app_widgets.dart';
import '../../core/ui/avatar_view.dart';
import '../../core/utils/app_error.dart';
import 'active_call_screen.dart';

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
  CallRecord? _incoming;
  PeerProfile? _peer;
  bool _busy = false;
  Timer? _expiry;
  final Set<String> _handled = <String>{};

  @override
  void initState() {
    super.initState();
    _subscription = ref.read(depsProvider).realtime.events.listen(_onEvent);
  }

  @override
  void dispose() {
    _expiry?.cancel();
    _subscription?.cancel();
    super.dispose();
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
          _IncomingCallCard(
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

class _IncomingCallCard extends StatelessWidget {
  const _IncomingCallCard({
    required this.record,
    required this.peer,
    required this.busy,
    required this.onAccept,
    required this.onDecline,
  });

  final CallRecord record;
  final PeerProfile? peer;
  final bool busy;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    final title = peer?.title ?? 'Panggilan masuk';
    return Material(
      color: Colors.black.withValues(alpha: 0.72),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppTokens.space24),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 380),
            padding: const EdgeInsets.all(AppTokens.space24),
            decoration: BoxDecoration(
              color: p.bgSurface,
              borderRadius: BorderRadius.circular(AppTokens.radiusDialog),
              border: Border.all(color: p.border),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.35),
                  blurRadius: 32,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  record.kind == CallKind.video
                      ? 'Panggilan video masuk'
                      : 'Panggilan suara masuk',
                  style: text.labelSmall?.copyWith(color: p.brandSoft),
                ),
                const SizedBox(height: AppTokens.space16),
                AvatarView(name: title, path: peer?.avatarPath, size: 92),
                const SizedBox(height: AppTokens.space16),
                Text(
                  title,
                  style: text.titleMedium,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (peer != null) ...[
                  const SizedBox(height: 4),
                  Text('@${peer!.username}', style: text.bodySmall),
                ],
                const SizedBox(height: AppTokens.space24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: busy ? null : onDecline,
                        icon: Icon(
                          Icons.call_end_rounded,
                          color: p.statusError,
                        ),
                        label: Text(
                          'Tolak',
                          style: TextStyle(color: p.statusError),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppTokens.space12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: busy ? null : onAccept,
                        icon: const Icon(Icons.call_rounded),
                        label: Text(busy ? 'Menyambung…' : 'Terima'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
