import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:zk_match_id/features/verification/credential_wallet_matcher.dart';

void main() {
  const localCredential = <String, dynamic>{
    'type': ['VerifiableCredential', 'NationalIdentityCredential'],
    'issuer': {'id': 'did:example:issuer'},
    'credentialSubject': {
      'name': 'Asha Rao',
      'aadhaarNumber': '123456781234',
    },
  };

  test('reads a W3C credential JSON object', () {
    final decoded = PresentedCredential.decode(jsonEncode(localCredential));
    expect(decoded.credential['credentialSubject'], isA<Map>());
    expect(decoded.source, 'credential JSON');
  });

  test('unwraps a DigiLocker JSON response containing an issued document', () {
    final decoded = PresentedCredential.decode(jsonEncode({
      'response': {
        'issuedDocuments': [
          {
            'documentType': 'IdentityCard',
            'name': 'Asha Rao',
            'maskedAadhaar': 'XXXX XXXX 1234',
          }
        ]
      }
    }));
    expect(decoded.credential['documentType'], 'IdentityCard');
    expect(decoded.source, 'DigiLocker JSON');
  });

  test('matches holder name and masked ID suffix against wallet credential', () {
    final match = CredentialWalletMatcher.match(
      walletName: 'My wallet',
      presented: const {
        'documentType': 'IdentityCard',
        'name': 'Asha Rao',
        'maskedAadhaar': 'XXXX XXXX 1234',
      },
      walletCredentials: const [localCredential],
    );
    expect(match.nameMatches, isTrue);
    expect(match.maskedIdentifierMatches, isTrue);
    expect(match.matches, isTrue);
    expect(match.maskedIdentifiers, ['•••• 1234']);
  });

  test('rejects a different holder name or identifier', () {
    final mismatch = CredentialWalletMatcher.match(
      walletName: 'My wallet',
      presented: const {
        'name': 'Asha Rao',
        'maskedAadhaar': 'XXXX XXXX 9876',
      },
      walletCredentials: const [localCredential],
    );
    expect(mismatch.nameMatches, isTrue);
    expect(mismatch.maskedIdentifierMatches, isFalse);
    expect(mismatch.matches, isFalse);

    final wrongHolder = CredentialWalletMatcher.match(
      walletName: 'My wallet',
      presented: const {
        'name': 'Another Person',
        'maskedAadhaar': 'XXXX XXXX 1234',
      },
      walletCredentials: const [localCredential],
    );
    expect(wrongHolder.nameMatches, isFalse);
    expect(wrongHolder.maskedIdentifierMatches, isTrue);
    expect(wrongHolder.matches, isFalse);
  });

  test('rejects oversized or non-JSON input', () {
    expect(
      () => PresentedCredential.decode('x' * (2 * 1024 * 1024 + 1)),
      throwsFormatException,
    );
    expect(() => PresentedCredential.decode('not a credential'),
        throwsFormatException);
  });
}
