import 'package:flutter/material.dart';

import '../../app/theme/app_tokens.dart';
import '../../core/models/conversation.dart';
import '../../core/services/call_repository.dart';
import '../../core/ui/avatar_view.dart';

/// Full-screen ringing card for an incoming call, shared by the realtime
/// overlay and by a tap on a call notification.
class IncomingCallCard extends StatelessWidget {
  const IncomingCallCard({
    super.key,
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
                        icon: Icon(Icons.call_end_rounded, color: p.statusError),
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
