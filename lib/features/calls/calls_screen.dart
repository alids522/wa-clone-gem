import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme/app_tokens.dart';
import '../../core/config/env.dart';
import '../../core/models/conversation.dart';
import '../../core/services/call_repository.dart';
import '../../core/ui/app_widgets.dart';
import '../../core/ui/avatar_view.dart';
import '../../core/utils/app_error.dart';
import '../../core/utils/formatters.dart';
import 'active_call_screen.dart';

class CallsScreen extends ConsumerStatefulWidget {
  const CallsScreen({super.key});

  @override
  ConsumerState<CallsScreen> createState() => _CallsScreenState();
}

class _CallsScreenState extends ConsumerState<CallsScreen> {
  List<CallRecord> _calls = const [];
  Map<String, PeerProfile> _peers = const {};
  bool _loading = true;
  bool _starting = false;
  AppError? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = _calls.isEmpty;
      _error = null;
    });
    try {
      final calls = await ref.read(depsProvider).calls.history();
      final me = ref.read(depsProvider).client.auth.currentUser?.id;
      final peerIds = <String>{for (final call in calls) call.peerIdFor(me)};
      final profiles = await Future.wait(
        peerIds.map((id) async {
          try {
            return await ref.read(depsProvider).profiles.peerProfile(id);
          } catch (_) {
            return null;
          }
        }),
      );
      if (!mounted) return;
      setState(() {
        _calls = calls;
        _peers = {
          for (final profile in profiles)
            if (profile != null) profile.userId: profile,
        };
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = mapError(error);
        _loading = false;
      });
    }
  }

  Future<void> _pickAndCall() async {
    final peer = await Navigator.of(context).push<PeerProfile>(
      MaterialPageRoute<PeerProfile>(builder: (_) => const _PeerPickerScreen()),
    );
    if (peer == null || !mounted) return;
    final kind = await _chooseKind();
    if (kind == null) return;
    await _startCall(peer, kind);
  }

  Future<CallKind?> _chooseKind() {
    return showModalBottomSheet<CallKind>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.call_rounded),
              title: const Text('Panggilan suara'),
              onTap: () => Navigator.of(context).pop(CallKind.voice),
            ),
            ListTile(
              leading: const Icon(Icons.videocam_rounded),
              title: const Text('Panggilan video'),
              onTap: () => Navigator.of(context).pop(CallKind.video),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _startCall(PeerProfile peer, CallKind kind) async {
    if (_starting) return;
    setState(() => _starting = true);
    try {
      final call = await ref
          .read(depsProvider)
          .calls
          .initiate(receiverId: peer.userId, kind: kind);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ActiveCallScreen(
            call: call,
            peerTitle: peer.title,
            peerAvatarPath: peer.avatarPath,
            outgoing: true,
            video: kind == CallKind.video,
          ),
        ),
      );
      if (mounted) unawaited(_load());
    } catch (error) {
      if (mounted) showAppSnack(context, mapError(error).message, error: true);
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _callBack(CallRecord record, CallKind kind) async {
    final peerId = record.peerIdFor(
      ref.read(depsProvider).client.auth.currentUser?.id,
    );
    final peer = _peers[peerId];
    if (peer != null) {
      await _startCall(peer, kind);
      return;
    }
    try {
      final profile = await ref.read(depsProvider).profiles.peerProfile(peerId);
      if (mounted) await _startCall(profile, kind);
    } catch (error) {
      if (mounted) showAppSnack(context, mapError(error).message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(depsProvider).client.auth.currentUser?.id;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Panggilan'),
        actions: [
          if (_starting)
            const Padding(
              padding: EdgeInsets.all(AppTokens.space16),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          IconButton(
            tooltip: 'Muat ulang',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      floatingActionButton: Env.callsEnabled
          ? FloatingActionButton(
              onPressed: _starting ? null : _pickAndCall,
              tooltip: 'Panggilan baru',
              child: const Icon(Icons.add_call),
            )
          : null,
      body: _body(me),
    );
  }

  Widget _body(String? me) {
    if (!Env.callsEnabled) {
      return const EmptyState(
        icon: Icons.phone_disabled_rounded,
        title: 'Panggilan belum tersedia',
        message: 'Fitur panggilan sedang dalam uji coba pada perangkat.',
      );
    }
    if (_loading) return const LoadingPane(label: 'Memuat riwayat panggilan…');
    if (_error != null) {
      return ErrorPane(
        message: _error!.message,
        code: _error!.code,
        onRetry: _load,
      );
    }
    if (_calls.isEmpty) {
      return EmptyState(
        icon: Icons.call_outlined,
        title: 'Belum ada panggilan',
        message: 'Panggilan suara dan video terenkripsi akan muncul di sini.',
        actionLabel: 'Mulai panggilan',
        onAction: _pickAndCall,
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.only(bottom: 96),
        itemCount: _calls.length,
        separatorBuilder: (_, __) =>
            Divider(height: 1, indent: 84, color: context.palette.border),
        itemBuilder: (context, index) {
          final call = _calls[index];
          final peerId = call.peerIdFor(me);
          final peer = _peers[peerId];
          return _CallTile(
            record: call,
            title: peer?.title ?? 'Pengguna',
            avatarPath: peer?.avatarPath,
            outgoing: call.isOutgoingFor(me),
            onTap: peer == null ? null : () => _callBack(call, call.kind),
            onCall: () => _callBack(call, call.kind),
            onVideo: () => _callBack(call, CallKind.video),
          );
        },
      ),
    );
  }
}

class _CallTile extends StatelessWidget {
  const _CallTile({
    required this.record,
    required this.title,
    required this.outgoing,
    this.avatarPath,
    this.onTap,
    this.onCall,
    this.onVideo,
  });

  final CallRecord record;
  final String title;
  final bool outgoing;
  final String? avatarPath;
  final VoidCallback? onTap;
  final VoidCallback? onCall;
  final VoidCallback? onVideo;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    final missed =
        !outgoing && (record.status == 'missed' || record.status == 'declined');
    final icon = missed
        ? Icons.call_missed_rounded
        : outgoing
        ? Icons.call_made_rounded
        : Icons.call_received_rounded;
    final iconColor = missed ? p.statusError : p.statusSuccess;

    return ListTile(
      onTap: onTap,
      leading: AvatarView(name: title, path: avatarPath, size: 48),
      title: Row(
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: text.bodyLarge?.copyWith(
                color: missed ? p.statusError : null,
              ),
            ),
          ),
          Text(
            Formatters.chatTimestamp(record.createdAt),
            style: text.labelSmall,
          ),
        ],
      ),
      subtitle: Row(
        children: [
          Icon(icon, size: 14, color: iconColor),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              '${record.kind.label} · '
              '${Formatters.callOutcome(direction: outgoing ? 'outgoing' : 'incoming', status: record.status, duration: record.duration)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: text.bodySmall,
            ),
          ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Panggilan suara',
            onPressed: onCall,
            icon: Icon(Icons.call_outlined, color: p.brandSoft),
          ),
          IconButton(
            tooltip: 'Panggilan video',
            onPressed: onVideo,
            icon: Icon(Icons.videocam_outlined, color: p.brandSoft),
          ),
        ],
      ),
    );
  }
}

class _PeerPickerScreen extends ConsumerStatefulWidget {
  const _PeerPickerScreen();

  @override
  ConsumerState<_PeerPickerScreen> createState() => _PeerPickerScreenState();
}

class _PeerPickerScreenState extends ConsumerState<_PeerPickerScreen> {
  final TextEditingController _query = TextEditingController();
  Timer? _debounce;
  List<PeerProfile> _results = const [];
  bool _loading = false;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _query,
          autofocus: true,
          autocorrect: false,
          textInputAction: TextInputAction.search,
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
      body: SafeArea(child: _body()),
    );
  }

  Widget _body() {
    if (_loading && _results.isEmpty)
      return const LoadingPane(label: 'Mencari…');
    if (_error != null) {
      return ErrorPane(
        message: _error!.message,
        onRetry: () => _search(_query.text),
      );
    }
    if (_query.text.trim().length < 2) {
      return const EmptyState(
        icon: Icons.person_search_outlined,
        title: 'Cari kontak',
        message: 'Ketik minimal 2 karakter username.',
      );
    }
    if (_results.isEmpty) {
      return const EmptyState(
        icon: Icons.search_off_rounded,
        title: 'Tidak ada hasil',
        message: 'Pastikan username benar.',
      );
    }
    return ListView.separated(
      itemCount: _results.length,
      separatorBuilder: (_, __) =>
          Divider(height: 1, indent: 72, color: context.palette.border),
      itemBuilder: (context, index) {
        final peer = _results[index];
        return ListTile(
          leading: AvatarView(
            name: peer.title,
            path: peer.avatarPath,
            size: 44,
          ),
          title: Text(peer.title),
          subtitle: Text('@${peer.username}'),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => Navigator.of(context).pop(peer),
        );
      },
    );
  }
}
