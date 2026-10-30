# Seven-minute demo script

## Setup

1. Start the Flutter app with `flutter run`.
2. Use the simulated OTP `1234`; the screen must show `Demo mode: OTP simulated`.
3. Complete the guided face movement check. Describe it as a local face-presence/movement demo, not an identity match.
4. Save and confirm the two requested words of the recovery phrase.
5. For demo credential issuance, run `issuer\npm start` and launch Android with `--dart-define=SIMULATED_ISSUER_API_URL=http://10.0.2.2:8090`.
6. Use phone `9999990001` with country code +91 to request the fictional sample, or import an existing QR/JSON file.

## Walkthrough

| Time | Action | Expected screen/result |
|---|---|---|
| 0:00 | Explain the local-only demo and simulated services | App welcome/wallet state |
| 0:45 | Enter the +91 demo number and request OTP | Demo OTP banner and four code boxes |
| 1:30 | Enter `1234`, complete the guided face poses | Verified phone then local movement result |
| 2:30 | Set wallet preferences and create/confirm recovery phrase | Wallet opens without exposing phrase afterward |
| 3:30 | Add a credential by QR or JSON | Credential appears in the local wallet |
| 4:30 | Request a fictional demo credential | Persistent `SIMULATED DIGILOCKER: demo data` label |
| 5:30 | Open Verify and present matching fields | Wallet match and issuer signature are reported separately |
| 6:30 | Show an edited/unsigned JSON credential or unmatched ID | Failure/untrusted result; no false success |
| 7:00 | Show backup settings and explain prover/backend limitations | `Advanced: file backup` remains secondary |

## If something fails

- If camera permission or camera hardware is unavailable, do not claim the face flow passed. Use the recorded test evidence only if an actual capture exists.
- If the issuer cannot be reached, use QR/JSON import. Never relabel a local file as issued by a real DigiLocker service.
- If signature verification is untrusted, show that status. Wallet field matching is not an authenticity result.
- There is no valid ZK proof QR fallback in this build. Explain that the native prover is not available.

## Screenshot checklist

See `docs/screenshots/README.md` for the manual capture list. Screenshots must be captured from an actual run; no mock images are included as runtime evidence.
