# On-chain Groth16 Verification (Polygon Amoy path)

This document covers the on-chain verifier chunk for SOP Objective 3:
a Solidity Groth16 verifier for `generic_verifier`, a thin identity wrapper
(issuer + revocation + nullifier anti-replay), Hardhat tests with gas
reporting, local e2e timings, and Amoy deploy wiring.

## Ceremony warning (dev only)

Public Powers of Tau mirrors (`storage.googleapis.com/zkevm/ptau/...`, Hermez
S3, PSE) returned **HTTP 403** in the build environment. The proving key in
`mopro/assets/generic_verifier_final.zkey` was therefore produced from a
**local 2^12 Powers of Tau** (`snarkjs powersoftau new bn128 12` → contribute →
beacon → prepare phase2). See `mopro/assets/DEV_CEREMONY_README.txt`.

**Do not use this zkey / `Groth16Verifier.sol` on mainnet.** Before any
security-sensitive deploy, re-run setup against an audited multi-party
ceremony file such as `powersOfTau28_hez_final_12.ptau`, then re-export the
Solidity verifier and refresh `verification_key.json` in both
`mopro/assets/` and `mobile/assets/`. The `.wasm`, `.zkey`, and vkey **must
always match the same circuit + ceremony**.

## Artifacts

| File | Role |
|------|------|
| `circuits/src/generic_verifier.circom` | Multi-predicate circuit (age / income / set) |
| `mopro/assets/generic_verifier.wasm` | Witness calculator |
| `mopro/assets/generic_verifier_final.zkey` | Groth16 proving key (local-dev ceremony) |
| `mopro/assets/generic_verifier.r1cs` | R1CS (350 constraints) |
| `mopro/assets/verification_key.json` | Verification key (also copied to `mobile/assets/`) |
| `contracts/contracts/Groth16Verifier.sol` | snarkjs-exported pairing verifier |
| `contracts/contracts/ZkIdentityVerifier.sol` | Issuer + revocation + nullifier wrapper |

Public signal order (snarkjs):

```
[0] nullifier
[1] predicateMode
[2] thresholdA
[3] thresholdB
[4..8] allowedSet[5]
[9] currentTimestamp
[10] sessionNonce
```

## Measured results (local Hardhat, 2026-10-29 Asia/Calcutta box)

| Predicate | Constraints | Prove (ms) | Off-chain verify (ms) | On-chain `verifyIdentity` gas |
|-----------|------------:|-----------:|----------------------:|------------------------------:|
| Age ≥ 18 (mode 3) | 350 | 471 | 14 | **324,972** |
| Income ≥ 4000 (mode 1) | 350 | 79 | 8 | **324,936** |

Additional gas (from `hardhat-gas-reporter` on the test suite):

| Op | Avg gas |
|----|--------:|
| `ZkIdentityVerifier.verifyIdentity` | ~324,984 |
| `IssuerRegistry.registerIssuer` | ~278,866 |
| `RevocationRegistry.revokeCredential` | ~49,103 |
| Deploy `Groth16Verifier` | ~551,775 |
| Deploy `ZkIdentityVerifier` | ~473,408 |

Raw JSON: `contracts/deployments/e2e-local-results.json`.

> First prove after process start is slower (wasm JIT / curve init). Re-runs of
> income in the same process were ~80 ms; cold age prove was ~470 ms on this box.

## How to run

### 1. Install & compile

```bash
cd contracts
npm install
npx hardhat compile
```

### 2. Tests (valid / tampered / revoked / replay) + gas

```bash
cd contracts
REPORT_GAS=true npx hardhat test
```

Expected: **7 passing**.

### 3. Local e2e (prove + off-chain + on-chain gas)

```bash
cd contracts
npx hardhat run scripts/e2e.js
```

### 4. Deploy locally (in-process Hardhat)

```bash
cd contracts
npx hardhat run scripts/deploy.js
# writes contracts/deployments/hardhat.json
```

### 5. Deploy to Polygon Amoy (chainId 80002)

```bash
cd contracts
cp .env.example .env
# edit .env:
#   AMOY_RPC_URL=https://rpc-amoy.polygon.technology
#   PRIVATE_KEY=0x...   # funded Amoy account
npx hardhat run scripts/deploy.js --network amoy
# writes contracts/deployments/amoy.json
```

Amoy config lives in `contracts/hardhat.config.js` (`networks.amoy`).

### 6. Re-run Groth16 setup (optional)

If you obtain a real ptau:

```bash
cd circuits
npm install
# place powersOfTau28_hez_final_12.ptau in build/
bash scripts/compile_circuit.sh generic_verifier
# then re-export Solidity verifier:
npx snarkjs zkey export solidityverifier \
  build/generic_verifier_final.zkey \
  ../contracts/contracts/Groth16Verifier.sol
```

Or regenerate a local-dev ceremony with `bash scripts/setup_local_dev.sh`.

## Wrapper behaviour (`ZkIdentityVerifier`)

1. `IssuerRegistry.isIssuerActive(issuerId)` — else `IssuerInactive`
2. `RevocationRegistry.isCredentialRevoked(credentialHash)` — else `CredentialRevoked`
3. Nullifier `pubSignals[0]` not previously used — else `NullifierAlreadyUsed`
4. `Groth16Verifier.verifyProof(...)` — else `InvalidProof`
5. Mark nullifier used; emit `IdentityVerified`

`issuerId` and `credentialHash` are calldata (not circuit-bound). Binding the
issuer signature into the circuit remains future work.
