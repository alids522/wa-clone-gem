import 'package:flutter/material.dart';

import '../../app/theme/app_tokens.dart';
import '../../core/ui/app_widgets.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const AdoetzLogo(size: 88),
            const SizedBox(height: AppTokens.space24),
            Text(
              'Adoetz Chat',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: AppTokens.space8),
            Text(
              'Pesan pribadi, terenkripsi.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: p.textSecondary),
            ),
            const SizedBox(height: AppTokens.space32),
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2.4),
            ),
          ],
        ),
      ),
    );
  }
}
