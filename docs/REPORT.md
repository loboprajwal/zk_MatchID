# MatchID project report

## Abstract

MatchID demonstrates a Flutter wallet that can hold identity-credential files locally and compare wallet identity fields with presented credentials. The project includes simulated credential issuance and groundwork for selective disclosure; production ZK proof generation and real identity-provider connections are not implemented.

## Problem and objective

Identity checks often disclose more data than a verifier needs. This project explores a local-first credential wallet and a future selective-disclosure flow while keeping the demonstration honest about which checks are simulated.

## Background

DigiLocker is India's document wallet and issuer ecosystem; this project does not connect to it. Verifiable credentials use issuer-signed claims. Selective-disclosure and zero-knowledge systems can prove predicates without disclosing source attributes, but doing so requires correctly designed circuits, keys and verifiers. MatchID's circuits and native Mopro code are research groundwork only.

## Design and implementation

The mobile client is Flutter. It stores data using platform-protected key-value storage, supports QR/JSON intake, and uses an interface for a local simulated issuer. Issued fictional documents use Ed25519 signatures. The verifier presents wallet matching separately from signature status. Supabase migrations and Edge Function scaffolding define roles, RLS, OTP attempt records and attestation endpoints; Flutter Auth/data integration and local backend execution remain outstanding.

## Security analysis

Phone OTP is simulated. The face camera flow verifies face presence/pose movement only. The face embedder is stubbed. The issuer key is ephemeral. No full credential should be uploaded by the demo service. See [SECURITY.md](SECURITY.md) for a STRIDE-lite assessment and production risks.

## Testing and results

See [TEST_CASES.md](TEST_CASES.md) for actual command outcomes and blockers. Existing Flutter, issuer, Solidity, and legacy circuit tests have passed in prior runs; the current modified Flutter tree must be rerun before release. Supabase integration, Android camera screenshots, and native ZK proof tests cannot pass without their respective runtimes and artifacts.

## Limitations and future work

Complete the approved local Identity/Wallet migration without data loss; connect Supabase Auth and APIs; validate document signatures server-side; add an actual admin UI; run local Supabase negative tests; implement a validated on-device face embedder only after consent/privacy review; compile and audit the native prover before enabling proof UI; and capture real demo screenshots.
