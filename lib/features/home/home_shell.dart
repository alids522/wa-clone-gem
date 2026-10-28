import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/models/conversation.dart';
import '../../core/services/call_repository.dart';
import '../../core/services/profile_repository.dart';
import '../../core/services/push_service.dart';
import '../../core/ui/app_widgets.dart';
import '../../core/ui/avatar_view.dart';
import '../../core/utils/app_error.dart';
import '../calls/active_call_screen.dart';
import '../calls/calls_screen.dart';
import '../calls/incoming_call_card.dart';
import '../chats/chat_screen.dart';
import '../chats/chats_screen.dart';
import '../settings/settings_screen.dart';

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _index = 0;
  StreamSubscription<PushRoute>? _routeSubscription;

  @override
  void initState() {
    super.initState();
    final push = ref.read(depsProvider).push;
    _routeSubscription = push.routes.listen(_onRoute);
    // Tapping a notification that launched a terminated app resolves before
    // this screen exists; the service keeps it until we ask for it.
    final initial = push.takeInitialRoute();
    if (initial != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _onRoute(initial));
    }
  }

  @override
  void dispose() {
    _routeSubscription?.cancel();
    super.dispose();
  }

  Future<void> _onRoute(PushRoute route) async {
    if (route.kind == PushRouteKind.call) {
      await _openCall(route.callId);
      return;
    }
    if (route.kind != PushRouteKind.message) return;
    final conversationId = route.conversationId;
    if (conversationId == null) return;
    final deps = ref.read(depsProvider);
    final conversation =
        await deps.chat.localConversation(conversationId) ??
        await ref
            .read(chatsControllerProvider.notifier)
            .openConversationById(conversationId);
    if (conversation == null || !mounted) return;
    setState(() => _index = 0);
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ChatScreen(conversation: conversation),
      ),
    );
  }

  /// A tap on a call notification: offer Terima/Tolak while the call is still
  /// ringing, otherwise show the history so the missed call is visible.
  Future<void> _openCall(String? callId) async {
    if (callId == null || !mounted) return;
    final deps = ref.read(depsProvider);
    final me = deps.client.auth.currentUser?.id;
    if (me == null) return;
    final call = await deps.calls.fetch(callId);
    if (!mounted || call == null || call.receiverId != me) return;

    final stillRinging =
        call.isRinging &&
        DateTime.now().difference(call.createdAt) < const Duration(seconds: 45);
    if (!stillRinging) {
      setState(() => _index = 1);
      showAppSnack(context, 'Panggilan sudah berakhir.');
      return;
    }

    PeerProfile? peer;
    try {
      peer = await deps.profiles.peerProfile(call.initiatorId);
    } catch (_) {}
    if (!mounted) return;

    var busy = false;
    await showDialog<void>(
      context: context,
      barrierColor: Colors.transparent,
      builder: (dialogContext) => StatefulBuilder(
        builder: (cardContext, setDialogState) => IncomingCallCard(
          record: call,
          peer: peer,
          busy: busy,
          onAccept: () async {
            setDialogState(() => busy = true);
            try {
              final accepted = await deps.calls.action(call.id, 'accept');
              if (dialogContext.mounted) Navigator.of(dialogContext).pop();
              if (!mounted) return;
              await Navigator.of(context).push(
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
              if (dialogContext.mounted) Navigator.of(dialogContext).pop();
              if (mounted) {
                showAppSnack(context, mapError(error).message, error: true);
              }
            }
          },
          onDecline: () async {
            Navigator.of(dialogContext).pop();
            try {
              await deps.calls.action(call.id, 'decline');
            } catch (_) {}
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Keeps the server-side preferences warm and mirrors the theme choice.
    ref.listen<AsyncValue<UserPreferences>>(preferencesControllerProvider, (
      previous,
      next,
    ) {
      final prefs = next.valueOrNull;
      if (prefs != null) {
        ref.read(themeControllerProvider.notifier).applyRemote(prefs.theme);
      }
    });

    final unread = ref.watch(totalUnreadProvider);
    final profile = ref.watch(currentProfileProvider);

    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: const [ChatsScreen(), CallsScreen(), SettingsScreen()],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: [
          NavigationDestination(
            icon: Badge(
              isLabelVisible: unread > 0,
              label: Text(unread > 99 ? '99+' : '$unread'),
              child: const Icon(Icons.chat_bubble_outline_rounded),
            ),
            selectedIcon: Badge(
              isLabelVisible: unread > 0,
              label: Text(unread > 99 ? '99+' : '$unread'),
              child: const Icon(Icons.chat_bubble_rounded),
            ),
            label: 'Obrolan',
          ),
          const NavigationDestination(
            icon: Icon(Icons.call_outlined),
            selectedIcon: Icon(Icons.call_rounded),
            label: 'Panggilan',
          ),
          NavigationDestination(
            icon: profile == null
                ? const Icon(Icons.settings_outlined)
                : AvatarView(
                    name: profile.displayName,
                    path: profile.avatarPath,
                    size: 26,
                  ),
            selectedIcon: const Icon(Icons.settings_rounded),
            label: 'Pengaturan',
          ),
        ],
      ),
    );
  }
}
