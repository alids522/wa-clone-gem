import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme/app_tokens.dart';
import '../../core/services/app_lock_service.dart';
import '../../core/ui/app_widgets.dart';

/// Wraps the whole app and covers it with the PIN/biometric screen whenever
/// App Lock is enabled and the app has been backgrounded past the timeout.
class AppLockGate extends ConsumerStatefulWidget {
  const AppLockGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends ConsumerState<AppLockGate>
    with WidgetsBindingObserver {
  AppLockService? _service;
  bool _locked = false;
  DateTime? _backgroundedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final service = ref.read(appLockServiceProvider);
    _service = service;
    unawaited(
      service.load().then((_) {
        if (!mounted) return;
        if (service.enabled && service.hasPin) {
          setState(() => _locked = true);
        }
      }),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final service = _service;
    if (service == null) return;
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        _backgroundedAt ??= DateTime.now();
        break;
      case AppLifecycleState.resumed:
        final at = _backgroundedAt;
        _backgroundedAt = null;
        if (at == null || !service.enabled || !service.hasPin) return;
        if (DateTime.now().difference(at) >= service.lockTimeout) {
          setState(() => _locked = true);
        }
        break;
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = _service;
    return Stack(
      children: [
        widget.child,
        if (_locked && service != null)
          Positioned.fill(
            child: _LockScreen(
              service: service,
              onUnlocked: () => setState(() => _locked = false),
            ),
          ),
      ],
    );
  }
}

class _LockScreen extends StatefulWidget {
  const _LockScreen({required this.service, required this.onUnlocked});

  final AppLockService service;
  final VoidCallback onUnlocked;

  @override
  State<_LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<_LockScreen> {
  final GlobalKey<PinKeypadState> _keypad = GlobalKey<PinKeypadState>();
  String? _error;
  bool _biometricsAvailable = false;
  bool _busy = false;
  bool _promptedBiometrics = false;

  @override
  void initState() {
    super.initState();
    unawaited(_checkBiometrics());
  }

  Future<void> _checkBiometrics() async {
    final available = await widget.service.canUseBiometrics;
    if (!mounted) return;
    setState(() => _biometricsAvailable = available);
    if (available && widget.service.biometricsEnabled && !_promptedBiometrics) {
      _promptedBiometrics = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_biometricUnlock());
      });
    }
  }

  Future<void> _onCompleted(String pin) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final ok = await widget.service.verifyPin(pin);
    if (!mounted) return;
    if (ok) {
      widget.onUnlocked();
      return;
    }
    unawaited(HapticFeedback.mediumImpact());
    _keypad.currentState?.clear();
    setState(() {
      _busy = false;
      _error = widget.service.cooldownMessage ?? 'PIN salah. Coba lagi.';
    });
  }

  Future<void> _biometricUnlock() async {
    if (_busy) return;
    setState(() => _busy = true);
    final ok = await widget.service.authenticateBiometrically();
    if (!mounted) return;
    if (ok) {
      widget.onUnlocked();
      return;
    }
    setState(() {
      _busy = false;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    final biometricsEnabled = widget.service.biometricsEnabled;
    return Material(
      color: p.bgPrimary,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppTokens.space24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const AdoetzLogo(size: 64),
                const SizedBox(height: AppTokens.space20),
                Text('Adoetz Chat terkunci', style: text.titleLarge),
                const SizedBox(height: AppTokens.space4),
                Text(
                  'Masukkan PIN untuk membuka aplikasi.',
                  style: text.bodySmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppTokens.space24),
                PinKeypad(
                  key: _keypad,
                  enabled: !_busy,
                  onCompleted: _onCompleted,
                  onBiometric: _biometricsAvailable && biometricsEnabled
                      ? _biometricUnlock
                      : null,
                ),
                SizedBox(
                  height: 48,
                  child: Center(
                    child: _error == null
                        ? null
                        : Text(
                            _error!,
                            style: text.bodySmall?.copyWith(
                              color: p.statusError,
                            ),
                            textAlign: TextAlign.center,
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class AppLockSettingsScreen extends ConsumerStatefulWidget {
  const AppLockSettingsScreen({super.key});

  @override
  ConsumerState<AppLockSettingsScreen> createState() =>
      _AppLockSettingsScreenState();
}

class _AppLockSettingsScreenState extends ConsumerState<AppLockSettingsScreen> {
  AppLockService get _service => ref.read(appLockServiceProvider);

  bool _enabled = false;
  bool _biometricsEnabled = false;
  bool _biometricsAvailable = false;
  Duration _timeout = const Duration(seconds: 30);
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final service = _service;
    await service.load();
    final available = await service.canUseBiometrics;
    if (!mounted) return;
    setState(() {
      _enabled = service.enabled;
      _biometricsEnabled = service.biometricsEnabled;
      _biometricsAvailable = available;
      _timeout = service.lockTimeout;
      _ready = true;
    });
  }

  Future<void> _toggleEnabled(bool value) async {
    final service = _service;
    if (!value) {
      final confirmed = await showConfirmDialog(
        context,
        title: 'Nonaktifkan kunci aplikasi?',
        message:
            'PIN dan pengaturan biometrik akan dihapus dari perangkat ini.',
        confirmLabel: 'Nonaktifkan',
        destructive: true,
      );
      if (!confirmed) return;
      await service.disable();
      if (!mounted) return;
      setState(() {
        _enabled = false;
        _biometricsEnabled = false;
      });
      return;
    }

    if (!service.hasPin) {
      final pin = await _promptNewPin();
      if (pin == null) return;
      await service.setPin(pin);
    }
    await service.enable();
    if (!mounted) return;
    setState(() => _enabled = true);
    if (_biometricsAvailable && !_biometricsEnabled) {
      await _toggleBiometrics(true);
    }
  }

  Future<void> _toggleBiometrics(bool value) async {
    final service = _service;
    if (value) {
      final ok = await service.authenticateBiometrically();
      if (!ok) {
        if (!mounted) return;
        showAppSnack(context, 'Biometrik tidak terverifikasi.', error: true);
        return;
      }
    }
    await service.setBiometricsEnabled(value);
    if (!mounted) return;
    setState(() => _biometricsEnabled = value);
  }

  Future<String?> _promptNewPin() async {
    final service = _service;
    final shouldVerify = service.hasPin;
    return Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (_) =>
            _SetupPinScreen(verifyCurrent: shouldVerify ? service : null),
      ),
    );
  }

  Future<void> _changePin() async {
    final pin = await _promptNewPin();
    if (pin == null) return;
    await _service.setPin(pin);
    if (!mounted) return;
    showAppSnack(context, 'PIN diperbarui.');
  }

  Future<void> _chooseTimeout() async {
    final options = <Duration, String>{
      Duration.zero: 'Langsung',
      Duration(seconds: 30): '30 detik',
      Duration(minutes: 1): '1 menit',
      Duration(minutes: 5): '5 menit',
    };
    final selected = await showDialog<Duration>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('Kunci otomatis setelah'),
        children: [
          RadioGroup<Duration>(
            groupValue: _timeout,
            onChanged: (value) => Navigator.of(dialogContext).pop(value),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final entry in options.entries)
                  RadioListTile<Duration>(
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
    await _service.setLockTimeout(selected);
    if (!mounted) return;
    setState(() => _timeout = selected);
  }

  static String _timeoutLabel(Duration value) {
    if (value == Duration.zero) return 'Langsung saat aplikasi ditinggalkan';
    if (value.inMinutes >= 1)
      return '${value.inMinutes} menit di latar belakang';
    return '${value.inSeconds} detik di latar belakang';
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Kunci aplikasi')),
      body: !_ready
          ? const LoadingPane(label: 'Memuat…')
          : ListView(
              padding: const EdgeInsets.only(bottom: AppTokens.space32),
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(
                    AppTokens.space16,
                    AppTokens.space12,
                    AppTokens.space16,
                    AppTokens.space8,
                  ),
                  child: InfoBanner(
                    message:
                        'PIN dan biometrik hanya membuka aplikasi di '
                        'perangkat ini. Pesan tetap terenkripsi end-to-end.',
                    icon: Icons.lock_outline_rounded,
                  ),
                ),
                SectionCard(
                  child: Column(
                    children: [
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        secondary: const Icon(Icons.lock_outline_rounded),
                        title: const Text('Aktifkan kunci aplikasi'),
                        subtitle: const Text(
                          'Minta PIN saat membuka Adoetz Chat.',
                        ),
                        value: _enabled,
                        onChanged: _toggleEnabled,
                      ),
                      if (_enabled) ...[
                        const Divider(height: 1),
                        AppSettingRow(
                          icon: Icons.password_rounded,
                          title: 'Ubah PIN',
                          subtitle: '${AppLockService.pinLength} digit angka',
                          onTap: _changePin,
                        ),
                        const Divider(height: 1),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          secondary: const Icon(Icons.fingerprint_rounded),
                          title: const Text('Buka dengan biometrik'),
                          subtitle: Text(
                            _biometricsAvailable
                                ? 'Gunakan sidik jari atau wajah terdaftar.'
                                : 'Belum ada biometrik terdaftar di perangkat.',
                          ),
                          value: _biometricsEnabled && _biometricsAvailable,
                          onChanged: _biometricsAvailable
                              ? _toggleBiometrics
                              : null,
                        ),
                        const Divider(height: 1),
                        AppSettingRow(
                          icon: Icons.timer_outlined,
                          title: 'Kunci otomatis',
                          subtitle: _timeoutLabel(_timeout),
                          onTap: _chooseTimeout,
                        ),
                      ],
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(AppTokens.space16),
                  child: Text(
                    'PIN tidak dapat dipulihkan dari server. Jika lupa, gunakan '
                    'biometrik atau masuk ulang dengan akun Anda. Karena kunci '
                    'enkripsi tersimpan di perangkat, menghapus data aplikasi '
                    'akan menghilangkan riwayat lokal.',
                    style: text.bodySmall?.copyWith(color: p.textSecondary),
                  ),
                ),
              ],
            ),
    );
  }
}

/// Two-step PIN setup; optionally verifies the current PIN first.
class _SetupPinScreen extends StatefulWidget {
  const _SetupPinScreen({this.verifyCurrent});

  final AppLockService? verifyCurrent;

  @override
  State<_SetupPinScreen> createState() => _SetupPinScreenState();
}

class _SetupPinScreenState extends State<_SetupPinScreen> {
  final GlobalKey<PinKeypadState> _keypad = GlobalKey<PinKeypadState>();
  _SetupStep _step = _SetupStep.current;
  String? _firstPin;
  String? _error;
  bool _verifying = false;

  @override
  void initState() {
    super.initState();
    if (widget.verifyCurrent == null) _step = _SetupStep.create;
  }

  String get _title => switch (_step) {
    _SetupStep.current => 'Masukkan PIN saat ini',
    _SetupStep.create => 'Buat PIN baru',
    _SetupStep.confirm => 'Ulangi PIN baru',
  };

  String get _subtitle => switch (_step) {
    _SetupStep.current => 'Verifikasi untuk melanjutkan.',
    _SetupStep.create => 'Gunakan ${AppLockService.pinLength} digit angka.',
    _SetupStep.confirm => 'Masukkan kembali PIN yang sama.',
  };

  Future<void> _onCompleted(String pin) async {
    switch (_step) {
      case _SetupStep.current:
        setState(() {
          _verifying = true;
          _error = null;
        });
        final ok = await widget.verifyCurrent!.verifyPin(pin);
        if (!mounted) return;
        if (ok) {
          setState(() {
            _verifying = false;
            _step = _SetupStep.create;
          });
          _keypad.currentState?.clear();
        } else {
          _keypad.currentState?.clear();
          setState(() {
            _verifying = false;
            _error =
                widget.verifyCurrent!.cooldownMessage ?? 'PIN saat ini salah.';
          });
        }
        break;
      case _SetupStep.create:
        setState(() {
          _firstPin = pin;
          _step = _SetupStep.confirm;
          _error = null;
        });
        _keypad.currentState?.clear();
        break;
      case _SetupStep.confirm:
        if (pin != _firstPin) {
          unawaited(HapticFeedback.mediumImpact());
          _keypad.currentState?.clear();
          setState(() => _error = 'PIN tidak cocok. Coba lagi.');
          return;
        }
        Navigator.of(context).pop(pin);
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('PIN aplikasi')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppTokens.space24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.password_rounded, size: 40, color: p.brandSoft),
                const SizedBox(height: AppTokens.space16),
                Text(
                  _title,
                  style: text.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppTokens.space4),
                Text(
                  _subtitle,
                  style: text.bodySmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppTokens.space24),
                PinKeypad(
                  key: _keypad,
                  enabled: !_verifying,
                  onCompleted: _onCompleted,
                ),
                SizedBox(
                  height: 56,
                  child: Center(
                    child: _error == null
                        ? null
                        : Text(
                            _error!,
                            style: text.bodySmall?.copyWith(
                              color: p.statusError,
                            ),
                            textAlign: TextAlign.center,
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

enum _SetupStep { current, create, confirm }

/// PIN dots plus a 3x4 keypad. Parent widgets decide what a completed PIN
/// means and call [PinKeypadState.clear] to retry.
class PinKeypad extends StatefulWidget {
  const PinKeypad({
    super.key,
    required this.onCompleted,
    this.enabled = true,
    this.onBiometric,
  });

  final ValueChanged<String> onCompleted;
  final bool enabled;
  final VoidCallback? onBiometric;

  @override
  State<PinKeypad> createState() => PinKeypadState();
}

class PinKeypadState extends State<PinKeypad> {
  String _pin = '';

  void clear() {
    if (!mounted) return;
    setState(() => _pin = '');
  }

  void _press(String digit) {
    if (!widget.enabled || _pin.length >= AppLockService.pinLength) return;
    final next = _pin + digit;
    unawaited(HapticFeedback.selectionClick());
    setState(() => _pin = next);
    if (next.length == AppLockService.pinLength) {
      widget.onCompleted(next);
    }
  }

  void _delete() {
    if (!widget.enabled || _pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < AppLockService.pinLength; i++)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 8),
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i < _pin.length ? p.brandSoft : Colors.transparent,
                  border: Border.all(
                    color: i < _pin.length ? p.brandSoft : p.border,
                    width: 1.5,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: AppTokens.space24),
        for (final row in const [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9'],
        ])
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (final digit in row)
                _Key(label: digit, onTap: () => _press(digit)),
            ],
          ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _Key(
              icon: widget.onBiometric == null
                  ? null
                  : Icons.fingerprint_rounded,
              label: widget.onBiometric == null ? '' : null,
              onTap: widget.onBiometric,
            ),
            _Key(label: '0', onTap: () => _press('0')),
            _Key(
              icon: Icons.backspace_outlined,
              label: null,
              onTap: _pin.isEmpty ? null : _delete,
            ),
          ],
        ),
      ],
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({this.label, this.icon, this.onTap});

  final String? label;
  final IconData? icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.all(6),
      child: Material(
        color: p.bgSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusCard),
          side: BorderSide(color: p.border),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppTokens.radiusCard),
          onTap: onTap,
          child: SizedBox(
            width: 72,
            height: 60,
            child: Center(
              child: icon != null
                  ? Icon(
                      icon,
                      color: onTap == null
                          ? p.textSecondary.withValues(alpha: 0.4)
                          : p.textPrimary,
                    )
                  : Text(
                      label ?? '',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: onTap == null
                            ? p.textSecondary.withValues(alpha: 0.4)
                            : p.textPrimary,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
