# Simulated DigiLocker demo issuer

This service creates **fictional demo credentials only**. It is not connected to DigiLocker, UIDAI, a government registry, or a real institution. The sample phone numbers and identities in `sample_credentials/demo_seed.json` are test fixtures. Aadhaar access in a real product requires the official DigiLocker user-consent flow, Aadhaar-linked phone, and OTP; this demo does not perform those operations.

## Run locally

```powershell
cd issuer
npm test
npm start
```

The service binds only to `127.0.0.1:8090`. `GET /health` reports its demo status, `GET /v1/public-key` returns the Ed25519 demo public key, and `POST /v1/demo/issue` accepts `{ "type": "aadhaar|voter_id|passport|college", "verifiedPhone": "+919999990001" }`. The five documented sample phone numbers map to five fictional holders. Each identity/type pair can be issued once per process; the service rejects duplicate fingerprints, unsupported types, unverified numbers, and unmatched test numbers. Requests and credentials are not logged.

Credentials are compact EdDSA JWS values in `token`, alongside the W3C-style credential JSON in `credential`. They are signed using an in-memory, randomly generated process key. Restarting the service rotates that demo key, so old credentials will no longer be trusted unless the client refreshes the public key. The key is deliberately not persisted or committed. Never use this demo key or sample data for production.

The verifier distinguishes signature validity, expiry, issuer, phone matching, and local revocation. The server's memory-only revocation and duplicate sets reset on restart and are not a production database. The application must display the simulated-issuer ribbon and must not represent these credentials as real DigiLocker documents.
