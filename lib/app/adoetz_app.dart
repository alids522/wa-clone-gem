import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/ui/app_widgets.dart';
import '../features/calls/incoming_call_overlay.dart';
import '../features/settings/app_lock_screen.dart';
import 'providers.dart';
import 'root_gate.dart';
import 'theme/app_theme.dart';

class AdoetzApp extends ConsumerWidget {
  const AdoetzApp({super.key});

  /// Lets services-free UI layers (incoming call overlay, notifications) push
  /// routes without holding a BuildContext.
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    return MaterialApp(
      title: 'Adoetz Chat',
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      locale: const Locale('id'),
      supportedLocales: const [Locale('id'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      scrollBehavior: const _AppScrollBehavior(),
      home: const RootGate(),
      builder: (context, child) {
        final media = MediaQuery.of(context);
        // Keep text legible but never let a huge system font break layouts.
        final scale = media.textScaler.clamp(
          minScaleFactor: 0.9,
          maxScaleFactor: 1.4,
        );
        return MediaQuery(
          data: media.copyWith(textScaler: scale),
          child: AppLockGate(
            child: IncomingCallOverlay(child: child ?? const SizedBox.shrink()),
          ),
        );
      },
    );
  }
}

class _AppScrollBehavior extends MaterialScrollBehavior {
  const _AppScrollBehavior();

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return child;
  }
}

/// A guarded route that refuses to open screens while signed out.
class AuthGate extends ConsumerWidget {
  const AuthGate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ready = ref.watch(authControllerProvider).isReady;
    if (!ready) {
      return const Scaffold(body: LoadingPane(label: 'Menyiapkan…'));
    }
    return child;
  }
}
