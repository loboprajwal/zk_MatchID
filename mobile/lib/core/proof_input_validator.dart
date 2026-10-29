/// Validates the fixed-width public/private input contract for
/// `generic_verifier.circom` before crossing the FFI boundary.
class ProofInputValidator {
  const ProofInputValidator._();

  static const maxCircuitInteger = 0xffffffff;

  static void validate({
    required int predicateMode,
    required int attributeValue,
    required String userSecret,
    required int credentialExpiry,
    required int thresholdA,
    required int thresholdB,
    required List<int> allowedSet,
    required int currentTimestamp,
    required String sessionNonce,
  }) {
    if (predicateMode < 1 || predicateMode > 3) {
      throw ArgumentError.value(
          predicateMode, 'predicateMode', 'must be 1, 2, or 3');
    }
    if (allowedSet.length != 5) {
      throw ArgumentError.value(
          allowedSet.length, 'allowedSet.length', 'must be exactly 5');
    }
    for (final (name, value) in <(String, int)>[
      ('attributeValue', attributeValue),
      ('credentialExpiry', credentialExpiry),
      ('thresholdA', thresholdA),
      ('thresholdB', thresholdB),
      ('currentTimestamp', currentTimestamp),
      for (var i = 0; i < allowedSet.length; i++)
        ('allowedSet[$i]', allowedSet[i]),
    ]) {
      if (value < 0 || value > maxCircuitInteger) {
        throw ArgumentError.value(
            value, name, 'must be a 32-bit unsigned integer');
      }
    }
    if (userSecret.isEmpty || userSecret.trim().isEmpty) {
      throw ArgumentError.value(userSecret, 'userSecret', 'must not be empty');
    }
    if (sessionNonce.isEmpty || sessionNonce.trim().isEmpty) {
      throw ArgumentError.value(
          sessionNonce, 'sessionNonce', 'must not be empty');
    }
    if (credentialExpiry < currentTimestamp) {
      throw ArgumentError('Credential is expired.');
    }
    switch (predicateMode) {
      case 1 when attributeValue < thresholdA:
        throw ArgumentError('Threshold predicate is not met.');
      case 2 when !allowedSet.contains(attributeValue):
        throw ArgumentError('Set membership predicate is not met.');
      case 3
          when thresholdB < attributeValue ||
              thresholdB - attributeValue < thresholdA:
        throw ArgumentError('Derived threshold predicate is not met.');
    }
  }
}
