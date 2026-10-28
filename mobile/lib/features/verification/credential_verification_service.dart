import 'dart:convert';

import 'package:cryptography/cryptography.dart';

enum CredentialCheckStatus {
  verified,
  malformed,
  unsupportedFormat,
  untrustedIssuer,
  invalidSignature,
  expired,
}

class CredentialVerificationResult {
  const CredentialVerificationResult({
    required this.status,
    required this.message,
    this.issuer,
    this.credentialType,
    this.expiresAt,
  });

  final CredentialCheckStatus status;
  final String message;
  final String? issuer;
  final String? credentialType;
  final DateTime? expiresAt;

  bool get verified => status == CredentialCheckStatus.verified;
}

class _TrustedKey {
  const _TrustedKey({
    required this.issuer,
    required this.algorithm,
    required this.publicKey,
    this.exponent,
  });

  final String issuer;
  final String algorithm;
  final String publicKey;
  final String? exponent;
}

/// Verifies compact JWS credential QR codes against a build-time issuer trust
/// registry. Supported algorithms are EdDSA and RS256. Unknown keys fail closed.
class CredentialVerificationService {
  CredentialVerificationService({required Map<String, dynamic> trustRegistry})
      : _keys = _parseRegistry(trustRegistry);

  static const String trustRegistryJson =
      String.fromEnvironment('CREDENTIAL_TRUST_REGISTRY_JSON');

  factory CredentialVerificationService.fromDartDefine() {
    if (trustRegistryJson.isEmpty) {
      return CredentialVerificationService(trustRegistry: const {});
    }
    try {
      final decoded = jsonDecode(trustRegistryJson);
      if (decoded is Map<String, dynamic>) {
        return CredentialVerificationService(trustRegistry: decoded);
      }
    } on FormatException {
      // An invalid configured registry becomes an empty trust set.
    }
    return CredentialVerificationService(trustRegistry: const {});
  }

  static const int maxQrBytes = 16 * 1024;
  final Map<String, _TrustedKey> _keys;

  Future<CredentialVerificationResult> verifyQr(
    String value, {
    DateTime? now,
  }) async {
    if (utf8.encode(value).length > maxQrBytes) {
      return const CredentialVerificationResult(
        status: CredentialCheckStatus.malformed,
        message: 'Credential code is too large to verify.',
      );
    }
    const prefix = 'zkmatchid-credential:v1:';
    final token =
        value.startsWith(prefix) ? value.substring(prefix.length) : value;
    final parts = token.split('.');
    if (parts.length != 3 || parts.any((part) => part.isEmpty)) {
      return const CredentialVerificationResult(
        status: CredentialCheckStatus.malformed,
        message: 'The credential QR is malformed.',
      );
    }

    try {
      final header = _decodeJson(parts[0]);
      final payload = _decodeJson(parts[1]);
      final signatureBytes = _decodeBase64Url(parts[2]);
      if (!const {'zkmatchid-credential+jwt', 'vc+jwt', 'JWT'}
          .contains(header['typ'])) {
        return const CredentialVerificationResult(
          status: CredentialCheckStatus.unsupportedFormat,
          message: 'The signed credential format is not supported.',
        );
      }
      final keyId = header['kid'];
      final algorithm = header['alg'];
      final issuerId = payload['iss'];
      final credential = payload['vc'] ?? payload['credential'];
      if (keyId is! String ||
          algorithm is! String ||
          issuerId is! String ||
          credential is! Map) {
        return const CredentialVerificationResult(
          status: CredentialCheckStatus.malformed,
          message: 'The signed credential is missing required fields.',
        );
      }
      final trusted = _keys[keyId];
      if (trusted == null ||
          trusted.issuer != issuerId ||
          trusted.algorithm != algorithm) {
        return const CredentialVerificationResult(
          status: CredentialCheckStatus.untrustedIssuer,
          message:
              'The credential issuer is not in this verifier’s trusted issuer registry.',
        );
      }

      final exp = payload['exp'];
      final issuedAt = payload['iat'];
      final notBefore = payload['nbf'];
      if (exp is! int || issuedAt is! int) {
        return const CredentialVerificationResult(
          status: CredentialCheckStatus.malformed,
          message: 'The signed credential has no valid issue or expiry time.',
        );
      }
      final current = (now ?? DateTime.now()).toUtc();
      final expiry =
          DateTime.fromMillisecondsSinceEpoch(exp * 1000, isUtc: true);
      if (issuedAt > current.millisecondsSinceEpoch ~/ 1000 + 60) {
        return const CredentialVerificationResult(
          status: CredentialCheckStatus.malformed,
          message: 'The credential issue time is invalid.',
        );
      }
      if (notBefore is int &&
          notBefore > current.millisecondsSinceEpoch ~/ 1000) {
        return const CredentialVerificationResult(
          status: CredentialCheckStatus.malformed,
          message: 'The credential is not valid yet.',
        );
      }
      if (!expiry.isAfter(current)) {
        return CredentialVerificationResult(
          status: CredentialCheckStatus.expired,
          message: 'The credential has expired.',
          issuer: issuerId,
          credentialType:
              _credentialType(Map<String, dynamic>.from(credential)),
          expiresAt: expiry,
        );
      }
      if (!_credentialIssuerMatches(
        Map<String, dynamic>.from(credential),
        issuerId,
      )) {
        return const CredentialVerificationResult(
          status: CredentialCheckStatus.malformed,
          message: 'The credential issuer does not match its signature issuer.',
        );
      }
      final credentialSubject = credential['credentialSubject'];
      if (payload['sub'] is String &&
          credentialSubject is Map &&
          credentialSubject['id'] != payload['sub']) {
        return const CredentialVerificationResult(
          status: CredentialCheckStatus.malformed,
          message: 'The signed subject does not match the credential subject.',
        );
      }
      final vcExpiryValue = credential['expirationDate'];
      if (vcExpiryValue is String) {
        final vcExpiry = DateTime.tryParse(vcExpiryValue)?.toUtc();
        if (vcExpiry == null) {
          return const CredentialVerificationResult(
            status: CredentialCheckStatus.malformed,
            message: 'The credential expiration date is invalid.',
          );
        }
        if (!vcExpiry.isAfter(current)) {
          return CredentialVerificationResult(
            status: CredentialCheckStatus.expired,
            message: 'The credential has expired.',
            issuer: issuerId,
            credentialType:
                _credentialType(Map<String, dynamic>.from(credential)),
            expiresAt: vcExpiry,
          );
        }
      }

      final signingInput = utf8.encode('${parts[0]}.${parts[1]}');
      final signature = Signature(
        signatureBytes,
        publicKey: _publicKey(trusted),
      );
      final valid = await _algorithm(algorithm).verify(
        signingInput,
        signature: signature,
      );
      if (!valid) {
        return const CredentialVerificationResult(
          status: CredentialCheckStatus.invalidSignature,
          message:
              'The issuer signature is invalid. Do not accept this credential.',
        );
      }
      return CredentialVerificationResult(
        status: CredentialCheckStatus.verified,
        message:
            'Issuer signature and expiry are valid. Holder identity and revocation status were not checked.',
        issuer: issuerId,
        credentialType: _credentialType(Map<String, dynamic>.from(credential)),
        expiresAt: expiry,
      );
    } on FormatException {
      return const CredentialVerificationResult(
        status: CredentialCheckStatus.malformed,
        message: 'The credential QR contains invalid data.',
      );
    } on ArgumentError {
      return const CredentialVerificationResult(
        status: CredentialCheckStatus.malformed,
        message: 'The credential QR contains invalid signing-key data.',
      );
    } catch (_) {
      return const CredentialVerificationResult(
        status: CredentialCheckStatus.malformed,
        message: 'The credential could not be verified.',
      );
    }
  }

  static Map<String, _TrustedKey> _parseRegistry(
      Map<String, dynamic> registry) {
    final issuers = registry['issuers'];
    if (issuers is! List) return const {};
    final result = <String, _TrustedKey>{};
    for (final item in issuers) {
      if (item is! Map) continue;
      final issuer = item['id'];
      final keys = item['keys'];
      if (issuer is! String || issuer.isEmpty || keys is! List) continue;
      for (final key in keys) {
        if (key is! Map) continue;
        final id = key['kid'];
        final algorithm = key['alg'];
        final publicKey = key['publicKey'];
        final exponent = key['exponent'];
        if (id is! String ||
            algorithm is! String ||
            publicKey is! String ||
            (algorithm != 'EdDSA' && algorithm != 'RS256') ||
            (algorithm == 'RS256' && exponent is! String)) {
          continue;
        }
        result[id] = _TrustedKey(
          issuer: issuer,
          algorithm: algorithm,
          publicKey: publicKey,
          exponent: exponent is String ? exponent : null,
        );
      }
    }
    return Map.unmodifiable(result);
  }

  static Map<String, dynamic> _decodeJson(String value) {
    final decoded = jsonDecode(utf8.decode(_decodeBase64Url(value)));
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('JWT component must be an object.');
    }
    return decoded;
  }

  static List<int> _decodeBase64Url(String value) =>
      base64Url.decode(base64Url.normalize(value));

  static PublicKey _publicKey(_TrustedKey key) {
    final bytes = _decodeBase64Url(key.publicKey);
    if (key.algorithm == 'EdDSA') {
      if (bytes.length != 32) {
        throw ArgumentError('Ed25519 key must be 32 bytes.');
      }
      return SimplePublicKey(bytes, type: KeyPairType.ed25519);
    }
    final exponent = key.exponent!;
    final exponentBytes = _decodeBase64Url(exponent);
    if (bytes.length < 256 || bytes.length > 1024 || exponentBytes.length > 4) {
      throw ArgumentError('RS256 issuer key must be at least 2048 bits.');
    }
    return RsaPublicKey(n: bytes, e: exponentBytes);
  }

  static SignatureAlgorithm _algorithm(String name) => switch (name) {
        'EdDSA' => Ed25519(),
        'RS256' => RsaSsaPkcs1v15.sha256(),
        _ => throw ArgumentError('Unsupported algorithm.'),
      };

  static bool _credentialIssuerMatches(
    Map<String, dynamic> credential,
    String jwtIssuer,
  ) {
    final types = credential['type'];
    final validTypes =
        (types is List && types.whereType<String>().isNotEmpty) ||
            (types is String && types.isNotEmpty);
    if (credential['credentialSubject'] is! Map || !validTypes) {
      return false;
    }
    final vcIssuer = credential['issuer'];
    if (vcIssuer is String) return vcIssuer == jwtIssuer;
    if (vcIssuer is Map) return vcIssuer['id'] == jwtIssuer;
    return false;
  }

  static String _credentialType(Map<String, dynamic> credential) {
    final types = credential['type'];
    if (types is List) {
      return types
              .whereType<String>()
              .where((type) => type != 'VerifiableCredential')
              .firstOrNull ??
          'Credential';
    }
    return types is String ? types : 'Credential';
  }
}
