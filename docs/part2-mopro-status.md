# Part 2 status: Mopro native proving engine

Part 2 is interpreted from `implementation_plan.md` as the Mopro native engine for generic predicates. This work is started, but the native proof runtime is not yet buildable in this checkout.

## Implemented in this pass

- Dart validates generic circuit inputs before FFI: mode, fixed five-element set, unsigned 32-bit bounds, expiry, and predicate satisfaction.
- Generic proof generation requires both native prove and verify symbols, then performs local pairing verification before returning a payload. Missing native symbols and failed verification fail closed.
- The legacy age-only API no longer returns the fixed placeholder proof points; Dart and Rust report it unavailable.
- The benchmark path now uses the generic prover, generates its secret per run, refuses to create simulated results when the native engine is absent, and reports separate witness timing as unavailable.
- Android and iOS packaging scripts were resolved to the fail-closed versions. They require actual circuit artifacts and verify each Android ABI output rather than copying a host library into an ABI folder.
- Rust request/serialization tests were corrected and an age-path fail-closed test was added.

## Verification and blockers

- `flutter analyze --no-pub` — exit 0, `No issues found! (ran in 8.7s)`.
- `flutter test --no-pub -r expanded` — exit 0, `All tests passed!` (33 passed, 6 native prover tests skipped because the native runtime is unavailable).
- `flutter build apk --debug` — exit 0, `Built build\app\outputs\flutter-apk\app-debug.apk` (Gradle reported Kotlin Gradle Plugin migration warnings; build took 305.3 seconds).
- `cargo test` — exit 1: `The term 'cargo' is not recognized as a name of a cmdlet, function, script file, or executable program.` Rust tests could not be run because Rust/Cargo is not installed or on PATH.
- `mopro/scripts/build_mobile.ps1` — exit 1 before build: required `mopro/assets/generic_verifier.r1cs` and `mopro/assets/generic_verifier_final.zkey` are missing. The verification key JSON exists, but it is not enough to prove.
- No Android device is connected. `flutter emulators --launch Pixel_10a` exits 1 during startup, so face camera behavior and native prover behavior have not been exercised on Android.

## Required before enabling proof UI

Install the Rust and Mopro mobile toolchains, compile and audit the generic circuit artifacts, generate Android libraries for each supported ABI and the iOS framework, and run Rust/Dart proof-generation plus local-verification vectors on device. Until those checks pass, keep the prover UI unexposed and do not call any payload a ZK proof.

