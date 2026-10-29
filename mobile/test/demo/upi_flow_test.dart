import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zk_match_id/core/qr_codec.dart';
import 'package:zk_match_id/demo/demo_proof_service.dart';
import 'package:zk_match_id/demo/demo_verifier_service.dart';
import 'package:zk_match_id/demo/predicates.dart';
import 'package:zk_match_id/demo/wallet_store.dart';
import 'package:zk_match_id/models/proof_payload.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    DemoProofService.instance.resetUsedForTests();
    DemoVerifierService.instance.clearConsumedForTests();
    WalletStore.instance.debugResetLoadedFlag();
    WalletStore.instance.wallets.clear();
    WalletStore.instance.activeWalletId = null;
    await WalletStore.instance.resetToSeed();
  });

  test('seed wallets expose Aadhaar, degree, address credentials', () async {
    await WalletStore.instance.ensureLoaded();
    expect(WalletStore.instance.wallets.length, greaterThanOrEqualTo(3));
    final w = WalletStore.instance.activeWallet!;
    expect(
      w.credentials.map((c) => c.type).toSet(),
      containsAll(['Aadhaar', 'Degree', 'Address']),
    );
  });

  test('create and switch wallets', () async {
    await WalletStore.instance.ensureLoaded();
    final created = await WalletStore.instance.createWallet('Travel');
    expect(WalletStore.instance.activeWalletId, created.id);
    await WalletStore.instance.switchWallet('wallet_vivek');
    expect(WalletStore.instance.activeWallet?.id, 'wallet_vivek');
  });

  test('groth16 catalog proof round-trips QR and verifies PASS', () async {
    await WalletStore.instance.ensureLoaded();
    await WalletStore.instance.switchWallet('wallet_vivek');
    final wallet = WalletStore.instance.activeWallet!;
    final pred = kDemoPredicates.firstWhere((p) => p.id == 'age_18');

    final built = await DemoProofService.instance.buildProofQr(
      wallet: wallet,
      predicate: pred,
    );
    expect(built.payload.proofKind, 'groth16_precomputed');
    expect(built.encoded.isNotEmpty, isTrue);

    final rawJson = built.payload.toRawJson();
    expect(rawJson.toLowerCase().contains('2000-01'), isFalse);
    expect(rawJson.contains('dateOfBirth'), isFalse);

    final decoded = QrCodec.decode(built.encoded);
    expect(decoded.sessionNonce, built.payload.sessionNonce);
    expect(decoded.catalogEntryId, built.payload.catalogEntryId);

    final result =
        await DemoVerifierService.instance.verifyEncodedQr(built.encoded);
    expect(result.pass, isTrue, reason: result.reason);
    expect(result.title, 'PASS');

    final replay =
        await DemoVerifierService.instance.verifyEncodedQr(built.encoded);
    expect(replay.pass, isFalse);
    expect(replay.reason.toLowerCase(), contains('nonce'));
  });

  test('expired proof fails', () async {
    await WalletStore.instance.ensureLoaded();
    await WalletStore.instance.switchWallet('wallet_sagar');
    final wallet = WalletStore.instance.activeWallet!;
    final pred = kDemoPredicates.firstWhere((p) => p.id == 'degree');
    final built = await DemoProofService.instance.buildProofQr(
      wallet: wallet,
      predicate: pred,
    );
    final oldTs = DateTime.now().millisecondsSinceEpoch ~/ 1000 - 400;
    final encoded = QrCodec.encode(_withTimestamp(built.payload, oldTs));
    final result = await DemoVerifierService.instance.verifyEncodedQr(encoded);
    expect(result.pass, isFalse);
    expect(result.reason.toLowerCase(), contains('expired'));
  });

  test('unknown issuer fails', () async {
    await WalletStore.instance.ensureLoaded();
    final wallet = WalletStore.instance.activeWallet!;
    final pred = kDemoPredicates.firstWhere((p) => p.id == 'residency');
    final built = await DemoProofService.instance.buildProofQr(
      wallet: wallet,
      predicate: pred,
    );
    final bad = _withIssuer(built.payload, 'did:zkmatch:evil');
    final result =
        await DemoVerifierService.instance.verifyEncodedQr(QrCodec.encode(bad));
    expect(result.pass, isFalse);
    expect(result.reason.toLowerCase(), contains('issuer'));
  });
}

ProofPayload _withTimestamp(ProofPayload p, int ts) => ProofPayload(
      proof: p.proof,
      publicInputs: p.publicInputs,
      sessionNonce: '${ts}_replay_test',
      issuerReference: p.issuerReference,
      predicateType: p.predicateType,
      predicateClaim: p.predicateClaim,
      ttlSeconds: p.ttlSeconds,
      timestamp: ts,
      proofKind: p.proofKind,
      catalogEntryId: p.catalogEntryId,
      demoSignature: p.demoSignature,
    );

ProofPayload _withIssuer(ProofPayload p, String issuer) => ProofPayload(
      proof: p.proof,
      publicInputs: p.publicInputs,
      sessionNonce: p.sessionNonce,
      issuerReference: issuer,
      predicateType: p.predicateType,
      predicateClaim: p.predicateClaim,
      ttlSeconds: p.ttlSeconds,
      timestamp: p.timestamp,
      proofKind: p.proofKind,
      catalogEntryId: p.catalogEntryId,
      demoSignature: p.demoSignature,
    );
