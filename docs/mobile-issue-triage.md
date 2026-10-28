# Reported issue triage

| Issue | Root cause (file:line) | Fix plan | Risk |
|---|---|---|---|
| 1. Backup cannot be skipped | `mobile/lib/main.dart:628-634` goes from wallet welcome directly to local wallet creation and explicitly states recovery phrases are not configured; there is no backup phase or completion/skip state. | Add an encrypted portable vault backup flow, a visible skip action, persist the decision in secure storage, and surface a later reminder. | A skipped backup cannot recover data after device loss. Current wallet has no separate signing/proving key to back up. |
| 2. No skip confirmation | No backup action or confirmation exists in `mobile/lib/main.dart`; no persisted backup preference exists in `VaultRepository`. | Confirm the skip, with primary action returning to backup and secondary action setting the secure skip flag. | The dialog must not imply recovery is possible without an actual backup. |
| 3. Restore frames missing | `mobile/lib/main.dart:246-269` presents an informational dialog, creates a new wallet, and imports an arbitrary credential JSON file; it does not restore wallet configuration/credentials as one archive. `VaultStore.wipe` at `1320-1324` deletes local data. | Add a versioned encrypted backup archive, import validation, replace/merge confirmation, and round-trip tests. Keep restore data encrypted at rest in a passphrase-protected archive. | The current wallet has no cryptographic identity key; restore can reproduce stored wallet data only, not nonexistent keys. |
| 4. OTP not working | There is no OTP screen/controller/client/service anywhere in `mobile/lib`; `mobile/android/app/src/main/AndroidManifest.xml:1-2` has camera permission only. No SMS provider, backend URL, or credentials are configured. | Use DigiLocker’s approved requester authentication and its own user authentication/OTP. Do not invent a separate OTP sender. | Requires an approved requester application, client ID, redirect URI, authorized scopes, and current integration specification. |
| 5. Face capture not working | No face capture/detection/service exists in `mobile/lib`; the only camera flow is QR scanning at `mobile/lib/main.dart:388-426`. Android camera permission is present; iOS camera usage text exists at `mobile/ios/Runner/Info.plist:29-30`. | Add camera permission handling and a front-camera capture screen with on-device face detection; keep captured pixels in memory and provide retake/confirm. | Face detection is not identity binding or liveness. A trusted face-match/liveness provider and consent policy are not configured. |
| 6. Issuer not provided / DigiLocker only | `mobile/lib/main.dart:303-427` imports user-supplied JSON or QR payloads. There is no DigiLocker repository or OAuth client. No runtime `/issuer` client is present today. | Remove manual credential injection from production and introduce a DigiLocker repository boundary. Integrate only after verifying the requester spec and configuring registered client/redirect/scopes. | Official API Setu requester PDFs/YAML linked from the current partner pages return 403 in this environment; do not guess endpoints or PKCE requirements. DigiLocker requires partner registration and credentials. |
| 7. Owner credentials not showing | `mobile/lib/main.dart:180-194` reads stored credentials but only uses `storedCredentials.isNotEmpty` to decide whether a wallet exists; it does not populate the UI list. The list is assigned later in `_unlock` at `272-301`, so the UI intentionally displays “Wallet locked” until successful biometric unlock. There is no DigiLocker fetch path. | Preserve the lock boundary, show a loading/error/retry state during unlock, and load the authorized owner’s DigiLocker-issued documents through the repository after consent. | Until DigiLocker access is configured, only locally stored credentials can be shown. Never display sensitive document data while locked. |
| 8. Proof generation not working | `mobile/lib/main.dart:927-968, 1052-1060` intentionally stops after consent. Rust exports generic C ABI functions in `mopro/src/lib.rs:156-221`, but Flutter has no FFI/Dart bridge. `mopro/mopro.toml` references absent `generic_verifier.r1cs` and `generic_verifier_final.zkey`; no Android `jniLibs` are present. | Correct the native build helper so it requires valid platform outputs and fails closed; integrate a Dart service only after circuit artifacts, ABI libraries, and verified test vectors are supplied. | Proof generation cannot run with a missing proving key/circuit artifact. Do not show success from a mock in production. |
| 9. Sharing proof not working | No share package or proof-share implementation exists in `mobile/pubspec.yaml` or `mobile/lib`; the proof path never produces a payload (issue 8). | Add a versioned minimal proof package, expiry checks, share/copy/QR options, and verification parsing after proof generation is operational. | A share UI without a valid proof would be misleading; public inputs and replay/expiry semantics must match the actual circuit/verifier. |

## Official DigiLocker source review

The current API Setu partner resource page lists the Requester API Specification v1.12 (Oct 2023), Meri Pehchaan API Specification v2.4 (Sep 2026), and a requester workflow manual. The official directory lists authorization-code, token, user-details, and issued-documents operations. The linked specifications were blocked with HTTP 403 during this audit. DigiLocker’s official integration page says requester integration is for registered partners and the platform uses OAuth 2.0. The flow therefore requires registered application details and the accessible current specification before the network client can be implemented safely.

Sources: [API Setu DigiLocker partner resources](https://apisetu.gov.in/digilocker), [API Setu DigiLocker API directory](https://directory.apisetu.gov.in/api-collection/digilocker), [DigiLocker security architecture](https://www.digilocker.gov.in/web/security-architecture).

## Fix status

| Issue | Status | Completion and remaining dependency |
|---|---|---|
| 1. Backup skip | Fixed | New wallet onboarding offers “Skip for now”; the decision is persisted in secure storage and a home reminder remains available. |
| 2. Skip confirmation | Fixed | Confirmation explains device-loss risk and offers “Go back and back up” or “Skip anyway”. |
| 3. Restore | Fixed | Versioned AES-GCM/PBKDF2 backup file restores wallet profile, credentials, and activity; wrong passphrases and damaged files fail closed. Round-trip test covers wipe and restore. There is no independent signing key in this app to restore. |
| 4. OTP | Implemented; provider setup required | The app now uses the separate Twilio Verify gateway. Configure Twilio Verify and deploy the server before phone linking can send SMS. DigiLocker’s internal OTP remains part of its future OAuth login. |
| 5. Face capture | Implemented with scope limit | Front-camera permission, centered-face detection, two-sided head movement and blink prompts, capture review, retake, and temporary-image cleanup are implemented. This is a basic local movement challenge, not face identity matching or certified liveness. |
| 6. DigiLocker-only credential source | Needs input | Manual JSON/credential-QR imports were removed. DigiLocker OAuth and document fetch are not implemented because the app has no registered client configuration and linked official specs are inaccessible here. |
| 7. Owner credentials | Needs input | The local credential list remains protected by biometric unlock. DigiLocker profile/document retrieval and loading/error states need working API access and field/scopes details. |
| 8. Proof generation | Needs input | Mopro build scripts now reject missing circuit assets and platform outputs. The configured R1CS/proving key and Android native libraries are absent, and no Flutter FFI bridge or test vectors exist. |
| 9. Share proof | Needs input | No proof can be serialized or verified until issue 8 provides a defined circuit, public-input schema, verifier, expiry/replay policy, and valid proof test vector. |

## Verification performed

- Baseline: Flutter 3.35.1 / Dart 3.9.0; `flutter pub get` succeeded. `flutter doctor -v` found the attached Moto G84 (API 35), no Pixel 4/API 36 emulator, and Android SDK licenses that are not accepted.
- `dart format lib/main.dart lib/data lib/features/onboarding/presentation/face_capture_screen.dart test` completed.
- `flutter analyze`: passed with no issues.
- `flutter analyze`: passed with no issues after the OTP, face challenge, and credential verifier changes.
- `flutter test -r expanded`: passed (12 tests), including encrypted backup/restore, phone OTP UI (send/verify, wrong-code rejection, resend countdown), signed credential verification, wallet lock/skip, and face permission handling.
- `node --test otp/server.test.mjs`: passed (5 tests) using a fake provider transport; no real SMS was sent.
- `flutter build apk --release`: passed; output is `mobile/build/app/outputs/flutter-apk/app-release.apk` (89.4 MB). This confirms compilation, not release readiness: Android is still configured to sign release builds with the debug key.
- Live camera/scan flow was not exercised because no Android device is currently connected. The Pixel 4/API 36 target was not available.
- No iOS build could be run on this Windows host. A CocoaPods Podfile now sets iOS 15.5 and camera permission macros for plugin integration.

## Follow-up: OTP, face challenge, and credential scan

The phone screen uses `OTP_API_BASE_URL` to call the independent Node service in `otp/`. The service delegates OTP generation, expiry, and verification to Twilio Verify; the app does not create or store codes. Configure server credentials in `otp/.env` and use HTTPS in deployment. Twilio Verify requires a configured six-digit Verify Service. The app stores the phone number in secure storage only after provider approval.

After successful phone linking, the face screen runs a local head-turn-both-sides and blink challenge, then returns a result to Settings. This detects movement, not who the person is, and is not resistant to every recorded-video or presentation attack.

The verifier camera now checks signed credential JWTs using EdDSA or RS256, a build-time public-key trust registry (`CREDENTIAL_TRUST_REGISTRY_JSON`), signature, issuer match, subject consistency, and expiry. Unknown issuers, unsupported formats, malformed payloads, and invalid signatures fail closed. It does not check holder control or revocation, and DigiLocker Secure QR/API validation still needs the official format and registered integration details. The scan frame therefore reports the exact limited checks it performed.

Tests: `node --test otp/server.test.mjs` (fake Twilio transport); Flutter OTP UI tests cover send/verify, wrong-code rejection, and resend countdown; credential verifier unit tests use ephemeral Ed25519 test keys. No real SMS is sent by tests.
