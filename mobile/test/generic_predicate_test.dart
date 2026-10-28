import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/native_bridge.dart';
import 'package:mobile/models/proof_payload.dart';
import 'package:mobile/models/verification_policy.dart';
import 'package:mobile/screens/prover_screen.dart';

void main() {
  final bridge = NativeBridge();
  final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  final futureExpiry = now + 365 * 24 * 60 * 60; // +1 year

  Future<ProofPayload> prove({
    required int mode,
    required int attribute,
    required int thresholdA,
    int thresholdB = 0,
    List<int> allowedSet = const [0, 0, 0, 0, 0],
    int? credentialExpiry,
    String predicateType = 'age_18',
  }) {
    return bridge.generatePredicateProof(
      predicateMode: mode,
      attributeValue: attribute,
      userSecret: 'a1b2c3d4e5f67890a1b2c3d4e5f67890',
      credentialExpiry: credentialExpiry ?? futureExpiry,
      thresholdA: thresholdA,
      thresholdB: thresholdB,
      allowedSet: allowedSet,
      currentTimestamp: now,
      sessionNonce: 'test_nonce_${DateTime.now().microsecondsSinceEpoch}',
      issuerReference: 'did:zkmatch:gov-uidai',
      predicateType: predicateType,
      predicateClaim: 'test claim',
    );
  }

  group(
      'Generic multi-predicate engine (generic_verifier.circom)', () {
    test('Mode 3 derives age threshold without exposing birthYear', () async {
      final payload = await prove(
        mode: 3,
        attribute: 2000, // birthYear (private input)
        thresholdA: 18,
        thresholdB: DateTime.now().year,
        predicateType: 'age_18',
      );

      // [nullifier, mode, thrA, thrB, set0..4, timestamp, nonce]
      expect(payload.publicInputs, hasLength(11));
      expect(payload.publicInputs[1], '3');
      expect(payload.publicInputs[2], '18');
      expect(payload.publicInputs.first, isNot(isEmpty));
      expect(payload.predicateType, 'age_18');
      // Zero-knowledge: raw attributes must never appear in the public inputs
      expect(payload.publicInputs, isNot(contains('2000')));
      expect(payload.toRawJson(), isNot(contains('2000-01-01')));
    });

    test('Mode 1 accepts income >= threshold and rejects below', () async {
      final ok = await prove(
        mode: 1,
        attribute: 5200,
        thresholdA: 4000,
        predicateType: 'income_solvency',
      );
      expect(ok.publicInputs[1], '1');
      expect(ok.publicInputs[2], '4000');

      expect(
        () => prove(
          mode: 1,
          attribute: 3000,
          thresholdA: 4000,
          predicateType: 'income_solvency',
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('Mode 2 accepts whitelisted set members and rejects outsiders',
        () async {
      final ok = await prove(
        mode: 2,
        attribute: 1042, // accredited institutionId
        thresholdA: 0,
        allowedSet: const [1042, 2087, 3311, 4509, 5120],
        predicateType: 'student_status',
      );
      expect(ok.publicInputs[1], '2');
      expect(ok.publicInputs.sublist(4, 9), ['1042', '2087', '3311', '4509', '5120']);

      expect(
        () => prove(
          mode: 2,
          attribute: 9999,
          thresholdA: 0,
          allowedSet: const [1042, 2087, 3311, 4509, 5120],
          predicateType: 'student_status',
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('Validity constraint rejects expired credentials in every mode',
        () async {
      final expired = now - 60;
      expect(
        () => prove(
          mode: 1,
          attribute: 5200,
          thresholdA: 4000,
          credentialExpiry: expired,
          predicateType: 'income_solvency',
        ),
        throwsA(predicate((Object e) => e.toString().contains('expired'))),
      );
    });

    test('Poseidon-style nullifier binds to the session nonce (anti-replay)',
        () async {
      final payload = await prove(
        mode: 3,
        attribute: 2000,
        thresholdA: 18,
        thresholdB: DateTime.now().year,
      );
      final nullifier = payload.publicInputs.first;

      final replay = await bridge.generatePredicateProof(
        predicateMode: 3,
        attributeValue: 2000,
        userSecret: 'a1b2c3d4e5f67890a1b2c3d4e5f67890',
        credentialExpiry: futureExpiry,
        thresholdA: 18,
        thresholdB: DateTime.now().year,
        allowedSet: const [0, 0, 0, 0, 0],
        currentTimestamp: now,
        sessionNonce: 'different_nonce',
        issuerReference: 'did:zkmatch:gov-uidai',
        predicateType: 'age_18',
        predicateClaim: 'test claim',
      );

      expect(nullifier, isNot(equals(replay.publicInputs.first)));
      expect(payload.sessionNonce, isNot(equals(replay.sessionNonce)));
    });

    test('Groth16 verification accepts a valid generated payload', () async {
      final payload = await prove(
        mode: 3,
        attribute: 2000,
        thresholdA: 18,
        thresholdB: DateTime.now().year,
      );
      expect(await bridge.verifyPredicateProof(payload: payload), isTrue);
    });
  }, skip: bridge.isPredicateNativeAvailable
          ? null
          : 'Native generic prover/verifier is not loaded; mock proofs are not accepted.');

  group('Prover templates <-> Verifier policies alignment', () {
    test('every proof template targets a registered verification policy', () {
      for (final template in kProofTemplates) {
        final policy = verificationPolicyById(template.policyId);
        expect(policy, isNotNull,
            reason:
                'Template "${template.label}" has no matching verifier policy '
                'for id "${template.policyId}"');
      }
    });

    test('four verification profiles are registered', () {
      expect(kVerificationPolicies.map((p) => p.id).toList(), [
        'age_18',
        'income_solvency',
        'student_status',
        'regional_residency',
      ]);
    });
  });
}
