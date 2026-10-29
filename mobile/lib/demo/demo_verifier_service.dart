import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../core/qr_codec.dart';
import '../models/proof_payload.dart';
import 'demo_proof_service.dart';

class VerifyResult {
  final bool pass;
  final String title;
  final String reason;
  final Map<String, String> details;

  const VerifyResult({
    required this.pass,
    required this.title,
    required this.reason,
    this.details = const {},
  });
}

/// Offline verifier for the UPI-style QR flow.
///
/// Checks (in order):
/// 1. Decode Base85 → ProofPayload (no raw PII expected)
/// 2. TTL / expiry from payload.timestamp + ttlSeconds
/// 3. Nonce single-use (anti-replay)
/// 4. Issuer allow-list
/// 5. Proof:
///    - `groth16_precomputed`: match against catalog entry (real snarkjs proof)
///      + public-input shape; pairing via native mopro is optional and currently
///      skipped on this demo path (honestly labeled in [reason]).
///    - `signed_demo`: HMAC verify with demo secret
class DemoVerifierService {
  static final DemoVerifierService instance = DemoVerifierService._();
  DemoVerifierService._();

  static const authorizedIssuers = {
    'did:zkmatch:gov-uidai',
    'did:zkmatch:university-pes',
    'did:zkmatch:municipal-bda',
    'did:zkmatch:bank-sbi',
  };

  final Set<String> _consumedNonces = {};
  Map<String, dynamic>? _vkey;

  Future<void> ensureVkeyLoaded() async {
    if (_vkey != null) return;
    final raw = await rootBundle.loadString('assets/verification_key.json');
    _vkey = jsonDecode(raw) as Map<String, dynamic>;
  }

  Future<VerifyResult> verifyEncodedQr(String encoded) async {
    await ensureVkeyLoaded();
    late final ProofPayload payload;
    try {
      payload = QrCodec.decode(encoded);
    } catch (e) {
      return VerifyResult(
        pass: false,
        title: 'FAIL',
        reason: 'Could not decode QR payload ($e)',
      );
    }
    return verifyPayload(payload);
  }

  Future<VerifyResult> verifyPayload(ProofPayload payload) async {
    await ensureVkeyLoaded();

    // 1) Expiry
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final age = now - payload.timestamp;
    if (payload.timestamp <= 0) {
      return const VerifyResult(
        pass: false,
        title: 'FAIL',
        reason: 'Missing timestamp on proof payload',
      );
    }
    if (age < -30) {
      return VerifyResult(
        pass: false,
        title: 'FAIL',
        reason: 'Proof timestamp is in the future (clock skew?)',
        details: _baseDetails(payload, age),
      );
    }
    if (age > payload.ttlSeconds) {
      return VerifyResult(
        pass: false,
        title: 'FAIL',
        reason:
            'Proof expired (${age}s old, TTL ${payload.ttlSeconds}s). Ask holder to regenerate QR.',
        details: _baseDetails(payload, age),
      );
    }

    // 2) Nonce single-use
    final nonce = payload.sessionNonce;
    if (nonce.isEmpty) {
      return VerifyResult(
        pass: false,
        title: 'FAIL',
        reason: 'Missing session nonce',
        details: _baseDetails(payload, age),
      );
    }
    if (_consumedNonces.contains(nonce)) {
      return VerifyResult(
        pass: false,
        title: 'FAIL',
        reason: 'Nonce already used (replay blocked)',
        details: _baseDetails(payload, age),
      );
    }

    // 3) Issuer
    if (!authorizedIssuers.contains(payload.issuerReference)) {
      return VerifyResult(
        pass: false,
        title: 'FAIL',
        reason: 'Issuer not in trust registry: ${payload.issuerReference}',
        details: _baseDetails(payload, age),
      );
    }

    // 4) Proof kind
    if (payload.proofKind == 'signed_demo') {
      final ok = DemoProofService.instance.verifyDemoSignature(payload);
      if (!ok) {
        return VerifyResult(
          pass: false,
          title: 'FAIL',
          reason: 'Signed-demo HMAC invalid',
          details: _baseDetails(payload, age),
        );
      }
      _consumedNonces.add(nonce);
      return VerifyResult(
        pass: true,
        title: 'PASS',
        reason:
            'Signed demo payload verified (HMAC). This is NOT a Groth16 proof — catalog was exhausted for this wallet/predicate.',
        details: {
          ..._baseDetails(payload, age),
          'Proof kind': 'signed_demo',
        },
      );
    }

    // groth16_precomputed (default)
    final entryId = payload.catalogEntryId;
    if (entryId == null || entryId.isEmpty) {
      return VerifyResult(
        pass: false,
        title: 'FAIL',
        reason: 'Groth16 payload missing catalog_entry_id',
        details: _baseDetails(payload, age),
      );
    }
    final entry = await DemoProofService.instance.catalogEntryById(entryId);
    if (entry == null) {
      return VerifyResult(
        pass: false,
        title: 'FAIL',
        reason: 'Unknown catalog entry $entryId',
        details: _baseDetails(payload, age),
      );
    }

    final catalogProof = Map<String, dynamic>.from(entry['proof'] as Map);
    final catalogPublics = List<String>.from(entry['public_inputs'] as List);
    final qrProof = payload.proof.toJson();
    if (!_deepEq(catalogProof, qrProof)) {
      return VerifyResult(
        pass: false,
        title: 'FAIL',
        reason: 'Groth16 proof points do not match catalog entry (tamper?)',
        details: _baseDetails(payload, age),
      );
    }
    if (!_listEq(catalogPublics, payload.publicInputs)) {
      return VerifyResult(
        pass: false,
        title: 'FAIL',
        reason: 'Public inputs do not match catalog entry (tamper?)',
        details: _baseDetails(payload, age),
      );
    }

    // Basic vkey presence / protocol check (pairing deferred to native/on-chain).
    final protocol = _vkey?['protocol'] as String? ?? '';
    final curve = _vkey?['curve'] as String? ?? '';
    if (protocol.isNotEmpty && protocol != 'groth16') {
      return VerifyResult(
        pass: false,
        title: 'FAIL',
        reason: 'verification_key.json protocol mismatch: $protocol',
        details: _baseDetails(payload, age),
      );
    }

    _consumedNonces.add(nonce);
    return VerifyResult(
      pass: true,
      title: 'PASS',
      reason:
          'Groth16 proof matched precomputed catalog (snarkjs · generic_verifier). '
          'Runtime BN254 pairing skipped on this Flutter path (no native mopro); '
          'same artifacts verify on-chain / with snarkjs. vkey=$protocol/$curve.',
      details: {
        ..._baseDetails(payload, age),
        'Proof kind': 'groth16_precomputed',
        'Catalog id': entryId,
        'Nullifier': _short(payload.nullifier),
        'vkey': '$protocol/$curve',
      },
    );
  }

  Map<String, String> _baseDetails(ProofPayload p, int age) => {
        'Claim': p.predicateClaim,
        'Issuer': p.issuerReference,
        'Predicate': p.predicateType,
        'Age': '${age}s / TTL ${p.ttlSeconds}s',
        'Nonce': _short(p.sessionNonce),
      };

  static String _short(String s) =>
      s.length <= 18 ? s : '${s.substring(0, 10)}…${s.substring(s.length - 6)}';

  static bool _listEq(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static bool _deepEq(dynamic a, dynamic b) {
    if (a is Map && b is Map) {
      if (a.length != b.length) return false;
      for (final k in a.keys) {
        if (!b.containsKey(k)) return false;
        if (!_deepEq(a[k], b[k])) return false;
      }
      return true;
    }
    if (a is List && b is List) {
      if (a.length != b.length) return false;
      for (var i = 0; i < a.length; i++) {
        if (!_deepEq(a[i], b[i])) return false;
      }
      return true;
    }
    return a?.toString() == b?.toString();
  }

  void clearConsumedForTests() => _consumedNonces.clear();
}
