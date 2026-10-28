import 'dart:convert';
import 'dart:typed_data';
import '../models/proof_payload.dart';

/// High-Density QR Codec using Ascii85 (Base85) compression.
/// Packs Groth16 BN254 elliptic curve points and public inputs into
/// an ultra-compact payload for offline optical scanning.
class QrCodec {
  static const String _ascii85Chars =
      '!"#\$%&\'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstu';

  /// Encodes a ProofPayload into a compressed Base85 string.
  static String encode(ProofPayload payload) {
    final rawJson = payload.toRawJson();
    final bytes = utf8.encode(rawJson);
    return encodeBytes(Uint8List.fromList(bytes));
  }

  /// Decodes a compressed Base85 string back into a ProofPayload.
  static ProofPayload decode(String encodedBase85) {
    final bytes = decodeToBytes(encodedBase85);
    final rawJson = utf8.decode(bytes);
    return ProofPayload.fromRawJson(rawJson);
  }

  /// Encodes raw bytes into Ascii85 (Base85).
  static String encodeBytes(Uint8List data) {
    final buffer = StringBuffer();
    final padding = (4 - (data.length % 4)) % 4;
    final paddedList = Uint8List(data.length + padding);
    paddedList.setRange(0, data.length, data);

    final byteData = ByteData.sublistView(paddedList);
    for (int i = 0; i < paddedList.length; i += 4) {
      final value = byteData.getUint32(i);
      final block = List<int>.filled(5, 0);
      int temp = value;
      for (int j = 4; j >= 0; j--) {
        block[j] = temp % 85;
        temp ~/= 85;
      }
      for (int k = 0; k < 5; k++) {
        buffer.write(_ascii85Chars[block[k]]);
      }
    }

    // Strip padding characters from the final block representation
    final result = buffer.toString();
    if (padding > 0) {
      return result.substring(0, result.length - padding);
    }
    return result;
  }

  /// Decodes an Ascii85 (Base85) string back to raw bytes.
  static Uint8List decodeToBytes(String ascii85) {
    final clean = ascii85.replaceAll(RegExp(r'\s+'), '');
    final padding = (5 - (clean.length % 5)) % 5;
    final padded = clean + ('u' * padding);

    final output = BytesBuilder();
    for (int i = 0; i < padded.length; i += 5) {
      int val = 0;
      for (int j = 0; j < 5; j++) {
        final charIndex = _ascii85Chars.indexOf(padded[i + j]);
        if (charIndex == -1) {
          throw FormatException('Invalid Base85 character: ${padded[i + j]}');
        }
        val = val * 85 + charIndex;
      }

      final block = Uint8List(4);
      final bd = ByteData.sublistView(block);
      bd.setUint32(0, val);
      output.add(block);
    }

    final fullBytes = output.takeBytes();
    if (padding > 0) {
      return Uint8List.sublistView(fullBytes, 0, fullBytes.length - padding);
    }
    return fullBytes;
  }
}
