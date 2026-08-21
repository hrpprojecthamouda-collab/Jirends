/// Shrinks a picked image before it is uploaded, using only `dart:ui` — the
/// engine's own codec, so no image-processing package is added to the app.
///
/// An avatar is drawn at 16–44px radius, so a 4MB camera photo is three orders
/// of magnitude more data than any screen will ever use. Shrinking it here
/// keeps the bucket small and, far more visibly, keeps member lists from
/// pulling megabytes per face.
///
/// PNG is the only format the engine can *encode*, so output is always PNG even
/// when the input was JPEG. That trades some file size for having no encoder
/// dependency; at 512px it lands well inside the bucket's 5MB cap.
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

/// Re-encode [bytes] so its longest side is at most [maxSide].
///
/// Returns null when the engine cannot decode the input at all — HEIC from an
/// iPhone is the case that matters — so the caller can decide whether to send
/// the original bytes instead of failing the whole upload.
Future<Uint8List?> downscaleImage(Uint8List bytes, {int maxSide = 512}) async {
  ui.ImmutableBuffer? buffer;
  try {
    // ImageDescriptor reads the header only, so the full-size bitmap is never
    // decoded just to find out how big it is.
    buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    final width = descriptor.width;
    final height = descriptor.height;

    final longest = width > height ? width : height;
    // Never upscale: a small picture blown up is bigger AND blurrier.
    final scale = longest <= maxSide ? 1.0 : maxSide / longest;

    final codec = await descriptor.instantiateCodec(
      targetWidth: (width * scale).round(),
      targetHeight: (height * scale).round(),
    );
    final frame = await codec.getNextFrame();
    final data = await frame.image.toByteData(format: ui.ImageByteFormat.png);

    frame.image.dispose();
    codec.dispose();
    descriptor.dispose();

    return data?.buffer.asUint8List();
  } catch (_) {
    return null;
  } finally {
    // Holds a native copy of the whole picked file (up to 5MB). The decode
    // path disposes its own objects, but this one outlives them and is just as
    // easy to leak on the failure path, so it is released here.
    buffer?.dispose();
  }
}
