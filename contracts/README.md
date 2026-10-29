# zk-MatchID: Blockchain Trust Layer (Smart Contracts)

The Blockchain Layer provides decentralized trust and integrity without storing any personally identifiable information (PII).

## Smart Contracts

1. **`IssuerRegistry.sol`** — authorized identity providers and public keys.
2. **`CredentialSchemaRegistry.sol`** — schema definitions / hashes.
3. **`RevocationRegistry.sol`** — credential revocation flags and Merkle roots.
4. **`Groth16Verifier.sol`** — snarkjs-exported pairing verifier for `generic_verifier` (Groth16 / BN254).
5. **`ZkIdentityVerifier.sol`** — wrapper that checks issuer status, revocation, nullifier anti-replay, then the Groth16 proof.

> The proving key under `mopro/assets/` was produced with a **local-dev Powers of Tau** (see `mopro/assets/DEV_CEREMONY_README.txt`). Replace with an audited ceremony before any production use.

## Quickstart

```bash
cd contracts
npm install
cp .env.example .env   # fill PRIVATE_KEY + AMOY_RPC_URL for Amoy deploys
npx hardhat compile
npx hardhat test       # includes gas reporter
npx hardhat run scripts/e2e.js
npx hardhat run scripts/deploy.js --network amoy
```

See `../docs/onchain-verification.md` for measured prove/verify/gas numbers and the full runbook.
