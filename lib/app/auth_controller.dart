import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../core/crypto/e2ee_service.dart';
import '../core/models/profile.dart';
import '../core/services/auth_repository.dart';
import '../core/services/chat_repository.dart';
import '../core/services/push_service.dart';
import '../core/services/realtime_service.dart';
import '../core/storage/local_database.dart';
import '../core/utils/app_error.dart';

enum AuthStage {
  booting,
  signedOut,
  ready,
  suspended,
  deviceConflict,
  pendingSetup,
  failure,
}

class AuthState {
  const AuthState({
    required this.stage,
    this.profile,
    this.error,
    this.busy = false,
  });

  final AuthStage stage;
  final Profile? profile;
  final AppError? error;
  final bool busy;

  bool get isReady => stage == AuthStage.ready;

  AuthState copyWith({
    AuthStage? stage,
    Profile? profile,
    AppError? error,
    bool? busy,
    bool clearError = false,
    bool clearProfile = false,
  }) {
    return AuthState(
      stage: stage ?? this.stage,
      profile: clearProfile ? null : (profile ?? this.profile),
      error: clearError ? null : (error ?? this.error),
      busy: busy ?? this.busy,
    );
  }
}

class AuthController extends StateNotifier<AuthState> {
  AuthController({
    required AuthRepository auth,
    required LocalDatabase db,
    required E2eeService e2ee,
    required RealtimeService realtime,
    required PushService push,
    required ChatRepository chat,
  }) : _auth = auth,
       _db = db,
       _e2ee = e2ee,
       _realtime = realtime,
       _push = push,
       _chat = chat,
       super(const AuthState(stage: AuthStage.booting)) {
    _subscription = _auth.onAuthStateChange.listen(_onAuthEvent);
    unawaited(initialize());
  }

  final AuthRepository _auth;
  final LocalDatabase _db;
  final E2eeService _e2ee;
  final RealtimeService _realtime;
  final PushService _push;
  final ChatRepository _chat;

  StreamSubscription<sb.AuthState>? _subscription;
  bool _bootstrapping = false;
  bool _started = false;

  Future<void> initialize() async {
    if (_started) return;
    _started = true;
    if (_auth.session == null) {
      state = const AuthState(stage: AuthStage.signedOut);
      return;
    }
    await _bootstrap();
  }

  void _onAuthEvent(sb.AuthState event) {
    if (event.event == sb.AuthChangeEvent.signedOut) {
      if (state.stage != AuthStage.signedOut) {
        state = const AuthState(stage: AuthStage.signedOut);
      }
      return;
    }
    if (event.event == sb.AuthChangeEvent.signedIn ||
        event.event == sb.AuthChangeEvent.initialSession) {
      if (!state.isReady && !_bootstrapping) {
        unawaited(_bootstrap());
      }
    }
  }

  Future<void> _bootstrap({bool replaceDevice = false}) async {
    if (_bootstrapping) return;
    _bootstrapping = true;
    state = state.copyWith(
      stage: AuthStage.booting,
      busy: true,
      clearError: true,
    );
    try {
      final profile = await _auth.loadAccount();
      if (profile.status == AccountStatus.suspended) {
        state = AuthState(stage: AuthStage.suspended, profile: profile);
        return;
      }
      await _e2ee.initialize(
        userId: profile.userId,
        replaceExistingDevice: replaceDevice,
      );
      _realtime.start();
      try {
        await _push.onSignedIn();
      } catch (_) {}
      try {
        await _chat.flushOutbox();
      } catch (_) {}
      state = AuthState(stage: AuthStage.ready, profile: profile);
    } on DeviceConflictException {
      state = const AuthState(stage: AuthStage.deviceConflict);
    } on AppError catch (error) {
      if (error.code == 'PROFILE_MISSING') {
        state = const AuthState(stage: AuthStage.pendingSetup);
      } else {
        state = AuthState(stage: AuthStage.failure, error: error);
      }
    } catch (error) {
      final appError = mapError(error);
      if (appError.code == 'PROFILE_MISSING') {
        state = const AuthState(stage: AuthStage.pendingSetup);
      } else {
        state = AuthState(stage: AuthStage.failure, error: appError);
      }
    } finally {
      _bootstrapping = false;
    }
  }

  Future<void> signIn({
    required String identifier,
    required String password,
  }) async {
    state = state.copyWith(busy: true, clearError: true);
    try {
      await _auth.signInWithPassword(
        identifier: identifier,
        password: password,
      );
      await _bootstrap();
    } catch (error) {
      state = state.copyWith(
        stage: AuthStage.signedOut,
        busy: false,
        error: mapError(error),
      );
      rethrow;
    }
  }

  /// Null means "could not check"; callers must not treat it as taken.
  Future<bool?> usernameAvailable(String username) =>
      _auth.usernameAvailable(username);

  Future<SignUpResult> signUp({
    required String inviteCode,
    required String username,
    required String email,
    required String password,
    required String displayName,
  }) async {
    state = state.copyWith(busy: true, clearError: true);
    try {
      final result = await _auth.signUp(
        inviteCode: inviteCode,
        username: username,
        email: email,
        password: password,
        displayName: displayName,
      );
      await _bootstrap();
      return result;
    } catch (error) {
      state = state.copyWith(busy: false, error: mapError(error));
      rethrow;
    }
  }

  Future<void> signOut() async {
    state = state.copyWith(busy: true);
    try {
      await _push.onSignedOut();
    } catch (_) {}
    await _auth.signOut();
    try {
      await _db.clearChatData();
    } catch (_) {}
    await _realtime.stop();
    state = const AuthState(stage: AuthStage.signedOut);
  }

  Future<void> replaceDevice() => _bootstrap(replaceDevice: true);
  Future<void> retry() => _bootstrap();

  Future<void> refreshProfile() async {
    try {
      final profile = await _auth.loadAccount();
      if (profile.status == AccountStatus.suspended) {
        state = AuthState(stage: AuthStage.suspended, profile: profile);
        return;
      }
      state = state.copyWith(profile: profile);
    } catch (error) {
      state = state.copyWith(error: mapError(error));
    }
  }

  void updateProfile(Profile profile) {
    state = state.copyWith(profile: profile);
  }

  void clearError() {
    state = state.copyWith(clearError: true);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
