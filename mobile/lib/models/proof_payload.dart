import 'dart:convert';

/// Represents the Groth16 zero-knowledge proof points on the BN254 elliptic curve.
class Groth16Proof {
  final List<String> piA;
  final List<List<String>> piB;
  final List<String> piC;
  final String protocol;
  final String curve;

  Groth16Proof({
    required this.piA,
    required this.piB,
    required this.piC,
    this.protocol = 'groth16',
    this.curve = 'bn128',
  });

  Map<String, dynamic> toJson() => {
        'pi_a': piA,
        'pi_b': piB,
        'pi_c': piC,
        'protocol': protocol,
        'curve': curve,
      };

  factory Groth16Proof.fromJson(Map<String, dynamic> json) {
    return Groth16Proof(
      piA: List<String>.from(json['pi_a'] ?? []),
      piB: (json['pi_b'] as List<dynamic>? ?? [])
          .map((row) => List<String>.from(row))
          .toList(),
      piC: List<String>.from(json['pi_c'] ?? []),
      protocol: json['protocol'] as String? ?? 'groth16',
      curve: json['curve'] as String? ?? 'bn128',
    );
  }
}

/// The complete proof payload exchanged during the offline QR handshake and FFI bridge calls.
class ProofPayload {
  final Groth16Proof proof;
  final List<String> publicInputs;
  final String sessionNonce;
  final String issuerReference;
  final String predicateType;
  final String predicateClaim;
  final int ttlSeconds;
  final int timestamp;

  ProofPayload({
    required this.proof,
    required this.publicInputs,
    required this.sessionNonce,
    this.issuerReference = 'did:zkmatch:gov-uidai',
    this.predicateType = 'age_18',
    this.predicateClaim = 'Age verified >= 18 with zero DOB disclosed',
    this.ttlSeconds = 120,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
        'proof': proof.toJson(),
        'public_inputs': publicInputs,
        'session_nonce': sessionNonce,
        'issuer_reference': issuerReference,
        'predicate_type': predicateType,
        'predicate_claim': predicateClaim,
        'ttl_seconds': ttlSeconds,
        'timestamp': timestamp,
      };

  factory ProofPayload.fromJson(Map<String, dynamic> json) {
    return ProofPayload(
      proof: json['proof'] is Map<String, dynamic>
          ? Groth16Proof.fromJson(json['proof'] as Map<String, dynamic>)
          : Groth16Proof.fromJson(Map<String, dynamic>.from(json['proof'] as Map)),
      publicInputs: List<String>.from(json['public_inputs'] as List? ?? []),
      sessionNonce: json['session_nonce'] as String? ?? json['sessionNonce'] as String? ?? '',
      issuerReference: json['issuer_reference'] as String? ?? json['issuer_ref'] as String? ?? 'did:zkmatch:gov-uidai',
      predicateType: json['predicate_type'] as String? ?? 'age_18',
      predicateClaim: json['predicate_claim'] as String? ?? 'Age verified >= 18 with zero DOB disclosed',
      ttlSeconds: json['ttl_seconds'] as int? ?? 120,
      timestamp: json['timestamp'] as int? ?? 0,
    );
  }

  String toRawJson() => jsonEncode(toJson());

  factory ProofPayload.fromRawJson(String raw) =>
      ProofPayload.fromJson(jsonDecode(raw) as Map<String, dynamic>);

  /// Circom serializes public outputs before public inputs. The generic
  /// circuit order is nullifier, mode, thresholds, allowedSet, timestamp,
  /// session nonce. Credential expiry remains private.
  String get nullifier => publicInputs.isNotEmpty ? publicInputs[0] : '';
  String get predicateMode => publicInputs.length > 1 ? publicInputs[1] : '';
  String get thresholdA => publicInputs.length > 2 ? publicInputs[2] : '';
  String get thresholdB => publicInputs.length > 3 ? publicInputs[3] : '';
  String get currentTimestamp => publicInputs.length > 9 ? publicInputs[9] : '';
  String get credentialExpiry => '';
}
