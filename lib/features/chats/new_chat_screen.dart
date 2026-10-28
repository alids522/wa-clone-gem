import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme/app_tokens.dart';
import '../../core/models/conversation.dart';
import '../../core/ui/app_widgets.dart';
import '../../core/ui/avatar_view.dart';
import '../../core/utils/app_error.dart';
import 'chat_screen.dart';

class NewChatScreen extends ConsumerStatefulWidget {
  const NewChatScreen({super.key});

  @override
  ConsumerState<NewChatScreen> createState() => _NewChatScreenState();
}

class _NewChatScreenState extends ConsumerState<NewChatScreen> {
  final _query = TextEditingController();
  Timer? _debounce;
  List<PeerProfile> _results = const [];
  bool _loading = false;
  bool _opening = false;
  AppError? _error;
  String _lastQuery = '';

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => _search(value));
  }

  Future<void> _search(String raw) async {
    final query = raw.trim();
    if (query == _lastQuery) return;
    _lastQuery = query;
    if (query.length < 2) {
      if (mounted) {
        setState(() {
          _results = const [];
          _loading = false;
          _error = null;
        });
      }
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await ref.read(depsProvider).profiles.searchUsers(query);
      if (!mounted || query != _lastQuery) return;
      setState(() => _results = results);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = mapError(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _open(PeerProfile peer) async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      final conversation = await ref
          .read(chatsControllerProvider.notifier)
          .openConversation(peer.userId);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => ChatScreen(conversation: conversation),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      showAppSnack(context, mapError(error).message, error: true);
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _query,
          autofocus: true,
          textInputAction: TextInputAction.search,
          autocorrect: false,
          onChanged: _onChanged,
          onSubmitted: _search,
          decoration: const InputDecoration(
            hintText: 'Cari username',
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            filled: false,
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (_opening)
              LinearProgressIndicator(
                minHeight: 2,
                backgroundColor: p.bgRaised,
              ),
            Expanded(child: _body(context)),
          ],
        ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    final p = context.palette;
    if (_loading && _results.isEmpty) {
      return const LoadingPane(label: 'Mencari…');
    }
    if (_error != null) {
      return ErrorPane(
        message: _error!.message,
        code: _error!.code,
        onRetry: () => _search(_query.text),
      );
    }
    if (_query.text.trim().length < 2) {
      return EmptyState(
        icon: Icons.person_search_outlined,
        title: 'Cari orang untuk diajak bicara',
        message: 'Ketik minimal 2 karakter username.',
      );
    }
    if (_results.isEmpty) {
      return EmptyState(
        icon: Icons.search_off_rounded,
        title: 'Tidak ada hasil',
        message:
            'Pastikan username benar, atau minta mereka membagikan '
            'username-nya.',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: AppTokens.space8),
      itemCount: _results.length,
      separatorBuilder: (_, __) =>
          Divider(height: 1, indent: 88, color: p.border),
      itemBuilder: (context, index) {
        final peer = _results[index];
        return ListTile(
          leading: AvatarView(
            name: peer.title,
            path: peer.avatarPath,
            size: 48,
          ),
          title: Text(peer.title),
          subtitle: Text(
            peer.bio.isEmpty
                ? '@${peer.username}'
                : '@${peer.username} · ${peer.bio}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => _open(peer),
        );
      },
    );
  }
}
