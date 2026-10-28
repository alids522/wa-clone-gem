import 'dart:convert';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../crypto/e2ee_service.dart';
import '../models/conversation.dart';
import '../models/message.dart';
import '../storage/local_database.dart';
import '../utils/app_error.dart';
import 'media_service.dart';
import 'profile_repository.dart';

class AttachmentDraft {
  const AttachmentDraft({
    required this.bytes,
    required this.mime,
    required this.name,
    this.durationMs,
    this.width,
    this.height,
  });

  final Uint8List bytes;
  final String mime;
  final String name;
  final int? durationMs;
  final int? width;
  final int? height;
}

class ChatRepository {
  ChatRepository({
    required SupabaseClient client,
    required LocalDatabase db,
    required E2eeService e2ee,
    required MediaService media,
    required ProfileRepository profiles,
  }) : _client = client,
       _db = db,
       _e2ee = e2ee,
       _media = media,
       _profiles = profiles;

  final SupabaseClient _client;
  final LocalDatabase _db;
  final E2eeService _e2ee;
  final MediaService _media;
  final ProfileRepository _profiles;

  String get _me => _client.auth.currentUser!.id;

  final Uuid _uuid = const Uuid();
  final Set<String> _decrypting = {};

  // ---------------------------------------------------------------------------
  // Conversations
  // ---------------------------------------------------------------------------

  Future<List<ConversationSummary>> localConversations() =>
      _db.getConversations();

  Future<ConversationSummary?> localConversation(String id) =>
      _db.getConversation(id);

  Future<List<ConversationSummary>> syncConversations() async {
    final response = await _client.rpc('get_my_conversations');
    final rows = (response as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(ConversationSummary.fromMap)
        .toList(growable: false);

    final flagged = <String>{};
    for (final row in rows) {
      final local = await _db.getConversation(row.id);
      if (local?.peerIdentityChanged == true) flagged.add(row.peerId);
    }
    await _db.upsertConversations(rows);
    for (final peerId in flagged) {
      await _db.setPeerIdentityChanged(peerId, true);
    }

    // Decrypt only the newest message per conversation, and only once.
    final ids = rows
        .map((row) => row.lastMessageId)
        .whereType<String>()
        .toSet()
        .toList(growable: false);
    if (ids.isNotEmpty) {
      try {
        final messageRows = await _client
            .from('messages')
            .select()
            .inFilter('id', ids);
        for (final raw in messageRows) {
          final map = (raw as Map).cast<String, dynamic>();
          final message = await _upsertFromServer(map);
          if (message != null && message.id == map['id']) {
            await _refreshConversationPreview(message);
          }
        }
      } catch (_) {
        // Previews fall back to local cache; message sync will retry.
      }
    }

    return _db.getConversations();
  }

  Future<ConversationSummary> openConversation(String peerId) async {
    final response = await _client.rpc(
      'get_or_create_direct_conversation',
      params: {'p_peer_id': peerId},
    );
    final conversationId = response as String;
    var summary = await _db.getConversation(conversationId);
    if (summary == null) {
      final peer = await _profiles.peerProfile(peerId);
      summary = ConversationSummary(
        id: conversationId,
        peerId: peerId,
        peerUsername: peer.username,
        peerDisplayName: peer.displayName,
        peerAvatarPath: peer.avatarPath,
      );
      await _db.upsertConversations([summary]);
      summary = await _db.getConversation(conversationId) ?? summary;
    }
    return summary;
  }

  // ---------------------------------------------------------------------------
  // Messages
  // ---------------------------------------------------------------------------

  Future<List<ChatMessage>> loadLocalMessages(
    String conversationId, {
    int limit = 40,
    DateTime? before,
  }) => _db.getMessages(conversationId, limit: limit, before: before);

  Future<List<ChatMessage>> syncMessages(String conversationId) async {
    final latest = await _db.getMessages(conversationId, limit: 1);
    final newestAt = latest.isEmpty ? null : latest.last.createdAt;

    var query = _client
        .from('messages')
        .select()
        .eq('conversation_id', conversationId);

    if (newestAt != null) {
      query = query.gt('created_at', newestAt.toUtc().toIso8601String());
    }

    var rows = await query.order('created_at', ascending: true).limit(100);
    if (newestAt == null && rows.length == 100) {
      final tail = await _client
          .from('messages')
          .select()
          .eq('conversation_id', conversationId)
          .order('created_at', ascending: false)
          .limit(100);
      rows = tail.reversed.toList(growable: false);
    }

    ChatMessage? last;
    final delivered = <String>[];
    for (final raw in rows) {
      final map = (raw as Map).cast<String, dynamic>();
      final message = await _upsertFromServer(map);
      if (message == null) continue;
      last = message;
      if (message.senderId != _me &&
          map['deleted_at'] == null &&
          message.status != MessageStatus.read) {
        delivered.add(message.id);
      }
    }
    if (last != null) {
      await _refreshConversationPreview(last);
    }
    if (delivered.isNotEmpty) {
      await _sendReceipts(delivered, 'delivered');
    }

    final result = await _db.getMessages(conversationId, limit: 60);
    return result;
  }

  /// Pages backwards through history. Server rows are decrypted and cached, so
  /// repeated scrolls never hit the network for messages already stored.
  Future<List<ChatMessage>> fetchOlderMessages(
    String conversationId, {
    required DateTime before,
    int limit = 40,
  }) async {
    final cached = await _db.getMessages(
      conversationId,
      limit: limit,
      before: before,
    );
    if (cached.length >= limit) return cached;

    final rows = await _client
        .from('messages')
        .select()
        .eq('conversation_id', conversationId)
        .lt('created_at', before.toUtc().toIso8601String())
        .order('created_at', ascending: false)
        .limit(limit);

    for (final raw in rows.reversed) {
      await _upsertFromServer((raw as Map).cast<String, dynamic>());
    }
    return _db.getMessages(conversationId, limit: limit, before: before);
  }

  /// Searches messages already decrypted and cached on this device. Nothing
  /// leaves the phone: the server never sees the query or the plaintext.
  Future<List<ChatMessage>> searchMessages(
    String conversationId,
    String query,
  ) => _db.searchMessages(conversationId, query);

  /// Pulls the reaction map for a conversation and caches it per message.
  Future<void> syncReactions(String conversationId) async {
    final rows = await _client.rpc(
      'get_conversation_reactions',
      params: {'p_conversation_id': conversationId},
    );
    if (rows is! List) return;
    final grouped = <String, Map<String, List<String>>>{};
    for (final row in rows) {
      if (row is! Map) continue;
      final messageId = row['message_id'] as String?;
      final emoji = row['emoji'] as String?;
      final userId = row['user_id'] as String?;
      if (messageId == null || emoji == null || userId == null) continue;
      grouped
          .putIfAbsent(messageId, () => {})
          .putIfAbsent(emoji, () => [])
          .add(userId);
    }
    await _db.clearReactions(conversationId);
    for (final entry in grouped.entries) {
      await _db.applyReactions(entry.key, entry.value);
    }
  }

  /// Toggles [emoji] for the signed-in user and returns the new map.
  Future<Map<String, List<String>>> setReaction({
    required String messageId,
    required String emoji,
  }) async {
    final result = await _client.rpc(
      'set_message_reaction',
      params: {'p_message_id': messageId, 'p_emoji': emoji},
    );
    final reactions = <String, List<String>>{};
    if (result is Map) {
      for (final entry in result.entries) {
        final value = entry.value;
        if (value is List) {
          reactions[entry.key.toString()] = value
              .map((item) => item.toString())
              .toList(growable: false);
        }
      }
    }
    await _db.applyReactions(messageId, reactions);
    return reactions;
  }

  /// Files a report. Message content is only sent when the reporter ticked the
  /// consent box; it is decrypted locally, never fetched from the server.
  Future<void> submitReport({
    required String reportedUserId,
    required String reason,
    String? details,
    String? messageId,
    String? sharedContent,
    bool shareContent = false,
  }) async {
    await _client.rpc(
      'submit_report',
      params: {
        'p_reported_user_id': reportedUserId,
        'p_reason': reason,
        'p_details': details?.trim(),
        'p_message_id': messageId,
        'p_shared_content': shareContent ? sharedContent : null,
        'p_share_content': shareContent && messageId != null,
      },
    );
  }

  Future<ChatMessage?> refreshMessage(String messageId) async {
    final rows = await _client
        .from('messages')
        .select()
        .eq('id', messageId)
        .limit(1);
    if (rows.isEmpty) return null;
    return _upsertFromServer((rows.first as Map).cast<String, dynamic>());
  }

  Future<ChatMessage?> _upsertFromServer(Map<String, dynamic> row) async {
    final id = row['id'] as String?;
    if (id == null) return null;
    final existing = await _db.getMessageById(id);
    final senderId = row['sender_id'] as String;

    if (existing != null) {
      if (row['deleted_at'] != null && existing.deletedAt == null) {
        await _db.markMessageDeleted(id);
        final updated = await _db.getMessageById(id);
        return updated;
      }
      final edited = row['edited_at'] != null;
      if (edited &&
          senderId != _me &&
          row['ciphertext'] != existing.ciphertext &&
          !_decrypting.contains(id)) {
        _decrypting.add(id);
        try {
          final envelope = await _e2ee.decrypt(
            senderId: senderId,
            ciphertext: row['ciphertext'] as String,
          );
          final message = ChatMessage.fromServerMap(
            row,
            envelope: envelope,
            status: existing.status,
          ).copyWith(editedAt: DateTime.now());
          await _db.upsertMessage(message);
          return message;
        } catch (_) {
          return existing;
        } finally {
          _decrypting.remove(id);
        }
      }
      return existing;
    }

    if (senderId == _me) {
      // Own messages are cached locally before sending. A missing row means the
      // local database was recreated; the ciphertext is not decryptable here.
      final message = ChatMessage.fromServerMap(
        row,
        status: MessageStatus.sent,
      );
      await _db.upsertMessage(message);
      return message;
    }

    if (_decrypting.contains(id)) return null;
    _decrypting.add(id);
    try {
      final envelope = await _e2ee.decrypt(
        senderId: senderId,
        ciphertext: row['ciphertext'] as String,
      );
      final message = ChatMessage.fromServerMap(
        row,
        envelope: envelope,
        status: MessageStatus.delivered,
      );
      await _db.upsertMessage(message);
      return message;
    } on DecryptionException {
      final message = ChatMessage.fromServerMap(
        row,
        status: MessageStatus.failed,
      ).copyWith(errorCode: 'DECRYPT_FAILED');
      await _db.upsertMessage(message);
      return message;
    } catch (_) {
      return null;
    } finally {
      _decrypting.remove(id);
    }
  }

  Future<void> _refreshConversationPreview(ChatMessage message) async {
    if (message.isDeleted) {
      await _db.setConversationPreview(
        conversationId: message.conversationId,
        messageId: message.id,
        preview: 'Pesan ini telah dihapus',
        at: message.createdAt,
      );
      return;
    }
    await _db.setConversationPreview(
      conversationId: message.conversationId,
      messageId: message.id,
      preview: message.preview,
      at: message.createdAt,
    );
  }

  Future<void> _sendReceipts(List<String> messageIds, String type) async {
    final rows = messageIds
        .map((id) => {'message_id': id, 'recipient_id': _me, 'type': type})
        .toList(growable: false);
    try {
      await _client
          .from('message_receipts')
          .upsert(rows, ignoreDuplicates: true);
    } catch (_) {
      // Receipts are best-effort; the next sync repeats them.
    }
  }

  Future<void> markRead(String conversationId) async {
    try {
      await _client.rpc(
        'mark_conversation_read',
        params: {'p_conversation_id': conversationId},
      );
      await _db.setUnread(conversationId, 0);
    } catch (error) {
      throw mapError(error);
    }
  }

  Future<void> applyReceipt(Map<String, dynamic> record) async {
    final messageId = record['message_id'] as String?;
    final type = record['type'] as String?;
    if (messageId == null || type == null) return;
    final message = await _db.getMessageById(messageId);
    if (message == null || message.senderId != _me) return;
    if (type == 'read') {
      await _db.updateMessageStatusById(messageId, MessageStatus.read);
    } else if (type == 'delivered' &&
        (message.status == MessageStatus.sent ||
            message.status == MessageStatus.delivered)) {
      await _db.updateMessageStatusById(messageId, MessageStatus.delivered);
    }
  }

  // ---------------------------------------------------------------------------
  // Sending (durable outbox)
  // ---------------------------------------------------------------------------

  Future<ChatMessage> sendText({
    required String conversationId,
    required String peerId,
    required String body,
    String? replyToId,
    String? replyPreview,
  }) async {
    final envelope = MessageEnvelope(
      body: body.trim(),
      replyToId: replyToId,
      replyPreview: replyPreview,
    );
    return _queueAndSend(
      conversationId: conversationId,
      peerId: peerId,
      kind: MessageKind.text,
      envelope: envelope,
    );
  }

  Future<ChatMessage> sendAttachment({
    required String conversationId,
    required String peerId,
    required AttachmentDraft draft,
    String caption = '',
    String? replyToId,
    String? replyPreview,
  }) async {
    final meta = await _media.uploadAttachment(
      conversationId: conversationId,
      bytes: draft.bytes,
      mime: draft.mime,
      name: draft.name,
      durationMs: draft.durationMs,
      width: draft.width,
      height: draft.height,
    );
    final kind = meta.fileKind;
    final envelope = MessageEnvelope(
      body: caption.trim(),
      replyToId: replyToId,
      replyPreview: replyPreview,
      attachments: [meta],
    );
    return _queueAndSend(
      conversationId: conversationId,
      peerId: peerId,
      kind: kind,
      envelope: envelope,
    );
  }

  Future<ChatMessage> _queueAndSend({
    required String conversationId,
    required String peerId,
    required MessageKind kind,
    required MessageEnvelope envelope,
  }) async {
    final clientId = _uuid.v4();
    final message = ChatMessage(
      id: clientId,
      clientMessageId: clientId,
      conversationId: conversationId,
      senderId: _me,
      createdAt: DateTime.now(),
      kind: kind,
      status: MessageStatus.queued,
      envelope: envelope,
      replyToId: envelope.replyToId,
      replyPreview: envelope.replyPreview,
      isLocalOnly: true,
    );
    await _db.upsertMessage(message);
    await _db.setConversationPreview(
      conversationId: conversationId,
      messageId: clientId,
      preview: message.preview,
      at: message.createdAt,
    );
    await _db.enqueueOutbox(
      clientMessageId: clientId,
      conversationId: conversationId,
      payload: jsonEncode({
        'peer_id': peerId,
        'envelope': envelope.toJson(),
        'kind': kind.wire,
        'protocol_version': 3,
      }),
    );
    await flushOutbox();
    return (await _db.getMessageByClientId(clientId)) ?? message;
  }

  Future<void> flushOutbox() async {
    final rows = await _db.dueOutbox();
    IdentityChangedException? identityError;
    for (final row in rows) {
      final clientId = row['client_message_id'] as String;
      final conversationId = row['conversation_id'] as String;
      final message = await _db.getMessageByClientId(clientId);
      if (message == null) {
        await _db.removeOutbox(clientId);
        continue;
      }
      final payload =
          jsonDecode(row['payload'] as String) as Map<String, dynamic>;
      final peerId = payload['peer_id'] as String? ?? '';
      if (peerId.isEmpty) {
        await _db.removeOutbox(clientId);
        continue;
      }
      final envelope = MessageEnvelope.fromJson(
        (payload['envelope'] as Map).cast<String, dynamic>(),
      );
      final kind = MessageKindX.fromWire(payload['kind'] as String?);
      final protocolVersion =
          (payload['protocol_version'] as num?)?.toInt() ?? 3;

      try {
        await _db.updateMessageStatus(clientId, MessageStatus.encrypting);
        final cipher = await _e2ee.encrypt(
          conversationId: conversationId,
          peerId: peerId,
          envelope: envelope,
        );
        await _db.updateMessageStatus(
          clientId,
          MessageStatus.sending,
          ciphertext: cipher.ciphertext,
        );

        final response = await _client.rpc(
          'send_message',
          params: {
            'p_conversation_id': conversationId,
            'p_client_message_id': clientId,
            'p_ciphertext': cipher.ciphertext,
            'p_protocol_version': protocolVersion,
            'p_message_type': kind.wire,
          },
        );
        final result = (response as Map).cast<String, dynamic>();
        final serverRow = (result['message'] as Map).cast<String, dynamic>();

        final serverMessage = ChatMessage.fromServerMap(
          serverRow,
          envelope: envelope,
          status: MessageStatus.sent,
        );
        await _db.replacePendingWithServer(
          clientMessageId: clientId,
          serverMessage: serverMessage,
        );
        await _db.removeOutbox(clientId);
        await _refreshConversationPreview(serverMessage);
      } on IdentityChangedException catch (error) {
        await _db.updateMessageStatus(
          clientId,
          MessageStatus.failed,
          errorCode: 'IDENTITY_CHANGED',
        );
        await _db.removeOutbox(clientId);
        await _db.setPeerIdentityChanged(peerId, true);
        identityError = error;
      } catch (error) {
        final appError = mapError(error);
        final attempts = ((row['attempts'] as int?) ?? 0) + 1;
        if (appError.retryable && attempts < 8) {
          await _db.updateMessageStatus(
            clientId,
            MessageStatus.queued,
            errorCode: appError.code,
          );
          await _db.rescheduleOutbox(
            clientId,
            attempts: attempts,
            delay: Duration(seconds: _backoffSeconds(attempts)),
          );
        } else {
          await _db.updateMessageStatus(
            clientId,
            MessageStatus.failed,
            errorCode: appError.code,
          );
          await _db.removeOutbox(clientId);
        }
      }
    }
    if (identityError != null) throw identityError;
  }

  int _backoffSeconds(int attempts) {
    final seconds = 5 * (1 << (attempts - 1).clamp(0, 6));
    return seconds > 300 ? 300 : seconds;
  }

  Future<ChatMessage> retrySend(ChatMessage message) async {
    final conversation = await _db.getConversation(message.conversationId);
    if (conversation == null || message.envelope == null) {
      throw const AppError('RETRY_FAILED', 'Pesan tidak dapat dikirim ulang.');
    }
    await _db.updateMessageStatus(
      message.clientMessageId,
      MessageStatus.queued,
      errorCode: '',
    );
    await _db.enqueueOutbox(
      clientMessageId: message.clientMessageId,
      conversationId: message.conversationId,
      payload: jsonEncode({
        'peer_id': conversation.peerId,
        'envelope': message.envelope!.toJson(),
        'kind': message.kind.wire,
        'protocol_version': message.protocolVersion,
      }),
    );
    await flushOutbox();
    return (await _db.getMessageByClientId(message.clientMessageId)) ?? message;
  }

  // ---------------------------------------------------------------------------
  // Mutations
  // ---------------------------------------------------------------------------

  Future<ChatMessage> editMessage(ChatMessage message, String newBody) async {
    final envelope = MessageEnvelope(
      body: newBody.trim(),
      replyToId: message.replyToId,
      replyPreview: message.replyPreview,
      attachments: message.attachments,
    );
    final conversation = await _db.getConversation(message.conversationId);
    if (conversation == null) {
      throw const AppError('EDIT_FAILED', 'Percakapan tidak ditemukan.');
    }
    try {
      final cipher = await _e2ee.encrypt(
        conversationId: message.conversationId,
        peerId: conversation.peerId,
        envelope: envelope,
      );
      final response = await _client.rpc(
        'edit_message',
        params: {'p_message_id': message.id, 'p_ciphertext': cipher.ciphertext},
      );
      final row = ((response as Map)['message'] as Map).cast<String, dynamic>();
      final updated = ChatMessage.fromServerMap(
        row,
        envelope: envelope,
        status: message.status,
      ).copyWith(editedAt: DateTime.now());
      await _db.upsertMessage(updated);
      await _refreshConversationPreview(updated);
      return updated;
    } catch (error) {
      if (error is IdentityChangedException) rethrow;
      throw mapError(error);
    }
  }

  Future<void> deleteForEveryone(ChatMessage message) async {
    try {
      await _client.rpc('delete_message', params: {'p_message_id': message.id});
      await _db.markMessageDeleted(message.id);
      final updated = await _db.getMessageById(message.id);
      if (updated != null) await _refreshConversationPreview(updated);
    } catch (error) {
      throw mapError(error);
    }
  }

  Future<void> deleteLocally(ChatMessage message) =>
      _db.deleteMessageLocal(message.id);

  Future<void> setPinned(String conversationId, bool pinned) async {
    try {
      await _client
          .from('conversation_members')
          .update({'pinned': pinned})
          .eq('conversation_id', conversationId)
          .eq('user_id', _me);
      await _db.setConversationFlags(conversationId, pinned: pinned);
    } catch (error) {
      throw mapError(error);
    }
  }

  Future<void> setMuted(String conversationId, bool muted) async {
    try {
      await _client
          .from('conversation_members')
          .update({'muted': muted})
          .eq('conversation_id', conversationId)
          .eq('user_id', _me);
      await _db.setConversationFlags(conversationId, muted: muted);
    } catch (error) {
      throw mapError(error);
    }
  }

  Future<void> clearLocalHistory(String conversationId) async {
    await _db.clearMessages(conversationId);
  }
}
