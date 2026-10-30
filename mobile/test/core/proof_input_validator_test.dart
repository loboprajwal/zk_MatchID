import 'package:flutter_test/flutter_test.dart';
import 'package:zk_match_id/core/native_bridge.dart';
import 'package:zk_match_id/core/proof_input_validator.dart';

void main() {
  test('accepts a valid threshold request with the circuit fixed-width set',
      () {
    expect(
      () => _validate(
        predicateMode: 1,
        attributeValue: 4000,
        thresholdA: 4000,
        thresholdB: 0,
        allowedSet: const [1, 2, 3, 4, 5],
      ),
      returnsNormally,
    );
  });

  test('rejects a wrong allowed-set width instead of silently padding it', () {
    expect(
      () => _validate(
        predicateMode: 2,
        attributeValue: 4,
        thresholdA: 0,
        thresholdB: 0,
        allowedSet: const [1, 2, 3],
      ),
      throwsArgumentError,
    );
  });

  test('rejects requests that cannot satisfy the circuit constraints', () {
    expect(
      () => _validate(
        predicateMode: 1,
        attributeValue: 3999,
        thresholdA: 4000,
        thresholdB: 0,
        allowedSet: const [1, 2, 3, 4, 5],
      ),
      throwsArgumentError,
    );
    expect(
      () => _validate(
        predicateMode: 1,
        attributeValue: 4000,
        thresholdA: 4000,
        thresholdB: 0,
        allowedSet: const [1, 2, 3, 4, 5],
        credentialExpiry: 1700000000,
      ),
      throwsArgumentError,
    );
  });

  test('legacy age proof API fails closed instead of returning mock points',
      () async {
    await expectLater(
      NativeBridge().generateAgeProof(
        birthYear: 2000,
        userSecret: 'runtime-generated-test-secret',
        currentYear: 2026,
        ageLimit: 18,
        sessionNonce: 'runtime-generated-test-nonce',
      ),
      throwsUnsupportedError,
    );
  });
}

void _validate({
  required int predicateMode,
  required int attributeValue,
  required int thresholdA,
  required int thresholdB,
  required List<int> allowedSet,
  int credentialExpiry = 1900000000,
  int currentTimestamp = 1800000000,
}) =>
    ProofInputValidator.validate(
      predicateMode: predicateMode,
      attributeValue: attributeValue,
      userSecret: 'runtime-generated-test-secret',
      credentialExpiry: credentialExpiry,
      thresholdA: thresholdA,
      thresholdB: thresholdB,
      allowedSet: allowedSet,
      currentTimestamp: currentTimestamp,
      sessionNonce: 'runtime-generated-test-nonce',
    );
