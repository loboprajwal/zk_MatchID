# zk-MatchID: Blockchain Trust Layer (Smart Contracts)

The Blockchain Layer provides decentralized trust and integrity without storing any personally identifiable information (PII).

## Smart Contracts

1. **`IssuerRegistry.sol`**:
   - Manages authorized identity providers (Government, Universities, Banks, Employers).
   - Stores issuer public keys, metadata, and activation status.
   - Used by the mobile verifier to validate issuer authenticity.

2. **`CredentialSchemaRegistry.sol`**:
   - Registers standard schema definitions and hashes (e.g., `AgeCredentialSchema`).
   - Ensures consistent attribute definitions across issuers and provers.

3. **`RevocationRegistry.sol`**:
   - Tracks credential revocation status via cryptographic hashes and Merkle accumulator roots.
   - Allows issuers to revoke credentials without revealing user identities.

## Quickstart

```bash
cd contracts
npm install
npx hardhat compile
npx hardhat test
```
