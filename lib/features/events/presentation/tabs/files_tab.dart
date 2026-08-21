/// Files tab — attachments for the event. Pick any file (bytes loaded in memory),
/// upload to the private Storage bucket, list, open via a short-lived signed URL,
/// and delete (uploader or organizer — RLS enforces). Membership gates both the
/// table row and the Storage object.
library;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../auth/application/auth_controller.dart';
import '../../application/attachment_controller.dart';
import '../../data/attachment.dart';

class FilesTab extends ConsumerWidget {
  const FilesTab({super.key, required this.eventId, this.shrinkWrap = false});
  final String eventId;

  /// Embedded mode: render as a plain column with an inline attach button, for
  /// nesting inside the Overview page's scrollable. The default (false) is the
  /// standalone full-height version with its own Scaffold + FAB.
  final bool shrinkWrap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final filesAsync = ref.watch(eventAttachmentsProvider(eventId));
    final uploading = ref.watch(attachmentActionsControllerProvider).isLoading;

    ref.listen(attachmentActionsControllerProvider, (_, n) {
      if (n.hasError && !n.isLoading) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(content: Text(messageForError(n.error!))));
      }
    });

    if (shrinkWrap) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          filesAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(messageForError(e)),
            ),
            data: (files) => files.isEmpty
                ? Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      t.filesEmpty,
                      style: TextStyle(color: AppColors.inkMuted),
                    ),
                  )
                : Column(
                    children: [
                      for (final (i, f) in files.indexed) ...[
                        if (i > 0)
                          Divider(height: 1, color: AppColors.outline),
                        _FileTile(eventId: eventId, file: f, flat: true),
                      ],
                    ],
                  ),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: uploading ? null : () => _pickAndUpload(context, ref),
            icon: uploading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.attach_file, size: 18),
            label: Text(uploading ? t.filesUploading : t.filesAttach),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.primary,
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
            ),
          ),
        ],
      );
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: uploading ? null : () => _pickAndUpload(context, ref),
        icon: uploading
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.attach_file),
        label: Text(uploading ? t.filesUploading : t.filesAttach),
      ),
      body: filesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(messageForError(e))),
        data: (files) => files.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    t.filesEmpty,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.inkMuted),
                  ),
                ),
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
                children: [
                  for (final f in files) _FileTile(eventId: eventId, file: f),
                ],
              ),
      ),
    );
  }

  Future<void> _pickAndUpload(BuildContext context, WidgetRef ref) async {
    final result = await FilePicker.pickFiles(withData: true);
    if (result == null || result.files.isEmpty) return;
    final picked = result.files.single;
    final bytes = picked.bytes;
    if (bytes == null) return; // withData should populate this
    await ref
        .read(attachmentActionsControllerProvider.notifier)
        .upload(eventId, filename: picked.name, bytes: bytes);
  }
}

class _FileTile extends ConsumerWidget {
  const _FileTile({
    required this.eventId,
    required this.file,
    this.flat = false,
  });
  final String eventId;
  final Attachment file;

  /// Render without its own Card, for nesting inside the Overview page's
  /// Files section (which is itself a card).
  final bool flat;

  IconData get _icon {
    final m = file.mimeType ?? '';
    if (m.startsWith('image/')) return Icons.image_outlined;
    if (m.contains('pdf')) return Icons.picture_as_pdf_outlined;
    if (m.startsWith('video/')) return Icons.movie_outlined;
    if (m.startsWith('audio/')) return Icons.audiotrack_outlined;
    return Icons.insert_drive_file_outlined;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final size = file.prettySize;

    final tile = ListTile(
      contentPadding: flat ? EdgeInsets.zero : null,
      leading: CircleAvatar(
        // ignore: deprecated_member_use
        backgroundColor: AppColors.blue.withOpacity(0.18),
        foregroundColor: AppColors.blue,
        child: Icon(_icon),
      ),
      title: Text(file.filename, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: size == null ? null : Text(size),
      onTap: () => _open(context, ref),
      trailing: IconButton(
        tooltip: t.filesDelete,
        icon: Icon(Icons.delete_outline, color: AppColors.inkMuted),
        onPressed: () => _confirmDelete(context, ref),
      ),
    );

    // Embedded in the Overview page the Files section is already a card, so
    // the row renders flat inside it; standalone it keeps its own card.
    return flat ? tile : Card(child: tile);
  }

  Future<void> _open(BuildContext context, WidgetRef ref) async {
    final t = AppLocalizations.of(context);
    final url = await ref
        .read(attachmentActionsControllerProvider.notifier)
        .openUrl(file.storagePath);
    if (url == null) return;
    final ok = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(t.filesOpenFailed)));
    }
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final t = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(t.filesDeleteConfirm(file.filename)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(t.commonCancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.coral),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(t.filesDelete),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(attachmentActionsControllerProvider.notifier).delete(file);
    }
  }
}
