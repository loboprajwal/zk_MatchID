# Implementation Plan: Generic Multi-Predicate ZK Verification Engine

Transform the project specifications and `AI Vibe-Coding Execution Prompts` from a single-purpose "Age Verifier" into a **Generic, Multi-Predicate Zero-Knowledge Verification Engine** solving critical real-world identity verification pain points.

---

## 1. Real-World Pain Points & Zero-Knowledge Solutions

| Real-World Scenario & Pain Point | Current Flawed Practice | zk-MatchID Generic ZK Solution |
| :--- | :--- | :--- |
| **1. Nightlife, Hospitality & Venues**<br/>Need to verify patron is 18+ or 21+. | Patron shows physical Driver's License/Passport; bouncer sees full name, exact DOB, address, license number, and can photograph it. | **Age Predicate Proof**: Proves $currentYear - birthYear \ge ageLimit$ using government-issued VC with zero PII disclosed. |
| **2. Apartment Rentals & Loan Pre-qualification**<br/>Need to verify applicant earns $\ge \$4,000/\text{mo}$ or credit score $\ge 700$. | Tenant uploads 3 months of bank statements, tax returns, and SSN; high risk of identity theft and data leaks. | **Income / Solvency Range Proof**: Proves $income \ge minIncome$ and $score \ge minScore$ from bank/tax VC without revealing exact balances or account numbers. |
| **3. Student / Academic Discounts & Software Access**<br/>Need to verify student is actively enrolled. | Student uploads scanned student ID with roll number, photo, and department; manual review or third-party tracking. | **Credential Membership Proof**: Proves active enrollment at an accredited university within an allowed set of institutional IDs without revealing student ID or GPA. |
| **4. Civic Subsidies & Regional Voting / Access**<br/>Need to verify resident belongs to an eligible state or jurisdiction. | User reveals complete street address, utility bills, or passport details. | **Set Membership Proof**: Proves $jurisdiction \in \{\text{allowed\_regions}\}$ without disclosing residential address. |
| **5. License & Certification Compliance**<br/>Need to verify professional license (medical, legal, security clearance) is active and unrevoked. | Centralized database lookup that tracks who is verifying whom, creating surveillance logs. | **Cryptographic Non-Revocation Proof**: Evaluates issuer signature and checks non-revocation accumulator offline against on-chain Merkle root. |

---

## 2. Proposed Changes

### Component 1: `AI Vibe-Coding Execution Prompts`
Rewrite all 6 phases into a comprehensive, enterprise-ready vibe-coding prompt suite:
- **Phase 1: Generic Multi-Predicate Circuit Engineering**
  - Circuit `generic_verifier.circom` with configurable modes:
    - **Mode 1 (Range / Threshold)**: Validates numeric attributes ($attribute \ge threshold$ or $min \le attribute \le max$).
    - **Mode 2 (Set Membership)**: Validates attribute belongs to an allowed set of up to $N$ elements without revealing which one.
    - **Mode 3 (Validity & Expiry)**: Enforces $expirationDate \ge currentDate$.
    - **Mode 4 (Cryptographic Commitment & Anti-Replay)**: $Poseidon(userSecretKey, sessionNonce)$ nullifier.
- **Phase 2: Mopro Native Proving Engine for Generic Predicates**
  - Universal proving wrapper `generate_credential_proof(...)` taking predicate rules, attribute values, and session nonce.
- **Phase 3: Blockchain Decentralized Trust Layer**
  - Multi-schema support (`AgeSchema`, `IncomeSchema`, `StudentSchema`, `AccreditationSchema`).
  - Merkle root revocation accumulators (`RevocationRegistry.sol`).
- **Phase 4: Multi-Issuer Credential Backend**
  - Issuance services for Government (Age/Residency), Financial (Income/Credit), and Academic (Enrollment).
- **Phase 5: Mobile UI with Multi-Profile Verification & QR Handshake**
  - Preset verification profiles (Nightlife 18+, Rental Income Solvency, Student Perk, Regional Residency).
  - Dynamic QR handshake with customizable relying-party criteria.
- **Phase 6: Multi-Predicate Academic Benchmarking Suite**
  - Comparative benchmark across Range Proofs, Set Membership, and Multi-Attribute proofs measuring witness time, proving latency, memory, and Base85 payload sizes.

---

### Component 2: `PRD.md` & System Documentation
- Update `PRD.md` to define the Generic Zero-Knowledge Identity Verification Engine.
- Update `docs/architecture.md` and `docs/handshake_protocol.md` with multi-predicate flows.

---

### Component 3: Circuit & Mobile Codebase Alignment
- **[NEW] `circuits/src/generic_verifier.circom`**: Circom circuit implementing range, set membership, and expiry verification.
- **[MODIFY] `mobile/lib/screens/prover_screen.dart`**: Add proof template selection (Age $\ge 18$, Income Solvency, Student Status, Regional Residency).
- **[MODIFY] `mobile/lib/screens/verifier_screen.dart`**: Allow verifier to select required verification policy.
- **[MODIFY] `mobile/lib/core/native_bridge.dart`**: Support multi-predicate parameters.

---

## 3. Verification Plan

### Automated Checks
- Validate `circuits/package.json` and syntax of `generic_verifier.circom`.
- Run `flutter analyze` and `flutter test` in `mobile/` to ensure zero compilation or lint errors.

### Manual Review
- Ensure prompt guidelines are clear, rigorous, and directly usable by AI agents to construct production-ready circuits and mobile features.
