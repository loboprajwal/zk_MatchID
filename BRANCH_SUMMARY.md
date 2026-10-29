# Branch `feat/upi-qr-demo`: UPI-style multi-wallet ZK QR demo

Demo priority: holder wallets → predicate → consent → QR; verifier scans → big PASS/FAIL.


## Restore note (additive)

A follow-up commit restored every file that had been removed relative to
`feat/onchain-verifier` (DigiLocker onboarding, benchmarks, tests, Android/iOS
config). The UPI demo remains **additive**: `lib/demo/*`, `lib/screens/upi/*`,
`lib/main_demo.dart`, plus a **UPI ZK demo** FAB on the existing MatchID home.
Default `flutter run` still launches `lib/main.dart`. Demo-only:
`flutter run -t lib/main_demo.dart`.


## What's new (this branch)

| Area | What | Files |
|---|---|---|
| Multi-wallet | Create / name / switch wallets; each holds Aadhaar (DOB), degree, address/state samples | `mobile/lib/demo/wallet_store.dart` |
| Prove flow | Predicate picker, consent sheet, QR (5 min TTL + nonce, no raw PII) | `mobile/lib/screens/upi/prove_tab.dart` |
| Verify flow | Camera scan (`mobile_scanner`) + single-device “use last QR” + paste; UPI-style PASS/FAIL card | `mobile/lib/screens/upi/verify_tab.dart`, reused `qr_scanner_view` / `verification_badge` |
| Groth16 proofs | **Real** snarkjs Groth16 proofs precomputed into asset catalog (local-dev zkey). Native mopro **not** required | `mobile/assets/demo_proof_catalog.json`, `scripts/generate_demo_proof_catalog.js` |
| Fallback | HMAC `signed_demo` when catalog slots for wallet×predicate are exhausted — labeled in UI/docs | `mobile/lib/demo/demo_proof_service.dart` |
| Verifier checks | Decode, TTL, nonce single-use, issuer allow-list, catalog proof match (+ vkey metadata) | `mobile/lib/demo/demo_verifier_service.dart` |

## Honest labeling (proof generation)

- Preferred QR path embeds a **real Groth16 proof** from the catalog (produced with `snarkjs.groth16.fullProve` against `mopro/assets/generic_verifier_final.zkey`).
- Flutter runtime does **not** run BN254 pairing itself on this branch; verifier matches the proof to the catalog entry and checks TTL/nonce/issuer. The same artifacts verify with snarkjs / on-chain `Groth16Verifier`.
- If catalog slots are used up, QR falls back to **`signed_demo` (HMAC)** and the UI says so.

## Demo script (UPI-like)

**Prep:** install a debug APK (see below) or `flutter run` on two devices / one device.

### One-device walkthrough
1. Open **Wallets** — three seeds: *Vivek Personal*, *Sagar Work*, *Prajwal Uni*. Tap one to activate. Optionally **New wallet**.
2. Open **Prove** — confirm active wallet. Pick e.g. **Age ≥ 18**.
3. Tap **Consent & generate QR** → read consent → **Allow & generate QR**.
4. Note subtitle: `Real Groth16 (precomputed…)` and expiry hint (5 minutes). Optional: **Copy payload**.
5. Open **Verify** → **Use last generated QR (single-device demo)**.
6. Expect big green **PASS** with claim, issuer, nullifier snippet, catalog id.
7. Tap **New Verification**, then verify the same QR again → **FAIL** (nonce replay).
8. Switch wallet to *Sagar Work*, prove **Holds a degree**, verify → PASS.
9. Prove **Resident of eligible state** on *Prajwal Uni*, verify → PASS.

### Two-device walkthrough
1. Device A (holder): Prove → show QR on screen.
2. Device B (verifier): **Scan QR with camera** → PASS/FAIL card.

### Failure demos
- Wait >5 minutes (or paste an old payload) → FAIL expired.
- Tamper issuer / proof bytes → FAIL.

## How to run mobile

```bash
export PATH="$HOME/flutter/bin:$PATH"   # or your Flutter SDK
cd mobile
flutter pub get
flutter analyze
flutter test
flutter run            # device / emulator
# optional debug APK:
flutter build apk --debug
# APK: build/app/outputs/flutter-apk/app-debug.apk
# (also copied to mobile/dist/zk-matchid-upi-demo-debug.apk locally; not committed)
```

Regenerate proof catalog (needs circuits/node_modules snarkjs + mopro assets):

```bash
node scripts/generate_demo_proof_catalog.js
```

## Caveats
- Ceremony is **local-dev pot12** — not production-trusted.
- Catalog-backed verify ≠ live pairing on-device; use snarkjs / Amoy contracts for full pairing.
- Camera scan needs a real device/emulator with camera permission; single-device button covers projector demos.
- Legacy DigiLocker/OTP screens remain under `lib/features` / `lib/screens` but are not the demo home.

---

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
npx hardhat test
node scripts/e2e.js
npx hardhat run scripts/deploy.js --network amoy
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
