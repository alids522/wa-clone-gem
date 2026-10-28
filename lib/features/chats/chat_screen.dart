import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../app/providers.dart';
import '../../app/theme/app_tokens.dart';
import '../../core/config/env.dart';
import '../../core/models/conversation.dart';
import '../../core/models/message.dart';
import '../../core/services/call_repository.dart';
import '../../core/services/chat_repository.dart';
import '../../core/ui/app_widgets.dart';
import '../../core/ui/avatar_view.dart';
import '../../core/utils/app_error.dart';
import '../../core/utils/debouncer.dart';
import '../../core/utils/formatters.dart';
import '../calls/active_call_screen.dart';
import 'chat_info_screen.dart';
import 'widgets/message_bubble.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key, required this.conversation});

  final ConversationSummary conversation;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final TextEditingController _text = TextEditingController();
  final ScrollController _scroll = ScrollController();
  ChatMessage? _replyTo;
  ChatMessage? _editing;
  bool _sending = false;

  final TextEditingController _search = TextEditingController();
  final Debouncer _searchDebounce = Debouncer(
    duration: const Duration(milliseconds: 300),
  );
  bool _searching = false;
  bool _searchBusy = false;
  List<ChatMessage>? _searchResults;

  final AudioRecorder _recorder = AudioRecorder();
  bool _recording = false;
  String? _recordPath;
  Timer? _recordTimer;
  Duration _recordElapsed = Duration.zero;

  String get _conversationId => widget.conversation.id;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _recordTimer?.cancel();
    _searchDebounce.dispose();
    _search.dispose();
    _recorder.dispose();
    _scroll.dispose();
    _text.dispose();
    super.dispose();
  }

  // --- Search ---------------------------------------------------------------

  void _toggleSearch() {
    setState(() {
      _searching = !_searching;
      if (!_searching) {
        _search.clear();
        _searchResults = null;
        _searchBusy = false;
      }
    });
    _searchDebounce.cancel();
  }

  void _onSearchChanged(String value) {
    final query = value.trim();
    _searchDebounce.cancel();
    if (query.isEmpty) {
      setState(() {
        _searchResults = null;
        _searchBusy = false;
      });
      return;
    }
    setState(() => _searchBusy = true);
    _searchDebounce.run(() async {
      try {
        final results = await ref
            .read(depsProvider)
            .chat
            .searchMessages(_conversationId, query);
        if (!mounted || _search.text.trim() != query) return;
        setState(() {
          _searchResults = results;
          _searchBusy = false;
        });
      } catch (error) {
        if (!mounted) return;
        setState(() => _searchBusy = false);
        showAppSnack(context, mapError(error).message, error: true);
      }
    });
  }

  // --- Forward --------------------------------------------------------------

  Future<void> _forward(ChatMessage message) async {
    final deps = ref.read(depsProvider);
    List<ConversationSummary> targets;
    try {
      final all = await deps.chat.localConversations();
      targets = all
          .where((item) => item.id != _conversationId)
          .toList(growable: false);
    } catch (error) {
      if (mounted) showAppSnack(context, mapError(error).message, error: true);
      return;
    }
    if (!mounted) return;
    if (targets.isEmpty) {
      showAppSnack(context, 'Belum ada obrolan lain untuk meneruskan pesan.');
      return;
    }

    final target = await showModalBottomSheet<ConversationSummary>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 460),
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: targets.length,
            itemBuilder: (context, index) {
              final item = targets[index];
              return ListTile(
                leading: AvatarView(
                  name: item.title,
                  path: item.peerAvatarPath,
                  size: 40,
                ),
                title: Text(item.title, maxLines: 1),
                subtitle: Text('@${item.peerUsername}'),
                onTap: () => Navigator.of(sheetContext).pop(item),
              );
            },
          ),
        ),
      ),
    );
    if (target == null || !mounted) return;

    try {
      final meta = message.firstAttachment;
      if (meta != null) {
        final file = await deps.media.downloadAttachment(meta);
        final bytes = await file.readAsBytes();
        await deps.chat.sendAttachment(
          conversationId: target.id,
          peerId: target.peerId,
          draft: AttachmentDraft(
            bytes: bytes,
            mime: meta.mime,
            name: meta.name,
            durationMs: meta.durationMs,
            width: meta.width,
            height: meta.height,
          ),
          caption: message.body,
        );
      } else if (message.body.trim().isNotEmpty) {
        await deps.chat.sendText(
          conversationId: target.id,
          peerId: target.peerId,
          body: message.body,
        );
      }
      if (mounted) {
        showAppSnack(context, 'Pesan diteruskan ke ${target.title}');
      }
    } catch (error) {
      if (mounted) showAppSnack(context, mapError(error).message, error: true);
    }
  }

  // --- Report ---------------------------------------------------------------

  Future<void> _reportMessage(ChatMessage message) async {
    final controller = ref.read(
      chatControllerProvider(_conversationId).notifier,
    );
    const reasons = <String, String>{
      'spam': 'Spam atau iklan',
      'harassment': 'Pelecehan atau ancaman',
      'scam': 'Penipuan',
      'illegal': 'Konten ilegal',
      'other': 'Lainnya',
    };
    final details = TextEditingController();
    var reason = 'spam';
    var shareContent = false;
    var busy = false;

    final submitted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Laporkan pesan'),
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
                CheckboxListTile(
                  value: shareContent,
                  onChanged: busy
                      ? null
                      : (value) =>
                            setDialogState(() => shareContent = value ?? false),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text('Sertakan isi pesan ini'),
                  subtitle: const Text(
                    'Pesan terenkripsi ujung-ke-ujung. Isinya hanya dikirim '
                    'ke admin bila Anda mencentang kotak ini.',
                  ),
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
                        await controller.report(
                          reportedUserId: widget.conversation.peerId,
                          reason: reason,
                          details: details.text,
                          message: message,
                          shareContent: shareContent,
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

  void _onScroll() {
    if (!_scroll.hasClients) return;
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 240) {
      final controller = ref.read(
        chatControllerProvider(_conversationId).notifier,
      );
      final state = ref.read(chatControllerProvider(_conversationId));
      if (state.hasMore && !state.loadingOlder && state.messages.isNotEmpty) {
        controller.loadOlder();
      }
    }
  }

  Future<void> _send() async {
    final controller = ref.read(
      chatControllerProvider(_conversationId).notifier,
    );
    final editing = _editing;
    final body = _text.text;
    if (editing != null) {
      if (body.trim().isEmpty || body.trim() == editing.body) {
        _cancelComposer();
        return;
      }
      try {
        await controller.editMessage(editing, body);
        _cancelComposer();
      } catch (error) {
        if (mounted)
          showAppSnack(context, mapError(error).message, error: true);
      }
      return;
    }
    if (body.trim().isEmpty || _sending) return;
    final replyTo = _replyTo;
    setState(() => _sending = true);
    _text.clear();
    setState(() => _replyTo = null);
    try {
      await controller.sendText(body, replyTo: replyTo);
      _scrollToBottom();
    } catch (error) {
      if (mounted) showAppSnack(context, mapError(error).message, error: true);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _cancelComposer() {
    setState(() {
      _editing = null;
      _replyTo = null;
    });
    _text.clear();
  }

  void _scrollToBottom() {
    if (!_scroll.hasClients) return;
    _scroll.animateTo(0, duration: AppTokens.normal, curve: Curves.easeOut);
  }

  // --- Attachments ----------------------------------------------------------

  Future<void> _showAttachmentSheet() async {
    final p = context.palette;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.photo_library_outlined, color: p.brandSoft),
              title: const Text('Foto dari galeri'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _pickImage(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: Icon(Icons.photo_camera_outlined, color: p.brandSoft),
              title: const Text('Ambil foto'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _pickImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: Icon(Icons.videocam_outlined, color: p.brandSoft),
              title: const Text('Video'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _pickVideo();
              },
            ),
            ListTile(
              leading: Icon(Icons.attach_file_rounded, color: p.brandSoft),
              title: const Text('Dokumen'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _pickDocument();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: source,
        maxWidth: 2048,
        imageQuality: 85,
      );
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      final mime =
          picked.mimeType ??
          lookupMimeType(picked.name, headerBytes: bytes) ??
          'image/jpeg';
      await _sendAttachment(
        AttachmentDraft(bytes: bytes, mime: mime, name: picked.name),
      );
    } catch (error) {
      if (mounted) showAppSnack(context, mapError(error).message, error: true);
    }
  }

  Future<void> _pickVideo() async {
    try {
      final picked = await ImagePicker().pickVideo(
        source: ImageSource.gallery,
        maxDuration: const Duration(minutes: 5),
      );
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      final mime =
          picked.mimeType ??
          lookupMimeType(picked.name, headerBytes: bytes) ??
          'video/mp4';
      await _sendAttachment(
        AttachmentDraft(bytes: bytes, mime: mime, name: picked.name),
      );
    } catch (error) {
      if (mounted) showAppSnack(context, mapError(error).message, error: true);
    }
  }

  Future<void> _pickDocument() async {
    try {
      final result = await FilePicker.platform.pickFiles(withData: true);
      final file = result?.files.firstOrNull;
      final bytes = file?.bytes;
      if (file == null || bytes == null) return;
      final mime =
          lookupMimeType(file.name, headerBytes: bytes) ??
          'application/octet-stream';
      await _sendAttachment(
        AttachmentDraft(bytes: bytes, mime: mime, name: file.name),
      );
    } catch (error) {
      if (mounted) showAppSnack(context, mapError(error).message, error: true);
    }
  }

  Future<void> _sendAttachment(AttachmentDraft draft) async {
    final controller = ref.read(
      chatControllerProvider(_conversationId).notifier,
    );
    final replyTo = _replyTo;
    setState(() => _replyTo = null);
    try {
      await controller.sendAttachment(
        draft,
        caption: _text.text,
        replyTo: replyTo,
      );
      _text.clear();
      _scrollToBottom();
    } catch (error) {
      if (mounted) showAppSnack(context, mapError(error).message, error: true);
    }
  }

  // --- Voice notes ----------------------------------------------------------

  Future<void> _startRecording() async {
    try {
      if (!await _recorder.hasPermission()) {
        if (mounted) {
          showAppSnack(
            context,
            'Izin mikrofon diperlukan untuk pesan suara.',
            error: true,
          );
        }
        return;
      }
      final dir = await getTemporaryDirectory();
      final path = p.join(
        dir.path,
        'voice_${DateTime.now().millisecondsSinceEpoch}.m4a',
      );
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 64000,
          sampleRate: 44100,
        ),
        path: path,
      );
      setState(() {
        _recording = true;
        _recordElapsed = Duration.zero;
        _recordPath = path;
      });
      _recordTimer?.cancel();
      _recordTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) return;
        setState(() {
          _recordElapsed += const Duration(seconds: 1);
        });
        if (_recordElapsed.inSeconds >= Env.voiceMaxSeconds) {
          _stopRecording(send: true);
        }
      });
    } catch (error) {
      if (mounted) showAppSnack(context, mapError(error).message, error: true);
    }
  }

  Future<void> _stopRecording({required bool send}) async {
    if (!_recording) return;
    _recordTimer?.cancel();
    final elapsed = _recordElapsed;
    String? path;
    try {
      path = await _recorder.stop();
    } catch (_) {
      path = _recordPath;
    }
    if (!mounted) return;
    setState(() {
      _recording = false;
      _recordPath = null;
      _recordElapsed = Duration.zero;
    });
    if (!send || path == null || elapsed.inMilliseconds < 800) return;
    try {
      final file = File(path);
      final bytes = await file.readAsBytes();
      final mime = lookupMimeType(path, headerBytes: bytes) ?? 'audio/mp4';
      await _sendAttachment(
        AttachmentDraft(
          bytes: bytes,
          mime: mime,
          name: p.basename(path),
          durationMs: elapsed.inMilliseconds,
        ),
      );
    } catch (error) {
      if (mounted) showAppSnack(context, mapError(error).message, error: true);
    }
  }

  // --- Message actions ------------------------------------------------------

  Future<void> _showMessageActions(ChatMessage message) async {
    final p = context.palette;
    final mine = message.senderId == widget.conversation.peerId ? false : true;
    final me = ref.read(depsProvider).client.auth.currentUser?.id;
    final controller = ref.read(
      chatControllerProvider(_conversationId).notifier,
    );
    final canEdit =
        mine &&
        message.kind == MessageKind.text &&
        !message.isDeleted &&
        !message.isLocalOnly &&
        DateTime.now().difference(message.createdAt).inMinutes < 15;

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!message.isDeleted && !message.isLocalOnly)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTokens.space12,
                  vertical: AppTokens.space4,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    for (final emoji in const [
                      '👍',
                      '❤️',
                      '😂',
                      '😮',
                      '😢',
                      '🙏',
                    ])
                      InkWell(
                        borderRadius: BorderRadius.circular(24),
                        onTap: () {
                          Navigator.of(sheetContext).pop();
                          controller.toggleReaction(message, emoji);
                        },
                        child: Container(
                          padding: const EdgeInsets.all(AppTokens.space8),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color:
                                (message.reactions[emoji] ?? const []).contains(
                                  me,
                                )
                                ? p.brandSoft.withValues(alpha: 0.18)
                                : Colors.transparent,
                          ),
                          child: Text(
                            emoji,
                            style: const TextStyle(fontSize: 22),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ListTile(
              leading: const Icon(Icons.reply_rounded),
              title: const Text('Balas'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                setState(() {
                  _replyTo = message;
                  _editing = null;
                });
              },
            ),
            if (message.body.trim().isNotEmpty)
              ListTile(
                leading: const Icon(Icons.copy_rounded),
                title: const Text('Salin teks'),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  await Clipboard.setData(ClipboardData(text: message.body));
                  if (mounted) showAppSnack(context, 'Teks disalin');
                },
              ),
            if (!message.isDeleted && !message.isLocalOnly)
              ListTile(
                leading: const Icon(Icons.forward_rounded),
                title: const Text('Teruskan'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _forward(message);
                },
              ),
            if (!mine)
              ListTile(
                leading: Icon(
                  Icons.report_gmailerrorred_rounded,
                  color: p.statusWarning,
                ),
                title: Text(
                  'Laporkan pesan',
                  style: TextStyle(color: p.statusWarning),
                ),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _reportMessage(message);
                },
              ),
            if (canEdit)
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Edit pesan'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  setState(() {
                    _editing = message;
                    _replyTo = null;
                    _text.text = message.body;
                    _text.selection = TextSelection.collapsed(
                      offset: message.body.length,
                    );
                  });
                },
              ),
            if (mine && !message.isDeleted && !message.isLocalOnly)
              ListTile(
                leading: Icon(
                  Icons.delete_outline_rounded,
                  color: p.statusError,
                ),
                title: Text(
                  'Hapus untuk semua',
                  style: TextStyle(color: p.statusError),
                ),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  final confirmed = await showConfirmDialog(
                    context,
                    title: 'Hapus pesan?',
                    message: 'Pesan akan dihapus untuk kedua pihak.',
                    confirmLabel: 'Hapus',
                    destructive: true,
                  );
                  if (!confirmed) return;
                  try {
                    await ref
                        .read(chatControllerProvider(_conversationId).notifier)
                        .deleteForEveryone(message);
                  } catch (error) {
                    if (mounted) {
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
              leading: const Icon(Icons.delete_sweep_outlined),
              title: const Text('Hapus dari perangkat'),
              onTap: () async {
                Navigator.of(sheetContext).pop();
                await ref
                    .read(chatControllerProvider(_conversationId).notifier)
                    .deleteLocally(message);
              },
            ),
          ],
        ),
      ),
    );
  }

  // --- Build ----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final provider = chatControllerProvider(_conversationId);
    final state = ref.watch(provider);
    final controller = ref.read(provider.notifier);
    final online = ref.watch(onlineStatusProvider);
    final conversation = state.conversation ?? widget.conversation;
    final query = _search.text.trim();
    final visibleMessages = _searching
        ? (_searchResults ?? const <ChatMessage>[])
        : state.messages;

    ref.listen<ChatState>(provider, (previous, next) {
      final error = next.error;
      if (error != null && previous?.error != error) {
        showAppSnack(context, error.message, error: true);
        controller.dismissError();
      }
      if (previous?.draft == '' &&
          next.draft.isNotEmpty &&
          _text.text.isEmpty) {
        _text.text = next.draft;
      }
    });

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: InkWell(
          onTap: () => _openInfo(conversation),
          child: Row(
            children: [
              AvatarView(
                name: conversation.title,
                path: conversation.peerAvatarPath,
                size: 38,
                showOnline: state.peerOnline,
              ),
              const SizedBox(width: AppTokens.space12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      conversation.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      state.peerTyping
                          ? 'sedang mengetik…'
                          : state.peerOnline
                          ? 'online'
                          : '@${conversation.peerUsername}',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: state.peerTyping
                            ? context.palette.brandSoft
                            : context.palette.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          IconButton(
            tooltip: _searching ? 'Tutup pencarian' : 'Cari pesan',
            onPressed: _toggleSearch,
            icon: Icon(
              _searching ? Icons.search_off_rounded : Icons.search_rounded,
            ),
          ),
          if (Env.callsEnabled) ...[
            IconButton(
              tooltip: 'Panggilan suara',
              onPressed: () => _startCall(CallKind.voice, conversation),
              icon: const Icon(Icons.call_outlined),
            ),
            IconButton(
              tooltip: 'Panggilan video',
              onPressed: () => _startCall(CallKind.video, conversation),
              icon: const Icon(Icons.videocam_outlined),
            ),
          ],
          IconButton(
            tooltip: 'Info obrolan',
            onPressed: () => _openInfo(conversation),
            icon: const Icon(Icons.info_outline_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          if (!online) const OfflineBanner(),
          if (conversation.peerIdentityChanged)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppTokens.space12,
                AppTokens.space8,
                AppTokens.space12,
                0,
              ),
              child: InkWell(
                onTap: () => _openInfo(conversation),
                child: const InfoBanner(
                  message:
                      'Kunci keamanan kontak ini berubah. Periksa nomor '
                      'keamanan sebelum mengirim pesan.',
                  icon: Icons.gpp_maybe_outlined,
                ),
              ),
            ),
          if (_searching)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppTokens.space12,
                AppTokens.space8,
                AppTokens.space12,
                AppTokens.space4,
              ),
              child: TextField(
                controller: _search,
                autofocus: true,
                textInputAction: TextInputAction.search,
                onChanged: _onSearchChanged,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Cari pesan di obrolan ini',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _searchBusy
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Bersihkan',
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () {
                            _search.clear();
                            _onSearchChanged('');
                            setState(() {});
                          },
                        ),
                ),
              ),
            ),
          if (_searching && query.isNotEmpty && !_searchBusy)
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTokens.space16,
                vertical: AppTokens.space4,
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '${visibleMessages.length} pesan cocok',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),
            ),
          Expanded(
            child: state.loading
                ? const LoadingPane(label: 'Memuat pesan…')
                : _MessageList(
                    messages: visibleMessages,
                    myId: ref.watch(depsProvider).client.auth.currentUser?.id,
                    hasMore: !_searching && state.hasMore,
                    loadingOlder: !_searching && state.loadingOlder,
                    emptyTitle: _searching
                        ? 'Tidak ada hasil'
                        : 'Mulai percakapan',
                    emptyMessage: _searching
                        ? 'Tidak ada pesan yang cocok dengan pencarian.'
                        : 'Pesan di obrolan ini terenkripsi end-to-end.',
                    onLongPress: _showMessageActions,
                    onRetry: (message) async {
                      try {
                        await controller.retry(message);
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
          ),
          _Composer(
            text: _text,
            replyTo: _replyTo,
            editing: _editing,
            sending: _sending || state.sendingAttachment,
            recording: _recording,
            recordElapsed: _recordElapsed,
            onCancelReply: () => setState(() => _replyTo = null),
            onCancelEdit: _cancelComposer,
            onAttach: _showAttachmentSheet,
            onSend: _send,
            onStartRecording: _startRecording,
            onCancelRecording: () => _stopRecording(send: false),
            onSendRecording: () => _stopRecording(send: true),
            onChanged: (value) {
              controller.setDraft(value);
              if (value.trim().isNotEmpty) controller.notifyTyping();
            },
          ),
        ],
      ),
    );
  }

  Future<void> _startCall(
    CallKind kind,
    ConversationSummary conversation,
  ) async {
    try {
      final call = await ref
          .read(depsProvider)
          .calls
          .initiate(receiverId: conversation.peerId, kind: kind);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ActiveCallScreen(
            call: call,
            peerTitle: conversation.title,
            peerAvatarPath: conversation.peerAvatarPath,
            outgoing: true,
            video: kind == CallKind.video,
          ),
        ),
      );
    } catch (error) {
      if (mounted) showAppSnack(context, mapError(error).message, error: true);
    }
  }

  void _openInfo(ConversationSummary conversation) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ChatInfoScreen(conversation: conversation),
      ),
    );
  }
}

bool _isMine(ChatMessage message, String? myId) => message.senderId == myId;

class _MessageList extends StatelessWidget {
  const _MessageList({
    required this.messages,
    required this.myId,
    required this.hasMore,
    required this.loadingOlder,
    required this.onLongPress,
    required this.onRetry,
    this.emptyTitle = 'Mulai percakapan',
    this.emptyMessage = 'Pesan di obrolan ini terenkripsi end-to-end.',
  });

  final List<ChatMessage> messages;
  final String? myId;
  final bool hasMore;
  final bool loadingOlder;
  final ValueChanged<ChatMessage> onLongPress;
  final ValueChanged<ChatMessage> onRetry;
  final String emptyTitle;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    if (messages.isEmpty) {
      return EmptyState(
        icon: Icons.lock_outline_rounded,
        title: emptyTitle,
        message: emptyMessage,
      );
    }
    return ListView.builder(
      controller: PrimaryScrollController.maybeOf(context),
      reverse: true,
      padding: const EdgeInsets.symmetric(vertical: AppTokens.space12),
      itemCount: messages.length + (hasMore || loadingOlder ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= messages.length) {
          return Padding(
            padding: const EdgeInsets.all(AppTokens.space16),
            child: Center(
              child: loadingOlder
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(
                      'Tarik ke atas untuk memuat pesan lama',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
            ),
          );
        }
        final message = messages[messages.length - 1 - index];
        final newer = index == 0 ? null : messages[messages.length - index];
        final showDay =
            newer == null || !_sameDay(newer.createdAt, message.createdAt);
        final mine = _isMine(message, myId);
        return Column(
          children: [
            if (showDay)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppTokens.space8),
                child: _DayChip(date: message.createdAt),
              ),
            MessageBubble(
              message: message,
              mine: mine,
              onLongPress: () => onLongPress(message),
              onRetry: () => onRetry(message),
            ),
          ],
        );
      },
    );
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

class _DayChip extends StatelessWidget {
  const _DayChip({required this.date});

  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.space12,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: p.bgRaised,
        borderRadius: BorderRadius.circular(AppTokens.radiusPill),
        border: Border.all(color: p.border),
      ),
      child: Text(
        Formatters.daySeparator(date),
        style: Theme.of(context).textTheme.labelSmall,
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.text,
    required this.replyTo,
    required this.editing,
    required this.sending,
    required this.recording,
    required this.recordElapsed,
    required this.onCancelReply,
    required this.onCancelEdit,
    required this.onAttach,
    required this.onSend,
    required this.onStartRecording,
    required this.onCancelRecording,
    required this.onSendRecording,
    required this.onChanged,
  });

  final TextEditingController text;
  final ChatMessage? replyTo;
  final ChatMessage? editing;
  final bool sending;
  final bool recording;
  final Duration recordElapsed;
  final VoidCallback onCancelReply;
  final VoidCallback onCancelEdit;
  final VoidCallback onAttach;
  final VoidCallback onSend;
  final VoidCallback onStartRecording;
  final VoidCallback onCancelRecording;
  final VoidCallback onSendRecording;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final textTheme = Theme.of(context).textTheme;

    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: p.bgSurface,
          border: Border(top: BorderSide(color: p.border)),
        ),
        padding: const EdgeInsets.fromLTRB(
          AppTokens.space8,
          AppTokens.space8,
          AppTokens.space8,
          AppTokens.space8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (editing != null)
              _ContextBar(
                icon: Icons.edit_outlined,
                title: 'Edit pesan',
                body: editing!.body,
                onClose: onCancelEdit,
              ),
            if (replyTo != null)
              _ContextBar(
                icon: Icons.reply_rounded,
                title: 'Membalas',
                body: replyTo!.preview,
                onClose: onCancelReply,
              ),
            if (recording)
              Row(
                children: [
                  IconButton(
                    tooltip: 'Batalkan rekaman',
                    onPressed: onCancelRecording,
                    icon: Icon(
                      Icons.delete_outline_rounded,
                      color: p.statusError,
                    ),
                  ),
                  Expanded(
                    child: Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: p.statusError,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: AppTokens.space8),
                        Text(
                          'Merekam ${Formatters.duration(recordElapsed)}',
                          style: textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                  IconButton.filled(
                    tooltip: 'Kirim pesan suara',
                    onPressed: onSendRecording,
                    icon: const Icon(Icons.send_rounded),
                  ),
                ],
              )
            else
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  IconButton(
                    tooltip: 'Lampirkan',
                    onPressed: sending ? null : onAttach,
                    icon: const Icon(Icons.add_circle_outline_rounded),
                  ),
                  Expanded(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 132),
                      child: TextField(
                        controller: text,
                        enabled: !sending,
                        minLines: 1,
                        maxLines: 5,
                        textCapitalization: TextCapitalization.sentences,
                        keyboardType: TextInputType.multiline,
                        textInputAction: TextInputAction.newline,
                        onChanged: onChanged,
                        decoration: InputDecoration(
                          hintText: 'Tulis pesan',
                          fillColor: p.bgRaised,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: AppTokens.space16,
                            vertical: AppTokens.space12,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(
                              AppTokens.radiusPill,
                            ),
                            borderSide: BorderSide.none,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(
                              AppTokens.radiusPill,
                            ),
                            borderSide: BorderSide(color: p.border),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(
                              AppTokens.radiusPill,
                            ),
                            borderSide: BorderSide(
                              color: p.focusRing,
                              width: 1.5,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppTokens.space8),
                  sending
                      ? const Padding(
                          padding: EdgeInsets.all(AppTokens.space12),
                          child: SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : ValueListenableBuilder<TextEditingValue>(
                          valueListenable: text,
                          builder: (context, value, _) {
                            final hasText = value.text.trim().isNotEmpty;
                            return IconButton.filled(
                              tooltip: hasText ? 'Kirim' : 'Rekam pesan suara',
                              onPressed: hasText ? onSend : onStartRecording,
                              icon: Icon(
                                hasText
                                    ? Icons.send_rounded
                                    : Icons.mic_none_rounded,
                              ),
                            );
                          },
                        ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _ContextBar extends StatelessWidget {
  const _ContextBar({
    required this.icon,
    required this.title,
    required this.body,
    required this.onClose,
  });

  final IconData icon;
  final String title;
  final String body;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final textTheme = Theme.of(context).textTheme;
    return Container(
      margin: const EdgeInsets.only(bottom: AppTokens.space8),
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.space12,
        vertical: AppTokens.space8,
      ),
      decoration: BoxDecoration(
        color: p.bgRaised,
        borderRadius: BorderRadius.circular(AppTokens.radiusCard),
        border: Border(left: BorderSide(color: p.brandSoft, width: 3)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: p.brandSoft),
          const SizedBox(width: AppTokens.space8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: textTheme.labelSmall?.copyWith(color: p.brandSoft),
                ),
                Text(
                  Formatters.messagePreview(body, max: 80),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodySmall,
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onClose,
            tooltip: 'Tutup',
            icon: const Icon(Icons.close_rounded, size: 18),
          ),
        ],
      ),
    );
  }
}
