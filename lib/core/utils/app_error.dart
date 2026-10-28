import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Stable, human-facing application failure. Codes are safe to log.
class AppError implements Exception {
  const AppError(this.code, this.message, {this.retryable = false, this.cause});

  final String code;
  final String message;
  final bool retryable;
  final Object? cause;

  String get diagnosticCode {
    final tail = code.length > 28 ? code.substring(0, 28) : code;
    return 'AC-$tail';
  }

  @override
  String toString() => 'AppError($code): $message';
}

/// Maps transport/SDK failures to the PRD's generic, actionable copy.
AppError mapError(Object error) {
  if (error is AppError) return error;

  if (error is AuthException) {
    final message = error.message.toLowerCase();
    if (message.contains('invalid') || message.contains('credentials')) {
      return AppError(
        'AUTH_INVALID',
        'Username/email atau password tidak sesuai.',
        cause: error,
      );
    }
    if (error.statusCode == '429' || message.contains('rate')) {
      return AppError(
        'AUTH_RATE_LIMIT',
        'Terlalu banyak percobaan. Coba lagi beberapa saat.',
        retryable: true,
        cause: error,
      );
    }
    return AppError(
      'AUTH_FAILED',
      'Autentikasi gagal. Silakan coba lagi.',
      retryable: true,
      cause: error,
    );
  }

  if (error is PostgrestException) {
    final code = error.code ?? 'DB';
    if (code == '23505') {
      if (error.message.contains('username')) {
        return AppError(
          'USERNAME_TAKEN',
          'Username sudah digunakan. Pilih username lain.',
          cause: error,
        );
      }
      return AppError(
        'CONFLICT',
        'Data sudah ada. Muat ulang lalu coba lagi.',
        cause: error,
      );
    }
    if (code == '42501' || code == 'PGRST301') {
      return AppError(
        'FORBIDDEN',
        'Anda tidak memiliki akses untuk tindakan ini.',
        cause: error,
      );
    }
    if (error.message.contains('DEVICE_EXISTS')) {
      return AppError(
        'DEVICE_EXISTS',
        'Akun ini sudah aktif di perangkat lain.',
        cause: error,
      );
    }
    if (error.message.contains('SUSPENDED')) {
      return AppError(
        'SUSPENDED',
        'Akun ini sedang dinonaktifkan.',
        cause: error,
      );
    }
    if (error.message.contains('BLOCKED')) {
      return AppError(
        'BLOCKED',
        'Pesan tidak dapat dikirim karena pengguna memblokir kontak ini.',
        cause: error,
      );
    }
    if (error.message.contains('RATE_LIMITED')) {
      return AppError(
        'RATE_LIMIT',
        'Terlalu banyak permintaan. Coba lagi beberapa saat.',
        retryable: true,
        cause: error,
      );
    }
    if (error.message.contains('BUSY')) {
      return AppError(
        'CALL_BUSY',
        'Sedang ada panggilan lain. Coba lagi nanti.',
        cause: error,
      );
    }
    if (error.message.contains('PEER_UNAVAILABLE')) {
      return AppError(
        'PEER_UNAVAILABLE',
        'Kontak tidak dapat dihubungi saat ini.',
        cause: error,
      );
    }
    if (error.message.contains('CALL_STATE_INVALID')) {
      return AppError('CALL_STATE', 'Panggilan sudah berakhir.', cause: error);
    }
    if (code.startsWith('08') || code == '57014') {
      return AppError(
        'DB_UNAVAILABLE',
        'Layanan sedang sibuk. Coba lagi.',
        retryable: true,
        cause: error,
      );
    }
    return AppError(
      'DB_ERROR',
      'Permintaan tidak dapat diproses. Coba lagi.',
      retryable: true,
      cause: error,
    );
  }

  if (error is FunctionException) {
    final details = error.details;
    if (details is Map && details['code'] is String) {
      final code = details['code'] as String;
      final message = details['message'];
      return AppError(
        code,
        message is String && message.isNotEmpty
            ? message
            : 'Permintaan tidak dapat diproses.',
        retryable: details['retryable'] == true,
        cause: error,
      );
    }
    return AppError(
      'FUNCTION_FAILED',
      'Permintaan tidak dapat diproses. Coba lagi.',
      retryable: true,
      cause: error,
    );
  }

  if (error is StorageException) {
    return AppError(
      'STORAGE_FAILED',
      'File belum dapat diproses. Coba lagi.',
      retryable: true,
      cause: error,
    );
  }

  if (error is TimeoutException) {
    return AppError(
      'TIMEOUT',
      'Koneksi terlalu lambat. Coba lagi.',
      retryable: true,
      cause: error,
    );
  }

  if (error is SocketException) {
    return const AppError(
      'OFFLINE',
      'Tidak ada koneksi. Pesan akan dikirim saat online.',
      retryable: true,
    );
  }

  final text = error.toString().toLowerCase();
  if (text.contains('socket') ||
      text.contains('network') ||
      text.contains('connection') ||
      text.contains('failed host lookup')) {
    return const AppError(
      'OFFLINE',
      'Tidak ada koneksi. Pesan akan dikirim saat online.',
      retryable: true,
    );
  }

  return AppError(
    'UNEXPECTED',
    'Terjadi kesalahan tak terduga. Coba lagi.',
    retryable: true,
    cause: error,
  );
}
