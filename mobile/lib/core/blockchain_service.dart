/// Blockchain Trust & Integrity Service.
/// Simulates and caches on-chain IssuerRegistry and RevocationRegistry states
/// to enable instantaneous, decentralized, offline verification without internet access.
class BlockchainIssuerInfo {
  final String issuerId;
  final String name;
  final String issuerType;
  final String publicKey;
  final bool isActive;
  final DateTime registeredAt;

  BlockchainIssuerInfo({
    required this.issuerId,
    required this.name,
    required this.issuerType,
    required this.publicKey,
    required this.isActive,
    required this.registeredAt,
  });
}

class BlockchainService {
  static final BlockchainService _instance = BlockchainService._internal();
  factory BlockchainService() => _instance;
  BlockchainService._internal() {
    _initializeDefaultRegistry();
  }

  // Local offline cache of on-chain IssuerRegistry
  final Map<String, BlockchainIssuerInfo> _cachedIssuers = {};
  // Local offline cache of revoked credential hashes
  final Set<String> _revokedCredentialHashes = {};

  void _initializeDefaultRegistry() {
    // Onboard default authorized issuers registered on-chain
    _cachedIssuers['did:zkmatch:gov-uidai'] = BlockchainIssuerInfo(
      issuerId: 'did:zkmatch:gov-uidai',
      name: 'National Identity Authority (Government)',
      issuerType: 'Government',
      publicKey: '04a1b2c3d4e5f67890abcdef1234567890abcdef...',
      isActive: true,
      registeredAt: DateTime(2024, 1, 1),
    );

    _cachedIssuers['did:zkmatch:university-pes'] = BlockchainIssuerInfo(
      issuerId: 'did:zkmatch:university-pes',
      name: 'State University Academic Registry',
      issuerType: 'University',
      publicKey: '04b2c3d4e5f67890abcdef1234567890abcdef...',
      isActive: true,
      registeredAt: DateTime(2024, 1, 15),
    );

    _cachedIssuers['did:zkmatch:bank-apex'] = BlockchainIssuerInfo(
      issuerId: 'did:zkmatch:bank-apex',
      name: 'Apex National Bank & Credit Authority',
      issuerType: 'FinancialInstitution',
      publicKey: '04c3d4e5f67890abcdef1234567890abcdef...',
      isActive: true,
      registeredAt: DateTime(2024, 3, 1),
    );

    _cachedIssuers['did:zkmatch:municipal-bda'] = BlockchainIssuerInfo(
      issuerId: 'did:zkmatch:municipal-bda',
      name: 'Bengaluru Municipal Authority',
      issuerType: 'Government',
      publicKey: '04d4e5f6a7b890abcdef1234567890abcdef...',
      isActive: true,
      registeredAt: DateTime(2024, 3, 15),
    );
  }

  /// Verifies if an issuer is registered and in active status on the blockchain
  Future<bool> isIssuerAuthorized(String issuerId) async {
    final issuer = _cachedIssuers[issuerId];
    return issuer != null && issuer.isActive;
  }

  /// Returns cached on-chain issuer details
  BlockchainIssuerInfo? getIssuer(String issuerId) {
    return _cachedIssuers[issuerId];
  }

  /// Verifies if a credential hash has been revoked on the blockchain
  Future<bool> isCredentialRevoked(String credentialHash) async {
    return _revokedCredentialHashes.contains(credentialHash);
  }

  /// Simulates syncing latest registry blocks from blockchain
  Future<void> syncWithBlockchain() async {
    // In production with web3dart / RPC:
    // Queries IssuerRegistry.sol and RevocationRegistry.sol events
    await Future.delayed(const Duration(milliseconds: 300));
  }
}
