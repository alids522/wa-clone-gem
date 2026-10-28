import 'package:flutter/material.dart';

/// Design tokens for Adoetz Chat (PRD chapter 6).
///
/// The palette is exposed as a [ThemeExtension] so widgets can read semantic
/// colours that Material's [ColorScheme] does not model (bubbles, status, …).
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.brightness,
    required this.bgPrimary,
    required this.bgSurface,
    required this.bgRaised,
    required this.brandPrimary,
    required this.brandSoft,
    required this.textPrimary,
    required this.textSecondary,
    required this.border,
    required this.bubbleIncoming,
    required this.bubbleOutgoing,
    required this.onBubbleOutgoing,
    required this.statusError,
    required this.statusSuccess,
    required this.statusWarning,
    required this.focusRing,
    required this.skeleton,
    required this.overlay,
  });

  final Brightness brightness;
  final Color bgPrimary;
  final Color bgSurface;
  final Color bgRaised;
  final Color brandPrimary;
  final Color brandSoft;
  final Color textPrimary;
  final Color textSecondary;
  final Color border;
  final Color bubbleIncoming;
  final Color bubbleOutgoing;
  final Color onBubbleOutgoing;
  final Color statusError;
  final Color statusSuccess;
  final Color statusWarning;
  final Color focusRing;
  final Color skeleton;
  final Color overlay;

  static const dark = AppPalette(
    brightness: Brightness.dark,
    bgPrimary: Color(0xFF080D18),
    bgSurface: Color(0xFF111B2C),
    bgRaised: Color(0xFF172337),
    brandPrimary: Color(0xFF2563EB),
    brandSoft: Color(0xFF60A5FA),
    textPrimary: Color(0xFFF8FAFC),
    textSecondary: Color(0xFF94A3B8),
    border: Color(0xFF26354A),
    bubbleIncoming: Color(0xFF172337),
    bubbleOutgoing: Color(0xFF1D4ED8),
    onBubbleOutgoing: Color(0xFFFFFFFF),
    statusError: Color(0xFFF87171),
    statusSuccess: Color(0xFF34D399),
    statusWarning: Color(0xFFFBBF24),
    focusRing: Color(0xFF93C5FD),
    skeleton: Color(0xFF1E2C42),
    overlay: Color(0xCC000000),
  );

  static const light = AppPalette(
    brightness: Brightness.light,
    bgPrimary: Color(0xFFF6F9FF),
    bgSurface: Color(0xFFFFFFFF),
    bgRaised: Color(0xFFE9F0FA),
    brandPrimary: Color(0xFF2563EB),
    brandSoft: Color(0xFF1D4ED8),
    textPrimary: Color(0xFF0F172A),
    textSecondary: Color(0xFF64748B),
    border: Color(0xFFDCE5F2),
    bubbleIncoming: Color(0xFFE8EFFA),
    bubbleOutgoing: Color(0xFF2563EB),
    onBubbleOutgoing: Color(0xFFFFFFFF),
    statusError: Color(0xFFB91C1C),
    statusSuccess: Color(0xFF047857),
    statusWarning: Color(0xFFB45309),
    focusRing: Color(0xFF1D4ED8),
    skeleton: Color(0xFFE2E8F0),
    overlay: Color(0xCC000000),
  );

  bool get isDark => brightness == Brightness.dark;

  @override
  AppPalette copyWith({
    Brightness? brightness,
    Color? bgPrimary,
    Color? bgSurface,
    Color? bgRaised,
    Color? brandPrimary,
    Color? brandSoft,
    Color? textPrimary,
    Color? textSecondary,
    Color? border,
    Color? bubbleIncoming,
    Color? bubbleOutgoing,
    Color? onBubbleOutgoing,
    Color? statusError,
    Color? statusSuccess,
    Color? statusWarning,
    Color? focusRing,
    Color? skeleton,
    Color? overlay,
  }) {
    return AppPalette(
      brightness: brightness ?? this.brightness,
      bgPrimary: bgPrimary ?? this.bgPrimary,
      bgSurface: bgSurface ?? this.bgSurface,
      bgRaised: bgRaised ?? this.bgRaised,
      brandPrimary: brandPrimary ?? this.brandPrimary,
      brandSoft: brandSoft ?? this.brandSoft,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      border: border ?? this.border,
      bubbleIncoming: bubbleIncoming ?? this.bubbleIncoming,
      bubbleOutgoing: bubbleOutgoing ?? this.bubbleOutgoing,
      onBubbleOutgoing: onBubbleOutgoing ?? this.onBubbleOutgoing,
      statusError: statusError ?? this.statusError,
      statusSuccess: statusSuccess ?? this.statusSuccess,
      statusWarning: statusWarning ?? this.statusWarning,
      focusRing: focusRing ?? this.focusRing,
      skeleton: skeleton ?? this.skeleton,
      overlay: overlay ?? this.overlay,
    );
  }

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppPalette(
      brightness: t < 0.5 ? brightness : other.brightness,
      bgPrimary: mix(bgPrimary, other.bgPrimary),
      bgSurface: mix(bgSurface, other.bgSurface),
      bgRaised: mix(bgRaised, other.bgRaised),
      brandPrimary: mix(brandPrimary, other.brandPrimary),
      brandSoft: mix(brandSoft, other.brandSoft),
      textPrimary: mix(textPrimary, other.textPrimary),
      textSecondary: mix(textSecondary, other.textSecondary),
      border: mix(border, other.border),
      bubbleIncoming: mix(bubbleIncoming, other.bubbleIncoming),
      bubbleOutgoing: mix(bubbleOutgoing, other.bubbleOutgoing),
      onBubbleOutgoing: mix(onBubbleOutgoing, other.onBubbleOutgoing),
      statusError: mix(statusError, other.statusError),
      statusSuccess: mix(statusSuccess, other.statusSuccess),
      statusWarning: mix(statusWarning, other.statusWarning),
      focusRing: mix(focusRing, other.focusRing),
      skeleton: mix(skeleton, other.skeleton),
      overlay: mix(overlay, other.overlay),
    );
  }
}

/// Spacing / radius / motion tokens. All values are logical pixels.
abstract final class AppTokens {
  static const double space4 = 4;
  static const double space8 = 8;
  static const double space12 = 12;
  static const double space16 = 16;
  static const double space20 = 20;
  static const double space24 = 24;
  static const double space32 = 32;

  static const double radiusInput = 8;
  static const double radiusCard = 12;
  static const double radiusDialog = 16;
  static const double radiusBubble = 20;
  static const double radiusPill = 999;

  static const Duration fast = Duration(milliseconds: 150);
  static const Duration normal = Duration(milliseconds: 220);

  static const double minTouchTarget = 48;
  static const double maxContentWidth = 720;
}

extension AppPaletteContext on BuildContext {
  AppPalette get palette => Theme.of(this).extension<AppPalette>()!;
}
