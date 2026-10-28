import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:open_filex/open_filex.dart';

import '../../../app/providers.dart';
import '../../../app/theme/app_tokens.dart';
import '../../../core/models/message.dart';
import '../../../core/utils/formatters.dart';

class AttachmentView extends ConsumerWidget {
  const AttachmentView({super.key, required this.meta, required this.outgoing});

  final AttachmentMeta meta;
  final bool outgoing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    switch (meta.fileKind) {
      case MessageKind.image:
        return _ImageAttachment(meta: meta);
      case MessageKind.audio:
        return _AudioAttachment(meta: meta, outgoing: outgoing);
      case MessageKind.video:
        return _FileCard(
          meta: meta,
          icon: Icons.play_circle_outline_rounded,
          label: 'Video',
        );
      case MessageKind.document:
      case MessageKind.text:
      case MessageKind.system:
        return _FileCard(
          meta: meta,
          icon: Icons.insert_drive_file_outlined,
          label: meta.name,
        );
    }
  }
}

class _ImageAttachment extends ConsumerWidget {
  const _ImageAttachment({required this.meta});

  final AttachmentMeta meta;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final file = ref.watch(attachmentFileProvider(attachmentCacheKey(meta)));
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppTokens.radiusCard),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 280, maxWidth: 280),
        child: file.when(
          data: (value) => GestureDetector(
            onTap: () => _showFullScreen(context, value),
            child: Hero(
              tag: meta.sha256,
              child: Image.file(
                value,
                fit: BoxFit.cover,
                gaplessPlayback: true,
              ),
            ),
          ),
          loading: () => Container(
            height: 180,
            width: 240,
            color: p.bgRaised,
            alignment: Alignment.center,
            child: const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
          error: (_, __) => Container(
            height: 120,
            width: 220,
            color: p.bgRaised,
            alignment: Alignment.center,
            padding: const EdgeInsets.all(AppTokens.space12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.broken_image_outlined, color: p.statusError),
                const SizedBox(height: AppTokens.space8),
                Text(
                  'Gambar tidak dapat dibuka',
                  style: Theme.of(context).textTheme.labelSmall,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showFullScreen(BuildContext context, File file) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: Stack(
          children: [
            Positioned.fill(
              child: InteractiveViewer(
                maxScale: 4,
                child: Image.file(file, fit: BoxFit.contain),
              ),
            ),
            SafeArea(
              child: Align(
                alignment: Alignment.topRight,
                child: IconButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  icon: const Icon(Icons.close_rounded, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FileCard extends ConsumerStatefulWidget {
  const _FileCard({
    required this.meta,
    required this.icon,
    required this.label,
  });

  final AttachmentMeta meta;
  final IconData icon;
  final String label;

  @override
  ConsumerState<_FileCard> createState() => _FileCardState();
}

class _FileCardState extends ConsumerState<_FileCard> {
  bool _busy = false;

  Future<void> _open() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final file = await ref.read(
        attachmentFileProvider(attachmentCacheKey(widget.meta)).future,
      );
      await OpenFilex.open(file.path);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Gagal membuka berkas: $error')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    return InkWell(
      onTap: _open,
      borderRadius: BorderRadius.circular(AppTokens.radiusCard),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 280),
        padding: const EdgeInsets.all(AppTokens.space12),
        decoration: BoxDecoration(
          color: p.isDark ? p.bgPrimary.withValues(alpha: 0.35) : p.bgSurface,
          borderRadius: BorderRadius.circular(AppTokens.radiusCard),
          border: Border.all(color: p.border),
        ),
        child: Row(
          children: [
            Icon(widget.icon, size: 28, color: p.brandSoft),
            const SizedBox(width: AppTokens.space12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodyMedium,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    Formatters.bytes(widget.meta.size),
                    style: text.labelSmall,
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppTokens.space8),
            if (_busy)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              Icon(Icons.download_rounded, color: p.textSecondary),
          ],
        ),
      ),
    );
  }
}

class _AudioAttachment extends ConsumerStatefulWidget {
  const _AudioAttachment({required this.meta, required this.outgoing});

  final AttachmentMeta meta;
  final bool outgoing;

  @override
  ConsumerState<_AudioAttachment> createState() => _AudioAttachmentState();
}

class _AudioAttachmentState extends ConsumerState<_AudioAttachment> {
  final AudioPlayer _player = AudioPlayer();
  bool _loading = false;
  String? _error;
  Duration _position = Duration.zero;
  bool _playing = false;

  @override
  void initState() {
    super.initState();
    _player.playerStateStream.listen((state) {
      if (mounted) setState(() => _playing = state.playing);
    });
    _player.positionStream.listen((position) {
      if (mounted) setState(() => _position = position);
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_loading) return;
    setState(() => _error = null);
    if (_player.playing) {
      await _player.pause();
      return;
    }
    if (_player.duration == null) {
      setState(() => _loading = true);
      try {
        final file = await ref.read(
          attachmentFileProvider(attachmentCacheKey(widget.meta)).future,
        );
        await _player.setFilePath(file.path);
      } catch (error) {
        if (mounted) setState(() => _error = 'Gagal memuat pesan suara');
        return;
      } finally {
        if (mounted) setState(() => _loading = false);
      }
    }
    await _player.play();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final total = Duration(milliseconds: widget.meta.durationMs ?? 0);
    final elapsed = _position > total ? total : _position;
    final progress = total.inMilliseconds == 0
        ? 0.0
        : (elapsed.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);

    return Container(
      constraints: const BoxConstraints(maxWidth: 260),
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.space12,
        vertical: AppTokens.space8,
      ),
      decoration: BoxDecoration(
        color: p.isDark
            ? p.bgPrimary.withValues(alpha: 0.35)
            : p.bgSurface.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(AppTokens.radiusCard),
        border: Border.all(color: p.border),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: _toggle,
            tooltip: _playing ? 'Jeda' : 'Putar',
            icon: _loading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    _playing
                        ? Icons.pause_circle_filled_rounded
                        : Icons.play_circle_fill_rounded,
                    color: p.brandSoft,
                    size: 32,
                  ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppTokens.radiusPill),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 4,
                    backgroundColor: p.bgRaised,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _error ??
                      '${Formatters.duration(elapsed)} / ${Formatters.duration(total)}',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: _error == null ? null : p.statusError,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
