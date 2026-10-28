import 'dart:convert';

enum MessageStatus {
  queued,
  encrypting,
  sending,
  sent,
  delivered,
  read,
  failed,
}

enum MessageKind { text, image, video, document, audio, system }

extension MessageKindX on MessageKind {
  String get wire => name;

  static MessageKind fromWire(String? value) {
    return MessageKind.values.firstWhere(
      (e) => e.name == value,
      orElse: () => MessageKind.text,
    );
  }

  String get label {
    switch (this) {
      case MessageKind.image:
        return 'Foto';
      case MessageKind.video:
        return 'Video';
      case MessageKind.document:
        return 'Dokumen';
      case MessageKind.audio:
        return 'Pesan suara';
      case MessageKind.system:
        return 'Peristiwa';
      case MessageKind.text:
        return 'Pesan';
    }
  }

  String get fallbackPreview {
    switch (this) {
      case MessageKind.image:
        return '📷 Foto';
      case MessageKind.video:
        return '🎬 Video';
      case MessageKind.document:
        return '📄 Dokumen';
      case MessageKind.audio:
        return '🎙️ Pesan suara';
      case MessageKind.system:
        return '';
      case MessageKind.text:
        return 'Pesan baru';
    }
  }
}

/// Metadata for an encrypted attachment. The content key only ever exists
/// wrapped inside the E2EE message envelope.
class AttachmentMeta {
  const AttachmentMeta({
    required this.id,
    required this.path,
    required this.key,
    required this.nonce,
    required this.sha256,
    required this.mime,
    required this.name,
    required this.size,
    this.durationMs,
    this.width,
    this.height,
  });

  final String id;
  final String path;
  final String key;
  final String nonce;
  final String sha256;
  final String mime;
  final String name;
  final int size;
  final int? durationMs;
  final int? width;
  final int? height;

  Map<String, dynamic> toJson() => {
    'id': id,
    'path': path,
    'key': key,
    'nonce': nonce,
    'sha256': sha256,
    'mime': mime,
    'name': name,
    'size': size,
    if (durationMs != null) 'duration_ms': durationMs,
    if (width != null) 'width': width,
    if (height != null) 'height': height,
  };

  factory AttachmentMeta.fromJson(Map<String, dynamic> json) {
    return AttachmentMeta(
      id: json['id'] as String? ?? '',
      path: json['path'] as String? ?? '',
      key: json['key'] as String? ?? '',
      nonce: json['nonce'] as String? ?? '',
      sha256: json['sha256'] as String? ?? '',
      mime: json['mime'] as String? ?? 'application/octet-stream',
      name: json['name'] as String? ?? 'file',
      size: (json['size'] as num?)?.toInt() ?? 0,
      durationMs: (json['duration_ms'] as num?)?.toInt(),
      width: (json['width'] as num?)?.toInt(),
      height: (json['height'] as num?)?.toInt(),
    );
  }
}

/// Decrypted body of a message. This object is only persisted in the
/// SQLCipher-protected local database.
class MessageEnvelope {
  const MessageEnvelope({
    required this.body,
    this.replyToId,
    this.replyPreview,
    this.attachments = const [],
    this.control = const {},
  });

  final String body;
  final String? replyToId;
  final String? replyPreview;
  final List<AttachmentMeta> attachments;
  final Map<String, dynamic> control;

  Map<String, dynamic> toJson() => {
    'v': 1,
    'body': body,
    if (replyToId != null) 'reply_to': replyToId,
    if (replyPreview != null) 'reply_preview': replyPreview,
    if (attachments.isNotEmpty)
      'attachments': attachments.map((e) => e.toJson()).toList(),
    if (control.isNotEmpty) 'control': control,
  };

  String encode() => jsonEncode(toJson());

  static MessageEnvelope decode(String raw) {
    final map = jsonDecode(raw) as Map<String, dynamic>;
    final attachments = (map['attachments'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(AttachmentMeta.fromJson)
        .toList(growable: false);
    return MessageEnvelope(
      body: map['body'] as String? ?? '',
      replyToId: map['reply_to'] as String?,
      replyPreview: map['reply_preview'] as String?,
      attachments: attachments,
      control: (map['control'] as Map?)?.cast<String, dynamic>() ?? const {},
    );
  }

  factory MessageEnvelope.fromJson(Map<String, dynamic> json) =>
      decode(jsonEncode(json));

  static MessageEnvelope empty() => const MessageEnvelope(body: '');
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.clientMessageId,
    required this.conversationId,
    required this.senderId,
    required this.createdAt,
    required this.kind,
    required this.status,
    this.ciphertext = '',
    this.protocolVersion = 3,
    this.envelope,
    this.replyToId,
    this.replyPreview,
    this.reactions = const {},
    this.editedAt,
    this.deletedAt,
    this.errorCode,
    this.isLocalOnly = false,
  });

  final String id;
  final String clientMessageId;
  final String conversationId;
  final String senderId;
  final DateTime createdAt;
  final MessageKind kind;
  final MessageStatus status;
  final String ciphertext;
  final int protocolVersion;
  final MessageEnvelope? envelope;
  final String? replyToId;
  final String? replyPreview;
  final Map<String, List<String>> reactions;
  final DateTime? editedAt;
  final DateTime? deletedAt;
  final String? errorCode;
  final bool isLocalOnly;

  bool get isDeleted => deletedAt != null;
  String get body =>
      deletedAt != null ? 'Pesan ini telah dihapus' : (envelope?.body ?? '');
  List<AttachmentMeta> get attachments => envelope?.attachments ?? const [];
  bool get hasAttachments => attachments.isNotEmpty;
  AttachmentMeta? get firstAttachment =>
      attachments.isEmpty ? null : attachments.first;

  String get preview {
    if (isDeleted) return 'Pesan ini telah dihapus';
    if (body.trim().isNotEmpty) return body;
    if (hasAttachments) return firstAttachment!.fileKind.fallbackPreview;
    return kind.fallbackPreview;
  }

  ChatMessage copyWith({
    String? id,
    String? ciphertext,
    MessageStatus? status,
    MessageEnvelope? envelope,
    Map<String, List<String>>? reactions,
    DateTime? editedAt,
    DateTime? deletedAt,
    String? errorCode,
    bool? isLocalOnly,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      clientMessageId: clientMessageId,
      conversationId: conversationId,
      senderId: senderId,
      createdAt: createdAt,
      kind: kind,
      status: status ?? this.status,
      ciphertext: ciphertext ?? this.ciphertext,
      protocolVersion: protocolVersion,
      envelope: envelope ?? this.envelope,
      replyToId: replyToId ?? this.replyToId,
      replyPreview: replyPreview ?? this.replyPreview,
      reactions: reactions ?? this.reactions,
      editedAt: editedAt ?? this.editedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      errorCode: errorCode ?? this.errorCode,
      isLocalOnly: isLocalOnly ?? this.isLocalOnly,
    );
  }

  Map<String, dynamic> toLocalMap() => {
    'id': id,
    'client_message_id': clientMessageId,
    'conversation_id': conversationId,
    'sender_id': senderId,
    'created_at': createdAt.toUtc().toIso8601String(),
    'kind': kind.name,
    'status': status.name,
    'ciphertext': ciphertext,
    'protocol_version': protocolVersion,
    'envelope': envelope?.encode(),
    'reply_to_id': replyToId,
    'reply_preview': replyPreview,
    'reactions': jsonEncode(reactions),
    'edited_at': editedAt?.toUtc().toIso8601String(),
    'deleted_at': deletedAt?.toUtc().toIso8601String(),
    'error_code': errorCode,
    'is_local_only': isLocalOnly ? 1 : 0,
  };

  factory ChatMessage.fromLocalMap(Map<String, Object?> map) {
    final rawEnvelope = map['envelope'] as String?;
    MessageEnvelope? envelope;
    if (rawEnvelope != null && rawEnvelope.isNotEmpty) {
      try {
        envelope = MessageEnvelope.decode(rawEnvelope);
      } catch (_) {
        envelope = null;
      }
    }
    Map<String, List<String>> reactions = {};
    final rawReactions = map['reactions'] as String?;
    if (rawReactions != null && rawReactions.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawReactions) as Map<String, dynamic>;
        reactions = decoded.map(
          (key, value) =>
              MapEntry(key, (value as List<dynamic>).cast<String>()),
        );
      } catch (_) {
        reactions = {};
      }
    }
    return ChatMessage(
      id: map['id'] as String,
      clientMessageId: map['client_message_id'] as String,
      conversationId: map['conversation_id'] as String,
      senderId: map['sender_id'] as String,
      createdAt:
          DateTime.tryParse(map['created_at'] as String? ?? '')?.toLocal() ??
          DateTime.now(),
      kind: MessageKindX.fromWire(map['kind'] as String?),
      status: MessageStatus.values.firstWhere(
        (e) => e.name == map['status'],
        orElse: () => MessageStatus.failed,
      ),
      ciphertext: map['ciphertext'] as String? ?? '',
      protocolVersion: (map['protocol_version'] as num?)?.toInt() ?? 3,
      envelope: envelope,
      replyToId: map['reply_to_id'] as String?,
      replyPreview: map['reply_preview'] as String?,
      reactions: reactions,
      editedAt: DateTime.tryParse(map['edited_at'] as String? ?? '')?.toLocal(),
      deletedAt: DateTime.tryParse(
        map['deleted_at'] as String? ?? '',
      )?.toLocal(),
      errorCode: map['error_code'] as String?,
      isLocalOnly: (map['is_local_only'] as num?)?.toInt() == 1,
    );
  }

  /// Server rows only ever contain ciphertext.
  factory ChatMessage.fromServerMap(
    Map<String, dynamic> map, {
    MessageEnvelope? envelope,
    MessageStatus status = MessageStatus.sent,
  }) {
    return ChatMessage(
      id: map['id'] as String,
      clientMessageId: map['client_message_id'] as String? ?? '',
      conversationId: map['conversation_id'] as String,
      senderId: map['sender_id'] as String,
      createdAt:
          DateTime.tryParse(
            (map['server_created_at'] ?? map['created_at']) as String? ?? '',
          )?.toLocal() ??
          DateTime.now(),
      kind: MessageKindX.fromWire(
        (map['envelope_metadata'] as Map?)?['kind'] as String? ??
            map['message_type'] as String?,
      ),
      status: status,
      ciphertext: map['ciphertext'] as String? ?? '',
      protocolVersion: (map['protocol_version'] as num?)?.toInt() ?? 3,
      envelope: envelope,
      editedAt: DateTime.tryParse(map['edited_at'] as String? ?? '')?.toLocal(),
      deletedAt: DateTime.tryParse(
        map['deleted_at'] as String? ?? '',
      )?.toLocal(),
    );
  }
}

extension AttachmentKindX on AttachmentMeta {
  MessageKind get fileKind {
    if (mime.startsWith('image/')) return MessageKind.image;
    if (mime.startsWith('video/')) return MessageKind.video;
    if (mime.startsWith('audio/')) return MessageKind.audio;
    return MessageKind.document;
  }
}
