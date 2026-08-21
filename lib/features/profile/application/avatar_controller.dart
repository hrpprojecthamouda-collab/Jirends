/// Picking, uploading and clearing the signed-in user's profile photo.
///
/// The picked image is shrunk to 512px before it leaves the device (see
/// [downscaleImage]); if the engine can't decode the format — HEIC is the real
/// case — the original bytes are sent instead, which the bucket's mime-type and
/// size limits still police.
library;

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/util/image_downscale.dart';
import '../../auth/data/profile.dart';
import '../../auth/data/profile_repository.dart';

class AvatarController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  ProfileRepository get _profiles => ref.read(profileRepositoryProvider);

  /// Opens the system picker and uploads what comes back.
  ///
  /// Returns false when the upload failed (the error is on [state] for the UI
  /// to render) and also when the user simply backed out of the picker — the
  /// two are told apart by [AsyncValue.hasError], since a cancelled pick is not
  /// something to apologise for.
  Future<bool> pickAndUpload() async {
    final result = await FilePicker.pickFiles(
      type: FileType.image,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return false;
    final picked = result.files.single;
    final original = picked.bytes;
    if (original == null) return false; // withData should populate this

    state = const AsyncLoading();
    final shrunk = await downscaleImage(original);
    state = await AsyncValue.guard(() async {
      await _profiles.setAvatar(
        bytes: shrunk ?? original,
        // downscaleImage always emits PNG; only the fallback keeps the
        // original container, so the extension has to follow the bytes.
        extension: shrunk != null ? 'png' : _extensionOf(picked.name),
        mimeType: shrunk != null ? 'image/png' : _mimeOf(picked.name),
      );
      ref.invalidate(myProfileProvider);
    });
    return !state.hasError;
  }

  /// Back to initials.
  Future<bool> remove() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await _profiles.removeAvatar();
      ref.invalidate(myProfileProvider);
    });
    return !state.hasError;
  }
}

/// The bucket only accepts png/jpeg/webp/gif, so anything else is labelled jpeg
/// and left to the server to reject — guessing a type we can't encode would
/// just move the failure somewhere less clear.
String _extensionOf(String filename) {
  final dot = filename.lastIndexOf('.');
  if (dot == -1 || dot == filename.length - 1) return 'jpg';
  return filename.substring(dot + 1).toLowerCase();
}

String _mimeOf(String filename) => switch (_extensionOf(filename)) {
      'png' => 'image/png',
      'webp' => 'image/webp',
      'gif' => 'image/gif',
      _ => 'image/jpeg',
    };

final avatarControllerProvider =
    AsyncNotifierProvider<AvatarController, void>(AvatarController.new);

/// The signed-in user's photo URL, or null when they haven't set one.
final myAvatarUrlProvider = Provider<String?>((ref) {
  return ref.watch(myProfileProvider).value?.avatarUrl;
});

/// Convenience for widgets that want the whole profile without importing the
/// auth layer directly.
final myProfileValueProvider = Provider<Profile?>((ref) {
  return ref.watch(myProfileProvider).value;
});
