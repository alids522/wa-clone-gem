import 'package:intl/intl.dart';

abstract final class Formatters {
  static final DateFormat _time = DateFormat.Hm('id_ID');
  static final DateFormat _day = DateFormat('d MMM', 'id_ID');
  static final DateFormat _dayYear = DateFormat('d MMM y', 'id_ID');
  static final DateFormat _full = DateFormat('d MMM y, Hm', 'id_ID');

  static String clock(DateTime value) => _time.format(value.toLocal());

  static String chatTimestamp(DateTime value) {
    final now = DateTime.now();
    final local = value.toLocal();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(local.year, local.month, local.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return _time.format(local);
    if (diff == 1) return 'Kemarin';
    if (diff < 7) {
      const names = ['Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab', 'Min'];
      return names[local.weekday - 1];
    }
    if (local.year == now.year) return _day.format(local);
    return _dayYear.format(local);
  }

  static String daySeparator(DateTime value) {
    final now = DateTime.now();
    final local = value.toLocal();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(local.year, local.month, local.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return 'Hari ini';
    if (diff == 1) return 'Kemarin';
    if (diff < 7) {
      const names = [
        'Senin',
        'Selasa',
        'Rabu',
        'Kamis',
        'Jumat',
        'Sabtu',
        'Minggu',
      ];
      return names[local.weekday - 1];
    }
    return _dayYear.format(local);
  }

  static String full(DateTime value) => _full.format(value.toLocal());

  static String messagePreview(String value, {int max = 60}) {
    final single = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (single.length <= max) return single;
    return '${single.substring(0, max)}…';
  }

  static String duration(Duration value) {
    final minutes = value.inMinutes;
    final seconds = value.inSeconds % 60;
    if (value.inHours > 0) {
      return '${value.inHours}:${(minutes % 60).toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  static String durationLong(Duration value) {
    if (value.inSeconds < 1) return '0 dtk';
    final parts = <String>[];
    if (value.inHours > 0) parts.add('${value.inHours} jam');
    if (value.inMinutes % 60 > 0) parts.add('${value.inMinutes % 60} mnt');
    if (value.inSeconds % 60 > 0 && value.inMinutes == 0) {
      parts.add('${value.inSeconds % 60} dtk');
    }
    return parts.join(' ');
  }

  static String relative(DateTime value) {
    final diff = DateTime.now().difference(value.toLocal());
    if (diff.inSeconds < 45) return 'baru saja';
    if (diff.inMinutes < 60) return '${diff.inMinutes} menit lalu';
    if (diff.inHours < 24) return '${diff.inHours} jam lalu';
    if (diff.inDays < 7) return '${diff.inDays} hari lalu';
    return _dayYear.format(value.toLocal());
  }

  static String bytes(int value) {
    if (value < 1024) return '$value B';
    if (value < 1024 * 1024) return '${(value / 1024).toStringAsFixed(1)} KB';
    if (value < 1024 * 1024 * 1024) {
      return '${(value / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(value / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  static String callOutcome({
    required String direction,
    required String status,
    required Duration duration,
  }) {
    if (status == 'missed' || status == 'declined' || status == 'no_answer') {
      return direction == 'outgoing'
          ? 'Tidak dijawab'
          : 'Panggilan tak terjawab';
    }
    if (status == 'failed') return 'Panggilan gagal';
    if (duration.inSeconds > 0) return durationLong(duration);
    return direction == 'outgoing' ? 'Keluar' : 'Masuk';
  }
}
