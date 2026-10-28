import 'dart:convert';

/// Represents a W3C-compliant Verifiable Credential issued by a trusted entity.
class VerifiableCredential {
  final String id;
  final List<String> type;
  final String issuerId;
  final String issuerName;
  final String schemaId;
  final String issuanceDate;
  final String expirationDate;
  final Map<String, dynamic> credentialSubject;
  final String signatureType;
  final String signatureValue;

  VerifiableCredential({
    required this.id,
    required this.type,
    required this.issuerId,
    required this.issuerName,
    required this.schemaId,
    required this.issuanceDate,
    required this.expirationDate,
    required this.credentialSubject,
    this.signatureType = 'Ed25519Signature2020',
    required this.signatureValue,
  });

  int get birthYear {
    final raw = credentialSubject['birthYear'];
    if (raw is int) return raw;
    if (raw is String) return int.tryParse(raw) ?? 2000;
    return 2000;
  }

  String get dateOfBirth => credentialSubject['dateOfBirth']?.toString() ?? '2000-01-01';

  Map<String, dynamic> toJson() => {
        '@context': ['https://www.w3.org/2018/credentials/v1'],
        'id': id,
        'type': type,
        'issuer': {
          'id': issuerId,
          'name': issuerName,
        },
        'schema': {
          'id': schemaId,
          'type': 'JsonSchemaValidator2018',
        },
        'issuanceDate': issuanceDate,
        'expirationDate': expirationDate,
        'credentialSubject': credentialSubject,
        'proof': {
          'type': signatureType,
          'signatureValue': signatureValue,
        },
      };

  factory VerifiableCredential.fromJson(Map<String, dynamic> json) {
    final issuer = json['issuer'] is Map<String, dynamic> ? json['issuer'] as Map<String, dynamic> : {};
    final schema = json['schema'] is Map<String, dynamic> ? json['schema'] as Map<String, dynamic> : {};
    final subject = json['credentialSubject'] is Map<String, dynamic>
        ? json['credentialSubject'] as Map<String, dynamic>
        : <String, dynamic>{};
    final proof = json['proof'] is Map<String, dynamic> ? json['proof'] as Map<String, dynamic> : {};

    return VerifiableCredential(
      id: json['id']?.toString() ?? '',
      type: (json['type'] as List<dynamic>? ?? []).map((e) => e.toString()).toList(),
      issuerId: issuer['id']?.toString() ?? 'did:zkmatch:unknown-issuer',
      issuerName: issuer['name']?.toString() ?? 'Unknown Issuer',
      schemaId: schema['id']?.toString() ?? '',
      issuanceDate: json['issuanceDate']?.toString() ?? '',
      expirationDate: json['expirationDate']?.toString() ?? '',
      credentialSubject: subject,
      signatureType: proof['type']?.toString() ?? 'Ed25519Signature2020',
      signatureValue: proof['signatureValue']?.toString() ?? '',
    );
  }

  String toRawJson() => jsonEncode(toJson());

  factory VerifiableCredential.fromRawJson(String raw) =>
      VerifiableCredential.fromJson(jsonDecode(raw) as Map<String, dynamic>);
}
