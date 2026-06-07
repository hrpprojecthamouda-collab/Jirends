/// AttachmentRepository — file metadata in public.attachments + bytes in the
/// private `event-attachments` Storage bucket (path `{event_id}/{name}`).
///
/// RLS gates both layers by event membership (the first path segment is the
/// event_id). The client adds no visibility logic. Uploads go bytes-first then
/// row; deletes go row-then-object (a leftover object is harmless and still
/// RLS-protected, whereas a leftover row pointing at nothing is worse).
library;

import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/error/failure.dart';
import '../../../core/supabase/supabase_providers.dart';
import 'attachment.dart';

const _bucket = 'event-attachments';

class AttachmentRepository {
  AttachmentRepository(this._client);
  final SupabaseClient _client;

  Future<List<Attachment>> fetchAttachments(String eventId) async {
    try {
      final rows = await _client
          .from('attachments')
          .select()
          .eq('event_id', eventId)
          .order('created_at', ascending: false);
      return rows.map(Attachment.fromJson).toList();
    } catch (e) {
      throw mapToFailure(e);
    }
  }

  Stream<List<Attachment>> watchAttachments(String eventId) {
    return _client
        .from('attachments')
        .stream(primaryKey: ['id'])
        .eq('event_id', eventId)
        .asyncMap((_) => fetchAttachments(eventId));
  }

  /// Upload [bytes] as [filename] to an event. Writes the object first (so a
  /// metadata row never dangles), then the row. The storage path is
  /// `{eventId}/{unique}_{filename}` to avoid collisions while keeping a
  /// readable name.
  Future<void> upload(
    String eventId, {
    required String filename,
    required Uint8List bytes,
    String? mimeType,
  }) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) throw const AuthFailure('You are not signed in.');
    final safe = filename.replaceAll(RegExp(r'[/\\]'), '_');
    final unique = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final path = '$eventId/${unique}_$safe';
    try {
      await _client.storage.from(_bucket).uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(contentType: mimeType, upsert: false),
          );
      await _client.from('attachments').insert({
        'event_id': eventId,
        'storage_path': path,
        'filename': safe,
        'mime_type': ?mimeType,
        'size_bytes': bytes.length,
        'uploaded_by': uid,
      });
    } catch (e) {
      throw mapToFailure(e);
    }
  }

  /// A short-lived signed URL to view/download a private object.
  Future<String> signedUrl(String storagePath) async {
    try {
      return await _client.storage
          .from(_bucket)
          .createSignedUrl(storagePath, 60 * 60); // 1 hour
    } catch (e) {
      throw mapToFailure(e);
    }
  }

  /// Delete the metadata row and then the object. RLS lets the uploader or an
  /// organizer delete.
  Future<void> delete(Attachment attachment) async {
    try {
      await _client.from('attachments').delete().eq('id', attachment.id);
      await _client.storage.from(_bucket).remove([attachment.storagePath]);
    } catch (e) {
      throw mapToFailure(e);
    }
  }
}

final attachmentRepositoryProvider = Provider<AttachmentRepository>((ref) {
  return AttachmentRepository(ref.watch(supabaseClientProvider));
});
