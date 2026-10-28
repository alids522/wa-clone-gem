import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../app/providers.dart';
import '../../app/theme/app_tokens.dart';
import '../../core/models/conversation.dart';
import '../../core/models/message.dart';
import '../../core/ui/app_widgets.dart';
import '../../core/ui/avatar_view.dart';
import '../../core/utils/app_error.dart';
import 'widgets/attachment_view.dart';

class ChatInfoScreen extends ConsumerStatefulWidget {
  const ChatInfoScreen({super.key, required this.conversation});

  final ConversationSummary conversation;

  @override
  ConsumerState<ChatInfoScreen> createState() => _ChatInfoScreenState();
}

class _ChatInfoScreenState extends ConsumerState<ChatInfoScreen> {
  PeerProfile? _peer;
  String? _safetyNumber;
  bool _verified = false;
  bool _blocked = false;
  bool _loading = true;
  bool _busy = false;
  AppError? _error;

  String get _peerId => widget.conversation.peerId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  void _showSharedMedia() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.92,
        expand: false,
        builder: (sheetContext, controller) => _SharedMediaSheet(
          conversationId: widget.conversation.id,
          scrollController: controller,
        ),
      ),
    );
  }

  Future<void> _reportUser() async {
    const reasons = <String, String>{
      'spam': 'Spam atau iklan',
      'harassment': 'Pelecehan atau ancaman',
      'scam': 'Penipuan',
      'illegal': 'Konten ilegal',
      'other': 'Lainnya',
    };
    final details = TextEditingController();
    var reason = 'spam';
    var busy = false;

    final submitted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Laporkan kontak'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: reason,
                  decoration: const InputDecoration(
                    labelText: 'Alasan',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final entry in reasons.entries)
                      DropdownMenuItem(
                        value: entry.key,
                        child: Text(entry.value),
                      ),
                  ],
                  onChanged: busy
                      ? null
                      : (value) {
                          if (value != null) {
                            setDialogState(() => reason = value);
                          }
                        },
                ),
                const SizedBox(height: AppTokens.space12),
                TextField(
                  controller: details,
                  enabled: !busy,
                  maxLines: 3,
                  maxLength: 500,
                  decoration: const InputDecoration(
                    labelText: 'Keterangan tambahan (opsional)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: AppTokens.space8),
                Text(
                  'Isi pesan tidak disertakan pada laporan ini. Untuk '
                  'melampirkan isi pesan tertentu, laporkan pesannya dari '
                  'menu pesan.',
                  style: Theme.of(dialogContext).textTheme.labelSmall,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.of(dialogContext).pop(),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: busy
                  ? null
                  : () async {
                      setDialogState(() => busy = true);
                      try {
                        await ref
                            .read(depsProvider)
                            .chat
                            .submitReport(
                              reportedUserId: _peerId,
                              reason: reason,
                              details: details.text,
                            );
                        if (dialogContext.mounted) {
                          Navigator.of(dialogContext).pop(true);
                        }
                      } catch (error) {
                        if (dialogContext.mounted) {
                          setDialogState(() => busy = false);
                          showAppSnack(
                            dialogContext,
                            mapError(error).message,
                            error: true,
                          );
                        }
                      }
                    },
              child: const Text('Kirim'),
            ),
          ],
        ),
      ),
    );

    details.dispose();
    if (submitted == true && mounted) {
      showAppSnack(context, 'Laporan terkirim. Terima kasih.');
    }
  }

  Future<void> _load() async {
    final deps = ref.read(depsProvider);
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait<Object?>([
        deps.profiles.peerProfile(_peerId),
        deps.e2ee.safetyNumber(_peerId),
        deps.e2ee.isVerified(_peerId),
        deps.profiles.isBlocked(_peerId),
      ]);
      if (!mounted) return;
      setState(() {
        _peer = results[0] as PeerProfile;
        _safetyNumber = results[1] as String?;
        _verified = results[2] as bool;
        _blocked = results[3] as bool;
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

  Future<void> _verify() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(depsProvider).e2ee.verifyPeer(_peerId);
      if (!mounted) return;
      setState(() => _verified = true);
      showAppSnack(context, 'Kontak ditandai terverifikasi.');
    } catch (error) {
      if (mounted) showAppSnack(context, mapError(error).message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resetSession() async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Setel ulang sesi enkripsi?',
      message:
          'Sesi enkripsi dengan kontak ini akan dibuat ulang. '
          'Pesan lama tetap dapat dibaca di perangkat ini.',
      confirmLabel: 'Setel ulang',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(depsProvider).e2ee.resetPeerSession(_peerId);
      final safety = await ref.read(depsProvider).e2ee.safetyNumber(_peerId);
      if (!mounted) return;
      setState(() {
        _safetyNumber = safety;
        _verified = false;
      });
      showAppSnack(context, 'Sesi enkripsi disetel ulang.');
    } catch (error) {
      if (mounted) showAppSnack(context, mapError(error).message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggleBlock() async {
    if (_blocked) {
      setState(() => _busy = true);
      try {
        await ref.read(depsProvider).profiles.unblockUser(_peerId);
        if (!mounted) return;
        setState(() => _blocked = false);
        showAppSnack(context, 'Blokir kontak dibuka.');
      } catch (error) {
        if (mounted)
          showAppSnack(context, mapError(error).message, error: true);
      } finally {
        if (mounted) setState(() => _busy = false);
      }
      return;
    }
    final confirmed = await showConfirmDialog(
      context,
      title: 'Blokir kontak?',
      message: 'Kontak tidak dapat mengirim pesan baru kepada Anda.',
      confirmLabel: 'Blokir',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(depsProvider).profiles.blockUser(_peerId);
      if (!mounted) return;
      setState(() => _blocked = true);
      showAppSnack(context, 'Kontak diblokir.');
    } catch (error) {
      if (mounted) showAppSnack(context, mapError(error).message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final chat = ref.watch(chatControllerProvider(widget.conversation.id));
    final conversation = chat.conversation ?? widget.conversation;
    final peer = _peer;

    return Scaffold(
      appBar: AppBar(title: const Text('Info kontak')),
      body: _loading
          ? const LoadingPane(label: 'Memuat info kontak…')
          : _error != null
          ? ErrorPane(message: _error!.message, onRetry: _load)
          : SafeArea(
              child: ListView(
                padding: const EdgeInsets.only(bottom: AppTokens.space32),
                children: [
                  const SizedBox(height: AppTokens.space16),
                  Center(
                    child: AvatarView(
                      name: peer?.title ?? conversation.title,
                      path: peer?.avatarPath ?? conversation.peerAvatarPath,
                      size: 104,
                    ),
                  ),
                  const SizedBox(height: AppTokens.space16),
                  Center(
                    child: Text(
                      peer?.title ?? conversation.title,
                      style: Theme.of(context).textTheme.titleLarge,
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Center(
                    child: Text(
                      '@${peer?.username ?? conversation.peerUsername}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  if ((peer?.bio ?? '').isNotEmpty) ...[
                    const SizedBox(height: AppTokens.space8),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppTokens.space32,
                      ),
                      child: Text(
                        peer!.bio,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                  ],
                  const SizedBox(height: AppTokens.space24),
                  if (conversation.peerIdentityChanged)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppTokens.space16,
                      ),
                      child: InfoBanner(
                        message:
                            'Kunci keamanan kontak ini berubah sejak terakhir '
                            'Anda memverifikasi. Verifikasi ulang sebelum '
                            'melanjutkan percakapan sensitif.',
                        icon: Icons.gpp_maybe_outlined,
                        color: p.statusWarning,
                      ),
                    ),
                  _SecuritySection(
                    safetyNumber: _safetyNumber,
                    verified: _verified,
                    busy: _busy,
                    onVerify: _verify,
                    onReset: _resetSession,
                    onCopy: _safetyNumber == null
                        ? null
                        : () => copySafely(
                            context,
                            _safetyNumber!,
                            'Nomor keamanan',
                          ),
                  ),
                  _Section(
                    title: 'Obrolan',
                    children: [
                      SwitchListTile(
                        value: conversation.pinned,
                        title: const Text('Sematkan obrolan'),
                        secondary: const Icon(Icons.push_pin_outlined),
                        onChanged: (value) async {
                          try {
                            await ref
                                .read(
                                  chatControllerProvider(
                                    widget.conversation.id,
                                  ).notifier,
                                )
                                .setPinned(value);
                          } catch (error) {
                            if (context.mounted) {
                              showAppSnack(
                                context,
                                mapError(error).message,
                                error: true,
                              );
                            }
                          }
                        },
                      ),
                      SwitchListTile(
                        value: conversation.muted,
                        title: const Text('Bisukan notifikasi'),
                        secondary: const Icon(Icons.notifications_off_outlined),
                        onChanged: (value) async {
                          try {
                            await ref
                                .read(
                                  chatControllerProvider(
                                    widget.conversation.id,
                                  ).notifier,
                                )
                                .setMuted(value);
                          } catch (error) {
                            if (context.mounted) {
                              showAppSnack(
                                context,
                                mapError(error).message,
                                error: true,
                              );
                            }
                          }
                        },
                      ),
                      ListTile(
                        leading: const Icon(Icons.photo_library_outlined),
                        title: const Text('Media dan berkas bersama'),
                        subtitle: const Text(
                          'Foto, video, dokumen, dan pesan suara.',
                        ),
                        onTap: _showSharedMedia,
                      ),
                      ListTile(
                        leading: const Icon(Icons.delete_sweep_outlined),
                        title: const Text('Bersihkan riwayat di perangkat'),
                        subtitle: const Text(
                          'Pesan tetap tersimpan pada kontak Anda.',
                        ),
                        onTap: () async {
                          final confirmed = await showConfirmDialog(
                            context,
                            title: 'Bersihkan riwayat?',
                            message:
                                'Semua pesan pada perangkat ini akan dihapus.',
                            confirmLabel: 'Bersihkan',
                            destructive: true,
                          );
                          if (!confirmed) return;
                          try {
                            await ref
                                .read(
                                  chatControllerProvider(
                                    widget.conversation.id,
                                  ).notifier,
                                )
                                .clearHistory();
                            if (context.mounted) {
                              showAppSnack(
                                context,
                                'Riwayat lokal dibersihkan.',
                              );
                            }
                          } catch (error) {
                            if (context.mounted) {
                              showAppSnack(
                                context,
                                mapError(error).message,
                                error: true,
                              );
                            }
                          }
                        },
                      ),
                    ],
                  ),
                  _Section(
                    title: 'Privasi',
                    children: [
                      ListTile(
                        leading: Icon(
                          _blocked
                              ? Icons.lock_open_rounded
                              : Icons.block_rounded,
                          color: _blocked ? p.statusSuccess : p.statusError,
                        ),
                        title: Text(
                          _blocked ? 'Buka blokir kontak' : 'Blokir kontak',
                          style: TextStyle(
                            color: _blocked ? p.statusSuccess : p.statusError,
                          ),
                        ),
                        subtitle: Text(
                          _blocked
                              ? 'Kontak ini tidak dapat mengirim pesan.'
                              : 'Kontak tidak dapat mengirim pesan baru.',
                        ),
                        onTap: _busy ? null : _toggleBlock,
                      ),
                      ListTile(
                        leading: Icon(
                          Icons.report_gmailerrorred_rounded,
                          color: p.statusWarning,
                        ),
                        title: Text(
                          'Laporkan kontak',
                          style: TextStyle(color: p.statusWarning),
                        ),
                        subtitle: const Text(
                          'Kirim laporan ke admin Adoetz Chat.',
                        ),
                        onTap: _busy ? null : _reportUser,
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppTokens.space24,
                      vertical: AppTokens.space16,
                    ),
                    child: Text(
                      'Percakapan ini terenkripsi end-to-end. Server hanya '
                      'menyimpan teks terenkripsi dan tidak memiliki kunci '
                      'privat Anda.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTokens.space16,
        AppTokens.space16,
        AppTokens.space16,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: AppTokens.space8),
            child: Text(
              title,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: p.brandSoft,
                letterSpacing: 0.8,
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: p.bgSurface,
              borderRadius: BorderRadius.circular(AppTokens.radiusCard),
              border: Border.all(color: p.border),
            ),
            child: Column(children: children),
          ),
        ],
      ),
    );
  }
}

class _SecuritySection extends StatelessWidget {
  const _SecuritySection({
    required this.safetyNumber,
    required this.verified,
    required this.busy,
    required this.onVerify,
    required this.onReset,
    required this.onCopy,
  });

  final String? safetyNumber;
  final bool verified;
  final bool busy;
  final VoidCallback onVerify;
  final VoidCallback onReset;
  final VoidCallback? onCopy;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    final groups = (safetyNumber ?? '').split(RegExp(r'\s+'));

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTokens.space16,
        AppTokens.space16,
        AppTokens.space16,
        0,
      ),
      child: SectionCard(
        title: 'Keamanan',
        description:
            'Bandingkan nomor keamanan secara tatap muka atau lewat saluran '
            'lain yang tepercaya.',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  verified
                      ? Icons.verified_user_rounded
                      : Icons.shield_outlined,
                  color: verified ? p.statusSuccess : p.textSecondary,
                ),
                const SizedBox(width: AppTokens.space8),
                Expanded(
                  child: Text(
                    verified ? 'Kontak terverifikasi' : 'Belum diverifikasi',
                    style: text.bodyMedium?.copyWith(
                      color: verified ? p.statusSuccess : null,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (safetyNumber != null && onCopy != null)
                  IconButton(
                    tooltip: 'Salin nomor keamanan',
                    onPressed: onCopy,
                    icon: const Icon(Icons.copy_rounded, size: 18),
                  ),
              ],
            ),
            const SizedBox(height: AppTokens.space12),
            if (safetyNumber == null)
              Text(
                'Nomor keamanan belum tersedia. Kirim pesan pertama untuk '
                'membangun sesi enkripsi.',
                style: text.bodySmall,
              )
            else
              Center(
                child: Container(
                  padding: const EdgeInsets.all(AppTokens.space12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(AppTokens.radiusCard),
                  ),
                  child: QrImageView(
                    data: 'adoetz:$safetyNumber',
                    version: QrVersions.auto,
                    size: 168,
                    backgroundColor: Colors.white,
                    padding: EdgeInsets.zero,
                  ),
                ),
              ),
            if (groups.length == 12) ...[
              const SizedBox(height: AppTokens.space12),
              for (var line = 0; line < 3; line++)
                Center(
                  child: SelectableText(
                    groups.sublist(line * 4, line * 4 + 4).join(' '),
                    style: text.bodyMedium?.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                      letterSpacing: 1.4,
                    ),
                  ),
                ),
            ],
            const SizedBox(height: AppTokens.space16),
            if (!verified)
              FilledButton.icon(
                onPressed: busy || safetyNumber == null ? null : onVerify,
                icon: const Icon(Icons.verified_user_outlined),
                label: const Text('Tandai terverifikasi'),
              ),
            if (!verified) const SizedBox(height: AppTokens.space8),
            OutlinedButton.icon(
              onPressed: busy ? null : onReset,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Setel ulang sesi enkripsi'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SharedMediaSheet extends ConsumerStatefulWidget {
  const _SharedMediaSheet({
    required this.conversationId,
    required this.scrollController,
  });

  final String conversationId;
  final ScrollController scrollController;

  @override
  ConsumerState<_SharedMediaSheet> createState() => _SharedMediaSheetState();
}

class _SharedMediaSheetState extends ConsumerState<_SharedMediaSheet> {
  List<AttachmentMeta> _items = const [];
  bool _loading = true;
  AppError? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final messages = await ref
          .read(depsProvider)
          .chat
          .loadLocalMessages(widget.conversationId, limit: 300);
      final items = <AttachmentMeta>[
        for (final message in messages.reversed) ...message.attachments,
      ];
      if (!mounted) return;
      setState(() {
        _items = items;
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

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppTokens.space16,
            0,
            AppTokens.space16,
            AppTokens.space8,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Media dan berkas bersama',
                  style: text.titleMedium,
                ),
              ),
              Text('${_items.length} item', style: text.labelSmall),
            ],
          ),
        ),
        if (_loading) const Expanded(child: LoadingPane(label: 'Memuat…')),
        if (!_loading && _error != null)
          Expanded(
            child: ErrorPane(message: _error!.message, onRetry: _load),
          ),
        if (!_loading && _error == null)
          Expanded(
            child: _items.isEmpty
                ? const EmptyState(
                    icon: Icons.photo_library_outlined,
                    title: 'Belum ada media',
                    message:
                        'Foto, video, dokumen, dan pesan suara akan '
                        'muncul di sini.',
                  )
                : ListView.separated(
                    controller: widget.scrollController,
                    padding: const EdgeInsets.fromLTRB(
                      AppTokens.space16,
                      AppTokens.space8,
                      AppTokens.space16,
                      AppTokens.space24,
                    ),
                    itemCount: _items.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: AppTokens.space8),
                    itemBuilder: (context, index) =>
                        AttachmentView(meta: _items[index], outgoing: false),
                  ),
          ),
      ],
    );
  }
}
