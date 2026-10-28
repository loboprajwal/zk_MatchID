# MatchID SMS OTP gateway

This service sends and checks six-digit SMS codes through Twilio Verify. Twilio keeps the OTP lifecycle, expiry, and verification attempts; the service never generates, logs, or returns an OTP. The Flutter app calls only this service, and Twilio credentials stay on the server.

## Configure and run

1. Create a Twilio Verify Service and set its code length to 6. Enable the intended destination countries and fraud protection in Twilio.
2. Copy `.env.example` to `.env` and set `TWILIO_API_KEY_SID`, `TWILIO_API_KEY_SECRET`, and `TWILIO_VERIFY_SERVICE_SID`. Keep `.env` out of source control.
3. Run `node --env-file=.env server.mjs` with Node.js 20 or newer. Deploy behind HTTPS and an IP-aware rate limiting reverse proxy. Do not expose this service directly to the public internet without network-level rate limiting.
4. Build the app with `--dart-define=OTP_API_BASE_URL=https://<your-host>`.

The current service has a per-process limit of five sends per phone number per hour. This is defense in depth; use a shared rate limit at the gateway for multi-instance deployments. No local OTP sandbox or release bypass is included.

## API

- `POST /v1/otp/send` with `{"phoneNumber":"+919876543210"}`
- `POST /v1/otp/verify` with `{"phoneNumber":"+919876543210","code":"123456"}`
- `GET /health` reports configuration status only; it never returns credentials.

Run tests with `node --test server.test.mjs`. Tests use a fake provider transport and do not send SMS.
