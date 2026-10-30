import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

/// Local-only face template helpers for the UPI demo wallet profile.
///
/// Images and templates stay on-device under the app documents directory.
/// Nothing is uploaded.
class FaceTemplateStore {
  FaceTemplateStore._();

  /// SHA-256 hex digest of [bytes], optionally salted with [extraMetrics].
  static String hashBytes(Uint8List bytes, {String extraMetrics = ''}) {
    final digest = sha256.convert([
      ...bytes,
      ...utf8.encode(extraMetrics),
    ]);
    return digest.toString();
  }

  /// Hash a face image file into a simple local template string.
  static Future<String> templateFromFile(
    File imageFile, {
    String extraMetrics = '',
  }) async {
    final bytes = await imageFile.readAsBytes();
    return hashBytes(Uint8List.fromList(bytes), extraMetrics: extraMetrics);
  }

  /// Copy [source] into `Documents/demo_faces/<walletId>.jpg` and return the path.
  static Future<String> persistFaceImage({
    required String walletId,
    required File source,
  }) async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/demo_faces');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final dest = File('${dir.path}/$walletId.jpg');
    await source.copy(dest.path);
    return dest.path;
  }

  /// Best-effort delete of a previously saved face image.
  static Future<void> deleteFaceImage(String? path) async {
    if (path == null || path.isEmpty) return;
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (_) {
      // ignore
    }
  }
}
