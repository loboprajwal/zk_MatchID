# Test cases and execution evidence

The following summarizes real commands run in this workspace. Results are not claims about a physical Android device, live Supabase, or web runtime.

| ID | Description | Expected | Actual | Result |
|---|---|---|---|---|
| FL-ANALYZE | `flutter analyze --no-pub` | No analyzer issues | `No issues found! (ran in 7.6s)` | Pass |
| FL-UNIT | `flutter test --no-pub -r expanded` | Unit/widget tests pass | `All tests passed!`; 41 passed, 6 skipped because native generic prover/verifier is not loaded | Pass with documented skips |
| FL-STORE-01 | Legacy migration preserves wallet credentials | Wallet #1 remains readable after verified onboarding migration | Test checks encrypted Wallet #1, removes old plaintext JSON keys after successful copy, and retains credential | Pass |
| FL-STORE-02 | Wallet key protects credential vault | Different mnemonic key cannot decrypt vault | Test changes the stored key and expects authenticated decryption to fail | Pass |
| FL-STORE-03 | Wallet separation and global document uniqueness | Wallets isolated; same document cannot be stored twice across local wallets | Test switches wallets and rejects cross-wallet duplicate | Pass |
| ISS-01 | Demo credential is signed with Ed25519 and verifies | Valid demo envelope | `npm test`: 4 passing | Pass |
| ISS-02 | Mismatch, duplicate, tampered, expired and revoked demo inputs fail | Clear rejection | Issuer negative-path cases included in 4 passing tests | Pass |
| CH-01 | Solidity issuer/schema/revocation authorization and state | Unauthorized calls fail; allowed updates work | Hardhat `npm test`: 3 passing | Pass |
| CIR-01 | Legacy age circuit constraints | Tests pass | Circuit `npm test`: 3 passing; no generic circuit test was present | Partial |
| APK-01 | Android debug build | APK builds | `flutter build apk --debug`: `Built build\\app\\outputs\\flutter-apk\\app-debug.apk` | Pass |
| SB-01 | Supabase unique/RLS/function tests | Local Supabase passes pgTAP and integration cases | Supabase CLI, Docker and PostgreSQL unavailable; test file not executed | Blocked |
| AND-01 | Physical face camera onboarding and screenshots | Camera detects poses and failure UI is captured | No Android emulator/device available; emulator launch failed | Blocked |
| ZK-01 | Native Mopro proof generation | Real proof is generated and verified | Native library and compiled proving artifacts absent; six native tests skipped | Blocked |

The repository contains `supabase/tests/schema_security.sql` for database constraint smoke checks. Backend negative cases (RLS cross-user reads, role escalation, replay, expiry, revocation, malformed payload) still require a local Supabase integration test run before a backend release.
