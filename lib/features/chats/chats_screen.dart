import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme/app_tokens.dart';
import '../../core/models/conversation.dart';
import '../../core/ui/app_widgets.dart';
import '../../core/ui/avatar_view.dart';
import '../../core/utils/formatters.dart';
import 'chat_screen.dart';
import 'new_chat_screen.dart';

class ChatsScreen extends ConsumerWidget {
  const ChatsScreen({super.key});

  Future<void> _open(BuildContext context, ConversationSummary item) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => ChatScreen(conversation: item)),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(chatsControllerProvider);
    final controller = ref.read(chatsControllerProvider.notifier);
    final online = ref.watch(onlineStatusProvider);

    ref.listen<ChatsState>(chatsControllerProvider, (previous, next) {
      final error = next.error;
      if (error != null && previous?.error != error) {
        showAppSnack(context, error.message, error: true);
        controller.dismissError();
      }
    });

    return Scaffold(
      appBar: AppBar(
        titleSpacing: AppTokens.space16,
        title: Row(
          children: [
            Text(
              'Adoetz Chat',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
            ),
            if (state.syncing) ...[
              const SizedBox(width: AppTokens.space12),
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ],
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Percakapan baru',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const NewChatScreen()),
            ),
            icon: const Icon(Icons.edit_square),
          ),
        ],
      ),
      body: Column(
        children: [
          if (!online) const OfflineBanner(),
          Expanded(
            child: RefreshIndicator(
              onRefresh: controller.refresh,
              child: state.loading
                  ? const ChatListSkeleton()
                  : state.conversations.isEmpty
                  ? EmptyState(
                      icon: Icons.forum_outlined,
                      title: 'Belum ada percakapan',
                      message:
                          'Mulai percakapan dengan mencari username orang '
                          'yang kamu kenal.',
                      actionLabel: 'Mulai percakapan',
                      onAction: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const NewChatScreen(),
                        ),
                      ),
                    )
                  : _ConversationList(
                      items: state.conversations,
                      onOpen: (item) => _open(context, item),
                      controller: controller,
                    ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Percakapan baru',
        onPressed: () => Navigator.of(
          context,
        ).push(MaterialPageRoute<void>(builder: (_) => const NewChatScreen())),
        child: const Icon(Icons.chat_bubble_outline_rounded),
      ),
    );
  }
}

class _ConversationList extends StatelessWidget {
  const _ConversationList({
    required this.items,
    required this.onOpen,
    required this.controller,
  });

  final List<ConversationSummary> items;
  final ValueChanged<ConversationSummary> onOpen;
  final ChatsController controller;

  @override
  Widget build(BuildContext context) {
    final pinned = items.where((item) => item.pinned).toList();
    final regular = items.where((item) => !item.pinned).toList();

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 96),
      children: [
        if (pinned.isNotEmpty) ...[
          const _SectionLabel('Disematkan'),
          ...pinned.map(
            (item) => _ConversationTile(
              item: item,
              onTap: () => onOpen(item),
              onLongPress: () => _showActions(context, item),
            ),
          ),
        ],
        if (regular.isNotEmpty) ...[
          if (pinned.isNotEmpty) const _SectionLabel('Semua obrolan'),
          ...regular.map(
            (item) => _ConversationTile(
              item: item,
              onTap: () => onOpen(item),
              onLongPress: () => _showActions(context, item),
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _showActions(
    BuildContext context,
    ConversationSummary item,
  ) async {
    final p = context.palette;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(
                item.pinned ? Icons.push_pin_outlined : Icons.push_pin_rounded,
              ),
              title: Text(item.pinned ? 'Lepas sematan' : 'Sematkan'),
              onTap: () async {
                Navigator.of(sheetContext).pop();
                await controller.setPinned(item.id, !item.pinned);
              },
            ),
            ListTile(
              leading: Icon(
                item.muted
                    ? Icons.notifications_active_outlined
                    : Icons.notifications_off_outlined,
              ),
              title: Text(item.muted ? 'Aktifkan notifikasi' : 'Bisukan'),
              onTap: () async {
                Navigator.of(sheetContext).pop();
                await controller.setMuted(item.id, !item.muted);
              },
            ),
            if (item.unreadCount > 0)
              ListTile(
                leading: const Icon(Icons.mark_chat_read_outlined),
                title: const Text('Tandai sudah dibaca'),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  await controller.markRead(item.id);
                },
              ),
            ListTile(
              leading: Icon(Icons.delete_outline_rounded, color: p.statusError),
              title: Text(
                'Hapus dari perangkat',
                style: TextStyle(color: p.statusError),
              ),
              onTap: () async {
                Navigator.of(sheetContext).pop();
                final confirmed = await showConfirmDialog(
                  context,
                  title: 'Hapus obrolan?',
                  message:
                      'Riwayat lokal obrolan ini dihapus dari perangkat. '
                      'Pesan tetap tersimpan di server.',
                  confirmLabel: 'Hapus',
                  destructive: true,
                );
                if (confirmed) await controller.clearHistory(item.id);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTokens.space20,
        AppTokens.space16,
        AppTokens.space20,
        AppTokens.space8,
      ),
      child: Text(
        text.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          letterSpacing: 0.8,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _ConversationTile extends StatelessWidget {
  const _ConversationTile({
    required this.item,
    required this.onTap,
    required this.onLongPress,
  });

  final ConversationSummary item;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    final hasUnread = item.unreadCount > 0;
    final subtitle = item.peerIdentityChanged
        ? 'Kunci keamanan berubah — ketuk untuk memeriksa'
        : item.subtitle;

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppTokens.space16,
          vertical: AppTokens.space12,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AvatarView(name: item.title, path: item.peerAvatarPath, size: 52),
            const SizedBox(width: AppTokens.space12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.bodyLarge?.copyWith(
                            fontWeight: hasUnread
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppTokens.space8),
                      Text(
                        item.lastMessageAt == null
                            ? ''
                            : Formatters.chatTimestamp(item.lastMessageAt!),
                        style: text.labelSmall?.copyWith(
                          color: hasUnread ? p.brandSoft : p.textSecondary,
                          fontWeight: hasUnread
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (item.peerIdentityChanged)
                        Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: Icon(
                            Icons.warning_amber_rounded,
                            size: 16,
                            color: p.statusWarning,
                          ),
                        ),
                      if (item.muted)
                        Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: Icon(
                            Icons.notifications_off_outlined,
                            size: 15,
                            color: p.textSecondary,
                          ),
                        ),
                      Expanded(
                        child: Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.bodySmall?.copyWith(
                            color: item.peerIdentityChanged
                                ? p.statusWarning
                                : (hasUnread ? p.textPrimary : p.textSecondary),
                            fontWeight: hasUnread
                                ? FontWeight.w600
                                : FontWeight.w400,
                          ),
                        ),
                      ),
                      if (hasUnread) ...[
                        const SizedBox(width: AppTokens.space8),
                        AppBadge(count: item.unreadCount, muted: item.muted),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
