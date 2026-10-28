import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme/app_tokens.dart';
import '../../core/ui/app_widgets.dart';
import '../../core/utils/app_error.dart';
import '../../core/utils/debouncer.dart';
import '../../core/utils/validators.dart';
import 'sign_in_screen.dart';

enum _UsernameStatus { unknown, checking, available, taken }

class SignUpScreen extends ConsumerStatefulWidget {
  const SignUpScreen({super.key});

  @override
  ConsumerState<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends ConsumerState<SignUpScreen> {
  final _formKey = GlobalKey<FormState>();
  final _invite = TextEditingController();
  final _username = TextEditingController();
  final _displayName = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  AppError? _error;
  _UsernameStatus _usernameStatus = _UsernameStatus.unknown;
  final _usernameDebounce = Debouncer(
    duration: const Duration(milliseconds: 450),
  );

  @override
  void dispose() {
    _usernameDebounce.dispose();
    _invite.dispose();
    _username.dispose();
    _displayName.dispose();
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _onUsernameChanged(String raw) {
    final value = Validators.normalizeUsername(raw);
    _usernameDebounce.cancel();
    if (Validators.username(value) != null) {
      if (_usernameStatus != _UsernameStatus.unknown) {
        setState(() => _usernameStatus = _UsernameStatus.unknown);
      }
      return;
    }
    setState(() => _usernameStatus = _UsernameStatus.checking);
    _usernameDebounce.run(() async {
      final available = await ref
          .read(authControllerProvider.notifier)
          .usernameAvailable(value);
      if (!mounted || Validators.normalizeUsername(_username.text) != value) {
        return;
      }
      setState(() {
        _usernameStatus = available == null
            ? _UsernameStatus.unknown
            : available
            ? _UsernameStatus.available
            : _UsernameStatus.taken;
      });
    });
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (_usernameStatus == _UsernameStatus.taken) {
      setState(
        () => _error = const AppError(
          'USERNAME_TAKEN',
          'Username sudah dipakai. Pilih yang lain.',
        ),
      );
      return;
    }
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(authControllerProvider.notifier)
          .signUp(
            inviteCode: _invite.text.trim(),
            username: Validators.normalizeUsername(_username.text),
            email: Validators.normalizeEmail(_email.text),
            password: _password.text,
            displayName: _displayName.text.trim(),
          );
      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = mapError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    final strength = Validators.passwordStrength(_password.text);

    return Scaffold(
      appBar: AppBar(title: const Text('Daftar')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppTokens.maxContentWidth,
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppTokens.space24),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Buat akun', style: text.headlineSmall),
                    const SizedBox(height: AppTokens.space8),
                    Text(
                      'Pendaftaran hanya dengan kode undangan dari admin.',
                      style: text.bodySmall,
                    ),
                    const SizedBox(height: AppTokens.space24),
                    if (_error != null) ...[
                      InfoBanner(
                        message: _error!.message,
                        icon: Icons.error_outline_rounded,
                        color: p.statusError,
                      ),
                      const SizedBox(height: AppTokens.space16),
                    ],
                    TextFormField(
                      controller: _invite,
                      enabled: !_busy,
                      textCapitalization: TextCapitalization.none,
                      autocorrect: false,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Kode undangan',
                        hintText: 'Tempel kode undangan di sini',
                        prefixIcon: Icon(Icons.confirmation_number_outlined),
                      ),
                      validator: Validators.inviteCode,
                    ),
                    const SizedBox(height: AppTokens.space16),
                    TextFormField(
                      controller: _username,
                      enabled: !_busy,
                      autocorrect: false,
                      textInputAction: TextInputAction.next,
                      onChanged: _onUsernameChanged,
                      decoration: InputDecoration(
                        labelText: 'Username',
                        hintText: 'huruf kecil, angka, underscore',
                        prefixIcon: const Icon(Icons.alternate_email_rounded),
                        helperText: switch (_usernameStatus) {
                          _UsernameStatus.checking => 'Memeriksa ketersediaan…',
                          _UsernameStatus.available => 'Username tersedia',
                          _UsernameStatus.taken => 'Username sudah dipakai',
                          _UsernameStatus.unknown => null,
                        },
                        helperStyle: TextStyle(
                          color: switch (_usernameStatus) {
                            _UsernameStatus.available => p.statusSuccess,
                            _UsernameStatus.taken => p.statusError,
                            _ => null,
                          },
                        ),
                        suffixIcon: switch (_usernameStatus) {
                          _UsernameStatus.checking => const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                          _UsernameStatus.available => Icon(
                            Icons.check_circle_outline_rounded,
                            color: p.statusSuccess,
                          ),
                          _UsernameStatus.taken => Icon(
                            Icons.error_outline_rounded,
                            color: p.statusError,
                          ),
                          _UsernameStatus.unknown => null,
                        },
                      ),
                      validator: Validators.username,
                    ),
                    const SizedBox(height: AppTokens.space16),
                    TextFormField(
                      controller: _displayName,
                      enabled: !_busy,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Nama tampilan',
                        prefixIcon: Icon(Icons.badge_outlined),
                      ),
                      validator: Validators.displayName,
                    ),
                    const SizedBox(height: AppTokens.space16),
                    TextFormField(
                      controller: _email,
                      enabled: !_busy,
                      keyboardType: TextInputType.emailAddress,
                      autocorrect: false,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        prefixIcon: Icon(Icons.mail_outline_rounded),
                      ),
                      validator: Validators.email,
                    ),
                    const SizedBox(height: AppTokens.space16),
                    PasswordField(
                      controller: _password,
                      label: 'Password',
                      hint: 'Minimal 12 karakter',
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.newPassword],
                      validator: Validators.password,
                    ),
                    if (_password.text.isNotEmpty) ...[
                      const SizedBox(height: AppTokens.space8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(
                          AppTokens.radiusPill,
                        ),
                        child: LinearProgressIndicator(
                          value: (strength + 1) / 5,
                          minHeight: 4,
                          backgroundColor: p.bgRaised,
                          color: strength >= 3
                              ? p.statusSuccess
                              : strength == 2
                              ? p.statusWarning
                              : p.statusError,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(switch (strength) {
                        0 || 1 => 'Lemah — tambahkan panjang dan variasi',
                        2 => 'Cukup — masih bisa ditingkatkan',
                        3 => 'Kuat',
                        _ => 'Sangat kuat',
                      }, style: text.labelSmall),
                    ],
                    const SizedBox(height: AppTokens.space16),
                    PasswordField(
                      controller: _confirm,
                      label: 'Ulangi password',
                      onSubmitted: (_) => _submit(),
                      validator: (value) {
                        if (value != _password.text) {
                          return 'Konfirmasi password tidak sama';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: AppTokens.space24),
                    FilledButton(
                      onPressed: _busy ? null : _submit,
                      child: _busy
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Buat akun'),
                    ),
                    const SizedBox(height: AppTokens.space16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('Sudah punya akun?', style: text.bodySmall),
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => Navigator.of(context).pushReplacement(
                                  MaterialPageRoute<void>(
                                    builder: (_) => const SignInScreen(),
                                  ),
                                ),
                          child: const Text('Masuk'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
