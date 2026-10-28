import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zk_match_id/features/verification/credential_verification_service.dart';

void main() {
  const issuer = 'did:example:registry';
  const kid = '$issuer#key-1';
  final algorithm = Ed25519();

  test('trusted, unexpired signed credential QR verifies', () async {
    final keyPair = await algorithm.newKeyPair();
    final publicKey = await keyPair.extractPublicKey();
    final service = CredentialVerificationService(
      trustRegistry: _registry(issuer, kid, base64Url.encode(publicKey.bytes)),
    );
    final token = await _signedCredential(
      algorithm,
      keyPair,
      issuer: issuer,
      kid: kid,
      now: DateTime.utc(2030),
      expiry: DateTime.utc(2031),
    );

    final result = await service.verifyQr(
      'zkmatchid-credential:v1:$token',
      now: DateTime.utc(2030),
    );
    expect(result.verified, isTrue);
    expect(result.issuer, issuer);
    expect(result.credentialType, 'IdentityCredential');
  });

  test('unknown issuer and invalid signature fail closed', () async {
    final keyPair = await algorithm.newKeyPair();
    final publicKey = await keyPair.extractPublicKey();
    final token = await _signedCredential(
      algorithm,
      keyPair,
      issuer: issuer,
      kid: kid,
      now: DateTime.utc(2030),
      expiry: DateTime.utc(2031),
    );
    final untrusted = CredentialVerificationService(trustRegistry: const {});
    expect(
      (await untrusted.verifyQr(token, now: DateTime.utc(2030))).status,
      CredentialCheckStatus.untrustedIssuer,
    );

    final service = CredentialVerificationService(
      trustRegistry: _registry(issuer, kid, base64Url.encode(publicKey.bytes)),
    );
    final pieces = token.split('.');
    final tampered = '${pieces[0]}.${pieces[1]}.'
        '${base64Url.encode(List<int>.filled(64, 0))}';
    expect(
      (await service.verifyQr(tampered, now: DateTime.utc(2030))).status,
      CredentialCheckStatus.invalidSignature,
    );
  });

  test('expired credential is rejected even with a valid signature', () async {
    final keyPair = await algorithm.newKeyPair();
    final publicKey = await keyPair.extractPublicKey();
    final service = CredentialVerificationService(
      trustRegistry: _registry(issuer, kid, base64Url.encode(publicKey.bytes)),
    );
    final token = await _signedCredential(
      algorithm,
      keyPair,
      issuer: issuer,
      kid: kid,
      now: DateTime.utc(2028),
      expiry: DateTime.utc(2029),
    );
    expect(
      (await service.verifyQr(token, now: DateTime.utc(2030))).status,
      CredentialCheckStatus.expired,
    );
  });
}

Map<String, dynamic> _registry(String issuer, String kid, String publicKey) => {
      'issuers': [
        {
          'id': issuer,
          'keys': [
            {'kid': kid, 'alg': 'EdDSA', 'publicKey': publicKey},
          ],
        },
      ],
    };

Future<String> _signedCredential(
  Ed25519 algorithm,
  KeyPair keyPair, {
  required String issuer,
  required String kid,
  required DateTime now,
  required DateTime expiry,
}) async {
  final header = _encodeJson(
      {'typ': 'zkmatchid-credential+jwt', 'alg': 'EdDSA', 'kid': kid});
  final payload = _encodeJson({
    'iss': issuer,
    'sub': 'did:example:holder',
    'iat': now.millisecondsSinceEpoch ~/ 1000,
    'exp': expiry.millisecondsSinceEpoch ~/ 1000,
    'vc': {
      'type': ['VerifiableCredential', 'IdentityCredential'],
      'issuer': {'id': issuer},
      'credentialSubject': {'id': 'did:example:holder'},
    },
  });
  final signingInput = '$header.$payload';
  final signature = await algorithm.sign(
    utf8.encode(signingInput),
    keyPair: keyPair,
  );
  return '$signingInput.${base64Url.encode(signature.bytes).replaceAll('=', '')}';
}

String _encodeJson(Map<String, dynamic> value) =>
    base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
