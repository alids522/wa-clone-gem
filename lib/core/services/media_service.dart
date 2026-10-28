import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../config/env.dart';
import '../crypto/media_crypto.dart';
import '../models/message.dart';
import '../utils/app_error.dart';

class MediaService {
  MediaService({required SupabaseClient client, required MediaCrypto crypto})
    : _client = client,
      _crypto = crypto;

  final SupabaseClient _client;
  final MediaCrypto _crypto;

  final Map<String, _SignedUrl> _avatarUrls = {};

  Future<AttachmentMeta> uploadAttachment({
    required String conversationId,
    required Uint8List bytes,
    required String mime,
    required String name,
    int? durationMs,
    int? width,
    int? height,
  }) async {
    final limit = mime.startsWith('image/')
        ? Env.imageMaxBytes
        : mime.startsWith('video/')
        ? Env.videoMaxBytes
        : Env.documentMaxBytes;
    if (bytes.length > limit) {
      throw AppError(
        'FILE_TOO_LARGE',
        'Ukuran berkas melebihi batas ${(limit / (1024 * 1024)).round()} MB.',
      );
    }

    final encrypted = await _crypto.encrypt(bytes);
    final path = '$conversationId/${const Uuid().v4()}.bin';

    final created = await _client.rpc(
      'create_attachment_object',
      params: {
        'p_conversation_id': conversationId,
        'p_storage_path': path,
        'p_size_bytes': encrypted.plainSize,
        'p_mime_hint': mime,
        'p_sha256': encrypted.sha256,
      },
    );
    final meta = (created as Map).cast<String, dynamic>();

    try {
      await _client.storage
          .from(Env.attachmentsBucket)
          .uploadBinary(
            path,
            encrypted.bytes,
            fileOptions: const FileOptions(
              contentType: 'application/octet-stream',
              upsert: false,
            ),
          );
    } catch (error) {
      // The staged object never became a message; drop the metadata row.
      try {
        await _client
            .from('attachment_objects')
            .delete()
            .eq('storage_path', path);
      } catch (_) {}
      throw mapError(error);
    }

    return AttachmentMeta(
      id: meta['id'] as String? ?? path,
      path: path,
      key: encrypted.key,
      nonce: encrypted.nonce,
      sha256: encrypted.sha256,
      mime: mime,
      name: name,
      size: encrypted.plainSize,
      durationMs: durationMs,
      width: width,
      height: height,
    );
  }

  Future<File> downloadAttachment(AttachmentMeta meta) async {
    final dir = await getTemporaryDirectory();
    final cacheDir = Directory(p.join(dir.path, 'adoetz_attachments'));
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }
    final safeName = _safeName(meta.name);
    final file = File(p.join(cacheDir.path, '${meta.sha256}_$safeName'));
    if (await file.exists() && await file.length() > 0) {
      return file;
    }

    final encrypted = await _client.storage
        .from(Env.attachmentsBucket)
        .download(meta.path);
    final clear = await _crypto.decrypt(
      ciphertext: encrypted,
      key: meta.key,
      expectedSha256: meta.sha256,
    );
    await file.writeAsBytes(clear, flush: true);
    return file;
  }

  Future<String> uploadAvatar({
    required String userId,
    required Uint8List bytes,
    required String mime,
  }) async {
    if (bytes.length > 5 * 1024 * 1024) {
      throw const AppError('FILE_TOO_LARGE', 'Foto profil maksimal 5 MB.');
    }
    final extension = switch (mime) {
      'image/png' => 'png',
      'image/webp' => 'webp',
      _ => 'jpg',
    };
    final path =
        '$userId/avatar_${DateTime.now().millisecondsSinceEpoch}.$extension';
    await _client.storage
        .from(Env.avatarsBucket)
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: mime, upsert: true),
        );
    return path;
  }

  Future<String?> avatarUrl(String? path) async {
    if (path == null || path.isEmpty) return null;
    final cached = _avatarUrls[path];
    if (cached != null && cached.expiresAt.isAfter(DateTime.now())) {
      return cached.url;
    }
    try {
      final url = await _client.storage
          .from(Env.avatarsBucket)
          .createSignedUrl(path, 3600);
      _avatarUrls[path] = _SignedUrl(
        url,
        DateTime.now().add(const Duration(minutes: 55)),
      );
      return url;
    } catch (_) {
      return null;
    }
  }

  Future<void> deleteAvatar(String? path) async {
    if (path == null || path.isEmpty) return;
    _avatarUrls.remove(path);
    try {
      await _client.storage.from(Env.avatarsBucket).remove([path]);
    } catch (_) {}
  }

  String _safeName(String name) {
    final cleaned = name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return cleaned.isEmpty ? 'file' : cleaned;
  }
}

class _SignedUrl {
  const _SignedUrl(this.url, this.expiresAt);

  final String url;
  final DateTime expiresAt;
}
