import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/ui/app_widgets.dart';
import '../features/auth/account_blocked_screen.dart';
import '../features/auth/device_conflict_screen.dart';
import '../features/auth/welcome_screen.dart';
import '../features/home/home_shell.dart';
import '../features/splash/splash_screen.dart';
import 'auth_controller.dart';
import 'providers.dart';

/// Single source of truth for which top-level surface is visible.
class RootGate extends ConsumerWidget {
  const RootGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);

    return switch (auth.stage) {
      AuthStage.booting => const SplashScreen(),
      AuthStage.signedOut => const WelcomeScreen(),
      AuthStage.ready => const HomeShell(),
      AuthStage.suspended => const AccountBlockedScreen(),
      AuthStage.deviceConflict => const DeviceConflictScreen(),
      AuthStage.pendingSetup => const PendingSetupScreen(),
      AuthStage.failure => Scaffold(
        body: SafeArea(
          child: ErrorPane(
            title: 'Tidak dapat memuat akun',
            message:
                auth.error?.message ??
                'Periksa koneksi internet lalu coba lagi.',
            code: auth.error?.code,
            onRetry: () => ref.read(authControllerProvider.notifier).retry(),
          ),
        ),
      ),
    };
  }
}
