# Security notes

## STRIDE-lite

| Threat | Current mitigation | Remaining risk |
|---|---|---|
| Spoofing | Demo OTP has a visible simulated banner; camera screen requires pose movement | No real SMS verification or biometric face matching; `FaceEmbedder` is a stub |
| Tampering | Local secure storage; signed demo JWS verification; size-limited JSON parsing | Local Android/device compromise and plain JSON imports remain risks; credential import is not yet server-validated |
| Repudiation | Local activity log; Supabase audit table and function writes are scaffolded | App is not connected to Supabase; local log can be cleared with wallet wipe |
| Information disclosure | Device-protected storage; face images are not sent to a backend | Credential claims exist in app memory while unlocked; no production security review |
| Denial of service | Client OTP lock and server RPC lockout scaffold; bounded payload validation | Backend functions/database were not run locally; service-level rate limits and deployment hardening remain |
| Elevation of privilege | RLS role checks and no client profile role update policy in migration | RLS and Edge Functions need live Supabase integration tests before production |

## Implemented vs simulated

- **Implemented locally:** Flutter secure key-value storage, device authentication gate, BIP-39 phrase validation/key derivation, AES-GCM credential/name encryption keyed by the mnemonic-derived wallet key, QR scanner, JSON file import, Ed25519 signature checks for configured issuer keys, expiry checks, local wallet field matching, and local Identity/Wallet separation with verified-onboarding legacy migration.
- **Simulated:** OTP (`1234`), DigiLocker documents and issuer identity, fictional sample people, and onboarding face identity claims. The camera pose check does not compare a user to a known identity.
- **Not implemented as production security:** native face embeddings, real DigiLocker/UIDAI integration, Supabase-connected app authentication, production secrets/key rotation, deployed backend, compiled Groth16 prover/verifier, and attestation key management. The local phone hash uses an installation-specific pepper and is not a server identity key.
- **ZK status:** no proof is generated in the wallet shell. The circuits and Mopro files are groundwork only; no production proving key or native library is shipped.

## Operational requirements

Never deploy the demo OTP endpoint or fictional issuer as a real identity service. Configure unique server secrets for `PHONE_HASH_PEPPER`, `OTP_CHALLENGE_SECRET`, and `ATTESTATION_SIGNING_SECRET`. Store them in managed secrets, rotate them, use TLS, set explicit CORS origins, enable Auth protections, review RLS policies, add operational rate limits, and run external security testing. The demo issuer's key, duplicate cache, and revocation cache are ephemeral by design.

No face embedding is currently computed. If a future implementation enables face deduplication, it requires explicit consent, retention/deletion policy, a documented feature flag and privacy assessment; no pgvector face table is part of the approved schema.
