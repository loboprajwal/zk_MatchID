import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../core/qr_codec.dart';
import '../models/proof_payload.dart';
import 'demo_session.dart';
import 'predicates.dart';
import 'wallet_store.dart';

/// Builds QR-ready proof payloads for the UPI-style demo.
///
/// HONEST LABEL:
/// - Preferred path: consume a **real Groth16 proof** from
///   `assets/demo_proof_catalog.json`, generated offline with snarkjs against
///   `mopro/assets/generic_verifier_final.zkey` (local-dev ceremony).
/// - Fallback path: `signed_demo` HMAC payload when the catalog is exhausted
///   for that wallet×predicate. This is NOT a SNARK — UI and docs say so.
///
/// Native mopro FFI is intentionally not required for this demo branch.
class DemoProofService {
  static final DemoProofService instance = DemoProofService._();
  DemoProofService._();

  static const int defaultTtlSeconds = 300; // 5 minutes
  static const String _demoHmacSecret = 'zk-matchid-demo-hmac-v1-not-for-prod';

  Map<String, dynamic>? _catalog;
  final Set<String> _usedCatalogIds = {};

  Future<void> ensureCatalogLoaded() async {
    if (_catalog != null) return;
    final raw = await rootBundle.loadString('assets/demo_proof_catalog.json');
    _catalog = jsonDecode(raw) as Map<String, dynamic>;
  }

  /// Produce an encoded QR string + payload for [wallet] proving [predicate].
  Future<({String encoded, ProofPayload payload, String proofKindLabel})>
      buildProofQr({
    required DemoWallet wallet,
    required DemoPredicate predicate,
  }) async {
    await ensureCatalogLoaded();
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    final entry = _takeCatalogEntry(wallet.id, predicate.id);
    late final ProofPayload payload;
    late final String kindLabel;

    if (entry != null) {
      final proofMap = Map<String, dynamic>.from(entry['proof'] as Map);
      final publics = List<String>.from(entry['public_inputs'] as List);
      // Holder-side freshness nonce (UPI-like): timestamp_random, tracked by verifier.
      final sessionNonce =
          '${now}_${wallet.id}_${predicate.id}_${entry['id']}'.replaceAll(' ', '');
      payload = ProofPayload(
        proof: Groth16Proof.fromJson(proofMap),
        publicInputs: publics,
        sessionNonce: sessionNonce,
        issuerReference: predicate.issuerReference,
        predicateType: predicate.id,
        predicateClaim: predicate.claim,
        ttlSeconds: defaultTtlSeconds,
        timestamp: now,
        proofKind: 'groth16_precomputed',
        catalogEntryId: entry['id'] as String,
      );
      kindLabel =
          'Real Groth16 (precomputed snarkjs · local-dev zkey) · catalog ${entry['id']}';
    } else {
      // Signed demo fallback — clearly labeled, no raw PII.
      final sessionNonce = '${now}_${wallet.id}_${predicate.id}_signed';
      final dummyProof = Groth16Proof(
        piA: ['0', '0', '0'],
        piB: [
          ['0', '0'],
          ['0', '0'],
          ['0', '0'],
        ],
        piC: ['0', '0', '0'],
      );
      final publics = <String>[
        // Synthetic nullifier from wallet+predicate+time (not Poseidon — demo only).
        _hashField('${wallet.id}|${predicate.id}|$now'),
        '0',
        '0',
        '0',
        '0',
        '0',
        '0',
        '0',
        '0',
        '2026',
        sessionNonce.replaceAll(RegExp(r'[^0-9]'), '').padRight(12, '0').substring(0, 12),
      ];
      final unsigned = ProofPayload(
        proof: dummyProof,
        publicInputs: publics,
        sessionNonce: sessionNonce,
        issuerReference: predicate.issuerReference,
        predicateType: predicate.id,
        predicateClaim: '${predicate.claim} [SIGNED DEMO FALLBACK]',
        ttlSeconds: defaultTtlSeconds,
        timestamp: now,
        proofKind: 'signed_demo',
      );
      final sig = _sign(unsigned);
      payload = ProofPayload(
        proof: unsigned.proof,
        publicInputs: unsigned.publicInputs,
        sessionNonce: unsigned.sessionNonce,
        issuerReference: unsigned.issuerReference,
        predicateType: unsigned.predicateType,
        predicateClaim: unsigned.predicateClaim,
        ttlSeconds: unsigned.ttlSeconds,
        timestamp: unsigned.timestamp,
        proofKind: 'signed_demo',
        demoSignature: sig,
      );
      kindLabel =
          'Signed demo fallback (HMAC) — NOT a Groth16 proof; catalog exhausted';
    }

    final encoded = QrCodec.encode(payload);
    DemoSession.lastEncodedQr = encoded;
    DemoSession.lastPayload = payload;
    DemoSession.lastWalletName = wallet.name;
    DemoSession.lastPredicateLabel = predicate.label;
    return (encoded: encoded, payload: payload, proofKindLabel: kindLabel);
  }

  Map<String, dynamic>? _takeCatalogEntry(String walletId, String predicateId) {
    final entries = (_catalog?['entries'] as List?) ?? const [];
    for (final raw in entries) {
      final e = Map<String, dynamic>.from(raw as Map);
      final id = e['id'] as String;
      if (_usedCatalogIds.contains(id)) continue;
      if (e['walletId'] != walletId) continue;
      if (e['predicateId'] != predicateId) continue;
      _usedCatalogIds.add(id);
      return e;
    }
    return null;
  }

  /// Look up a catalog entry by id (verifier uses this).
  Future<Map<String, dynamic>?> catalogEntryById(String id) async {
    await ensureCatalogLoaded();
    final entries = (_catalog?['entries'] as List?) ?? const [];
    for (final raw in entries) {
      final e = Map<String, dynamic>.from(raw as Map);
      if (e['id'] == id) return e;
    }
    return null;
  }

  String _sign(ProofPayload p) {
    final body = jsonEncode({
      'public_inputs': p.publicInputs,
      'session_nonce': p.sessionNonce,
      'issuer_reference': p.issuerReference,
      'predicate_type': p.predicateType,
      'timestamp': p.timestamp,
      'ttl_seconds': p.ttlSeconds,
    });
    final hmac = Hmac(sha256, utf8.encode(_demoHmacSecret));
    return hmac.convert(utf8.encode(body)).toString();
  }

  bool verifyDemoSignature(ProofPayload p) {
    if (p.demoSignature == null) return false;
    final expected = _sign(ProofPayload(
      proof: p.proof,
      publicInputs: p.publicInputs,
      sessionNonce: p.sessionNonce,
      issuerReference: p.issuerReference,
      predicateType: p.predicateType,
      predicateClaim: p.predicateClaim,
      ttlSeconds: p.ttlSeconds,
      timestamp: p.timestamp,
      proofKind: p.proofKind,
    ));
    return expected == p.demoSignature;
  }

  static String _hashField(String input) {
    final digest = sha256.convert(utf8.encode(input));
    // Keep decimal digits only so it looks like a field element string.
    final hex = digest.toString();
    final asBig = BigInt.parse(hex.substring(0, 30), radix: 16);
    return asBig.toString();
  }

  /// Test helper: reset used catalog slots.
  void resetUsedForTests() => _usedCatalogIds.clear();
}
