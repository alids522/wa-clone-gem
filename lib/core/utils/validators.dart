/// Pure validators shared by forms and tests.
abstract final class Validators {
  static final RegExp _username = RegExp(r'^[a-z][a-z0-9_]{2,23}$');
  static final RegExp _email = RegExp(
    r"^[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?)+$",
  );

  static const Set<String> reservedUsernames = {
    'admin',
    'administrator',
    'root',
    'support',
    'system',
    'adoetz',
    'adoetzchat',
    'help',
    'security',
    'moderator',
    'official',
  };

  static String normalizeUsername(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '');

  static String normalizeEmail(String value) => value.trim().toLowerCase();

  static String? username(String? raw) {
    if (raw == null || raw.trim().isEmpty) return 'Username wajib diisi';
    final value = normalizeUsername(raw);
    if (value.length < 3) return 'Username minimal 3 karakter';
    if (value.length > 24) return 'Username maksimal 24 karakter';
    if (!_username.hasMatch(value)) {
      return 'Gunakan huruf kecil, angka, dan underscore; diawali huruf';
    }
    if (reservedUsernames.contains(value)) return 'Username ini tidak tersedia';
    return null;
  }

  static String? email(String? raw) {
    if (raw == null || raw.trim().isEmpty) return 'Email wajib diisi';
    final value = normalizeEmail(raw);
    if (value.length > 254) return 'Email terlalu panjang';
    if (!_email.hasMatch(value)) return 'Format email tidak valid';
    return null;
  }

  /// Password policy: length first, no arbitrary composition rules.
  static String? password(String? raw, {bool enforceStrength = true}) {
    if (raw == null || raw.isEmpty) return 'Password wajib diisi';
    if (raw.length < 12) return 'Password minimal 12 karakter';
    if (raw.length > 256) return 'Password maksimal 256 karakter';
    if (enforceStrength && raw.trim().toLowerCase() == 'password1234') {
      return 'Password terlalu mudah ditebak';
    }
    return null;
  }

  /// 0..4 educational strength score.
  static int passwordStrength(String value) {
    if (value.isEmpty) return 0;
    var score = 0;
    if (value.length >= 12) score++;
    if (value.length >= 16) score++;
    if (RegExp(r'[A-Z]').hasMatch(value) && RegExp(r'[a-z]').hasMatch(value)) {
      score++;
    }
    if (RegExp(r'[0-9]').hasMatch(value)) score++;
    if (RegExp(r'[^A-Za-z0-9]').hasMatch(value)) score++;
    if (RegExp(r'(.)\1{2,}').hasMatch(value)) score--;
    return score.clamp(0, 4);
  }

  static String? inviteCode(String? raw) {
    final value = raw?.trim() ?? '';
    if (value.isEmpty) return 'Kode undangan wajib diisi';
    if (value.length < 8) return 'Kode undangan tidak valid';
    if (value.length > 128) return 'Kode undangan tidak valid';
    return null;
  }

  static String? displayName(String? raw) {
    final value = raw?.trim() ?? '';
    if (value.isEmpty) return 'Nama tampilan wajib diisi';
    if (value.length > 48) return 'Nama tampilan maksimal 48 karakter';
    return null;
  }

  static String? bio(String? raw) {
    if ((raw?.trim().length ?? 0) > 160) return 'Bio maksimal 160 karakter';
    return null;
  }
}
