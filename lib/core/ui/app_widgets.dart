import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme/app_tokens.dart';
import '../utils/app_error.dart';

/// Brand mark used on splash, welcome and empty states.
class AdoetzLogo extends StatelessWidget {
  const AdoetzLogo({super.key, this.size = 72});

  final double size;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Semantics(
      label: 'Adoetz Chat',
      image: true,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [p.brandSoft, p.brandPrimary],
          ),
          borderRadius: BorderRadius.circular(size * 0.3),
          boxShadow: [
            BoxShadow(
              color: p.brandPrimary.withValues(alpha: 0.28),
              blurRadius: size * 0.35,
              offset: Offset(0, size * 0.1),
            ),
          ],
        ),
        child: Icon(
          Icons.chat_bubble_rounded,
          color: Colors.white,
          size: size * 0.46,
        ),
      ),
    );
  }
}

class AppAvatar extends StatelessWidget {
  const AppAvatar({
    super.key,
    required this.name,
    this.imageUrl,
    this.size = 48,
    this.showOnline = false,
  });

  final String name;
  final String? imageUrl;
  final double size;
  final bool showOnline;

  String get _initials {
    final parts = name.trim().split(RegExp(r'\s+')).where((e) => e.isNotEmpty);
    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      return parts.first.characters.take(2).toString().toUpperCase();
    }
    return (parts.first.characters.first + parts.elementAt(1).characters.first)
        .toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final fallback = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: p.brandPrimary.withValues(alpha: p.isDark ? 0.28 : 0.14),
        shape: BoxShape.circle,
        border: Border.all(color: p.border),
      ),
      child: Text(
        _initials,
        style: TextStyle(
          color: p.isDark ? p.brandSoft : p.brandPrimary,
          fontWeight: FontWeight.w600,
          fontSize: size * 0.34,
        ),
      ),
    );

    return Semantics(
      label: name.isEmpty ? 'Avatar' : 'Avatar $name',
      image: true,
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            ClipOval(
              child: imageUrl == null || imageUrl!.isEmpty
                  ? fallback
                  : Image.network(
                      imageUrl!,
                      width: size,
                      height: size,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => fallback,
                      loadingBuilder: (context, child, progress) =>
                          progress == null ? child : fallback,
                    ),
            ),
            if (showOnline)
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  width: size * 0.26,
                  height: size * 0.26,
                  decoration: BoxDecoration(
                    color: p.statusSuccess,
                    shape: BoxShape.circle,
                    border: Border.all(color: p.bgSurface, width: 2),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class AppBadge extends StatelessWidget {
  const AppBadge({super.key, required this.count, this.muted = false});

  final int count;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    if (count <= 0) return const SizedBox.shrink();
    return Semantics(
      label: '$count unread messages',
      child: Container(
        constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
        padding: const EdgeInsets.symmetric(horizontal: 7),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: muted ? p.bgRaised : p.brandPrimary,
          borderRadius: BorderRadius.circular(AppTokens.radiusPill),
          border: muted ? Border.all(color: p.border) : null,
        ),
        child: Text(
          count > 99 ? '99+' : '$count',
          style: TextStyle(
            color: muted ? p.textSecondary : Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.child,
    this.title,
    this.description,
    this.padding = const EdgeInsets.all(AppTokens.space16),
  });

  final Widget child;
  final String? title;
  final String? description;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(
        color: p.bgSurface,
        borderRadius: BorderRadius.circular(AppTokens.radiusCard),
        border: Border.all(color: p.border),
      ),
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title != null) ...[
              Text(title!, style: text.titleMedium),
              if (description != null) ...[
                const SizedBox(height: 4),
                Text(description!, style: text.bodySmall),
              ],
              const SizedBox(height: AppTokens.space16),
            ],
            child,
          ],
        ),
      ),
    );
  }
}

class AppSettingRow extends StatelessWidget {
  const AppSettingRow({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final color = destructive ? p.statusError : p.textPrimary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTokens.radiusCard),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AppTokens.minTouchTarget),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppTokens.space16,
            vertical: AppTokens.space12,
          ),
          child: Row(
            children: [
              Icon(icon, color: destructive ? p.statusError : p.textSecondary),
              const SizedBox(width: AppTokens.space16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: Theme.of(
                        context,
                      ).textTheme.bodyLarge?.copyWith(color: color),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) trailing!,
              if (trailing == null && onTap != null) ...[
                const SizedBox(width: AppTokens.space8),
                Icon(Icons.chevron_right_rounded, color: p.textSecondary),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppTokens.space32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: p.bgRaised,
                shape: BoxShape.circle,
                border: Border.all(color: p.border),
              ),
              child: Icon(icon, size: 38, color: p.brandSoft),
            ),
            const SizedBox(height: AppTokens.space24),
            Text(title, style: text.titleMedium, textAlign: TextAlign.center),
            if (message != null) ...[
              const SizedBox(height: AppTokens.space8),
              Text(
                message!,
                style: text.bodySmall,
                textAlign: TextAlign.center,
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: AppTokens.space24),
              SizedBox(
                width: 220,
                child: FilledButton(
                  onPressed: onAction,
                  child: Text(actionLabel!),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class ErrorPane extends StatelessWidget {
  const ErrorPane({
    super.key,
    required this.message,
    this.title = 'Terjadi kesalahan',
    this.code,
    this.onRetry,
  });

  final String title;
  final String message;
  final String? code;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppTokens.space32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, size: 48, color: p.statusError),
            const SizedBox(height: AppTokens.space16),
            Text(title, style: text.titleMedium, textAlign: TextAlign.center),
            const SizedBox(height: AppTokens.space8),
            Text(message, style: text.bodySmall, textAlign: TextAlign.center),
            if (code != null) ...[
              const SizedBox(height: AppTokens.space8),
              SelectableText(
                code!,
                style: text.labelSmall?.copyWith(color: p.textSecondary),
              ),
            ],
            if (onRetry != null) ...[
              const SizedBox(height: AppTokens.space24),
              SizedBox(
                width: 200,
                child: FilledButton(
                  onPressed: onRetry,
                  child: const Text('Coba lagi'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class LoadingPane extends StatelessWidget {
  const LoadingPane({super.key, this.label});

  final String? label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
          if (label != null) ...[
            const SizedBox(height: AppTokens.space16),
            Text(label!, style: Theme.of(context).textTheme.bodySmall),
          ],
        ],
      ),
    );
  }
}

class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key, this.onRetry});

  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        color: p.statusWarning.withValues(alpha: 0.14),
        padding: const EdgeInsets.symmetric(
          horizontal: AppTokens.space16,
          vertical: AppTokens.space8,
        ),
        child: Row(
          children: [
            Icon(Icons.cloud_off_rounded, size: 18, color: p.statusWarning),
            const SizedBox(width: AppTokens.space8),
            Expanded(
              child: Text(
                'Tidak ada koneksi. Pesan akan dikirim saat online.',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: p.statusWarning),
              ),
            ),
            if (onRetry != null)
              TextButton(
                onPressed: onRetry,
                style: TextButton.styleFrom(
                  foregroundColor: p.statusWarning,
                  minimumSize: const Size(48, 48),
                ),
                child: const Text('Coba'),
              ),
          ],
        ),
      ),
    );
  }
}

class PasswordField extends StatefulWidget {
  const PasswordField({
    super.key,
    required this.controller,
    this.label = 'Password',
    this.hint,
    this.onSubmitted,
    this.autofillHints = const [AutofillHints.password],
    this.validator,
    this.textInputAction = TextInputAction.done,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final ValueChanged<String>? onSubmitted;
  final List<String> autofillHints;
  final String? Function(String?)? validator;
  final TextInputAction textInputAction;

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: widget.controller,
      obscureText: _obscure,
      autofillHints: widget.autofillHints,
      textInputAction: widget.textInputAction,
      onFieldSubmitted: widget.onSubmitted,
      validator: widget.validator,
      decoration: InputDecoration(
        labelText: widget.label,
        hintText: widget.hint,
        suffixIcon: IconButton(
          tooltip: _obscure ? 'Tampilkan password' : 'Sembunyikan password',
          onPressed: () => setState(() => _obscure = !_obscure),
          icon: Icon(
            _obscure
                ? Icons.visibility_off_outlined
                : Icons.visibility_outlined,
          ),
        ),
      ),
    );
  }
}

class LabeledField extends StatelessWidget {
  const LabeledField({super.key, required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: AppTokens.space8),
          child: Text(label, style: Theme.of(context).textTheme.bodySmall),
        ),
        child,
      ],
    );
  }
}

class InfoBanner extends StatelessWidget {
  const InfoBanner({
    super.key,
    required this.message,
    this.icon = Icons.info_outline_rounded,
    this.color,
  });

  final String message;
  final IconData icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final tone = color ?? p.brandSoft;
    return Container(
      padding: const EdgeInsets.all(AppTokens.space12),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppTokens.radiusCard),
        border: Border.all(color: tone.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: tone),
          const SizedBox(width: AppTokens.space8),
          Expanded(
            child: Text(
              message,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: p.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

class SkeletonBox extends StatelessWidget {
  const SkeletonBox({super.key, this.width, this.height = 14, this.radius = 6});

  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: context.palette.skeleton,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

class ChatListSkeleton extends StatelessWidget {
  const ChatListSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(AppTokens.space16),
      itemCount: 7,
      separatorBuilder: (_, __) => const SizedBox(height: AppTokens.space16),
      itemBuilder: (_, __) => Row(
        children: [
          const SkeletonBox(width: 52, height: 52, radius: 26),
          const SizedBox(width: AppTokens.space12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonBox(width: 140, height: 14),
                SizedBox(height: 8),
                SkeletonBox(width: 220, height: 12),
              ],
            ),
          ),
          const SizedBox(width: AppTokens.space12),
          const SkeletonBox(width: 38, height: 10),
        ],
      ),
    );
  }
}

Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Lanjutkan',
  String cancelLabel = 'Batal',
  bool destructive = false,
}) async {
  final p = context.palette;
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(cancelLabel),
        ),
        FilledButton(
          style: destructive
              ? FilledButton.styleFrom(
                  backgroundColor: p.statusError,
                  foregroundColor: Colors.white,
                )
              : null,
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}

Future<void> showReasonDialog({
  required BuildContext context,
  required String title,
  required String description,
  required Future<void> Function(String reason) onConfirm,
  String confirmLabel = 'Konfirmasi',
  bool destructive = true,
}) async {
  final controller = TextEditingController();
  final formKey = GlobalKey<FormState>();
  var busy = false;
  final p = context.palette;

  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(title),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(description),
              const SizedBox(height: AppTokens.space16),
              TextFormField(
                controller: controller,
                minLines: 3,
                maxLines: 5,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Alasan',
                  hintText: 'Jelaskan alasan tindakan ini',
                ),
                validator: (value) {
                  final text = value?.trim() ?? '';
                  if (text.length < 5) return 'Alasan minimal 5 karakter';
                  return null;
                },
              ),
              const SizedBox(height: AppTokens.space8),
              Text(
                'Tindakan ini dicatat di audit log.',
                style: Theme.of(context).textTheme.labelSmall,
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
            style: destructive
                ? FilledButton.styleFrom(
                    backgroundColor: p.statusError,
                    foregroundColor: Colors.white,
                  )
                : null,
            onPressed: busy
                ? null
                : () async {
                    if (!(formKey.currentState?.validate() ?? false)) return;
                    setState(() => busy = true);
                    try {
                      await onConfirm(controller.text.trim());
                      if (dialogContext.mounted) {
                        Navigator.of(dialogContext).pop();
                      }
                    } catch (error) {
                      if (dialogContext.mounted) {
                        showAppSnack(
                          dialogContext,
                          mapError(error).message,
                          error: true,
                        );
                      }
                    } finally {
                      if (dialogContext.mounted) setState(() => busy = false);
                    }
                  },
            child: busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(confirmLabel),
          ),
        ],
      ),
    ),
  );
  controller.dispose();
}

void showAppSnack(BuildContext context, String message, {bool error = false}) {
  if (!context.mounted) return;
  final p = context.palette;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              error ? Icons.error_outline_rounded : Icons.check_circle_outline,
              color: error ? p.statusError : p.statusSuccess,
              size: 20,
            ),
            const SizedBox(width: AppTokens.space12),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
}

Future<void> copySafely(
  BuildContext context,
  String value,
  String label,
) async {
  await Clipboard.setData(ClipboardData(text: value));
  if (context.mounted) showAppSnack(context, '$label disalin');
}

class AppScaffold extends StatelessWidget {
  const AppScaffold({
    super.key,
    required this.title,
    required this.child,
    this.actions,
    this.leading,
    this.bottomNavigationBar,
    this.floatingActionButton,
    this.resizeToAvoidBottomInset = true,
  });

  final String title;
  final Widget child;
  final List<Widget>? actions;
  final Widget? leading;
  final Widget? bottomNavigationBar;
  final Widget? floatingActionButton;
  final bool resizeToAvoidBottomInset;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title), leading: leading, actions: actions),
      body: SafeArea(child: child),
      bottomNavigationBar: bottomNavigationBar,
      floatingActionButton: floatingActionButton,
      resizeToAvoidBottomInset: resizeToAvoidBottomInset,
    );
  }
}

class ImageBytesView extends StatelessWidget {
  const ImageBytesView(this.bytes, {super.key, this.fit = BoxFit.cover});

  final Uint8List bytes;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    return Image.memory(
      bytes,
      fit: fit,
      gaplessPlayback: true,
      errorBuilder: (_, __, ___) => Container(
        color: context.palette.bgRaised,
        alignment: Alignment.center,
        child: Icon(
          Icons.broken_image_outlined,
          color: context.palette.textSecondary,
        ),
      ),
    );
  }
}
