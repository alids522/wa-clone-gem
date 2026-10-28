import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme/app_tokens.dart';
import '../../core/services/admin_repository.dart';
import '../../core/ui/app_widgets.dart';
import '../../core/ui/avatar_view.dart';
import '../../core/utils/app_error.dart';
import '../../core/utils/formatters.dart';

class AdminScreen extends ConsumerStatefulWidget {
  const AdminScreen({super.key});

  @override
  ConsumerState<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends ConsumerState<AdminScreen> {
  int _index = 0;

  static const _titles = [
    'Ringkasan',
    'Pengguna',
    'Undangan',
    'Laporan',
    'Audit log',
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Admin · ${_titles[_index]}')),
      body: IndexedStack(
        index: _index,
        children: const [
          _OverviewTab(),
          _UsersTab(),
          _InvitesTab(),
          _ReportsTab(),
          _AuditTab(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.insights_outlined),
            selectedIcon: Icon(Icons.insights_rounded),
            label: 'Ringkasan',
          ),
          NavigationDestination(
            icon: Icon(Icons.people_outline_rounded),
            selectedIcon: Icon(Icons.people_rounded),
            label: 'Pengguna',
          ),
          NavigationDestination(
            icon: Icon(Icons.confirmation_number_outlined),
            selectedIcon: Icon(Icons.confirmation_number_rounded),
            label: 'Undangan',
          ),
          NavigationDestination(
            icon: Icon(Icons.shield_outlined),
            selectedIcon: Icon(Icons.shield_rounded),
            label: 'Laporan',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long_rounded),
            label: 'Audit',
          ),
        ],
      ),
    );
  }
}

class _OverviewTab extends ConsumerStatefulWidget {
  const _OverviewTab();

  @override
  ConsumerState<_OverviewTab> createState() => _OverviewTabState();
}

class _OverviewTabState extends ConsumerState<_OverviewTab> {
  AdminStats? _stats;
  AppError? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = _stats == null;
      _error = null;
    });
    try {
      final stats = await ref.read(depsProvider).admin.stats();
      if (!mounted) return;
      setState(() {
        _stats = stats;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = mapError(error);
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const LoadingPane(label: 'Memuat ringkasan…');
    if (_error != null) {
      return ErrorPane(message: _error!.message, onRetry: _load);
    }
    final stats = _stats!;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(AppTokens.space16),
        children: [
          Wrap(
            spacing: AppTokens.space12,
            runSpacing: AppTokens.space12,
            children: [
              _StatCard(label: 'Total pengguna', value: stats.totalUsers),
              _StatCard(label: 'Aktif', value: stats.activeUsers),
              _StatCard(label: 'Ditangguhkan', value: stats.suspendedUsers),
              _StatCard(label: 'Undangan aktif', value: stats.activeInvites),
              _StatCard(
                label: 'Undangan siap pakai',
                value: stats.pendingInvites,
              ),
            ],
          ),
          const SizedBox(height: AppTokens.space24),
          Text(
            'Aktivitas terbaru',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: AppTokens.space8),
          if (stats.recentActions.isEmpty)
            Text(
              'Belum ada aktivitas admin.',
              style: Theme.of(context).textTheme.bodySmall,
            )
          else
            for (final entry in stats.recentActions) _AuditTile(entry: entry),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      width: 150,
      padding: const EdgeInsets.all(AppTokens.space16),
      decoration: BoxDecoration(
        color: p.bgSurface,
        borderRadius: BorderRadius.circular(AppTokens.radiusCard),
        border: Border.all(color: p.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$value',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: p.brandSoft,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _UsersTab extends ConsumerStatefulWidget {
  const _UsersTab();

  @override
  ConsumerState<_UsersTab> createState() => _UsersTabState();
}

class _UsersTabState extends ConsumerState<_UsersTab> {
  final TextEditingController _query = TextEditingController();
  Timer? _debounce;
  List<AdminUserSummary> _users = const [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  int _total = 0;
  String? _role;
  String? _status;
  AppError? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  Future<void> _load({bool append = false}) async {
    if (append && (!_hasMore || _loadingMore)) return;
    setState(() {
      if (append) {
        _loadingMore = true;
      } else {
        _loading = _users.isEmpty;
      }
      _error = null;
    });
    try {
      final page = await ref
          .read(depsProvider)
          .admin
          .listUsers(
            query: _query.text,
            role: _role,
            status: _status,
            limit: 20,
            offset: append ? _users.length : 0,
          );
      if (!mounted) return;
      setState(() {
        _users = append ? [..._users, ...page.users] : page.users;
        _hasMore = page.hasMore;
        _total = page.total;
        _loading = false;
        _loadingMore = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = mapError(error);
        _loading = false;
        _loadingMore = false;
      });
    }
  }

  void _onSearch(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => _load());
  }

  Future<void> _openUser(AdminUserSummary user) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _UserSheet(userId: user.userId, seed: user),
    );
    if (mounted) unawaited(_load());
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppTokens.space16,
            AppTokens.space12,
            AppTokens.space16,
            AppTokens.space8,
          ),
          child: TextField(
            controller: _query,
            autocorrect: false,
            textInputAction: TextInputAction.search,
            onChanged: _onSearch,
            onSubmitted: (_) => _load(),
            decoration: const InputDecoration(
              hintText: 'Cari username, email, atau user id',
              prefixIcon: Icon(Icons.search_rounded),
            ),
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: AppTokens.space16),
          child: Row(
            children: [
              for (final entry in const {
                'Semua': null,
                'Admin': 'admin',
                'User': 'user',
              }.entries)
                Padding(
                  padding: const EdgeInsets.only(right: AppTokens.space8),
                  child: FilterChip(
                    label: Text(entry.key),
                    selected: _role == entry.value,
                    onSelected: (_) {
                      setState(() => _role = entry.value);
                      unawaited(_load());
                    },
                  ),
                ),
              const SizedBox(width: AppTokens.space8),
              for (final entry in const {
                'Aktif': 'active',
                'Ditangguhkan': 'suspended',
              }.entries)
                Padding(
                  padding: const EdgeInsets.only(right: AppTokens.space8),
                  child: FilterChip(
                    label: Text(entry.key),
                    selected: _status == entry.value,
                    onSelected: (_) {
                      setState(() => _status = entry.value);
                      unawaited(_load());
                    },
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: AppTokens.space8),
        if (_loading)
          const Expanded(child: LoadingPane(label: 'Memuat pengguna…')),
        if (!_loading && _error != null)
          Expanded(
            child: ErrorPane(message: _error!.message, onRetry: () => _load()),
          ),
        if (!_loading && _error == null)
          Expanded(
            child: _users.isEmpty
                ? const EmptyState(
                    icon: Icons.people_outline_rounded,
                    title: 'Tidak ada pengguna',
                    message: 'Coba ubah kata kunci atau filter.',
                  )
                : RefreshIndicator(
                    onRefresh: () => _load(),
                    child: ListView.separated(
                      itemCount: _users.length + 1,
                      separatorBuilder: (_, __) => Divider(
                        height: 1,
                        indent: 72,
                        color: context.palette.border,
                      ),
                      itemBuilder: (context, index) {
                        if (index == _users.length) {
                          return Padding(
                            padding: const EdgeInsets.all(AppTokens.space16),
                            child: Column(
                              children: [
                                Text(
                                  'Menampilkan ${_users.length} dari $_total',
                                  style: Theme.of(context).textTheme.labelSmall,
                                ),
                                if (_hasMore) ...[
                                  const SizedBox(height: AppTokens.space8),
                                  OutlinedButton(
                                    onPressed: _loadingMore
                                        ? null
                                        : () => _load(append: true),
                                    child: _loadingMore
                                        ? const SizedBox(
                                            width: 18,
                                            height: 18,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : const Text('Muat lebih banyak'),
                                  ),
                                ],
                              ],
                            ),
                          );
                        }
                        final user = _users[index];
                        return ListTile(
                          onTap: () => _openUser(user),
                          leading: AvatarView(
                            name: user.label,
                            path: user.avatarPath,
                            size: 44,
                          ),
                          title: Row(
                            children: [
                              Flexible(
                                child: Text(
                                  user.label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (user.isAdmin) ...[
                                const SizedBox(width: 6),
                                _Tag(text: 'Admin', tone: _Tone.brand),
                              ],
                              if (user.isSuspended) ...[
                                const SizedBox(width: 6),
                                _Tag(text: 'Suspended', tone: _Tone.error),
                              ],
                            ],
                          ),
                          subtitle: Text(
                            user.email ?? '@${user.username}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: Text(
                            user.lastSignInAt == null
                                ? 'Belum masuk'
                                : Formatters.relative(user.lastSignInAt!),
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        );
                      },
                    ),
                  ),
          ),
      ],
    );
  }
}

class _UserSheet extends ConsumerStatefulWidget {
  const _UserSheet({required this.userId, this.seed});

  final String userId;
  final AdminUserSummary? seed;

  @override
  ConsumerState<_UserSheet> createState() => _UserSheetState();
}

class _UserSheetState extends ConsumerState<_UserSheet> {
  AdminUserDetail? _detail;
  bool _loading = true;
  bool _busy = false;
  AppError? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = _detail == null;
      _error = null;
    });
    try {
      final detail = await ref.read(depsProvider).admin.user(widget.userId);
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = mapError(error);
        _loading = false;
      });
    }
  }

  Future<void> _changeRole(String role) async {
    setState(() => _busy = true);
    try {
      await showReasonDialog(
        context: context,
        title: role == 'admin' ? 'Jadikan admin?' : 'Turunkan menjadi user?',
        description: 'Perubahan peran dicatat di audit log.',
        destructive: role != 'admin',
        confirmLabel: 'Simpan',
        onConfirm: (reason) async {
          await ref
              .read(depsProvider)
              .admin
              .setRole(widget.userId, role, reason);
          if (mounted) await _load();
        },
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _changeStatus(String status) async {
    setState(() => _busy = true);
    try {
      await showReasonDialog(
        context: context,
        title: status == 'suspended' ? 'Tangguhkan akun?' : 'Aktifkan kembali?',
        description: status == 'suspended'
            ? 'Pengguna akan langsung kehilangan akses dan token push dicabut.'
            : 'Akun akan dapat masuk dan menggunakan aplikasi kembali.',
        destructive: status == 'suspended',
        confirmLabel: status == 'suspended' ? 'Tangguhkan' : 'Aktifkan',
        onConfirm: (reason) async {
          await ref
              .read(depsProvider)
              .admin
              .setStatus(widget.userId, status, reason);
          if (mounted) await _load();
        },
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    final detail = _detail;
    final summary = detail?.summary ?? widget.seed;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppTokens.space16,
          0,
          AppTokens.space16,
          AppTokens.space16,
        ),
        child: _loading
            ? const SizedBox(height: 240, child: LoadingPane())
            : _error != null
            ? SizedBox(
                height: 240,
                child: ErrorPane(message: _error!.message, onRetry: _load),
              )
            : detail == null || summary == null
            ? const SizedBox.shrink()
            : SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        AvatarView(
                          name: summary.label,
                          path: summary.avatarPath,
                          size: 56,
                        ),
                        const SizedBox(width: AppTokens.space12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(summary.label, style: text.titleMedium),
                              Text(
                                '@${summary.username}',
                                style: text.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        _Tag(
                          text: summary.isAdmin ? 'Admin' : 'User',
                          tone: summary.isAdmin ? _Tone.brand : _Tone.neutral,
                        ),
                        const SizedBox(width: 6),
                        _Tag(
                          text: summary.isSuspended ? 'Suspended' : 'Aktif',
                          tone: summary.isSuspended
                              ? _Tone.error
                              : _Tone.success,
                        ),
                      ],
                    ),
                    const SizedBox(height: AppTokens.space16),
                    _InfoRow(label: 'Email', value: summary.email ?? '—'),
                    _InfoRow(
                      label: 'Dibuat',
                      value: summary.createdAt == null
                          ? '—'
                          : Formatters.full(summary.createdAt!),
                    ),
                    _InfoRow(
                      label: 'Masuk terakhir',
                      value: summary.lastSignInAt == null
                          ? '—'
                          : Formatters.full(summary.lastSignInAt!),
                    ),
                    _InfoRow(
                      label: 'Perangkat aktif',
                      value: '${summary.deviceCount}',
                    ),
                    if (detail.bio.isNotEmpty)
                      _InfoRow(label: 'Bio', value: detail.bio),
                    if (detail.reasonCode != null)
                      _InfoRow(
                        label: 'Alasan penangguhan',
                        value: detail.reasonCode!,
                      ),
                    const SizedBox(height: AppTokens.space16),
                    if (summary.userId !=
                        ref.read(depsProvider).client.auth.currentUser?.id)
                      Wrap(
                        spacing: AppTokens.space8,
                        runSpacing: AppTokens.space8,
                        children: [
                          if (!summary.isAdmin)
                            FilledButton.icon(
                              onPressed: _busy
                                  ? null
                                  : () => _changeRole('admin'),
                              icon: const Icon(Icons.shield_outlined),
                              label: const Text('Jadikan admin'),
                            )
                          else
                            OutlinedButton.icon(
                              onPressed: _busy
                                  ? null
                                  : () => _changeRole('user'),
                              icon: const Icon(Icons.shield_moon_outlined),
                              label: const Text('Turunkan ke user'),
                            ),
                          if (!summary.isSuspended)
                            FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: p.statusError,
                                foregroundColor: Colors.white,
                              ),
                              onPressed: _busy
                                  ? null
                                  : () => _changeStatus('suspended'),
                              icon: const Icon(Icons.block_rounded),
                              label: const Text('Tangguhkan'),
                            )
                          else
                            FilledButton.icon(
                              onPressed: _busy
                                  ? null
                                  : () => _changeStatus('active'),
                              icon: const Icon(Icons.check_circle_outline),
                              label: const Text('Aktifkan'),
                            ),
                        ],
                      ),
                    const SizedBox(height: AppTokens.space16),
                    Text('Perangkat', style: text.titleMedium),
                    const SizedBox(height: AppTokens.space8),
                    if (detail.devices.isEmpty)
                      Text(
                        'Belum ada perangkat terdaftar.',
                        style: text.bodySmall,
                      )
                    else
                      for (final device in detail.devices)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.smartphone_rounded),
                          title: Text(device['status'] as String? ?? 'unknown'),
                          subtitle: Text(
                            'Terdaftar ${Formatters.relative(DateTime.tryParse(device['created_at'] as String? ?? '') ?? DateTime.now())}',
                          ),
                        ),
                  ],
                ),
              ),
      ),
    );
  }
}

class _InvitesTab extends ConsumerStatefulWidget {
  const _InvitesTab();

  @override
  ConsumerState<_InvitesTab> createState() => _InvitesTabState();
}

class _InvitesTabState extends ConsumerState<_InvitesTab> {
  List<Invitation> _invites = const [];
  bool _loading = true;
  AppError? _error;
  String? _filter;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = _invites.isEmpty;
      _error = null;
    });
    try {
      final result = await ref
          .read(depsProvider)
          .admin
          .invitations(status: _filter);
      if (!mounted) return;
      setState(() {
        _invites = result;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = mapError(error);
        _loading = false;
      });
    }
  }

  Future<void> _create() async {
    final label = TextEditingController();
    final uses = TextEditingController(text: '1');
    final days = TextEditingController(text: '7');
    final intended = TextEditingController();
    final formKey = GlobalKey<FormState>();
    var busy = false;

    final created = await showDialog<CreatedInvitation>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Buat undangan'),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: label,
                    decoration: const InputDecoration(
                      labelText: 'Label (opsional)',
                      hintText: 'Mis. Rekrutmen Batch 2',
                    ),
                  ),
                  const SizedBox(height: AppTokens.space8),
                  TextFormField(
                    controller: intended,
                    decoration: const InputDecoration(
                      labelText: 'Ditujukan untuk (opsional)',
                    ),
                  ),
                  const SizedBox(height: AppTokens.space8),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: uses,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Maks. pakai',
                          ),
                          validator: (value) {
                            final parsed = int.tryParse(value ?? '');
                            if (parsed == null || parsed < 1 || parsed > 100) {
                              return '1–100';
                            }
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(width: AppTokens.space8),
                      Expanded(
                        child: TextFormField(
                          controller: days,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Berlaku (hari)',
                          ),
                          validator: (value) {
                            final parsed = int.tryParse(value ?? '');
                            if (parsed == null || parsed < 1 || parsed > 90) {
                              return '1–90';
                            }
                            return null;
                          },
                        ),
                      ),
                    ],
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
                        final invitation = await ref
                            .read(depsProvider)
                            .admin
                            .createInvitation(
                              label: label.text.trim().isEmpty
                                  ? null
                                  : label.text.trim(),
                              intendedFor: intended.text.trim().isEmpty
                                  ? null
                                  : intended.text.trim(),
                              maxUses: int.parse(uses.text.trim()),
                              expiresAt: DateTime.now().add(
                                Duration(days: int.parse(days.text.trim())),
                              ),
                            );
                        if (dialogContext.mounted) {
                          Navigator.of(dialogContext).pop(invitation);
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
                  : const Text('Buat'),
            ),
          ],
        ),
      ),
    );
    label.dispose();
    uses.dispose();
    days.dispose();
    intended.dispose();

    if (created == null || !mounted) return;
    unawaited(_load());
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Kode undangan'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Bagikan kode ini secara pribadi. Kode hanya ditampilkan sekali.',
            ),
            const SizedBox(height: AppTokens.space12),
            SelectableText(
              created.rawCode,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(letterSpacing: 1.2),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Tutup'),
          ),
          FilledButton(
            onPressed: () {
              copySafely(context, created.rawCode, 'Kode undangan');
              Navigator.of(context).pop();
            },
            child: const Text('Salin'),
          ),
        ],
      ),
    );
  }

  Future<void> _revoke(Invitation invitation) async {
    await showReasonDialog(
      context: context,
      title: 'Cabut undangan?',
      description: 'Kode ini tidak dapat digunakan lagi setelah dicabut.',
      confirmLabel: 'Cabut',
      onConfirm: (reason) async {
        await ref
            .read(depsProvider)
            .admin
            .revokeInvitation(invitation.id, reason);
        if (mounted) await _load();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppTokens.space16,
            AppTokens.space12,
            AppTokens.space16,
            AppTokens.space8,
          ),
          child: Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: AppTokens.space8,
                  children: [
                    for (final entry in const {
                      'Semua': null,
                      'Aktif': 'active',
                      'Dicabut': 'revoked',
                    }.entries)
                      FilterChip(
                        label: Text(entry.key),
                        selected: _filter == entry.value,
                        onSelected: (_) {
                          setState(() => _filter = entry.value);
                          unawaited(_load());
                        },
                      ),
                  ],
                ),
              ),
              FilledButton.icon(
                onPressed: _create,
                icon: const Icon(Icons.add_rounded),
                label: const Text('Buat'),
              ),
            ],
          ),
        ),
        if (_loading) const Expanded(child: LoadingPane(label: 'Memuat…')),
        if (!_loading && _error != null)
          Expanded(
            child: ErrorPane(message: _error!.message, onRetry: _load),
          ),
        if (!_loading && _error == null)
          Expanded(
            child: _invites.isEmpty
                ? const EmptyState(
                    icon: Icons.confirmation_number_outlined,
                    title: 'Belum ada undangan',
                    message:
                        'Buat kode undangan untuk mengundang pengguna baru.',
                  )
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView.separated(
                      itemCount: _invites.length,
                      separatorBuilder: (_, __) =>
                          Divider(height: 1, indent: 16, color: p.border),
                      itemBuilder: (context, index) {
                        final invitation = _invites[index];
                        final tone =
                            invitation.isActive &&
                                !invitation.isExpired &&
                                !invitation.isExhausted
                            ? _Tone.success
                            : _Tone.neutral;
                        return ListTile(
                          title: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  invitation.label?.isNotEmpty == true
                                      ? invitation.label!
                                      : 'Undangan ${invitation.id.substring(0, 8)}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              _Tag(text: invitation.stateLabel, tone: tone),
                            ],
                          ),
                          subtitle: Text(
                            '${invitation.usedCount}/${invitation.maxUses} dipakai · '
                            'kedaluwarsa ${invitation.expiresAt == null ? '—' : Formatters.chatTimestamp(invitation.expiresAt!)}'
                            '${invitation.intendedFor == null ? '' : ' · ${invitation.intendedFor}'}',
                          ),
                          trailing: invitation.isActive
                              ? IconButton(
                                  tooltip: 'Cabut',
                                  onPressed: () => _revoke(invitation),
                                  icon: Icon(
                                    Icons.block_rounded,
                                    color: p.statusError,
                                  ),
                                )
                              : null,
                        );
                      },
                    ),
                  ),
          ),
      ],
    );
  }
}

const _reportReasons = <String, String>{
  'spam': 'Spam atau iklan',
  'harassment': 'Pelecehan',
  'scam': 'Penipuan',
  'illegal': 'Konten ilegal',
  'other': 'Lainnya',
};

const _reportStatuses = <String, String>{
  'open': 'Baru',
  'reviewing': 'Ditinjau',
  'resolved': 'Selesai',
  'dismissed': 'Diabaikan',
};

class _ReportsTab extends ConsumerStatefulWidget {
  const _ReportsTab();

  @override
  ConsumerState<_ReportsTab> createState() => _ReportsTabState();
}

class _ReportsTabState extends ConsumerState<_ReportsTab> {
  String? _status;
  List<AdminReport> _reports = const [];
  bool _loading = true;
  AppError? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = _reports.isEmpty;
      _error = null;
    });
    try {
      final page = await ref
          .read(depsProvider)
          .admin
          .reports(status: _status, limit: 50);
      if (!mounted) return;
      setState(() {
        _reports = page;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = mapError(error);
        _loading = false;
      });
    }
  }

  Future<void> _update(AdminReport report, String status) async {
    final note = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Tandai: ${_reportStatuses[status] ?? status}'),
        content: TextField(
          controller: note,
          maxLines: 3,
          maxLength: 300,
          decoration: const InputDecoration(
            labelText: 'Catatan penyelesaian (opsional)',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
    final text = note.text;
    note.dispose();
    if (confirmed != true || !mounted) return;

    try {
      await ref
          .read(depsProvider)
          .admin
          .updateReport(reportId: report.id, status: status, note: text);
      if (!mounted) return;
      showAppSnack(context, 'Laporan diperbarui.');
      await _load();
    } catch (error) {
      if (!mounted) return;
      showAppSnack(context, mapError(error).message, error: true);
    }
  }

  void _open(AdminReport report) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppTokens.space16,
            0,
            AppTokens.space16,
            AppTokens.space16,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                report.targetLabel,
                style: Theme.of(sheetContext).textTheme.titleLarge,
              ),
              const SizedBox(height: AppTokens.space8),
              _InfoRow(
                label: 'Pelapor',
                value: report.reporterUsername == null
                    ? '—'
                    : '@${report.reporterUsername}',
              ),
              _InfoRow(
                label: 'Alasan',
                value: _reportReasons[report.reason] ?? report.reason,
              ),
              _InfoRow(
                label: 'Status',
                value: _reportStatuses[report.status] ?? report.status,
              ),
              _InfoRow(
                label: 'Waktu',
                value: Formatters.chatTimestamp(report.createdAt),
              ),
              if ((report.details ?? '').isNotEmpty) ...[
                const SizedBox(height: AppTokens.space12),
                Text(
                  'Keterangan pelapor',
                  style: Theme.of(sheetContext).textTheme.labelLarge,
                ),
                const SizedBox(height: AppTokens.space4),
                Text(report.details!),
              ],
              if ((report.sharedContent ?? '').isNotEmpty) ...[
                const SizedBox(height: AppTokens.space12),
                Text(
                  'Isi pesan (dibagikan dengan izin)',
                  style: Theme.of(sheetContext).textTheme.labelLarge,
                ),
                const SizedBox(height: AppTokens.space4),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppTokens.space12),
                  decoration: BoxDecoration(
                    color: sheetContext.palette.bgRaised,
                    borderRadius: BorderRadius.circular(AppTokens.radiusCard),
                    border: Border.all(color: sheetContext.palette.border),
                  ),
                  child: Text(report.sharedContent!),
                ),
              ],
              if ((report.resolutionNote ?? '').isNotEmpty) ...[
                const SizedBox(height: AppTokens.space12),
                _InfoRow(label: 'Catatan admin', value: report.resolutionNote!),
              ],
              const SizedBox(height: AppTokens.space16),
              Wrap(
                spacing: AppTokens.space8,
                runSpacing: AppTokens.space8,
                children: [
                  for (final entry in _reportStatuses.entries)
                    if (entry.key != report.status)
                      OutlinedButton(
                        onPressed: () {
                          Navigator.of(sheetContext).pop();
                          _update(report, entry.key);
                        },
                        child: Text(entry.value),
                      ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 56,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(
              horizontal: AppTokens.space16,
              vertical: AppTokens.space8,
            ),
            children: [
              ChoiceChip(
                label: const Text('Semua'),
                selected: _status == null,
                onSelected: (_) {
                  setState(() => _status = null);
                  unawaited(_load());
                },
              ),
              for (final entry in _reportStatuses.entries) ...[
                const SizedBox(width: AppTokens.space8),
                ChoiceChip(
                  label: Text(entry.value),
                  selected: _status == entry.key,
                  onSelected: (_) {
                    setState(() => _status = entry.key);
                    unawaited(_load());
                  },
                ),
              ],
            ],
          ),
        ),
        if (_loading) const Expanded(child: LoadingPane(label: 'Memuat…')),
        if (!_loading && _error != null)
          Expanded(
            child: ErrorPane(message: _error!.message, onRetry: () => _load()),
          ),
        if (!_loading && _error == null)
          Expanded(
            child: _reports.isEmpty
                ? const EmptyState(
                    icon: Icons.shield_outlined,
                    title: 'Belum ada laporan',
                  )
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView.builder(
                      itemCount: _reports.length,
                      itemBuilder: (context, index) {
                        final report = _reports[index];
                        return ListTile(
                          leading: Icon(
                            Icons.shield_outlined,
                            color: report.status == 'open'
                                ? context.palette.statusWarning
                                : context.palette.textSecondary,
                          ),
                          title: Text(
                            '${report.targetLabel} · '
                            '${_reportReasons[report.reason] ?? report.reason}',
                          ),
                          subtitle: Text(
                            [
                              if (report.reporterUsername != null)
                                'oleh @${report.reporterUsername}',
                              if ((report.details ?? '').isNotEmpty)
                                report.details!,
                            ].join(' · '),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: _Tag(
                            text:
                                _reportStatuses[report.status] ?? report.status,
                            tone: switch (report.status) {
                              'open' => _Tone.error,
                              'reviewing' => _Tone.brand,
                              'resolved' => _Tone.success,
                              _ => _Tone.neutral,
                            },
                          ),
                          onTap: () => _open(report),
                        );
                      },
                    ),
                  ),
          ),
      ],
    );
  }
}

class _AuditTab extends ConsumerStatefulWidget {
  const _AuditTab();

  @override
  ConsumerState<_AuditTab> createState() => _AuditTabState();
}

class _AuditTabState extends ConsumerState<_AuditTab> {
  final TextEditingController _query = TextEditingController();
  Timer? _debounce;
  List<AdminAuditEntry> _entries = const [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  AppError? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  Future<void> _load({bool append = false}) async {
    if (append && (!_hasMore || _loadingMore)) return;
    setState(() {
      if (append) {
        _loadingMore = true;
      } else {
        _loading = _entries.isEmpty;
      }
      _error = null;
    });
    try {
      final page = await ref
          .read(depsProvider)
          .admin
          .auditLogs(
            limit: 50,
            offset: append ? _entries.length : 0,
            query: _query.text,
          );
      if (!mounted) return;
      setState(() {
        _entries = append ? [..._entries, ...page] : page;
        _hasMore = page.length == 50;
        _loading = false;
        _loadingMore = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = mapError(error);
        _loading = false;
        _loadingMore = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(AppTokens.space16),
          child: TextField(
            controller: _query,
            onChanged: (value) {
              _debounce?.cancel();
              _debounce = Timer(
                const Duration(milliseconds: 350),
                () => _load(),
              );
            },
            decoration: const InputDecoration(
              hintText: 'Cari aksi atau alasan',
              prefixIcon: Icon(Icons.search_rounded),
            ),
          ),
        ),
        if (_loading) const Expanded(child: LoadingPane(label: 'Memuat…')),
        if (!_loading && _error != null)
          Expanded(
            child: ErrorPane(message: _error!.message, onRetry: () => _load()),
          ),
        if (!_loading && _error == null)
          Expanded(
            child: _entries.isEmpty
                ? const EmptyState(
                    icon: Icons.receipt_long_outlined,
                    title: 'Belum ada catatan',
                  )
                : RefreshIndicator(
                    onRefresh: () => _load(),
                    child: ListView.builder(
                      itemCount: _entries.length + 1,
                      itemBuilder: (context, index) {
                        if (index == _entries.length) {
                          if (!_hasMore) return const SizedBox(height: 24);
                          return Padding(
                            padding: const EdgeInsets.all(AppTokens.space16),
                            child: OutlinedButton(
                              onPressed: _loadingMore
                                  ? null
                                  : () => _load(append: true),
                              child: _loadingMore
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Text('Muat lebih banyak'),
                            ),
                          );
                        }
                        return _AuditTile(entry: _entries[index]);
                      },
                    ),
                  ),
          ),
      ],
    );
  }
}

class _AuditTile extends StatelessWidget {
  const _AuditTile({required this.entry});

  final AdminAuditEntry entry;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    final failed = entry.result != 'success';
    return ListTile(
      leading: Icon(
        failed ? Icons.error_outline_rounded : Icons.history_rounded,
        color: failed ? p.statusError : p.textSecondary,
      ),
      title: Text(entry.action),
      subtitle: Text(
        [
          if (entry.actorUsername != null) 'oleh @${entry.actorUsername}',
          if (entry.targetUsername != null) 'ke @${entry.targetUsername}',
          if (entry.reason != null && entry.reason!.isNotEmpty) entry.reason!,
        ].join(' · '),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Text(
        Formatters.chatTimestamp(entry.createdAt),
        style: text.labelSmall,
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 130, child: Text(label, style: text.bodySmall)),
          Expanded(child: Text(value, style: text.bodyMedium)),
        ],
      ),
    );
  }
}

enum _Tone { neutral, brand, success, error }

class _Tag extends StatelessWidget {
  const _Tag({required this.text, required this.tone});

  final String text;
  final _Tone tone;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final color = switch (tone) {
      _Tone.brand => p.brandSoft,
      _Tone.success => p.statusSuccess,
      _Tone.error => p.statusError,
      _Tone.neutral => p.textSecondary,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppTokens.radiusPill),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
