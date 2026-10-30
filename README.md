# MatchID — credential wallet demo

MatchID is a Flutter credential-wallet demonstration. It stores imported credentials in platform-protected local storage, scans QR codes or reads JSON exports, compares presented identity fields with wallet contents, and can check a fictional credential's Ed25519 signature against the local simulated issuer service.

**This is a demonstration build.** DigiLocker, SMS OTP, and the sample documents are simulated. The face screen checks camera presence and movement only; face embedding remains a stub. The QR wallet match is not an issuer verification. The app does not yet have a production ZK prover or a connected Supabase Auth workflow. The unused legacy prover/verifier screens are retained as source, but are not part of the wallet navigation.

## Run the Flutter app

```powershell
cd mobile
flutter pub get
flutter analyze --no-pub
flutter test --no-pub
flutter run
```

The onboarding demo OTP is `1234`. The simulated issuer data includes fictional phone `+919999990001` (enter `9999990001` in the +91 phone field). For an Android emulator, start the demo issuer from another terminal and configure its endpoint:

```powershell
cd issuer
npm test
npm start
```

Run the app with `--dart-define=SIMULATED_ISSUER_API_URL=http://10.0.2.2:8090`. On a physical device, use a reachable HTTPS endpoint or a LAN URL only after changing the provider's local-network policy deliberately. The issuer's Ed25519 key, duplicate cache, and revocation set are ephemeral and reset when it restarts; this local service is for demos only.

## Current features

- Flutter wallet shell, encrypted local key-value storage, device authentication lock, activity log, and encrypted `.zkidbackup` import/export.
- Recovery phrase creation and confirmation; the wallet key is derived from BIP-39 seed material.
- Phone demo OTP and guided three-pose face-presence check. Face embedding is intentionally a stub; no biometric identity match is claimed.
- Credential QR scanner and DigiLocker JSON-file import.
- Simulated demo credential issuance, Ed25519 signature verification, expiry/issuer checks, and wallet-name plus masked-identifier matching.
- Solidity trust-registry contracts and a Supabase schema/function scaffold, subject to the limitations in [docs/SECURITY.md](docs/SECURITY.md).

## Repository areas

- `mobile/` — Flutter app and tests.
- `issuer/` — local-only simulated DigiLocker issuer and test suite.
- `contracts/` — Solidity issuer, schema, and revocation registries.
- `circuits/`, `mopro/` — circuit and native proving groundwork; no production proving artifacts are included.
- `supabase/` — schema and Edge Function scaffold; local Supabase integration has not been executed in this environment.
- `docs/` — architecture, security, test evidence, demo, and migration notes.

## Verification

See [docs/TEST_CASES.md](docs/TEST_CASES.md) for commands actually run and unavailable checks. This README intentionally makes no claim that an end-to-end Supabase, Android camera, or ZK proof flow has passed.
