import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme/app_tokens.dart';
import '../../core/ui/app_widgets.dart';
import '../../core/utils/app_error.dart';

class DeviceConflictScreen extends ConsumerStatefulWidget {
  const DeviceConflictScreen({super.key});

  @override
  ConsumerState<DeviceConflictScreen> createState() =>
      _DeviceConflictScreenState();
}

class _DeviceConflictScreenState extends ConsumerState<DeviceConflictScreen> {
  bool _busy = false;

  Future<void> _replace() async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Gunakan perangkat ini?',
      message:
          'Perangkat lain akan dikeluarkan dan sesi enkripsinya dihentikan. '
          'Pesan lama di perangkat itu tidak dapat dibuka lagi.',
      confirmLabel: 'Gunakan di sini',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(authControllerProvider.notifier).replaceDevice();
    } catch (error) {
      if (!mounted) return;
      showAppSnack(context, mapError(error).message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signOut() async {
    setState(() => _busy = true);
    await ref.read(authControllerProvider.notifier).signOut();
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppTokens.maxContentWidth,
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppTokens.space24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.phonelink_lock_rounded, size: 56),
                  const SizedBox(height: AppTokens.space24),
                  Text(
                    'Akun ini aktif di perangkat lain',
                    style: text.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppTokens.space12),
                  Text(
                    'Adoetz Chat hanya mengizinkan satu perangkat aktif per akun '
                    'agar kunci enkripsi tetap aman. Gunakan perangkat ini untuk '
                    'memindahkan sesi, atau keluar.',
                    style: text.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppTokens.space32),
                  FilledButton(
                    onPressed: _busy ? null : _replace,
                    child: _busy
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Gunakan perangkat ini'),
                  ),
                  const SizedBox(height: AppTokens.space12),
                  OutlinedButton(
                    onPressed: _busy ? null : _signOut,
                    child: const Text('Keluar'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
