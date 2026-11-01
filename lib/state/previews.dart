import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:wraith_core/models.dart';

const _imageExt = {'jpg', 'jpeg', 'png', 'webp', 'gif', 'bmp', 'heic', 'heif'};

bool isPreviewable(String name) {
  final dot = name.lastIndexOf('.');
  return dot >= 0 && _imageExt.contains(name.substring(dot + 1).toLowerCase());
}

/// Small PNG thumbnails (≤ ~96 KB each) for up to 8 images in [files], keyed
/// by index. Anything that fails to decode is simply skipped.
Future<Map<int, Uint8List>> buildPreviews(List<FileEntry> files) async {
  final out = <int, Uint8List>{};
  for (var i = 0; i < files.length && out.length < 8; i++) {
    final f = files[i];
    final path = f.path;
    if (path == null || !isPreviewable(f.name) || f.size > 30 * 1024 * 1024) continue;
    try {
      final bytes = await File(path).readAsBytes();
      for (final width in const [176, 120]) {
        final codec = await ui.instantiateImageCodec(bytes, targetWidth: width);
        final frame = await codec.getNextFrame();
        final data = await frame.image.toByteData(format: ui.ImageByteFormat.png);
        frame.image.dispose();
        codec.dispose();
        if (data == null) break;
        if (data.lengthInBytes <= 96 * 1024) {
          out[i] = data.buffer.asUint8List();
          break;
        }
      }
    } catch (_) {}
  }
  return out;
}
