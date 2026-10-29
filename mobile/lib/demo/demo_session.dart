import '../models/proof_payload.dart';

/// In-memory bridge so a single-device demo can verify the last generated QR
/// without a second phone / camera.
class DemoSession {
  static String? lastEncodedQr;
  static ProofPayload? lastPayload;
  static String? lastWalletName;
  static String? lastPredicateLabel;
}
