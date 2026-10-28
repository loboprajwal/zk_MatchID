# zk-MatchID: End-to-End Privacy-Preserving Identity Verification

[![Flutter](https://img.shields.io/badge/Flutter-3.35.1-02569B?logo=flutter)](https://flutter.dev)
[![Circom](https://img.shields.io/badge/Circom-2.1+-yellow)](https://docs.circom.io)
[![Solidity](https://img.shields.io/badge/Solidity-0.8.20-363636?logo=solidity)](https://soliditylang.org/)
[![Groth16](https://img.shields.io/badge/Cryptography-Groth16_BN254-blueviolet)](https://eprint.iacr.org/2016/260)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

> *"Prove what's needed. Keep the rest private."*

**zk-MatchID** is an offline-first, peer-to-peer (P2P) zero-knowledge mutual identity verification platform. It allows individuals to prove identity predicates (e.g., "Age $\ge$ 18" or credential status) using digitally signed Verifiable Credentials (VCs) issued by trusted authorities, without disclosing full name, date of birth, or any personally identifiable information (PII).

---

## 4-Layer Architecture

```
┌────────────────────────────────────────────────────────┐
│ 1. Trusted Issuers (Identity Providers)                │
│    Govt (UIDAI/Passport), Universities, Employers      │
│    • Digitally Signed Verifiable Credentials (VCs)     │
└──────────────────────────┬─────────────────────────────┘
                           │
┌──────────────────────────▼─────────────────────────────┐
│ 2. Blockchain Layer - Trust & Integrity (No PII)       │
│    • IssuerRegistry.sol (Public keys & status)         │
│    • CredentialSchemaRegistry.sol (Schema definitions) │
│    • RevocationRegistry.sol (CRLs & Merkle roots)      │
└──────────────────────────┬─────────────────────────────┘
                           │
┌──────────────────────────▼─────────────────────────────┐
│ 3. User Mobile App (Prover - Flutter & Mopro)          │
│    • Identity Vault (Biometric KeyStore & VCs)         │
│    • On-Device Groth16 Prover (BN254 curve, < 2.0s)    │
│    • Dynamic QR Codec (Ascii85 / Base85 Compression)   │
└──────────────────────────┬─────────────────────────────┘
                           │  (P2P Offline Dynamic QR)
┌──────────────────────────▼─────────────────────────────┐
│ 4. Verifier (Relying Party - Venue/Event/Service)      │
│    • Ephemeral Challenge Generator (Nonce QR + TTL)    │
│    • Offline Scanner & Groth16 Pairing Verifier        │
│    • Policy Match, Issuer & Anti-Replay Checks         │
│    • Result Card: "VERIFIED: Income Solvency Met ✓"    │
└────────────────────────────────────────────────────────┘
```

---

## Repository Structure

```
zk-MatchID/
├── circuits/                         # Phase 1: Circom 2.1 ZK Circuit Layer
│   ├── src/
│   │   ├── generic_verifier.circom   # Multi-predicate circuit (threshold, set membership, expiry, nullifier)
│   │   └── age_verifier.circom       # Legacy single-purpose baseline circuit
│   ├── scripts/
│   │   ├── compile_circuit.sh        # Bash compilation & Powers of Tau trusted setup
│   │   └── compile_circuit.ps1       # PowerShell compilation helper for Windows
│   ├── tests/
│   │   └── age_verifier.test.js      # Circuit constraint and nullifier test suite
│   ├── package.json                  # snarkjs, circomlib dependencies
│   └── .gitignore
│
├── mopro/                            # Phase 2: Mopro Native Proving Engine (Rust)
│   ├── Cargo.toml                    # Cargo manifest with mopro-ffi, arkworks, uniffi
│   ├── mopro.toml                    # Mopro target config for Android (NDK) & iOS
│   ├── src/
│   │   ├── lib.rs                    # UniFFI and C-ABI exports for Dart FFI
│   │   ├── prover.rs                 # Native Groth16 witness & proof generation (< 2.0s)
│   │   └── verifier.rs               # Offline Groth16 pairing verifier
│   ├── assets/                       # Destination for compiled r1cs, zkey, and vkey
│   │   └── .gitkeep
│   ├── scripts/
│   │   ├── build_mobile.sh           # Shell script to compile Android .so & iOS framework
│   │   └── build_mobile.ps1          # Windows build helper
│   └── .gitignore
│
├── contracts/                        # Phase 3: Blockchain Trust Layer (Solidity)
│   ├── contracts/
│   │   ├── IssuerRegistry.sol        # Authorized identity providers & public keys
│   │   ├── CredentialSchemaRegistry.sol # Standard credential schema definitions
│   │   └── RevocationRegistry.sol    # Credential revocation status & Merkle roots
│   ├── hardhat.config.js             # Hardhat EVM toolchain configuration
│   ├── package.json
│   └── README.md
│
├── issuer/                           # Phase 4: Trusted Issuer Backend & Mock Service
│   ├── src/
│   │   └── issuer_service.js         # Service to generate & sign Verifiable Credentials
│   ├── sample_credentials/
│   │   ├── government_id_vc.json     # Government ID credential (Age predicate)
│   │   ├── financial_solvency_vc.json # Financial credential (Income predicate)
│   │   ├── university_student_vc.json # University Student credential (Set membership)
│   │   └── civic_residency_vc.json   # Municipal Residency credential (Set membership)
│   ├── package.json
│   └── README.md
│
├── mobile/                           # Phase 5 & 6: Mobile Application (Flutter)
│   ├── lib/
│   │   ├── main.dart                 # App entrypoint with navigation tabs & Material 3 theme
│   │   ├── core/
│   │   │   ├── native_bridge.dart    # Dart FFI bridge to Mopro Rust shared library
│   │   │   ├── qr_codec.dart         # Base85 Groth16 proof & public input compression
│   │   │   ├── nonce_manager.dart    # Interactive anti-replay session nonce manager
│   │   │   ├── vault_service.dart    # Biometric / encrypted credential vault
│   │   │   └── blockchain_service.dart # On-chain issuer & revocation query/cache
│   │   ├── screens/
│   │   │   ├── vault_screen.dart     # Identity Vault (VC list, biometric lock, ZK key)
│   │   │   ├── prover_screen.dart    # Proof template selection (Age/Income/Student/Residency)
│   │   │   ├── verifier_screen.dart  # Policy selector, challenge QR, camera scanner
│   │   │   └── benchmark_dashboard.dart # Performance metrics & real-time graphs
│   │   ├── widgets/
│   │   │   ├── qr_display.dart       # High-density dynamic QR renderer
│   │   │   ├── qr_scanner_view.dart  # Offline camera scanner view
│   │   │   └── verification_badge.dart # Verification success/failure result card
│   │   ├── benchmark/
│   │   │   ├── benchmark_runner.dart # 50-cycle automated benchmark runner
│   │   │   └── metrics_exporter.dart # CSV export to mobile device storage
│   │   └── models/
│   │       ├── verifiable_credential.dart # W3C Verifiable Credential data model
│   │       ├── proof_payload.dart    # Groth16 proof with predicateType & TTL
│   │       ├── verification_policy.dart # Shared prover templates & verifier policies
│   │       └── benchmark_metric.dart # Metric data point model
│   ├── pubspec.yaml                  # Flutter dependencies
│   └── test/
│       └── widget_test.dart          # Widget integration tests
│
├── docs/                             # System Documentation
│   ├── architecture.md               # End-to-end architecture & Groth16 pairing specs
│   └── handshake_protocol.md         # Interactive anti-replay QR handshake specs
│
├── PRD.md                            # Product Requirements Document
├── AI Vibe-Coding Execution Prompts  # Multi-phase execution prompt specs
├── System Verification Checklist     # Acceptance test checklist
└── .gitignore                        # Global repository gitignore
```

---

## 6-Step End-to-End Flow

1. **Issuer Onboards:** Issuer registers public key and credential schema on the Blockchain Layer (`IssuerRegistry.sol`).
2. **Issue Credential:** Issuer signs credential and delivers it to the user (`issuer_service.js`).
3. **Store in Vault:** User securely stores credential in encrypted mobile vault (`VaultScreen`).
4. **Verifier Challenge:** Verifier selects the required policy (Age / Income / Student / Residency), generates an ephemeral session nonce, and shows the QR code (`VerifierScreen`).
5. **Generate Proof:** User selects a proof template and generates the multi-predicate ZK proof on-device bound to the verifier nonce, displaying the QR (`ProverScreen`).
6. **Verify:** Verifier scans QR, enforces the policy match, and checks proof, nonce, and issuer status offline, displaying the policy result: `"VERIFIED: Income Solvency Met ✓"`.

---

## Quickstart Guide

### 1. Smart Contracts (`contracts/`)
```bash
cd contracts
npm install
npx hardhat compile
```

### 2. Issuer Service (`issuer/`)
```bash
cd issuer
npm run issue
```

### 3. ZK Circuits (`circuits/`)
```bash
cd circuits
npm install
npm run compile           # Linux / macOS / WSL
# OR:
npm run compile:windows   # Windows PowerShell
```

### 4. Mopro Mobile Bindings (`mopro/`)
```bash
cd mopro
bash scripts/build_mobile.sh
# OR:
powershell -ExecutionPolicy Bypass -File scripts/build_mobile.ps1
```

### 5. Mobile Application (`mobile/`)
```bash
cd mobile
flutter pub get
flutter test
flutter run
```
