import 'dart:convert';
import 'dart:math';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/verifiable_credential.dart';

/// Secure Vault Service managing encrypted user credentials and secrets.
class VaultService {
  static final VaultService _instance = VaultService._internal();
  factory VaultService() => _instance;
  VaultService._internal();

  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  static const String _keyBirthYear = 'vault_birth_year';
  static const String _keyUserSecret = 'vault_user_secret';
  static const String _keyDobString = 'vault_dob_string';
  static const String _keyCredentialsList = 'vault_credentials_list';
  static const String _keyCredentialVersion = 'vault_credential_version';

  /// Bumped whenever the default multi-sector credential set changes so
  /// existing vaults are upgraded in place (e.g. when new predicate
  /// attributes such as institutionId / jurisdictionCode are introduced).
  static const String _credentialVersion = '2';

  /// Initializes the mock test identity & signed Verifiable Credentials if not already set.
  Future<void> initializeDefaultIdentity() async {
    final existingBirthYear = await _storage.read(key: _keyBirthYear);
    final storedVersion = await _storage.read(key: _keyCredentialVersion);
    final needsCredentialSeed =
        existingBirthYear == null || storedVersion != _credentialVersion;

    if (needsCredentialSeed) {
      if (existingBirthYear == null) {
        final rng = Random.secure();
        final secret = List<int>.generate(16, (_) => rng.nextInt(256))
            .map((b) => b.toRadixString(16).padLeft(2, '0'))
            .join();

        await _storage.write(key: _keyDobString, value: '2000-01-01');
        await _storage.write(key: _keyBirthYear, value: '2000');
        await _storage.write(key: _keyUserSecret, value: secret);
      }

      // Pre-load default signed Verifiable Credentials (all four sectors)
      final defaultCredentials = [
        VerifiableCredential(
          id: 'urn:uuid:7c9e6679-7425-40de-944b-e07fc1f90ae7',
          type: ['VerifiableCredential', 'NationalIdentityCredential'],
          issuerId: 'did:zkmatch:gov-uidai',
          issuerName: 'National Identity Authority (Government)',
          schemaId: 'schema:zkmatch:age-verification-v1',
          issuanceDate: '2024-01-01T00:00:00.000Z',
          expirationDate: '2034-01-01T00:00:00.000Z',
          credentialSubject: {
            'id': 'did:zkmatch:holder-local',
            'documentType': 'National_ID',
            'dateOfBirth': '2000-01-01',
            'birthYear': 2000,
            'nationality': 'IND',
          },
          signatureValue: 'a8f9c1b2d4e6f801234567890abcdef1234567890abcdef1234567890abcdef1',
        ),
        VerifiableCredential(
          id: 'urn:uuid:3f8a4b2c-91d5-48ef-b32c-7e6d5a1b0c9f',
          type: ['VerifiableCredential', 'UniversityStudentCredential'],
          issuerId: 'did:zkmatch:university-pes',
          issuerName: 'State University Academic Registry',
          schemaId: 'schema:zkmatch:student-verification-v1',
          issuanceDate: '2024-08-01T00:00:00.000Z',
          expirationDate: '2028-08-01T00:00:00.000Z',
          credentialSubject: {
            'id': 'did:zkmatch:holder-local',
            'studentId': 'UNI-2024-8841',
            'institutionId': 1042,
            'program': 'Computer Science & Engineering',
            'birthYear': 2000,
            'enrollmentStatus': 'Active',
          },
          signatureValue: 'b1c2d3e4f5a6b7c8d9e0f1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b1c2',
        ),
        VerifiableCredential(
          id: 'urn:uuid:5d8e7a6b-9c21-4f3e-8a0b-1d2e3f4a5b6c',
          type: ['VerifiableCredential', 'FinancialSolvencyCredential'],
          issuerId: 'did:zkmatch:bank-apex',
          issuerName: 'Apex National Bank & Credit Authority',
          schemaId: 'schema:zkmatch:financial-solvency-v1',
          issuanceDate: '2024-06-01T00:00:00.000Z',
          expirationDate: '2030-06-01T00:00:00.000Z',
          credentialSubject: {
            'id': 'did:zkmatch:holder-local',
            'accountCategory': 'VerifiedSalaryAccount',
            'monthlyIncome': 5200,
            'creditScore': 760,
            'solvencyStatus': 'Approved',
          },
          signatureValue: 'c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2c3d4',
        ),
        VerifiableCredential(
          id: 'urn:uuid:9b4d2e77-5c31-4a86-9f2d-6e8a1c3b5d7f',
          type: ['VerifiableCredential', 'CivicResidencyCredential'],
          issuerId: 'did:zkmatch:municipal-bda',
          issuerName: 'Bengaluru Municipal Authority',
          schemaId: 'schema:zkmatch:civic-residency-v1',
          issuanceDate: '2024-03-01T00:00:00.000Z',
          expirationDate: '2032-03-01T00:00:00.000Z',
          credentialSubject: {
            'id': 'did:zkmatch:holder-local',
            'jurisdictionCode': 29,
            'district': 'Bengaluru Urban',
            'residencyStatus': 'Active',
          },
          signatureValue: 'd7e8f9a0b1c2d3e4f5a6b7c8d9e0f1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8',
        ),
      ];

      final serialized = jsonEncode(defaultCredentials.map((c) => c.toJson()).toList());
      await _storage.write(key: _keyCredentialsList, value: serialized);
      await _storage.write(key: _keyCredentialVersion, value: _credentialVersion);
    }
  }

  Future<int> getBirthYear() async {
    final val = await _storage.read(key: _keyBirthYear);
    return int.tryParse(val ?? '2000') ?? 2000;
  }

  Future<String> getDobString() async {
    final val = await _storage.read(key: _keyDobString);
    return val ?? '2000-01-01';
  }

  Future<String> getUserSecretKey() async {
    final val = await _storage.read(key: _keyUserSecret);
    return val ?? '1234567890abcdef1234567890abcdef';
  }

  Future<List<VerifiableCredential>> getCredentials() async {
    final raw = await _storage.read(key: _keyCredentialsList);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list.map((item) => VerifiableCredential.fromJson(item as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> addCredential(VerifiableCredential vc) async {
    final list = await getCredentials();
    list.add(vc);
    final serialized = jsonEncode(list.map((c) => c.toJson()).toList());
    await _storage.write(key: _keyCredentialsList, value: serialized);
  }

  Future<void> updateIdentity({
    required String dobString,
    required int birthYear,
  }) async {
    await _storage.write(key: _keyDobString, value: dobString);
    await _storage.write(key: _keyBirthYear, value: birthYear.toString());
  }
}
