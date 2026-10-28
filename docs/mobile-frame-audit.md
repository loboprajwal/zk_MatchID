# Mobile frame audit

Audit source: `mobile/design/frames.html`, copied from the user-provided `zkid_app_all_frames.html`. The Flutter implementation is currently a single `main.dart` with a Material 3 shell; it has no named route table. “Partial” means an adjacent flow or visual approximation exists but the specific frame or behavior is not implemented as designed.

## Navigation and trust boundaries

Current reachable flow: Welcome → create/restore local wallet → Wallet tab ↔ Prove tab / Verify tab / Activity tab / Settings tab. Wallet supports biometric-gated credential import (JSON file, pasted JSON, issuer QR scan), credential detail and delete; settings exposes lock and type-to-confirm wipe. Credential import does not establish issuer trust. Prove reviews a requested claim but intentionally stops before generating a proof. Verify can create a temporary transport QR and scan a response but intentionally rejects it because no authenticated policy registry or production native verifier is installed. No successful identity decision is possible in this build.

Proposed named route map when navigation is extracted: `/welcome`, `/wallet`, `/credentials/:id`, `/credentials/import`, `/credentials/accept`, `/prove`, `/prove/consent`, `/prove/face-match`, `/prove/generating`, `/prove/share`, `/prove/cache`, `/verify/request`, `/verify/scan`, `/verify/checking`, `/verify/result`, `/activity`, `/settings`, `/settings/phone`, `/unlock`, `/settings/wipe`, `/benchmarks`, `/benchmarks/compare`, plus `/` fallback. These routes are an audit recommendation, not routes currently registered in code.

## Frame inventory

| Frame | Status | Route | Notes |
|---|---|---|---|
| 01 · Welcome | Partial | `/welcome` | Local wallet create/restore shell; no phone onboarding, learn-more route, or mnemonic setup. |
| 02 · Phone number entry | Missing | `/onboarding/phone` | No OTP issuer or phone verification integration. |
| 03 · OTP verification | Missing | `/onboarding/otp` | No OTP flow. |
| 04 · Face-binding capture | Missing | `/onboarding/face-binding` | No liveness implementation. |
| 05 · Binding success | Missing | `/onboarding/binding-success` | Depends on liveness verification. |
| 06 · Wallet name + device lock | Partial | `/onboarding/wallet` | Wallet name dialog exists; no onboarding lock toggle. |
| 07 · Mnemonic backup | Missing | `/onboarding/backup` | No recovery phrase/key derivation. |
| 08 · Backup verification | Missing | `/onboarding/backup/verify` | No recovery phrase. |
| 09 · Restore flow | Partial | `/restore` | Restore explanation and JSON import exist; no phrase or QR wallet restore. |
| 10 · Credential list | Partial | `/wallet` | Locked/empty/list states and add action exist; layout differs from frame. |
| 11 · Credential detail | Partial | `/credentials/:id` | Detail dialog and delete exist; no reveal/menu behavior as drawn. |
| 12 · Add credential (scan) | Partial | `/credentials/import` | JSON import and QR camera scan exist; no issuer link verification. |
| 13 · Credential accept prompt | Missing | `/credentials/accept` | Import stores credential as unverified without a separate designed accept screen. |
| 14 · Predicate selector | Partial | `/prove` | Credential/claim selection exists; no preset cards or custom predicate controls. |
| 15 · Consent screen | Partial | `/prove/consent` | Consent review dialog exists; flow ends safely without disclosure. |
| 16 · Live face-match at proof time | Missing | `/prove/face-match` | No face-match implementation. |
| 17 · Proof generation | Missing | `/prove/generating` | No native proof generation wired to Flutter. |
| 18 · Share proof | Missing | `/prove/share` | No proof is produced or shared. |
| 19 · Proof cache | Missing | `/prove/cache` | No proof reuse/cache. |
| 20 · Verifier request builder | Partial | `/verify/request` | Temporary QR challenge exists; no trusted policy/issuer configuration. |
| 21 · Verifier — scan proof | Partial | `/verify/scan` | Camera scanner exists; rejects responses without trusted verifier. |
| 22 · On-chain verification | Missing | `/verify/checking` | No chain integration. |
| 23 · Verification result — pass | Missing | `/verify/result` | No success path; verifier fails closed. |
| 24 · Verification result — fail | Partial | `/verify/result` | Failure messaging exists in scanner flow, not the designed result screen. |
| 25 · Activity / verification log | Partial | `/activity` | Local event list exists; no pass/fail verification records. |
| 26 · Settings | Partial | `/settings` | Local security/storage settings exist; several design rows/settings are absent. |
| 27 · Linked number management | Missing | `/settings/phone` | No linked number or OTP service. |
| 28 · Biometric lock screen | Partial | `/unlock` | Biometric unlock is invoked; no dedicated lock frame or passcode fallback. |
| 29 · Wipe wallet | Partial | `/settings/wipe` | Type-to-confirm destructive dialog exists; not a dedicated screen. |
| 30 · Benchmark dashboard | Missing | `/benchmarks` | No benchmark instrumentation or dashboard. |
| 31 · Comparison mode | Missing | `/benchmarks/compare` | No comparison data or methodology. |

## State coverage and implementation gaps

The wallet has loading, locked and empty states; import and storage errors surface through snackbars. There is no shared loading skeleton, error/retry/offline state system or not-found route. The HTML frame source does not define a dark theme. Mopro Rust source exists, but Android/iOS generated libraries and a Dart FFI bridge are not present in this checkout. No issuer trust root, production proving/verifying key, or chain configuration is available. Enabling proof or pass outcomes without these materials would misrepresent trust, so those paths currently fail closed.
