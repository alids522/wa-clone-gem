import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_tokens.dart';

/// Builds the two product themes: Midnight Blue (dark) and Ice Blue (light).
abstract final class AppTheme {
  static ThemeData get dark => _build(AppPalette.dark);
  static ThemeData get light => _build(AppPalette.light);

  static ThemeData _build(AppPalette p) {
    final scheme = ColorScheme(
      brightness: p.brightness,
      primary: p.brandPrimary,
      onPrimary: Colors.white,
      primaryContainer: p.brandSoft.withValues(alpha: p.isDark ? 0.22 : 0.14),
      onPrimaryContainer: p.isDark
          ? const Color(0xFFDBEAFE)
          : const Color(0xFF172554),
      secondary: p.brandSoft,
      onSecondary: p.isDark ? const Color(0xFF04101F) : Colors.white,
      error: p.statusError,
      onError: Colors.white,
      surface: p.bgSurface,
      onSurface: p.textPrimary,
      surfaceContainerHighest: p.bgRaised,
      onSurfaceVariant: p.textSecondary,
      outline: p.border,
      outlineVariant: p.border,
      shadow: Colors.black,
      scrim: p.overlay,
      inverseSurface: p.textPrimary,
      onInverseSurface: p.bgPrimary,
      inversePrimary: p.brandSoft,
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: p.brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: p.bgPrimary,
      canvasColor: p.bgPrimary,
      fontFamily: null,
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.standard,
    );

    final text = base.textTheme
        .apply(bodyColor: p.textPrimary, displayColor: p.textPrimary)
        .copyWith(
          displaySmall: TextStyle(
            fontSize: 28,
            height: 34 / 28,
            fontWeight: FontWeight.w600,
            color: p.textPrimary,
          ),
          headlineSmall: TextStyle(
            fontSize: 22,
            height: 28 / 22,
            fontWeight: FontWeight.w600,
            color: p.textPrimary,
          ),
          titleMedium: TextStyle(
            fontSize: 18,
            height: 24 / 18,
            fontWeight: FontWeight.w500,
            color: p.textPrimary,
          ),
          bodyLarge: TextStyle(
            fontSize: 16,
            height: 22 / 16,
            color: p.textPrimary,
          ),
          bodyMedium: TextStyle(
            fontSize: 15,
            height: 22 / 15,
            color: p.textPrimary,
          ),
          bodySmall: TextStyle(
            fontSize: 13,
            height: 18 / 13,
            color: p.textSecondary,
          ),
          labelSmall: TextStyle(
            fontSize: 12,
            height: 18 / 12,
            color: p.textSecondary,
            letterSpacing: 0.2,
          ),
        );

    return base.copyWith(
      textTheme: text,
      extensions: [p],
      appBarTheme: AppBarTheme(
        backgroundColor: p.bgPrimary,
        surfaceTintColor: Colors.transparent,
        foregroundColor: p.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: text.headlineSmall,
        systemOverlayStyle: p.isDark
            ? SystemUiOverlayStyle.light.copyWith(
                statusBarColor: Colors.transparent,
                systemNavigationBarColor: p.bgPrimary,
                systemNavigationBarIconBrightness: Brightness.light,
              )
            : SystemUiOverlayStyle.dark.copyWith(
                statusBarColor: Colors.transparent,
                systemNavigationBarColor: p.bgPrimary,
                systemNavigationBarIconBrightness: Brightness.dark,
              ),
      ),
      iconTheme: IconThemeData(color: p.textSecondary, size: 22),
      dividerTheme: DividerThemeData(color: p.border, thickness: 1, space: 1),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.bgRaised,
        hintStyle: text.bodyMedium?.copyWith(color: p.textSecondary),
        labelStyle: text.bodySmall,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppTokens.space16,
          vertical: AppTokens.space16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusInput),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusInput),
          borderSide: BorderSide(color: p.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusInput),
          borderSide: BorderSide(color: p.focusRing, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusInput),
          borderSide: BorderSide(color: p.statusError),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusInput),
          borderSide: BorderSide(color: p.statusError, width: 2),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(AppTokens.minTouchTarget),
          backgroundColor: p.brandPrimary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: p.bgRaised,
          disabledForegroundColor: p.textSecondary,
          textStyle: text.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTokens.radiusInput),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(AppTokens.minTouchTarget),
          foregroundColor: p.brandSoft,
          side: BorderSide(color: p.border),
          textStyle: text.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTokens.radiusInput),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(
            AppTokens.minTouchTarget,
            AppTokens.minTouchTarget,
          ),
          foregroundColor: p.brandSoft,
          textStyle: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: p.brandSoft,
        selectionColor: p.brandPrimary.withValues(alpha: 0.35),
        selectionHandleColor: p.brandPrimary,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: p.bgSurface,
        indicatorColor: p.brandPrimary.withValues(
          alpha: p.isDark ? 0.22 : 0.12,
        ),
        height: 68,
        elevation: 0,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => text.labelSmall?.copyWith(
            color: states.contains(WidgetState.selected)
                ? p.brandSoft
                : p.textSecondary,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w600
                : FontWeight.w500,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? p.brandSoft
                : p.textSecondary,
            size: 24,
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: p.isDark ? p.bgRaised : const Color(0xFF0F172A),
        contentTextStyle: text.bodyMedium?.copyWith(color: Colors.white),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusCard),
        ),
        insetPadding: const EdgeInsets.all(AppTokens.space16),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: p.bgSurface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusDialog),
        ),
        titleTextStyle: text.titleMedium,
        contentTextStyle: text.bodyMedium,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: p.bgSurface,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: p.bgSurface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppTokens.radiusDialog),
          ),
        ),
      ),
      cardTheme: CardThemeData(
        color: p.bgSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusCard),
          side: BorderSide(color: p.border),
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: p.textSecondary,
        textColor: p.textPrimary,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppTokens.space16,
          vertical: 4,
        ),
        minVerticalPadding: 10,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusCard),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) =>
              s.contains(WidgetState.selected) ? Colors.white : p.textSecondary,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? p.brandPrimary : p.bgRaised,
        ),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? p.brandPrimary
              : p.textSecondary,
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? p.brandPrimary
              : Colors.transparent,
        ),
        side: BorderSide(color: p.border, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: p.brandSoft,
        linearTrackColor: p.bgRaised,
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: p.bgRaised,
        selectedColor: p.brandPrimary.withValues(alpha: 0.2),
        labelStyle: text.labelSmall?.copyWith(color: p.textPrimary),
        side: BorderSide(color: p.border),
        shape: const StadiumBorder(),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: p.isDark ? p.bgRaised : const Color(0xFF0F172A),
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: text.bodySmall?.copyWith(color: Colors.white),
      ),
    );
  }
}
