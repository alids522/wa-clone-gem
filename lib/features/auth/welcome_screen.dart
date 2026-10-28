import 'package:flutter/material.dart';

import '../../app/theme/app_tokens.dart';
import '../../core/ui/app_widgets.dart';
import 'sign_in_screen.dart';
import 'sign_up_screen.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
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
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: AppTokens.space24),
                  const AdoetzLogo(size: 76),
                  const SizedBox(height: AppTokens.space24),
                  Text('Adoetz Chat', style: text.displaySmall),
                  const SizedBox(height: AppTokens.space8),
                  Text(
                    'Percakapan pribadi dengan enkripsi end-to-end. '
                    'Undangan hanya dari orang yang kamu percaya.',
                    style: text.bodyMedium?.copyWith(color: p.textSecondary),
                  ),
                  const SizedBox(height: AppTokens.space32),
                  _Feature(
                    icon: Icons.lock_outline_rounded,
                    title: 'Terenkripsi end-to-end',
                    message:
                        'Kunci percakapan tidak pernah meninggalkan perangkat.',
                  ),
                  const SizedBox(height: AppTokens.space16),
                  _Feature(
                    icon: Icons.person_add_alt_1_rounded,
                    title: 'Hanya lewat undangan',
                    message:
                        'Tidak ada pendaftaran terbuka. Setiap akun diajak '
                        'oleh admin atau anggota tepercaya.',
                  ),
                  const SizedBox(height: AppTokens.space16),
                  _Feature(
                    icon: Icons.phonelink_lock_rounded,
                    title: 'Satu perangkat per akun',
                    message:
                        'Sesi aktif dilindungi dan perangkat baru harus '
                        'dikonfirmasi.',
                  ),
                  const SizedBox(height: AppTokens.space32),
                  FilledButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const SignInScreen(),
                      ),
                    ),
                    child: const Text('Masuk'),
                  ),
                  const SizedBox(height: AppTokens.space12),
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const SignUpScreen(),
                      ),
                    ),
                    child: const Text('Saya punya kode undangan'),
                  ),
                  const SizedBox(height: AppTokens.space24),
                  Center(
                    child: Text('Adoetz Chat v1.0', style: text.labelSmall),
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

class _Feature extends StatelessWidget {
  const _Feature({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: p.bgRaised,
            borderRadius: BorderRadius.circular(AppTokens.radiusCard),
            border: Border.all(color: p.border),
          ),
          child: Icon(icon, color: p.brandSoft, size: 22),
        ),
        const SizedBox(width: AppTokens.space16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: text.bodyLarge),
              const SizedBox(height: 2),
              Text(message, style: text.bodySmall),
            ],
          ),
        ),
      ],
    );
  }
}
