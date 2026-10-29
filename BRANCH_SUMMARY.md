# Branch `feat/onchain-verifier`: What We Built

This branch adds **on-chain zero-knowledge proof verification**, which covers SOP Objective 3. It also adds the first measured numbers for Objective 4.

## What's new

| Area | What was added | Files |
|---|---|---|
| Trusted setup | A local development Powers of Tau (2^12) plus the Groth16 setup for `generic_verifier`. The public ptau mirrors were blocked, so these keys are for development only. | `circuits/scripts/setup_local_dev.sh`, `mopro/assets/DEV_CEREMONY_README.txt` |
| Circuit artifacts | Matching `wasm`, `zkey`, `r1cs` and `verification_key.json` files | `mopro/assets/`, `mobile/assets/verification_key.json` |
| Solidity verifier | `Groth16Verifier.sol`, exported with snarkjs | `contracts/contracts/Groth16Verifier.sol` |
| Identity verifier wrapper | `ZkIdentityVerifier.sol` checks the issuer in IssuerRegistry, checks revocation in RevocationRegistry, blocks nullifier replay and emits an event | `contracts/contracts/ZkIdentityVerifier.sol` |
| Tests | 7 Hardhat tests, all passing, with gas reporting | `contracts/test/` |
| Network | Polygon Amoy network config (chainId 80002) and `.env.example` | `contracts/hardhat.config.js`, `contracts/.env.example` |
| Scripts | A script that deploys every contract, and an end-to-end script that proves, then verifies off-chain, then verifies on-chain | `contracts/scripts/deploy.js`, `contracts/scripts/e2e.js` |
| Docs | Runbook with the results | `docs/onchain-verification.md` |

## Test coverage
These 7 tests pass:
- a valid age proof
- a valid income proof
- a tampered public input
- a tampered proof
- a revoked credential
- a nullifier replay
- an inactive issuer

## Measured results (local Hardhat)

| Predicate | Constraints | Prove | Off-chain verify | On-chain gas |
|---|---:|---:|---:|---:|
| Age ≥ 18 | 350 | 471 ms | 14 ms | 324,972 |
| Income ≥ 4000 | 350 | 79 ms | 8 ms | 324,936 |

## How to run
```bash
cd contracts
npm install
npx hardhat test                                # tests + gas report
node scripts/e2e.js                             # end-to-end prove + verify
npx hardhat run scripts/deploy.js --network amoy  # needs PRIVATE_KEY in .env
```

## Caveats
- The ceremony is a local development one. Replace it with an audited ptau before making any security claims.
- Not deployed on Amoy yet. That needs a funded testnet key.

## Still to build
1. Deploy to Polygon Amoy and record the contract addresses.
2. Real EdDSA (Baby Jubjub) issuer signing, with the signature checked inside the circuit.
3. Circuit tests that generate and verify real proofs, plus a dedicated degree predicate.
4. A native mopro prover in the Flutter app, with the simulated proofs removed.
5. Connect the mobile app to the Amoy contracts (the offline QR path stays).
6. Objective 4: Amoy benchmarks and the DigiLocker comparison write-up.
