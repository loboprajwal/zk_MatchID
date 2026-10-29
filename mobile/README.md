# zk-MatchID mobile (UPI-style ZK QR demo)

Flutter app for the team demo: **multi-wallet holder** + **predicate → consent → QR** + **verifier scan → PASS/FAIL**.

## Tabs
- **Wallets** — create / switch seeded wallets (Aadhaar DOB, degree, address).
- **Prove** — pick age≥18 / age≥21 / degree / residency → consent → QR (5 min TTL, nonce, no raw PII).
- **Verify** — camera scan, or “use last QR” for one-phone demos.

## Proofs (honest)
QR prefers **real Groth16** proofs from `assets/demo_proof_catalog.json` (snarkjs + local-dev zkey). If catalog slots are exhausted, falls back to HMAC **`signed_demo`** (labeled). Native mopro is optional / not required for this demo.

```bash
flutter pub get && flutter analyze && flutter test
flutter run
flutter build apk --debug
```

See root `BRANCH_SUMMARY.md` for the full demo script.
