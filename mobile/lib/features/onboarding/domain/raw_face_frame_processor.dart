import 'dart:io';
import 'dart:typed_data';

import 'face_pose_state_machine.dart';

class RawFaceFrameProcessor {
  Future<List<double>> computeAndDelete(
      String path, FaceEmbedder embedder) async {
    final file = File(path);
    Uint8List? raw;
    try {
      raw = await file.readAsBytes();
      return await embedder.embed(raw);
    } finally {
      raw?.fillRange(0, raw.length, 0);
      if (await file.exists()) await file.delete();
    }
  }
}
