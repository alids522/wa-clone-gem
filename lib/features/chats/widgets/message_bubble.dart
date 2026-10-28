import 'package:flutter/material.dart';

import '../../../app/theme/app_tokens.dart';
import '../../../core/models/message.dart';
import '../../../core/utils/formatters.dart';
import 'attachment_view.dart';

class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.mine,
    this.onLongPress,
    this.onRetry,
  });

  final ChatMessage message;
  final bool mine;
  final VoidCallback? onLongPress;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    final background = mine ? p.bubbleOutgoing : p.bubbleIncoming;
    final foreground = mine ? p.onBubbleOutgoing : p.textPrimary;
    final secondary = mine
        ? p.onBubbleOutgoing.withValues(alpha: 0.75)
        : p.textSecondary;

    final radius = BorderRadius.only(
      topLeft: const Radius.circular(AppTokens.radiusBubble),
      topRight: const Radius.circular(AppTokens.radiusBubble),
      bottomLeft: Radius.circular(mine ? AppTokens.radiusBubble : 6),
      bottomRight: Radius.circular(mine ? 6 : AppTokens.radiusBubble),
    );

    final failed = mine && message.status == MessageStatus.failed;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.space12,
        vertical: 2,
      ),
      child: Column(
        crossAxisAlignment: mine
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onLongPress: onLongPress,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.78,
              ),
              child: Container(
                decoration: BoxDecoration(
                  color: background,
                  borderRadius: radius,
                  border: mine ? null : Border.all(color: p.border),
                ),
                padding: const EdgeInsets.fromLTRB(
                  AppTokens.space12,
                  AppTokens.space8,
                  AppTokens.space12,
                  AppTokens.space8,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (message.replyPreview != null)
                      _ReplyPreview(preview: message.replyPreview!, mine: mine),
                    if (message.hasAttachments)
                      Padding(
                        padding: const EdgeInsets.only(
                          bottom: AppTokens.space4,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: message.attachments
                              .map(
                                (attachment) => Padding(
                                  padding: const EdgeInsets.only(
                                    bottom: AppTokens.space4,
                                  ),
                                  child: AttachmentView(
                                    meta: attachment,
                                    outgoing: mine,
                                  ),
                                ),
                              )
                              .toList(growable: false),
                        ),
                      ),
                    if (message.isDeleted)
                      Text(
                        'Pesan ini telah dihapus',
                        style: text.bodyMedium?.copyWith(
                          color: secondary,
                          fontStyle: FontStyle.italic,
                        ),
                      )
                    else if (message.body.trim().isNotEmpty)
                      Text(
                        message.body,
                        style: text.bodyMedium?.copyWith(color: foreground),
                      ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (message.editedAt != null)
                          Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: Text(
                              'diedit',
                              style: text.labelSmall?.copyWith(
                                color: secondary,
                                fontSize: 10,
                              ),
                            ),
                          ),
                        Text(
                          Formatters.clock(message.createdAt),
                          style: text.labelSmall?.copyWith(
                            color: secondary,
                            fontSize: 10,
                          ),
                        ),
                        if (mine) ...[
                          const SizedBox(width: 4),
                          _StatusIcon(status: message.status),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (message.reactions.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Wrap(
                spacing: 4,
                runSpacing: 2,
                children: [
                  for (final entry in message.reactions.entries)
                    if (entry.value.isNotEmpty)
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: p.bgRaised,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: p.border),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 1,
                          ),
                          child: Text(
                            '${entry.key} ${entry.value.length}',
                            style: text.labelSmall?.copyWith(
                              color: p.textSecondary,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ),
                ],
              ),
            ),
          if (failed)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: InkWell(
                onTap: onRetry,
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 2,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.error_outline_rounded,
                        size: 14,
                        color: p.statusError,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _failureLabel(message.errorCode),
                        style: text.labelSmall?.copyWith(color: p.statusError),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Ketuk untuk coba lagi',
                        style: text.labelSmall?.copyWith(
                          color: p.brandSoft,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _failureLabel(String? code) {
    switch (code) {
      case 'IDENTITY_CHANGED':
        return 'Kunci keamanan berubah.';
      case 'BLOCKED':
        return 'Pesan diblokir.';
      case 'RATE_LIMITED':
        return 'Terlalu banyak pesan.';
      case 'DECRYPT_FAILED':
        return 'Tidak dapat didekripsi.';
      default:
        return 'Gagal terkirim.';
    }
  }
}

class _StatusIcon extends StatelessWidget {
  const _StatusIcon({required this.status});

  final MessageStatus status;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final base = p.onBubbleOutgoing.withValues(alpha: 0.8);
    switch (status) {
      case MessageStatus.queued:
      case MessageStatus.encrypting:
      case MessageStatus.sending:
        return Icon(Icons.schedule_rounded, size: 13, color: base);
      case MessageStatus.sent:
        return Icon(Icons.check_rounded, size: 14, color: base);
      case MessageStatus.delivered:
        return Icon(Icons.done_all_rounded, size: 14, color: base);
      case MessageStatus.read:
        return const Icon(
          Icons.done_all_rounded,
          size: 14,
          color: Color(0xFF7DD3FC),
        );
      case MessageStatus.failed:
        return Icon(
          Icons.error_outline_rounded,
          size: 14,
          color: p.statusError,
        );
    }
  }
}

class _ReplyPreview extends StatelessWidget {
  const _ReplyPreview({required this.preview, required this.mine});

  final String preview;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final color = mine ? p.onBubbleOutgoing : p.textSecondary;
    return Container(
      margin: const EdgeInsets.only(bottom: AppTokens.space4),
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.space8,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: mine
            ? Colors.black.withValues(alpha: 0.18)
            : p.bgRaised.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(6),
        border: Border(
          left: BorderSide(color: color.withValues(alpha: 0.8), width: 2),
        ),
      ),
      child: Text(
        Formatters.messagePreview(preview, max: 90),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
      ),
    );
  }
}
