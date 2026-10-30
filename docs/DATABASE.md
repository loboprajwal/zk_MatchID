# Database and access control

`supabase/migrations/202610290001_initial_schema.sql` defines the approved remote model: profiles and roles; one identity per account and unique peppered phone hash; multiple wallets under an identity; globally unique credential fingerprints; issuer trust keys; verifier requests; one-use proof nonces; OTP attempt state; and append-only audit records.

## Constraints and RLS

- `identities.user_id` and `identities.phone_hash` are unique; the OTP Edge Function computes `HMAC-SHA256(phone, PHONE_HASH_PEPPER)` so plaintext phone numbers are not stored in the database.
- `wallets.identity_id` references one identity; `(identity_id, name_masked)` is unique.
- `credentials.doc_fingerprint` is globally unique, so a document cannot be registered to two wallets.
- `proofs.nonce` and `verification_requests.nonce_hash` are unique. Nonce consumption is an atomic update that requires an unused, unexpired proof and matching signature.
- Roles live in `profiles.role`. Clients have no profile update policy; role changes are administrative/service-side.
- Owner predicates scope identity, wallet and credential reads. Verifier request reads are scoped to the creating verifier. OTP, proof writes and audit writes use service-role Edge Functions only.
- Verified identity creation is service-side only. The client cannot forge `phone_hash` or `verified_at`.

RLS is enabled on every application table. A local pgTAP smoke test exists at `supabase/tests/schema_security.sql`; it was not run because Supabase CLI/Docker/PostgreSQL are not available in this environment. Review the SQL and execute it in local Supabase before relying on this scaffold.

## Local seed

`supabase/seed.sql` creates four local-only demo Auth users: one admin, one verifier, and two holders. Passwords are demo-only and must never be reused in a hosted environment. The demo issuer uses an ephemeral process key, so its public key must be registered dynamically by a future issuer integration; the seed intentionally does not insert a fake key.

## Local migration caveat

The Flutter app has a local Identity/Wallet separation and verified-onboarding migration for its legacy vault. It is not yet connected to Supabase Auth or the remote schema. No remote migration has been run against existing user data. The remote database migration remains a separate deployment step.
