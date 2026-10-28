import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite_sqlcipher/sqflite.dart';

import '../models/call_record.dart';
import '../models/conversation.dart';
import '../models/message.dart';
import '../models/profile.dart';

/// SQLCipher-encrypted local database. It stores message ciphertext, decrypted
/// presentation cache, the Signal ratchet state and the durable outbox.
class LocalDatabase {
  LocalDatabase._(this._db);

  final Database _db;
  static const int schemaVersion = 1;

  static Future<LocalDatabase> open(String password) async {
    final dir = await getDatabasesPath();
    final path = p.join(dir, 'adoetz_chat.db');
    final db = await openDatabase(
      path,
      password: password,
      version: schemaVersion,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: _create,
      onUpgrade: _upgrade,
    );
    return LocalDatabase._(db);
  }

  Future<void> close() => _db.close();

  static Future<void> _create(Database db, int version) async {
    await db.execute('''
      CREATE TABLE kv (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE profiles (
        user_id TEXT PRIMARY KEY,
        username TEXT NOT NULL,
        display_name TEXT NOT NULL,
        avatar_path TEXT,
        bio TEXT,
        discoverable INTEGER NOT NULL DEFAULT 1,
        role TEXT NOT NULL DEFAULT 'user',
        status TEXT NOT NULL DEFAULT 'active',
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE conversations (
        id TEXT PRIMARY KEY,
        peer_id TEXT NOT NULL,
        peer_username TEXT NOT NULL,
        peer_display_name TEXT NOT NULL,
        peer_avatar_path TEXT,
        last_message_id TEXT,
        last_message_text TEXT,
        last_message_at TEXT,
        unread_count INTEGER NOT NULL DEFAULT 0,
        pinned INTEGER NOT NULL DEFAULT 0,
        muted INTEGER NOT NULL DEFAULT 0,
        peer_identity_changed INTEGER NOT NULL DEFAULT 0,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX conversations_peer_idx ON conversations(peer_id)',
    );
    await db.execute('''
      CREATE TABLE messages (
        id TEXT PRIMARY KEY,
        client_message_id TEXT NOT NULL,
        conversation_id TEXT NOT NULL,
        sender_id TEXT NOT NULL,
        created_at TEXT NOT NULL,
        kind TEXT NOT NULL,
        status TEXT NOT NULL,
        ciphertext TEXT NOT NULL DEFAULT '',
        protocol_version INTEGER NOT NULL DEFAULT 3,
        envelope TEXT,
        reply_to_id TEXT,
        reply_preview TEXT,
        reactions TEXT NOT NULL DEFAULT '{}',
        edited_at TEXT,
        deleted_at TEXT,
        error_code TEXT,
        is_local_only INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute(
      'CREATE UNIQUE INDEX messages_client_idx ON messages(client_message_id)',
    );
    await db.execute(
      'CREATE INDEX messages_conversation_idx ON messages(conversation_id, created_at)',
    );
    await db.execute('''
      CREATE TABLE outbox (
        client_message_id TEXT PRIMARY KEY,
        conversation_id TEXT NOT NULL,
        payload TEXT NOT NULL,
        attempts INTEGER NOT NULL DEFAULT 0,
        next_attempt_at TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE drafts (
        conversation_id TEXT PRIMARY KEY,
        text TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE call_logs (
        id TEXT PRIMARY KEY,
        peer_id TEXT NOT NULL,
        peer_name TEXT NOT NULL,
        peer_username TEXT NOT NULL,
        peer_avatar_path TEXT,
        type TEXT NOT NULL,
        direction TEXT NOT NULL,
        status TEXT NOT NULL,
        started_at TEXT NOT NULL,
        ended_at TEXT,
        duration_seconds INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute(
      'CREATE INDEX call_logs_started_idx ON call_logs(started_at DESC)',
    );
    await db.execute('''
      CREATE TABLE peer_fingerprints (
        user_id TEXT PRIMARY KEY,
        fingerprint TEXT NOT NULL,
        verified INTEGER NOT NULL DEFAULT 0,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
  }

  static Future<void> _upgrade(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    // Transactional migrations land here. v1 is the initial schema.
  }

  // ---------------------------------------------------------------------------
  // Generic key/value (Signal records, cursors, flags)
  // ---------------------------------------------------------------------------

  Future<String?> kvGet(String key) async {
    final rows = await _db.query(
      'kv',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['value'] as String;
  }

  Future<void> kvSet(String key, String value) async {
    await _db.insert('kv', {
      'key': key,
      'value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> kvDelete(String key) async {
    await _db.delete('kv', where: 'key = ?', whereArgs: [key]);
  }

  Future<List<MapEntry<String, String>>> kvList(String prefix) async {
    final rows = await _db.query(
      'kv',
      where: 'key LIKE ?',
      whereArgs: ['$prefix%'],
    );
    return rows
        .map((row) => MapEntry(row['key'] as String, row['value'] as String))
        .toList(growable: false);
  }

  // ---------------------------------------------------------------------------
  // Profiles
  // ---------------------------------------------------------------------------

  Future<void> upsertProfile(Profile profile) async {
    await _db.insert('profiles', {
      'user_id': profile.userId,
      'username': profile.username,
      'display_name': profile.displayName,
      'avatar_path': profile.avatarPath,
      'bio': profile.bio,
      'discoverable': profile.discoverable ? 1 : 0,
      'role': profile.role.name,
      'status': profile.status.name,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Profile?> getProfile(String userId) async {
    final rows = await _db.query(
      'profiles',
      where: 'user_id = ?',
      whereArgs: [userId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    return Profile(
      userId: row['user_id'] as String,
      username: row['username'] as String,
      displayName: row['display_name'] as String,
      avatarPath: row['avatar_path'] as String?,
      bio: row['bio'] as String? ?? '',
      discoverable: (row['discoverable'] as int? ?? 1) == 1,
      role: accountRoleFromWire(row['role'] as String?),
      status: accountStatusFromWire(row['status'] as String?),
    );
  }

  // ---------------------------------------------------------------------------
  // Conversations
  // ---------------------------------------------------------------------------

  Future<void> upsertConversations(List<ConversationSummary> items) async {
    final batch = _db.batch();
    for (final item in items) {
      final existing = await _db.query(
        'conversations',
        columns: ['last_message_text', 'last_message_at'],
        where: 'id = ?',
        whereArgs: [item.id],
        limit: 1,
      );
      final existingText = existing.isEmpty
          ? null
          : existing.first['last_message_text'] as String?;
      final existingAt = existing.isEmpty
          ? null
          : existing.first['last_message_at'] as String?;
      final remoteAt = item.lastMessageAt?.toUtc().toIso8601String();
      final useRemoteText =
          item.lastMessagePreview?.isNotEmpty == true || existingText == null;
      final useRemoteAt =
          remoteAt != null &&
          (existingAt == null || remoteAt.compareTo(existingAt) >= 0);

      batch.insert('conversations', {
        'id': item.id,
        'peer_id': item.peerId,
        'peer_username': item.peerUsername,
        'peer_display_name': item.peerDisplayName,
        'peer_avatar_path': item.peerAvatarPath,
        'last_message_id': item.lastMessageId,
        'last_message_text': useRemoteText
            ? item.lastMessagePreview
            : existingText,
        'last_message_at': useRemoteAt ? remoteAt : existingAt,
        'unread_count': item.unreadCount,
        'pinned': item.pinned ? 1 : 0,
        'muted': item.muted ? 1 : 0,
        'peer_identity_changed': item.peerIdentityChanged ? 1 : 0,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<List<ConversationSummary>> getConversations() async {
    final rows = await _db.query(
      'conversations',
      orderBy: 'pinned DESC, last_message_at DESC, updated_at DESC',
    );
    return rows.map(_conversationFromRow).toList(growable: false);
  }

  Future<ConversationSummary?> getConversation(String id) async {
    final rows = await _db.query(
      'conversations',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _conversationFromRow(rows.first);
  }

  Future<void> setConversationPreview({
    required String conversationId,
    required String messageId,
    required String preview,
    required DateTime at,
  }) async {
    await _db.update(
      'conversations',
      {
        'last_message_id': messageId,
        'last_message_text': preview,
        'last_message_at': at.toUtc().toIso8601String(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [conversationId],
    );
  }

  Future<void> setConversationFlags(
    String conversationId, {
    bool? pinned,
    bool? muted,
  }) async {
    await _db.update(
      'conversations',
      {
        if (pinned != null) 'pinned': pinned ? 1 : 0,
        if (muted != null) 'muted': muted ? 1 : 0,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [conversationId],
    );
  }

  Future<void> setUnread(String conversationId, int count) async {
    await _db.update(
      'conversations',
      {'unread_count': count},
      where: 'id = ?',
      whereArgs: [conversationId],
    );
  }

  Future<void> setPeerIdentityChanged(String peerId, bool changed) async {
    await _db.update(
      'conversations',
      {'peer_identity_changed': changed ? 1 : 0},
      where: 'peer_id = ?',
      whereArgs: [peerId],
    );
  }

  Future<void> deleteConversation(String conversationId) async {
    await _db.transaction((txn) async {
      await txn.delete(
        'messages',
        where: 'conversation_id = ?',
        whereArgs: [conversationId],
      );
      await txn.delete(
        'drafts',
        where: 'conversation_id = ?',
        whereArgs: [conversationId],
      );
      await txn.delete(
        'conversations',
        where: 'id = ?',
        whereArgs: [conversationId],
      );
    });
  }

  ConversationSummary _conversationFromRow(Map<String, Object?> row) {
    return ConversationSummary(
      id: row['id'] as String,
      peerId: row['peer_id'] as String,
      peerUsername: row['peer_username'] as String,
      peerDisplayName: row['peer_display_name'] as String,
      peerAvatarPath: row['peer_avatar_path'] as String?,
      lastMessageId: row['last_message_id'] as String?,
      lastMessageAt: DateTime.tryParse(
        row['last_message_at'] as String? ?? '',
      )?.toLocal(),
      lastMessagePreview: row['last_message_text'] as String?,
      unreadCount: (row['unread_count'] as int?) ?? 0,
      pinned: (row['pinned'] as int? ?? 0) == 1,
      muted: (row['muted'] as int? ?? 0) == 1,
      peerIdentityChanged: (row['peer_identity_changed'] as int? ?? 0) == 1,
    );
  }

  // ---------------------------------------------------------------------------
  // Messages
  // ---------------------------------------------------------------------------

  Future<void> upsertMessage(ChatMessage message) async {
    await _db.insert(
      'messages',
      message.toLocalMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> upsertMessages(List<ChatMessage> messages) async {
    if (messages.isEmpty) return;
    final batch = _db.batch();
    for (final message in messages) {
      batch.insert(
        'messages',
        message.toLocalMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<void> replacePendingWithServer({
    required String clientMessageId,
    required ChatMessage serverMessage,
  }) async {
    await _db.transaction((txn) async {
      await txn.delete(
        'messages',
        where: 'client_message_id = ? AND is_local_only = 1',
        whereArgs: [clientMessageId],
      );
      await txn.insert(
        'messages',
        serverMessage.toLocalMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
  }

  Future<List<ChatMessage>> getMessages(
    String conversationId, {
    int limit = 40,
    DateTime? before,
  }) async {
    final rows = await _db.query(
      'messages',
      where: before == null
          ? 'conversation_id = ?'
          : 'conversation_id = ? AND created_at < ?',
      whereArgs: before == null
          ? [conversationId]
          : [conversationId, before.toUtc().toIso8601String()],
      orderBy: 'created_at DESC',
      limit: limit,
    );
    final result = rows.map(ChatMessage.fromLocalMap).toList();
    return result.reversed.toList(growable: false);
  }

  /// Local full-text-ish search over the decrypted envelope. Matches the
  /// message body, attachment names and the reply preview.
  Future<List<ChatMessage>> searchMessages(
    String conversationId,
    String query, {
    int limit = 100,
  }) async {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return const [];
    final rows = await _db.query(
      'messages',
      where: 'conversation_id = ? AND deleted_at IS NULL AND envelope LIKE ?',
      whereArgs: [conversationId, '%${query.trim()}%'],
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return rows
        .map(ChatMessage.fromLocalMap)
        .where((message) {
          final body = message.body.toLowerCase();
          if (body.contains(needle)) return true;
          if ((message.replyPreview ?? '').toLowerCase().contains(needle)) {
            return true;
          }
          return message.attachments.any(
            (meta) => meta.name.toLowerCase().contains(needle),
          );
        })
        .toList(growable: false);
  }

  Future<ChatMessage?> getMessageByClientId(String clientMessageId) async {
    final rows = await _db.query(
      'messages',
      where: 'client_message_id = ?',
      whereArgs: [clientMessageId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return ChatMessage.fromLocalMap(rows.first);
  }

  Future<ChatMessage?> getMessageById(String id) async {
    final rows = await _db.query(
      'messages',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return ChatMessage.fromLocalMap(rows.first);
  }

  Future<void> updateMessageStatus(
    String clientMessageId,
    MessageStatus status, {
    String? errorCode,
    String? ciphertext,
  }) async {
    await _db.update(
      'messages',
      {
        'status': status.name,
        'error_code': errorCode,
        if (ciphertext != null) 'ciphertext': ciphertext,
      },
      where: 'client_message_id = ?',
      whereArgs: [clientMessageId],
    );
  }

  Future<void> updateMessageStatusById(
    String messageId,
    MessageStatus status,
  ) async {
    await _db.update(
      'messages',
      {'status': status.name},
      where: 'id = ?',
      whereArgs: [messageId],
    );
  }

  Future<void> updateMessageEnvelope(
    String clientMessageId,
    MessageEnvelope envelope,
    MessageKind kind,
  ) async {
    await _db.update(
      'messages',
      {'envelope': envelope.encode(), 'kind': kind.name},
      where: 'client_message_id = ?',
      whereArgs: [clientMessageId],
    );
  }

  Future<void> applyReactions(
    String messageId,
    Map<String, List<String>> reactions,
  ) async {
    await _db.update(
      'messages',
      {'reactions': jsonEncode(reactions)},
      where: 'id = ?',
      whereArgs: [messageId],
    );
  }

  /// Drops cached reactions for a conversation before a full reconciliation,
  /// so reactions removed while this device was offline disappear too.
  Future<void> clearReactions(String conversationId) async {
    await _db.update(
      'messages',
      {'reactions': '{}'},
      where: "conversation_id = ? AND reactions <> '{}'",
      whereArgs: [conversationId],
    );
  }

  Future<void> markMessageDeleted(String messageId) async {
    await _db.update(
      'messages',
      {'deleted_at': DateTime.now().toUtc().toIso8601String()},
      where: 'id = ?',
      whereArgs: [messageId],
    );
  }

  Future<void> deleteMessageLocal(String messageId) async {
    await _db.delete('messages', where: 'id = ?', whereArgs: [messageId]);
  }

  Future<void> clearMessages(String conversationId) async {
    await _db.delete(
      'messages',
      where: 'conversation_id = ?',
      whereArgs: [conversationId],
    );
  }

  Future<int> messageCount() async {
    final result = await _db.rawQuery('SELECT COUNT(*) AS c FROM messages');
    return (result.first['c'] as int?) ?? 0;
  }

  // ---------------------------------------------------------------------------
  // Outbox
  // ---------------------------------------------------------------------------

  Future<void> enqueueOutbox({
    required String clientMessageId,
    required String conversationId,
    required String payload,
  }) async {
    final now = DateTime.now().toUtc();
    await _db.insert('outbox', {
      'client_message_id': clientMessageId,
      'conversation_id': conversationId,
      'payload': payload,
      'attempts': 0,
      'next_attempt_at': now.toIso8601String(),
      'created_at': now.toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, Object?>>> dueOutbox({int limit = 20}) async {
    final now = DateTime.now().toUtc().toIso8601String();
    return _db.query(
      'outbox',
      where: 'next_attempt_at <= ?',
      whereArgs: [now],
      orderBy: 'created_at ASC',
      limit: limit,
    );
  }

  Future<void> rescheduleOutbox(
    String clientMessageId, {
    required int attempts,
    required Duration delay,
  }) async {
    await _db.update(
      'outbox',
      {
        'attempts': attempts,
        'next_attempt_at': DateTime.now().toUtc().add(delay).toIso8601String(),
      },
      where: 'client_message_id = ?',
      whereArgs: [clientMessageId],
    );
  }

  Future<void> removeOutbox(String clientMessageId) async {
    await _db.delete(
      'outbox',
      where: 'client_message_id = ?',
      whereArgs: [clientMessageId],
    );
  }

  Future<int> outboxCount() async {
    final result = await _db.rawQuery('SELECT COUNT(*) AS c FROM outbox');
    return (result.first['c'] as int?) ?? 0;
  }

  // ---------------------------------------------------------------------------
  // Drafts
  // ---------------------------------------------------------------------------

  Future<void> saveDraft(String conversationId, String text) async {
    if (text.trim().isEmpty) {
      await deleteDraft(conversationId);
      return;
    }
    await _db.insert('drafts', {
      'conversation_id': conversationId,
      'text': text,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<String?> getDraft(String conversationId) async {
    final rows = await _db.query(
      'drafts',
      columns: ['text'],
      where: 'conversation_id = ?',
      whereArgs: [conversationId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['text'] as String?;
  }

  Future<void> deleteDraft(String conversationId) async {
    await _db.delete(
      'drafts',
      where: 'conversation_id = ?',
      whereArgs: [conversationId],
    );
  }

  // ---------------------------------------------------------------------------
  // Calls
  // ---------------------------------------------------------------------------

  Future<void> upsertCallLog(CallRecord record) async {
    await _db.insert(
      'call_logs',
      record.toLocalMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<CallRecord>> getCallLogs({int limit = 100}) async {
    final rows = await _db.query(
      'call_logs',
      orderBy: 'started_at DESC',
      limit: limit,
    );
    return rows.map(CallRecord.fromLocalMap).toList(growable: false);
  }

  Future<void> deleteCallLog(String id) async {
    await _db.delete('call_logs', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> clearCallLogs() async {
    await _db.delete('call_logs');
  }

  // ---------------------------------------------------------------------------
  // Peer identity fingerprints
  // ---------------------------------------------------------------------------

  Future<String?> getPeerFingerprint(String userId) async {
    final rows = await _db.query(
      'peer_fingerprints',
      where: 'user_id = ?',
      whereArgs: [userId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['fingerprint'] as String?;
  }

  /// Returns true when a previously known fingerprint changed.
  Future<bool> savePeerFingerprint(String userId, String fingerprint) async {
    final existing = await getPeerFingerprint(userId);
    final changed = existing != null && existing != fingerprint;
    await _db.insert('peer_fingerprints', {
      'user_id': userId,
      'fingerprint': fingerprint,
      'verified': existing == fingerprint ? 1 : 0,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    return changed;
  }

  Future<void> markPeerVerified(String userId) async {
    await _db.update(
      'peer_fingerprints',
      {'verified': 1},
      where: 'user_id = ?',
      whereArgs: [userId],
    );
  }

  Future<bool> isPeerVerified(String userId) async {
    final rows = await _db.query(
      'peer_fingerprints',
      columns: ['verified'],
      where: 'user_id = ?',
      whereArgs: [userId],
      limit: 1,
    );
    if (rows.isEmpty) return false;
    return (rows.first['verified'] as int? ?? 0) == 1;
  }

  // ---------------------------------------------------------------------------
  // Local settings
  // ---------------------------------------------------------------------------

  Future<String?> getSetting(String key) async {
    final rows = await _db.query(
      'settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['value'] as String?;
  }

  Future<void> setSetting(String key, String value) async {
    await _db.insert('settings', {
      'key': key,
      'value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Removes cached conversations/messages but keeps the E2EE ratchet state so
  /// signing back into the same account on this device keeps sessions working.
  Future<void> clearChatData() async {
    await _db.transaction((txn) async {
      await txn.delete('messages');
      await txn.delete('outbox');
      await txn.delete('drafts');
      await txn.delete('conversations');
      await txn.delete('call_logs');
    });
  }

  Future<void> clearAllUserData() async {
    await _db.transaction((txn) async {
      await txn.delete('messages');
      await txn.delete('conversations');
      await txn.delete('outbox');
      await txn.delete('drafts');
      await txn.delete('call_logs');
      await txn.delete('profiles');
      await txn.delete('peer_fingerprints');
      await txn.delete('kv');
    });
  }
}
