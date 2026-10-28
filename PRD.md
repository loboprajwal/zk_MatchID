# Product Requirements Document: zk-MatchID
*Generic Privacy-Preserving Identity Verification Engine with Zero-Knowledge Proofs*  
**"Prove what's needed. Keep the rest private."**

---

## 1. Project Goal & Real-World Problem Statement

Current identity verification systems rely on dangerous **over-disclosure** and **centralized tracking**:
- Patrons showing driver's licenses for 18+ venue entry unnecessarily disclose full names, exact dates of birth, and home addresses.
- Prospective tenants applying for housing upload unencrypted bank statements and tax filings to prove financial solvency ($Income \ge \$4,000/\text{mo}$, $CreditScore \ge 700$), creating high exposure to identity theft and data leaks.
- Students and citizens proving institutional membership or regional residency are tracked through centralized API calls that log user activity across the web and physical locations.

**zk-MatchID** provides a generic, peer-to-peer (P2P), offline-first zero-knowledge verification engine. It enables individuals to prove customizable predicates (such as age limits, income solvency, institutional enrollment, or regional residency) using digitally signed Verifiable Credentials (VCs) issued by trusted authorities—without transmitting or revealing any underlying personally identifiable information (PII).

---

## 2. Core Verification Capabilities & Predicate Modes

The zk-MatchID cryptographic engine implements four generic predicate evaluation modes:

1. **Threshold & Range Predicates (`Mode 1 & Mode 3`):**
   - Proves a private numeric attribute satisfies a threshold or bounded range without disclosing the exact quantity:
     - **Adult Verification:** $currentYear - birthYear \ge ageLimit$.
     - **Income Solvency:** $monthlyIncome \ge minRequiredIncome$ (e.g., $\ge \$4,000/\text{mo}$).
     - **Credit Reliability:** $minScore \le creditScore \le maxScore$ (e.g., $700 \le score \le 850$).
2. **Whitelisted Set Membership Predicates (`Mode 2`):**
   - Proves a private attribute belongs to an authorized set of $N$ entities without disclosing which one:
     - **Academic Enrollment:** $institutionId \in \{\text{Accredited University Whitelist}\}$.
     - **Regional Residency:** $jurisdictionCode \in \{\text{Eligible States / Municipalities}\}$.
3. **Temporal Validity & Expiration Predicates:**
   - Enforces that credentials and authorizations are strictly active:
     - $credentialExpiry \ge currentTimestamp$.
4. **Anti-Replay Interactive Nullifier:**
   - Evaluates a cryptographic nullifier:
     $$\text{nullifier} = \text{Poseidon}(\text{userSecretKey}, \text{sessionNonce})$$
   - Binds the proof to a single ephemeral verifier challenge, preventing camera recording and replay attacks.

---

## 3. Architecture Overview & System Layers

### Layer 1: Trusted Issuers (Identity Providers)
- **Entities:** Government agencies (UIDAI, Passport, RTO), Academic Registrars (Universities), Financial Institutions (Banks, Tax Authorities), and Licensing Boards.
- **Function:** Issues **Digitally Signed Verifiable Credentials (VCs)** using asymmetric private keys.
- **Attributes Supported:** `birthYear`, `dateOfBirth`, `monthlyIncome`, `creditScore`, `institutionId`, `enrollmentStatus`, `jurisdictionCode`.
- **Privacy Standard:** Zero personal data is ever committed to public networks or blockchains.

### Layer 2: Blockchain Layer — Trust & Integrity (No Personal Data)
- **Issuer Registry (`IssuerRegistry.sol`):** Public smart contract maintaining authorized issuers, public keys, and active statuses across government, university, and financial sectors.
- **Credential Schemas (`CredentialSchemaRegistry.sol`):** Standardized schemas (`AgeSchema`, `FinancialSolvencySchema`, `StudentSchema`, `ResidencySchema`).
- **Revocation Registry (`RevocationRegistry.sol`):** On-chain Merkle accumulator roots and cryptographic revocation lists (CRLs) allowing instant offline non-revocation checks.

### Layer 3: User Mobile App (Prover - Flutter & Mopro)
1. **Identity Vault (Secure Storage):**
   - Multi-credential wallet storing signed VCs.
   - Encrypted with hardware KeyStore / Secure Enclave and protected by Biometric / Face Unlock.
2. **On-Device ZK Proving Engine (Mopro BN254):**
   - Automatically maps selected credential attributes to generic circuit witness inputs.
   - Compiles witness and generates Groth16 zero-knowledge proofs natively on-device in $< 2.0$ seconds.
3. **Dynamic QR Encoding (Base85):**
   - Packs Groth16 points and public inputs into compressed Ascii85 for rapid optical camera scanning with short TTL.

### Layer 4: Verifier (Relying Party - Venues, Landlords, Campuses)
1. **Dynamic Challenge Generation:**
   - Generates an ephemeral session nonce with a 60–120s TTL and displays a request QR code.
2. **Offline Scan & Verify:**
   - Scans the Prover's dynamic QR code using the in-app camera.
   - Evaluates Groth16 pairing equations offline on the BN254 curve.
   - Validates anti-replay nonce freshness and checks issuer authenticity against the local blockchain cache.
3. **Result Presentation:**
   - Displays clear, minimal verification cards (e.g., `"VERIFIED: Income Solvency Met ✓"`, `"VERIFIED: Age >= 18 ✓"`) with zero PII disclosed.

---

## 4. Real-World Use Case Profiles

| Profile Name | Target Use Case | Credential Source | Evaluated Predicate | PII Kept Private |
| :--- | :--- | :--- | :--- | :--- |
| **Nightlife & Venues** | Bars, clubs, restricted entertainment | Government ID VC | $Age \ge 18 \text{ or } 21$ | Name, DOB, address, license number |
| **Tenant Solvency** | Apartment rentals, leasing | Bank / Payroll VC | $Income \ge \$4,000/\text{mo}$ | Bank statements, salary, employer |
| **Credit Eligibility** | Loan pre-qualification, utilities | Credit Bureau VC | $CreditScore \ge 700$ | SSN, payment history, debt balances |
| **Student Discount** | Campus perks, transit, software | University Student VC | $Institution \in Whitelist$ | Student ID, roll number, grades |
| **Civic Subsidies** | Regional voting, public transport | Municipal VC | $Region \in AllowedStates$ | Street address, utility bills |

---

## 5. Security & Privacy Guarantees
- **Selective Disclosure:** Users prove only the required predicate; all collateral attributes remain secret.
- **Offline Resilience:** Pairing checks and nonce validations execute 100% offline without cellular or WiFi connectivity.
- **Anti-Tracking:** Ephemeral nonces and Poseidon nullifiers ensure verifiers cannot correlate multiple visits by the same user.
- **Hardware-Enforced Keys:** Private ZK seeds and credentials never leave the mobile device's secure hardware vault.