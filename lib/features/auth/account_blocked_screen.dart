import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme/app_tokens.dart';
import '../../core/models/profile.dart';
import '../../core/ui/app_widgets.dart';
import '../../core/utils/app_error.dart';

class AccountBlockedScreen extends ConsumerStatefulWidget {
  const AccountBlockedScreen({super.key});

  @override
  ConsumerState<AccountBlockedScreen> createState() =>
      _AccountBlockedScreenState();
}

class _AccountBlockedScreenState extends ConsumerState<AccountBlockedScreen> {
  bool _busy = false;

  Future<void> _signOut() async {
    setState(() => _busy = true);
    await ref.read(authControllerProvider.notifier).signOut();
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(authControllerProvider).profile;
    final text = Theme.of(context).textTheme;
    final p = context.palette;
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
                  Icon(Icons.gpp_maybe_rounded, size: 56, color: p.statusError),
                  const SizedBox(height: AppTokens.space24),
                  Text(
                    'Akun ditangguhkan',
                    style: text.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppTokens.space12),
                  Text(
                    profile == null
                        ? 'Akun ini tidak dapat digunakan saat ini.'
                        : '@${profile.username} tidak dapat digunakan saat ini. '
                              'Hubungi admin Adoetz Chat untuk informasi lebih lanjut.',
                    style: text.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppTokens.space32),
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

class PendingSetupScreen extends ConsumerStatefulWidget {
  const PendingSetupScreen({super.key});

  @override
  ConsumerState<PendingSetupScreen> createState() => _PendingSetupScreenState();
}

class _PendingSetupScreenState extends ConsumerState<PendingSetupScreen> {
  bool _busy = false;

  Future<void> _retry() async {
    setState(() => _busy = true);
    try {
      await ref.read(authControllerProvider.notifier).retry();
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
                  const Icon(Icons.person_off_outlined, size: 56),
                  const SizedBox(height: AppTokens.space24),
                  Text(
                    'Profil belum tersedia',
                    style: text.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppTokens.space12),
                  Text(
                    'Akun ini belum memiliki profil Adoetz Chat. Minta admin '
                    'melengkapi profil, lalu coba lagi.',
                    style: text.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppTokens.space32),
                  FilledButton(
                    onPressed: _busy ? null : _retry,
                    child: const Text('Coba lagi'),
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

/// Kept for callers that need the status description without the widget.
String accountStatusLabel(AccountStatus status) {
  switch (status) {
    case AccountStatus.active:
      return 'Aktif';
    case AccountStatus.suspended:
      return 'Ditangguhkan';
    case AccountStatus.deleted:
      return 'Dihapus';
  }
}
