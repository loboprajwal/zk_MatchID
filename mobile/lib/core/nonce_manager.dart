import 'dart:math';

/// Manages dynamic interactive nonces to prevent replay attacks during QR verification.
class NonceManager {
  static final NonceManager _instance = NonceManager._internal();
  factory NonceManager() => _instance;
  NonceManager._internal();

  final Set<String> _consumedNonces = {};
  static const int nonceTtlSeconds = 120; // 2 minute lifetime

  /// Generates a dynamic, timestamp-anchored random nonce.
  String generateNonce() {
    final rng = Random.secure();
    final randomPart = List<int>.generate(8, (_) => rng.nextInt(256))
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return '${timestamp}_$randomPart';
  }

  /// Validates an incoming nonce:
  /// 1. Checks that the nonce has not already been used (anti-replay).
  /// 2. Checks that the nonce has not expired.
  bool validateAndConsumeNonce(String nonce) {
    if (_consumedNonces.contains(nonce)) {
      // Replay attack detected!
      return false;
    }

    final parts = nonce.split('_');
    if (parts.length != 2) return false;

    final timestamp = int.tryParse(parts[0]);
    if (timestamp == null) return false;

    final now = DateTime.now().millisecondsSinceEpoch;
    final ageSeconds = (now - timestamp) / 1000;

    if (ageSeconds < 0 || ageSeconds > nonceTtlSeconds) {
      // Nonce expired or invalid clock
      return false;
    }

    // Mark nonce as consumed
    _consumedNonces.add(nonce);
    return true;
  }

  /// Resets consumed nonces (useful for testing).
  void clearConsumedNonces() {
    _consumedNonces.clear();
  }
}
