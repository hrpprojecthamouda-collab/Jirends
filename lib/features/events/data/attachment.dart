/// Attachment — a row of public.attachments: metadata for a file in Storage.
/// The bytes live in the private `event-attachments` bucket at
/// `{event_id}/{filename}` (= storage_path). Scoped to event members by RLS on
/// both the table and the Storage object; no client visibility logic.
library;

import 'package:freezed_annotation/freezed_annotation.dart';

part 'attachment.freezed.dart';
part 'attachment.g.dart';

@freezed
abstract class Attachment with _$Attachment {
  const Attachment._();

  const factory Attachment({
    required String id,
    required String eventId,
    required String storagePath,
    required String filename,
    String? mimeType,
    int? sizeBytes,
    required String uploadedBy,
    required DateTime createdAt,
  }) = _Attachment;

  factory Attachment.fromJson(Map<String, dynamic> json) =>
      _$AttachmentFromJson(json);

  /// Human-readable size, e.g. "240 KB". Null when size is unknown.
  String? get prettySize {
    final b = sizeBytes;
    if (b == null) return null;
    if (b < 1024) return '$b B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(0)} KB';
    return '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
