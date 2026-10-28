import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;

import '../core/models/conversation.dart';
import '../core/models/message.dart';
import '../core/models/profile.dart';
import '../core/services/app_lock_service.dart';
import '../core/services/chat_repository.dart';
import '../core/services/profile_repository.dart';
import '../core/services/realtime_service.dart';
import '../core/utils/app_error.dart';
import 'auth_controller.dart';
import 'dependencies.dart';

/// Overridden in `main()` with the instance built by [AppDependencies.create].
final depsProvider = Provider<AppDependencies>(
  (ref) => throw UnimplementedError('depsProvider must be overridden'),
);

final authControllerProvider = StateNotifierProvider<AuthController, AuthState>(
  (ref) {
    final deps = ref.watch(depsProvider);
    return AuthController(
      auth: deps.auth,
      db: deps.db,
      e2ee: deps.e2ee,
      realtime: deps.realtime,
      push: deps.push,
      chat: deps.chat,
    );
  },
);

final currentProfileProvider = Provider<Profile?>(
  (ref) => ref.watch(authControllerProvider).profile,
);

/// Downloads and decrypts an attachment once per unique envelope metadata.
final attachmentFileProvider = FutureProvider.autoDispose.family<File, String>((
  ref,
  key,
) async {
  final map = jsonDecode(key) as Map<String, dynamic>;
  return ref
      .watch(depsProvider)
      .media
      .downloadAttachment(AttachmentMeta.fromJson(map));
});

String attachmentCacheKey(AttachmentMeta meta) => jsonEncode(meta.toJson());

/// Resolves a private-bucket avatar path into a short-lived signed URL.
final avatarUrlProvider = FutureProvider.autoDispose.family<String?, String?>((
  ref,
  path,
) async {
  if (path == null || path.isEmpty) return null;
  try {
    return await ref.watch(depsProvider).profiles.avatarUrl(path);
  } catch (_) {
    return null;
  }
});

// -----------------------------------------------------------------------------
// Theme
// -----------------------------------------------------------------------------

class ThemeController extends StateNotifier<ThemeMode> {
  ThemeController(this._prefs) : super(_read(_prefs));

  static const _key = 'app_theme_mode';

  final SharedPreferences _prefs;

  static ThemeMode _read(SharedPreferences prefs) {
    switch (prefs.getString(_key)) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  static ThemeMode fromWire(String value) {
    switch (value) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  Future<void> setMode(ThemeMode mode) async {
    if (state == mode) return;
    state = mode;
    await _prefs.setString(_key, mode.name);
  }

  /// Applies the server-side preference without writing back to the server.
  void applyRemote(String theme) {
    final mode = fromWire(theme);
    if (state == mode) return;
    state = mode;
    unawaited(_prefs.setString(_key, mode.name));
  }
}

final themeControllerProvider =
    StateNotifierProvider<ThemeController, ThemeMode>(
      (ref) => ThemeController(ref.watch(depsProvider).prefs),
    );

final themeModeProvider = Provider<ThemeMode>(
  (ref) => ref.watch(themeControllerProvider),
);

/// Local-only app lock. Shared by the gate in `AdoetzApp` and settings.
final appLockServiceProvider = Provider<AppLockService>((ref) {
  final deps = ref.watch(depsProvider);
  return AppLockService(secure: deps.secure, prefs: deps.prefs);
});

// -----------------------------------------------------------------------------
// Privacy / notification preferences
// -----------------------------------------------------------------------------

class PreferencesController extends StateNotifier<AsyncValue<UserPreferences>> {
  PreferencesController(this._profiles) : super(const AsyncValue.loading()) {
    unawaited(load());
  }

  final ProfileRepository _profiles;

  Future<void> load() async {
    state = const AsyncValue.loading();
    try {
      state = AsyncValue.data(await _profiles.loadPreferences());
    } catch (_) {
      // Defaults are privacy-safe; the app stays usable offline.
      state = const AsyncValue.data(UserPreferences());
    }
  }

  Future<void> update(UserPreferences preferences) async {
    final previous = state.valueOrNull ?? const UserPreferences();
    state = AsyncValue.data(preferences);
    try {
      state = AsyncValue.data(await _profiles.savePreferences(preferences));
    } catch (error) {
      state = AsyncValue.data(previous);
      throw mapError(error);
    }
  }

  Future<void> setReadReceipts(bool value) => update(
    (state.valueOrNull ?? const UserPreferences()).copyWith(
      readReceipts: value,
    ),
  );

  Future<void> setTypingIndicators(bool value) => update(
    (state.valueOrNull ?? const UserPreferences()).copyWith(
      typingIndicators: value,
    ),
  );

  Future<void> setNotificationPrivacy(String value) => update(
    (state.valueOrNull ?? const UserPreferences()).copyWith(
      notificationPrivacy: value,
    ),
  );
}

final preferencesControllerProvider =
    StateNotifierProvider<PreferencesController, AsyncValue<UserPreferences>>(
      (ref) => PreferencesController(ref.watch(depsProvider).profiles),
    );

// -----------------------------------------------------------------------------
// Connectivity
// -----------------------------------------------------------------------------

final connectivityProvider = StreamProvider<List<ConnectivityResult>>(
  (ref) => Connectivity().onConnectivityChanged,
);

final onlineStatusProvider = Provider<bool>((ref) {
  return ref
      .watch(connectivityProvider)
      .maybeWhen(
        data: (results) =>
            results.any((result) => result != ConnectivityResult.none),
        orElse: () => true,
      );
});

// -----------------------------------------------------------------------------
// Conversation list
// -----------------------------------------------------------------------------

class ChatsState {
  const ChatsState({
    this.conversations = const [],
    this.loading = true,
    this.syncing = false,
    this.error,
  });

  final List<ConversationSummary> conversations;
  final bool loading;
  final bool syncing;
  final AppError? error;

  int get totalUnread =>
      conversations.fold<int>(0, (sum, item) => sum + item.unreadCount);

  List<ConversationSummary> get pinned =>
      conversations.where((item) => item.pinned).toList(growable: false);

  List<ConversationSummary> get regular =>
      conversations.where((item) => !item.pinned).toList(growable: false);

  ChatsState copyWith({
    List<ConversationSummary>? conversations,
    bool? loading,
    bool? syncing,
    AppError? error,
    bool clearError = false,
  }) {
    return ChatsState(
      conversations: conversations ?? this.conversations,
      loading: loading ?? this.loading,
      syncing: syncing ?? this.syncing,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class ChatsController extends StateNotifier<ChatsState> {
  ChatsController({required AppDependencies deps})
    : _deps = deps,
      super(const ChatsState()) {
    _subscription = _deps.realtime.events.listen(_onEvent);
    _connectivity = Connectivity().onConnectivityChanged.listen(
      _onConnectivityChanged,
    );
    unawaited(refresh());
  }

  final AppDependencies _deps;

  StreamSubscription<RealtimeEvent>? _subscription;
  StreamSubscription<List<ConnectivityResult>>? _connectivity;
  Timer? _debounce;
  bool _syncing = false;
  bool _wasOnline = true;

  Future<void> refresh() async {
    final local = await _deps.chat.localConversations();
    if (!mounted) return;
    state = state.copyWith(conversations: local, loading: false);
    await sync();
  }

  /// Reloads only from the encrypted local cache.
  Future<void> refreshLocal() async {
    final local = await _deps.chat.localConversations();
    if (!mounted) return;
    state = state.copyWith(conversations: local, loading: false);
  }

  Future<void> sync() async {
    if (_deps.client.auth.currentUser == null) return;
    if (_syncing) return;
    _syncing = true;
    state = state.copyWith(syncing: true, clearError: true);
    try {
      final list = await _deps.chat.syncConversations();
      if (!mounted) return;
      state = ChatsState(conversations: list);
    } catch (error) {
      if (!mounted) return;
      state = state.copyWith(syncing: false, error: mapError(error));
    } finally {
      _syncing = false;
      if (mounted) state = state.copyWith(syncing: false);
    }
  }

  Future<ConversationSummary> openConversation(String peerId) async {
    final conversation = await _deps.chat.openConversation(peerId);
    await refreshLocal();
    return conversation;
  }

  /// Used by notification taps where only the conversation id is known.
  Future<ConversationSummary?> openConversationById(
    String conversationId,
  ) async {
    final local = await _deps.chat.localConversation(conversationId);
    if (local != null) return local;
    await sync();
    return _deps.chat.localConversation(conversationId);
  }

  Future<void> markRead(String conversationId) async {
    try {
      await _deps.chat.markRead(conversationId);
      await refreshLocal();
    } catch (error) {
      state = state.copyWith(error: mapError(error));
    }
  }

  Future<void> setPinned(String conversationId, bool pinned) async {
    await _deps.chat.setPinned(conversationId, pinned);
    await refreshLocal();
  }

  Future<void> setMuted(String conversationId, bool muted) async {
    await _deps.chat.setMuted(conversationId, muted);
    await refreshLocal();
  }

  Future<void> clearHistory(String conversationId) async {
    await _deps.chat.clearLocalHistory(conversationId);
    await refreshLocal();
  }

  void dismissError() {
    if (state.error == null) return;
    state = state.copyWith(clearError: true);
  }

  void _onEvent(RealtimeEvent event) {
    switch (event.kind) {
      case RealtimeKind.receiptCreated:
        unawaited(refreshLocal());
        break;
      case RealtimeKind.messageCreated:
      case RealtimeKind.messageUpdated:
        unawaited(refreshLocal());
        _scheduleSync();
        break;
      case RealtimeKind.callChanged:
      case RealtimeKind.reactionChanged:
        break;
    }
  }

  void _onConnectivityChanged(List<ConnectivityResult> results) {
    final online = results.any((result) => result != ConnectivityResult.none);
    if (online && !_wasOnline) {
      unawaited(_deps.chat.flushOutbox().catchError((_) {}));
      _scheduleSync();
    }
    _wasOnline = online;
  }

  void _scheduleSync() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), () {
      unawaited(sync());
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    unawaited(_subscription?.cancel());
    unawaited(_connectivity?.cancel());
    super.dispose();
  }
}

final chatsControllerProvider =
    StateNotifierProvider<ChatsController, ChatsState>(
      (ref) => ChatsController(deps: ref.watch(depsProvider)),
    );

final totalUnreadProvider = Provider<int>(
  (ref) => ref.watch(chatsControllerProvider).totalUnread,
);

// -----------------------------------------------------------------------------
// Chat detail
// -----------------------------------------------------------------------------

class ChatState {
  const ChatState({
    this.conversation,
    this.messages = const [],
    this.draft = '',
    this.loading = true,
    this.loadingOlder = false,
    this.hasMore = true,
    this.sendingAttachment = false,
    this.peerTyping = false,
    this.peerOnline = false,
    this.error,
  });

  final ConversationSummary? conversation;
  final List<ChatMessage> messages;
  final String draft;
  final bool loading;
  final bool loadingOlder;
  final bool hasMore;
  final bool sendingAttachment;
  final bool peerTyping;
  final bool peerOnline;
  final AppError? error;

  String get title => conversation?.title ?? '';

  ChatState copyWith({
    ConversationSummary? conversation,
    List<ChatMessage>? messages,
    String? draft,
    bool? loading,
    bool? loadingOlder,
    bool? hasMore,
    bool? sendingAttachment,
    bool? peerTyping,
    bool? peerOnline,
    AppError? error,
    bool clearError = false,
  }) {
    return ChatState(
      conversation: conversation ?? this.conversation,
      messages: messages ?? this.messages,
      draft: draft ?? this.draft,
      loading: loading ?? this.loading,
      loadingOlder: loadingOlder ?? this.loadingOlder,
      hasMore: hasMore ?? this.hasMore,
      sendingAttachment: sendingAttachment ?? this.sendingAttachment,
      peerTyping: peerTyping ?? this.peerTyping,
      peerOnline: peerOnline ?? this.peerOnline,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class ChatController extends StateNotifier<ChatState> {
  ChatController({
    required AppDependencies deps,
    required this.conversationId,
    this.onConversationsChanged,
  }) : _deps = deps,
       super(const ChatState()) {
    _subscription = _deps.realtime.events.listen(_onEvent);
    unawaited(load());
  }

  final AppDependencies _deps;
  final String conversationId;
  final void Function()? onConversationsChanged;

  StreamSubscription<RealtimeEvent>? _subscription;
  RealtimeChannel? _channel;
  Timer? _syncDebounce;
  Timer? _typingTimer;
  Timer? _draftTimer;
  DateTime? _lastTypingSent;
  int _limit = 60;

  String? get _me => _deps.client.auth.currentUser?.id;

  Future<void> load() async {
    final conversation = await _deps.chat.localConversation(conversationId);
    final messages = await _deps.chat.loadLocalMessages(
      conversationId,
      limit: _limit,
    );
    final draft = await _deps.db.getDraft(conversationId);
    if (!mounted) return;
    state = state.copyWith(
      conversation: conversation,
      messages: messages,
      draft: draft ?? '',
      loading: false,
    );
    _openChannel();
    unawaited(_sync());
    unawaited(_syncReactions());
    unawaited(markRead());
  }

  Future<void> _syncReactions() async {
    try {
      await _deps.chat.syncReactions(conversationId);
      if (!mounted) return;
      await _reloadLocal();
    } catch (_) {
      // Reactions are decoration: never surface a sync failure for them.
    }
  }

  Future<void> toggleReaction(ChatMessage message, String emoji) async {
    try {
      final reactions = await _deps.chat.setReaction(
        messageId: message.id,
        emoji: emoji,
      );
      if (!mounted) return;
      state = state.copyWith(
        messages: state.messages
            .map(
              (item) => item.id == message.id
                  ? item.copyWith(reactions: reactions)
                  : item,
            )
            .toList(growable: false),
      );
    } catch (error) {
      if (!mounted) return;
      state = state.copyWith(error: mapError(error));
    }
  }

  Future<void> report({
    required String reportedUserId,
    required String reason,
    String? details,
    ChatMessage? message,
    bool shareContent = false,
  }) async {
    await _deps.chat.submitReport(
      reportedUserId: reportedUserId,
      reason: reason,
      details: details,
      messageId: message?.id,
      sharedContent: message?.body,
      shareContent: shareContent,
    );
  }

  Future<void> _sync() async {
    try {
      final messages = await _deps.chat.syncMessages(conversationId);
      if (!mounted) return;
      _limit = math.max(_limit, messages.length);
      await _reloadLocal();
    } catch (error) {
      if (!mounted) return;
      state = state.copyWith(error: mapError(error));
    }
  }

  Future<void> _reloadLocal() async {
    final messages = await _deps.chat.loadLocalMessages(
      conversationId,
      limit: _limit,
    );
    final conversation = await _deps.chat.localConversation(conversationId);
    if (!mounted) return;
    state = state.copyWith(messages: messages, conversation: conversation);
  }

  Future<void> refresh() async {
    await _sync();
    onConversationsChanged?.call();
  }

  Future<void> loadOlder() async {
    if (state.loadingOlder || !state.hasMore || state.messages.isEmpty) return;
    state = state.copyWith(loadingOlder: true);
    try {
      final before = state.messages.first.createdAt;
      final older = await _deps.chat.fetchOlderMessages(
        conversationId,
        before: before,
        limit: 40,
      );
      if (!mounted) return;
      _limit += older.length;
      state = state.copyWith(hasMore: older.length >= 40, loadingOlder: false);
      await _reloadLocal();
    } catch (error) {
      if (!mounted) return;
      state = state.copyWith(loadingOlder: false, error: mapError(error));
    }
  }

  Future<void> sendText(String text, {ChatMessage? replyTo}) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    final conversation = await _requireConversation();
    _clearDraft();
    await _deps.chat.sendText(
      conversationId: conversationId,
      peerId: conversation.peerId,
      body: trimmed,
      replyToId: replyTo?.id,
      replyPreview: replyTo?.preview,
    );
    await _reloadLocal();
    onConversationsChanged?.call();
  }

  Future<void> sendAttachment(
    AttachmentDraft draft, {
    String caption = '',
    ChatMessage? replyTo,
  }) async {
    final conversation = await _requireConversation();
    state = state.copyWith(sendingAttachment: true);
    try {
      await _deps.chat.sendAttachment(
        conversationId: conversationId,
        peerId: conversation.peerId,
        draft: draft,
        caption: caption,
        replyToId: replyTo?.id,
        replyPreview: replyTo?.preview,
      );
      _clearDraft();
      await _reloadLocal();
      onConversationsChanged?.call();
    } finally {
      if (mounted) state = state.copyWith(sendingAttachment: false);
    }
  }

  Future<void> retry(ChatMessage message) async {
    await _deps.chat.retrySend(message);
    await _reloadLocal();
    onConversationsChanged?.call();
  }

  Future<void> editMessage(ChatMessage message, String body) async {
    if (body.trim().isEmpty) return;
    await _deps.chat.editMessage(message, body);
    await _reloadLocal();
    onConversationsChanged?.call();
  }

  Future<void> deleteForEveryone(ChatMessage message) async {
    await _deps.chat.deleteForEveryone(message);
    await _reloadLocal();
    onConversationsChanged?.call();
  }

  Future<void> deleteLocally(ChatMessage message) async {
    await _deps.chat.deleteLocally(message);
    await _reloadLocal();
    onConversationsChanged?.call();
  }

  Future<void> markRead() async {
    try {
      await _deps.chat.markRead(conversationId);
      if (!mounted) return;
      await _reloadLocal();
      unawaited(_broadcast('read', const {}));
      onConversationsChanged?.call();
    } catch (_) {
      // Reading receipts is best-effort; the next sync retries.
    }
  }

  Future<void> setPinned(bool pinned) async {
    await _deps.chat.setPinned(conversationId, pinned);
    await _reloadLocal();
    onConversationsChanged?.call();
  }

  Future<void> setMuted(bool muted) async {
    await _deps.chat.setMuted(conversationId, muted);
    await _reloadLocal();
    onConversationsChanged?.call();
  }

  Future<void> clearHistory() async {
    await _deps.chat.clearLocalHistory(conversationId);
    _limit = 60;
    await _reloadLocal();
    onConversationsChanged?.call();
  }

  // --- Drafts ---------------------------------------------------------------

  void setDraft(String text) {
    if (state.draft == text) return;
    state = state.copyWith(draft: text);
    _draftTimer?.cancel();
    _draftTimer = Timer(const Duration(milliseconds: 600), () {
      unawaited(_persistDraft(text));
    });
  }

  Future<void> _persistDraft(String text) async {
    try {
      await _deps.db.saveDraft(conversationId, text);
    } catch (_) {}
  }

  void _clearDraft() {
    _draftTimer?.cancel();
    state = state.copyWith(draft: '');
    unawaited(_deps.db.deleteDraft(conversationId));
  }

  // --- Typing and presence --------------------------------------------------

  void notifyTyping() {
    if (state.conversation == null) return;
    final now = DateTime.now();
    final last = _lastTypingSent;
    if (last != null && now.difference(last) < const Duration(seconds: 3)) {
      return;
    }
    _lastTypingSent = now;
    final me = _me;
    if (me == null) return;
    unawaited(_broadcast('typing', {'user_id': me}));
  }

  void _openChannel() {
    if (_channel != null) return;
    final me = _me;
    if (me == null) return;
    final channel = _deps.client.channel(
      'conversation:$conversationId',
      opts: const RealtimeChannelConfig(
        private: true,
        self: true,
        enabled: true,
      ),
    );

    channel
        .onBroadcast(
          event: 'typing',
          callback: (payload) {
            final data = _payloadOf(payload);
            if (data['user_id'] == me) return;
            _onPeerTyping();
          },
        )
        .onBroadcast(
          event: 'read',
          callback: (payload) {
            final data = _payloadOf(payload);
            if (data['user_id'] == me) return;
            unawaited(_reloadLocal());
          },
        )
        .onPresenceSync((_) => _syncPresence())
        .onPresenceJoin((_) => _syncPresence())
        .onPresenceLeave((_) => _syncPresence())
        .subscribe((status, error) async {
          if (status == RealtimeSubscribeStatus.subscribed) {
            try {
              await channel.track({
                'user_id': me,
                'online_at': DateTime.now().toUtc().toIso8601String(),
              });
            } catch (_) {}
            _syncPresence();
          }
        });

    _channel = channel;
  }

  Map<String, dynamic> _payloadOf(Map<String, dynamic> payload) {
    final inner = payload['payload'];
    if (inner is Map) return Map<String, dynamic>.from(inner);
    return payload;
  }

  void _onPeerTyping() {
    if (!state.peerTyping) state = state.copyWith(peerTyping: true);
    _typingTimer?.cancel();
    _typingTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) state = state.copyWith(peerTyping: false);
    });
  }

  void _syncPresence() {
    final channel = _channel;
    final peerId = state.conversation?.peerId;
    if (channel == null || peerId == null) return;
    var online = false;
    for (final entry in channel.presenceState()) {
      for (final presence in entry.presences) {
        if (presence.payload['user_id'] == peerId) online = true;
      }
    }
    if (online != state.peerOnline) state = state.copyWith(peerOnline: online);
  }

  Future<void> _broadcast(String event, Map<String, dynamic> payload) async {
    final channel = _channel;
    if (channel == null) return;
    try {
      await channel.sendBroadcastMessage(event: event, payload: payload);
    } catch (_) {}
  }

  void _onEvent(RealtimeEvent event) {
    switch (event.kind) {
      case RealtimeKind.receiptCreated:
        unawaited(_applyReceipt(event.record));
        break;
      case RealtimeKind.messageCreated:
      case RealtimeKind.messageUpdated:
        if (event.conversationId == conversationId) _scheduleSync();
        break;
      case RealtimeKind.callChanged:
        break;
      case RealtimeKind.reactionChanged:
        unawaited(_syncReactions());
        break;
    }
  }

  Future<void> _applyReceipt(Map<String, dynamic> record) async {
    await _deps.chat.applyReceipt(record);
    if (!mounted) return;
    await _reloadLocal();
  }

  void _scheduleSync() {
    _syncDebounce?.cancel();
    _syncDebounce = Timer(const Duration(milliseconds: 300), () {
      unawaited(_sync());
    });
  }

  Future<ConversationSummary> _requireConversation() async {
    final existing = state.conversation;
    if (existing != null) return existing;
    final loaded = await _deps.chat.localConversation(conversationId);
    if (loaded == null) {
      throw const AppError('CHAT_NOT_FOUND', 'Percakapan tidak ditemukan.');
    }
    if (mounted) state = state.copyWith(conversation: loaded);
    return loaded;
  }

  void dismissError() {
    if (state.error == null) return;
    state = state.copyWith(clearError: true);
  }

  @override
  void dispose() {
    _syncDebounce?.cancel();
    _typingTimer?.cancel();
    if (_draftTimer?.isActive ?? false) {
      unawaited(_deps.db.saveDraft(conversationId, state.draft));
    }
    _draftTimer?.cancel();
    unawaited(_subscription?.cancel());
    final channel = _channel;
    _channel = null;
    if (channel != null) unawaited(_deps.client.removeChannel(channel));
    super.dispose();
  }
}

final chatControllerProvider = StateNotifierProvider.autoDispose
    .family<ChatController, ChatState, String>((ref, conversationId) {
      final deps = ref.watch(depsProvider);
      return ChatController(
        deps: deps,
        conversationId: conversationId,
        onConversationsChanged: () {
          try {
            ref.read(chatsControllerProvider.notifier).refreshLocal();
          } catch (_) {}
        },
      );
    });
