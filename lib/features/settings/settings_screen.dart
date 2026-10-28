import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mime/mime.dart';

import '../../app/providers.dart';
import '../../app/theme/app_tokens.dart';
import '../../core/models/profile.dart';
import '../../core/services/profile_repository.dart';
import '../../core/ui/app_widgets.dart';
import '../../core/ui/avatar_view.dart';
import '../../core/utils/app_error.dart';
import '../../core/utils/formatters.dart';
import '../admin/admin_screen.dart';
import 'app_lock_screen.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(currentProfileProvider);
    final prefs = ref.watch(preferencesControllerProvider);
    final themeMode = ref.watch(themeModeProvider);
    final p = context.palette;

    return Scaffold(
      appBar: AppBar(title: const Text('Pengaturan')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: AppTokens.space32),
          children: [
            if (profile != null) _ProfileHeader(profile: profile),
            _Group(
              title: 'Akun',
              children: [
                if (profile != null)
                  AppSettingRow(
                    icon: Icons.person_outline_rounded,
                    title: 'Edit profil',
                    subtitle: 'Nama tampilan, bio, dan keterlihatan',
                    onTap: () => _editProfile(context, ref, profile),
                  ),
                AppSettingRow(
                  icon: Icons.photo_camera_outlined,
                  title: 'Ganti foto profil',
                  onTap: () => _changeAvatar(context, ref),
                ),
                AppSettingRow(
                  icon: Icons.devices_rounded,
                  title: 'Perangkat ini',
                  subtitle: 'Satu perangkat aktif per akun',
                  onTap: () => _showDeviceInfo(context, profile),
                ),
              ],
            ),
            _Group(
              title: 'Tampilan',
              children: [
                AppSettingRow(
                  icon: Icons.dark_mode_outlined,
                  title: 'Tema',
                  subtitle: _themeLabel(themeMode),
                  onTap: () => _chooseTheme(context, ref, themeMode),
                ),
              ],
            ),
            _Group(
              title: 'Privasi',
              children: [
                prefs.when(
                  data: (value) => Column(
                    children: [
                      SwitchListTile(
                        secondary: const Icon(Icons.done_all_rounded),
                        title: const Text('Laporan dibaca'),
                        subtitle: const Text(
                          'Kirim tanda sudah dibaca kepada kontak.',
                        ),
                        value: value.readReceipts,
                        onChanged: (enabled) => ref
                            .read(preferencesControllerProvider.notifier)
                            .setReadReceipts(enabled),
                      ),
                      SwitchListTile(
                        secondary: const Icon(Icons.keyboard_alt_outlined),
                        title: const Text('Indikator sedang mengetik'),
                        subtitle: const Text(
                          'Bagikan status mengetik kepada kontak.',
                        ),
                        value: value.typingIndicators,
                        onChanged: (enabled) => ref
                            .read(preferencesControllerProvider.notifier)
                            .setTypingIndicators(enabled),
                      ),
                      AppSettingRow(
                        icon: Icons.notifications_active_outlined,
                        title: 'Privasi notifikasi',
                        subtitle: _notificationLabel(value.notificationPrivacy),
                        onTap: () =>
                            _chooseNotificationPrivacy(context, ref, value),
                      ),
                    ],
                  ),
                  loading: () => const Padding(
                    padding: EdgeInsets.all(AppTokens.space24),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (error, _) => Padding(
                    padding: const EdgeInsets.all(AppTokens.space16),
                    child: Row(
                      children: [
                        Icon(Icons.error_outline_rounded, color: p.statusError),
                        const SizedBox(width: AppTokens.space8),
                        Expanded(
                          child: Text(
                            mapError(error).message,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                        TextButton(
                          onPressed: () => ref
                              .read(preferencesControllerProvider.notifier)
                              .load(),
                          child: const Text('Coba'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            _Group(
              title: 'Keamanan',
              children: [
                AppSettingRow(
                  icon: Icons.lock_outline_rounded,
                  title: 'Kunci aplikasi',
                  subtitle: 'PIN dan biometrik',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const AppLockSettingsScreen(),
                    ),
                  ),
                ),
                AppSettingRow(
                  icon: Icons.verified_user_outlined,
                  title: 'Enkripsi end-to-end',
                  subtitle: 'Aktif untuk semua percakapan 1:1',
                  onTap: () => _showEncryptionInfo(context),
                ),
              ],
            ),
            if (profile?.isAdmin ?? false)
              _Group(
                title: 'Administrasi',
                children: [
                  AppSettingRow(
                    icon: Icons.admin_panel_settings_outlined,
                    title: 'Panel admin',
                    subtitle: 'Pengguna, undangan, dan audit log',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const AdminScreen(),
                      ),
                    ),
                  ),
                ],
              ),
            _Group(
              title: 'Tentang',
              children: [
                AppSettingRow(
                  icon: Icons.info_outline_rounded,
                  title: 'Adoetz Chat',
                  subtitle: 'Versi 1.0.0 (build 1)',
                  onTap: () => showAboutDialog(
                    context: context,
                    applicationName: 'Adoetz Chat',
                    applicationVersion: '1.0.0',
                    applicationLegalese: '© 2026 Adoetz Chat',
                  ),
                ),
                AppSettingRow(
                  icon: Icons.privacy_tip_outlined,
                  title: 'Kebijakan privasi',
                  onTap: () => _showPrivacy(context),
                ),
                AppSettingRow(
                  icon: Icons.description_outlined,
                  title: 'Lisensi open source',
                  onTap: () => showLicensePage(
                    context: context,
                    applicationName: 'Adoetz Chat',
                    applicationVersion: '1.0.0',
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(AppTokens.space16),
              child: OutlinedButton.icon(
                onPressed: () => _signOut(context, ref),
                icon: Icon(Icons.logout_rounded, color: p.statusError),
                label: Text(
                  'Keluar dari akun',
                  style: TextStyle(color: p.statusError),
                ),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(AppTokens.minTouchTarget),
                  side: BorderSide(color: p.statusError.withValues(alpha: 0.5)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _themeLabel(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.dark:
        return 'Midnight Blue (gelap)';
      case ThemeMode.light:
        return 'Ice Blue (terang)';
      case ThemeMode.system:
        return 'Mengikuti sistem';
    }
  }

  static String _notificationLabel(String value) {
    switch (value) {
      case 'hidden':
        return 'Sembunyikan detail';
      case 'full':
        return 'Nama dan isi pesan';
      default:
        return 'Nama pengirim saja';
    }
  }

  Future<void> _chooseTheme(
    BuildContext context,
    WidgetRef ref,
    ThemeMode current,
  ) async {
    final selected = await showDialog<ThemeMode>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('Tema aplikasi'),
        children: [
          RadioGroup<ThemeMode>(
            groupValue: current,
            onChanged: (value) => Navigator.of(dialogContext).pop(value),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final mode in ThemeMode.values)
                  RadioListTile<ThemeMode>(
                    value: mode,
                    title: Text(_themeLabel(mode)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    if (selected == null) return;
    await ref.read(themeControllerProvider.notifier).setMode(selected);
    final latest =
        ref.read(preferencesControllerProvider).valueOrNull ??
        const UserPreferences();
    try {
      await ref
          .read(preferencesControllerProvider.notifier)
          .update(latest.copyWith(theme: selected.name));
    } catch (_) {
      // The local theme is authoritative; server sync retries on next change.
    }
  }

  Future<void> _chooseNotificationPrivacy(
    BuildContext context,
    WidgetRef ref,
    UserPreferences preferences,
  ) async {
    const options = {
      'sender': 'Nama pengirim saja',
      'hidden': 'Sembunyikan semua detail',
      'full': 'Nama dan isi pesan',
    };
    final selected = await showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('Privasi notifikasi'),
        children: [
          RadioGroup<String>(
            groupValue: preferences.notificationPrivacy,
            onChanged: (value) => Navigator.of(dialogContext).pop(value),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final entry in options.entries)
                  RadioListTile<String>(
                    value: entry.key,
                    title: Text(entry.value),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    if (selected == null) return;
    await ref
        .read(preferencesControllerProvider.notifier)
        .setNotificationPrivacy(selected);
  }

  Future<void> _editProfile(
    BuildContext context,
    WidgetRef ref,
    Profile profile,
  ) async {
    final messengerContext = context;
    final nameController = TextEditingController(text: profile.displayName);
    final bioController = TextEditingController(text: profile.bio);
    var discoverable = profile.discoverable;
    final formKey = GlobalKey<FormState>();
    var busy = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Edit profil'),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    controller: nameController,
                    textCapitalization: TextCapitalization.words,
                    maxLength: 40,
                    decoration: const InputDecoration(
                      labelText: 'Nama tampilan',
                    ),
                    validator: (value) {
                      final text = value?.trim() ?? '';
                      if (text.length < 2) return 'Nama minimal 2 karakter';
                      if (text.length > 40) return 'Nama maksimal 40 karakter';
                      return null;
                    },
                  ),
                  const SizedBox(height: AppTokens.space8),
                  TextFormField(
                    controller: bioController,
                    maxLength: 120,
                    maxLines: 2,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(labelText: 'Bio'),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: discoverable,
                    title: const Text('Dapat ditemukan'),
                    subtitle: const Text('Muncul di hasil pencarian username.'),
                    onChanged: (value) => setState(() => discoverable = value),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.of(dialogContext).pop(),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: busy
                  ? null
                  : () async {
                      if (!(formKey.currentState?.validate() ?? false)) return;
                      setState(() => busy = true);
                      try {
                        final updated = await ref
                            .read(depsProvider)
                            .profiles
                            .updateProfile(
                              displayName: nameController.text.trim(),
                              bio: bioController.text.trim(),
                              discoverable: discoverable,
                            );
                        ref
                            .read(authControllerProvider.notifier)
                            .updateProfile(updated);
                        if (dialogContext.mounted) {
                          Navigator.of(dialogContext).pop();
                          showAppSnack(messengerContext, 'Profil diperbarui.');
                        }
                      } catch (error) {
                        if (dialogContext.mounted) {
                          showAppSnack(
                            dialogContext,
                            mapError(error).message,
                            error: true,
                          );
                        }
                      } finally {
                        if (dialogContext.mounted) {
                          setState(() => busy = false);
                        }
                      }
                    },
              child: busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Simpan'),
            ),
          ],
        ),
      ),
    );
    nameController.dispose();
    bioController.dispose();
  }

  Future<void> _changeAvatar(BuildContext context, WidgetRef ref) async {
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 88,
      );
      if (picked == null) return;
      final Uint8List bytes = await picked.readAsBytes();
      final mime =
          picked.mimeType ??
          lookupMimeType(picked.name, headerBytes: bytes) ??
          'image/jpeg';
      final updated = await ref
          .read(depsProvider)
          .profiles
          .changeAvatar(bytes, mime);
      ref.read(authControllerProvider.notifier).updateProfile(updated);
      if (context.mounted) showAppSnack(context, 'Foto profil diperbarui.');
    } catch (error) {
      if (context.mounted) {
        showAppSnack(context, mapError(error).message, error: true);
      }
    }
  }

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Keluar dari akun?',
      message:
          'Riwayat obrolan lokal pada perangkat ini akan dihapus. '
          'Kunci enkripsi tetap tersimpan aman di perangkat.',
      confirmLabel: 'Keluar',
      destructive: true,
    );
    if (!confirmed) return;
    await ref.read(authControllerProvider.notifier).signOut();
  }

  Future<void> _showDeviceInfo(BuildContext context, Profile? profile) async {
    final lastSignIn = profile?.lastSignInAt;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Perangkat ini'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Akun ini hanya dapat aktif pada satu perangkat. '
              'Masuk di perangkat lain akan memindahkan sesi aktif.',
            ),
            const SizedBox(height: AppTokens.space12),
            if (lastSignIn != null)
              Text('Masuk terakhir: ${Formatters.full(lastSignIn)}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Tutup'),
          ),
        ],
      ),
    );
  }

  Future<void> _showEncryptionInfo(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Enkripsi end-to-end'),
        content: const Text(
          'Setiap pesan dienkripsi di perangkat Anda dengan protokol Signal '
          'sebelum dikirim. Server Adoetz Chat hanya menyimpan teks terenkripsi, '
          'lampiran terenkripsi, dan kunci publik — tidak pernah kunci privat '
          'atau isi pesan dalam bentuk terbuka.\n\n'
          'Nomor keamanan dapat dibandingkan dari halaman info kontak untuk '
          'memastikan tidak ada penyadapan.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Mengerti'),
          ),
        ],
      ),
    );
  }

  Future<void> _showPrivacy(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Kebijakan privasi'),
        content: const SingleChildScrollView(
          child: Text(
            'Adoetz Chat mengumpulkan data minimum yang dibutuhkan untuk '
            'menjalankan layanan:\n\n'
            '• Akun: username, email, nama tampilan, foto profil.\n'
            '• Pesan: hanya ciphertext dan metadata pengiriman.\n'
            '• Lampiran: kontainer terenkripsi di penyimpanan privat.\n'
            '• Perangkat: token push untuk notifikasi.\n\n'
            'Kami tidak menjual data, tidak menampilkan iklan, dan tidak '
            'memindai isi pesan. Data dihapus saat akun dihapus, sesuai '
            'kebijakan retensi.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Tutup'),
          ),
        ],
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.profile});

  final Profile profile;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTokens.space16,
        AppTokens.space16,
        AppTokens.space16,
        0,
      ),
      child: Container(
        padding: const EdgeInsets.all(AppTokens.space16),
        decoration: BoxDecoration(
          color: p.bgSurface,
          borderRadius: BorderRadius.circular(AppTokens.radiusCard),
          border: Border.all(color: p.border),
        ),
        child: Row(
          children: [
            AvatarView(name: profile.label, path: profile.avatarPath, size: 64),
            const SizedBox(width: AppTokens.space16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          profile.label,
                          style: text.titleMedium,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (profile.isAdmin) ...[
                        const SizedBox(width: AppTokens.space8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: p.brandSoft.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(
                              AppTokens.radiusPill,
                            ),
                          ),
                          child: Text(
                            'Admin',
                            style: text.labelSmall?.copyWith(
                              color: p.brandSoft,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text('@${profile.username}', style: text.bodySmall),
                  if ((profile.email ?? '').isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      profile.email!,
                      style: text.labelSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTokens.space16,
        AppTokens.space20,
        AppTokens.space16,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: AppTokens.space8),
            child: Text(
              title,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: p.brandSoft,
                letterSpacing: 0.8,
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: p.bgSurface,
              borderRadius: BorderRadius.circular(AppTokens.radiusCard),
              border: Border.all(color: p.border),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(children: children),
          ),
        ],
      ),
    );
  }
}
