# Production migration plan

| Component | Demo implementation | Production implementation | Effort |
|---|---|---|---|
| Phone OTP | Flutter mock code `1234`; Edge Function scaffold | SMS provider behind `OtpService`, verified server-side, abuse monitoring | Medium |
| DigiLocker | Fictional local Ed25519 issuer and sample seed | Register as a DigiLocker requester/partner; OAuth2; official Issued Documents/eKYC APIs | High; approval and compliance dependent |
| Aadhaar | Masked fictional suffix only | Follow UIDAI rules; verify official offline eKYC signatures; minimize/avoid Aadhaar retention | High |
| Issuer signing | Ephemeral local Ed25519 key | Managed KMS/HSM signing, key rotation, certificate and issuer trust lifecycle | High |
| Credential storage | Flutter platform-protected local store | Threat-modelled mobile encryption, backup-key recovery, secure deletion and pentesting | Medium/High |
| Attestation | Supabase Edge Function HMAC scaffold | Audited signing key, policy service, revocation checks, operational monitoring | Medium |
| ZK proof | Circom/Mopro groundwork; no active proof generation | Audited circuits, ceremony/proving keys, mobile native build, verifier and independent review | High |
| Database | Supabase schema/RLS scaffold | Reviewed migration, least-privilege policies, backups, retention, monitoring | Medium |
| Face | ML Kit pose detection; embedding stub | Consent-led on-device face verification with validated model and deletion controls | High |

Production onboarding must include consent and data minimization under India's DPDP Act, UIDAI/Aadhaar-specific requirements, audit retention limits, incident response, key management, and independent penetration testing. Obtain legal/compliance review before handling real identity documents.
