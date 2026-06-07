/// Attachment controllers: a live list per event plus an action notifier for
/// upload / delete and resolving a signed URL to open a file.
library;

import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/attachment.dart';
import '../data/attachment_repository.dart';

final eventAttachmentsProvider =
    StreamProvider.family<List<Attachment>, String>((ref, eventId) {
  return ref.watch(attachmentRepositoryProvider).watchAttachments(eventId);
});

class AttachmentActionsController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  AttachmentRepository get _repo => ref.read(attachmentRepositoryProvider);

  Future<void> upload(
    String eventId, {
    required String filename,
    required Uint8List bytes,
    String? mimeType,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _repo.upload(
          eventId,
          filename: filename,
          bytes: bytes,
          mimeType: mimeType,
        ));
  }

  Future<void> delete(Attachment attachment) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _repo.delete(attachment));
  }

  /// Resolve a signed URL for opening a file (null on error — surfaced in state).
  Future<String?> openUrl(String storagePath) async {
    state = const AsyncLoading();
    String? url;
    state = await AsyncValue.guard(() async {
      url = await _repo.signedUrl(storagePath);
    });
    return state.hasError ? null : url;
  }
}

final attachmentActionsControllerProvider =
    AsyncNotifierProvider<AttachmentActionsController, void>(
        AttachmentActionsController.new);
