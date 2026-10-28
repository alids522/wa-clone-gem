import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/services/profile_repository.dart';
import '../../core/services/push_service.dart';
import '../../core/ui/avatar_view.dart';
import '../calls/calls_screen.dart';
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
    _routeSubscription = ref.read(depsProvider).push.routes.listen(_onRoute);
  }

  @override
  void dispose() {
    _routeSubscription?.cancel();
    super.dispose();
  }

  Future<void> _onRoute(PushRoute route) async {
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
