# Part 1 frame gap table (01–09)

Verification date: 2026-10-29. Flutter checks ran from `mobile/`. This table records implemented flows and the limits of the demo. Android screenshot evidence is **blocked** because the configured Pixel 10a emulator exited during startup; no substitute or fabricated screenshots are included.

| Frame | Implementation status | Route / evidence | Remaining gap |
|---|---|---|---|
| 01 · Welcome | Implemented | Existing wallet shell in `mobile/lib/main.dart`; create routes into guarded onboarding, restore remains available. Covered by `test/widget_test.dart`. | Screenshot not captured (Android emulator unavailable). |
| 02 · Phone entry | Implemented | `PhoneOtpScreen` in `mobile/lib/features/onboarding/presentation/phone_otp_screen.dart`; +91 and exactly 10 digits. | OTP is simulated only; no SMS provider. Screenshot not captured. |
| 03 · OTP verification | Implemented | `MockOtpService` code `1234`, four OTP inputs, resend cooldown, five failures then temporary lock; visible demo banner. Tests in `mobile/test/features/phone_otp_screen_test.dart` and `mobile/test/features/onboarding_services_test.dart`. | No production OTP; Supabase/provider integration is Part 5. Screenshot not captured. |
| 04 · Face capture | Partial / demo-only | Ordered LEFT → RIGHT → FRONT pose state machine in `mobile/lib/features/onboarding/domain/face_pose_state_machine.dart`; animated pose coach, front-camera rotation compensation, accurate ML Kit mode, wider face framing, low-light guidance, timeout, face-count checks and failure UI in `mobile/lib/features/onboarding/presentation/face_capture_screen.dart`. Failure text: “Unable to proceed. Face match couldn't be detected.” Raw frame cleanup is tested. | `FaceEmbedder` is a stub. Face identity matching/template creation is not real or stored; live camera behavior was not exercised because the Pixel 10a emulator exits during startup. Failure screenshot not captured. |
| 05 · Binding success | Implemented with explicit demo disclosure | Dedicated `BindingSuccessScreen`; guarded after OTP and all poses. It states simulated OTP and that there is no biometric identity match. | The success label refers only to demo number/pose flow, not identity verification. Screenshot not captured. |
| 06 · Wallet name + device lock | Implemented | Dedicated `WalletSetupScreen`, name validation and persistence; lock preference requires successful device-auth capability/authentication. Covered by `mobile/test/features/wallet_setup_screen_test.dart`. | Device biometrics not exercised on physical hardware. Screenshot not captured. |
| 07 · Mnemonic backup | Implemented | Secure BIP-39 generation and derived wallet key in `mobile/lib/features/onboarding/domain/mnemonic_backup.dart`; encrypted local key storage; confirmation flow, Android secure-screen flag, 30-second clipboard clear. | Screenshot not captured. Device-level screenshot prevention was not runtime-verified. |
| 08 · Backup confirmation | Implemented | Two unique cryptographically random positions; confirmation gates continuation. Covered by `mobile/test/features/onboarding_services_test.dart` and `mobile/test/widget_test.dart`. | Screenshot not captured. |
| 09 · Restore wallet | Implemented for mnemonic and advanced file backup | Mnemonic normalization/checksum validation in restore screen; `.zkidbackup` remains the secondary “Advanced: file backup” path. Cross-format key-equivalence test in `mobile/test/data/vault_store_backup_test.dart`. | Mnemonic restores wallet key/config, not credentials that exist only on the original device; UI discloses this. Screenshot not captured. |

## Verification evidence

- `flutter pub get` — exit 0, “Got dependencies!”
- `flutter analyze --no-pub` — exit 0, “No issues found!”
- `flutter test --no-pub -r expanded` — exit 0, “All tests passed!” (28 passed, 6 skipped because the native generic prover/verifier is not loaded; those tests explicitly reject mock proofs.)
- `flutter devices` — Windows, Chrome and Edge are available; no Android device was connected.
- `flutter emulators` — Pixel 10a is configured.
- `flutter emulators --launch Pixel_10a` — exit 1: “The Android emulator exited with code 1 during startup. Android emulator stderr: Address these issues and try again.” Therefore none of the requested Android screenshots exist in this checkout.

## Demo limitations

This Part 1 build has simulated OTP and pose detection only. There is no real face embedding or biometric match. The success screen communicates that limitation. BIP-39 material derives/protects the wallet key, but it cannot recreate device-local credentials without a synced/portable credential payload. The approved Identity/Wallet data model is not introduced here; no additional data-model change was made.
