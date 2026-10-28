<<<<<<< HEAD
# MatchID mobile

Flutter client for a local credential wallet and experimental privacy-preserving identity proof workflow. This checkout is not ready for real identity decisions: DigiLocker access is not configured, the Flutter app has no generated Mopro bridge, and verification intentionally fails closed.

## Toolchain

- Flutter 3.35.1 / Dart 3.9.0 (the checked-in mobile project supports Dart `>=3.5.0 <4.0.0`)
- Android SDK / compile SDK 36; Android Studio JDK 21 works with the current Gradle build. The Gradle Android plugin compiles app sources for Java 17.
- iOS deployment target 15.5 (required by the selected ML Kit face detection plugin)
- Rust toolchain and the project’s Circom artifacts are needed to build Mopro. Native output must be produced for each target ABI; a host Cargo build is not an Android/iOS build.

## Run and verify

From `mobile/`:

```powershell
flutter pub get
flutter analyze
flutter test
flutter run
```

To build an Android debug APK:

```powershell
cd android
.\gradlew.bat assembleDebug --stacktrace
```

The design source is `design/frames.html`. The implementation audit, including current frame status and the suggested route map, is in `../docs/mobile-frame-audit.md`.

## Mopro native bindings

The Rust crate is in `../mopro`. Build using its platform-aware helper only after confirming the required Rust targets, Mopro CLI, and circuit artifacts are installed:

```powershell
cd ..\mopro
powershell -ExecutionPolicy Bypass -File scripts/build_mobile.ps1
```

The helpers now fail closed if the circuit artifacts, Mopro CLI outputs, or platform libraries are missing. They do not copy a host `cargo build` output into an Android ABI folder. The Flutter app does not currently call the Rust functions.

## Current architecture and limits

`lib/main.dart` contains the wallet UI and flows. `lib/core/theme/app_theme.dart` defines design tokens and the Material 3 theme. `lib/data/vault_repository.dart` provides an injectable persistence boundary; `VaultStore` stores credentials using `flutter_secure_storage`. The backup archive uses AES-GCM with PBKDF2 key derivation and restores wallet configuration, credentials, and activity. Credentials stay hidden until biometric unlock. JSON and credential QR import are disabled; the only supported new credential source is DigiLocker, which needs partner configuration before it can be enabled.

The current features are local wallet creation, encrypted backup/restore, biometric-gated access, SMS OTP phone linking, an on-device face movement challenge, and a QR credential verifier. SMS uses the separate Twilio Verify gateway in `../otp`; provider credentials remain server-side. Face motion and blink checks do not identify a person or provide certified liveness. The verifier supports signed credential JWTs using EdDSA or RS256 with an explicit issuer trust registry, checks expiry, and rejects unknown keys. It does not check holder binding, revocation, or DigiLocker-specific QR formats. DigiLocker login/document retrieval, proof generation/sharing, on-chain verification, benchmark screens, localization, and multi-flavor release setup still need implementation/configuration. No holder identity or revocation pass is presented.

Run the SMS gateway using `../otp/README.md`. Configure the mobile build with `--dart-define=OTP_API_BASE_URL=https://<your-otp-host>` and `CREDENTIAL_TRUST_REGISTRY_JSON` containing only issuer public keys, as illustrated by `config/app.defines.example.json`. Never put Twilio secrets or issuer private keys in Flutter defines.

## Release status

Do not publish a release from the current Gradle signing configuration: release builds currently use the debug signing key. Production signing, ABI-specific Mopro builds, audited proving/verifying keys, issuer trust configuration, release obfuscation, and platform security review must be completed first. The app requests camera access for QR scanning and biometric permissions for local vault unlock.
=======
# mobile

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
>>>>>>> 017065faef1486607dd045e1cf3c06c4fb72c3e0
