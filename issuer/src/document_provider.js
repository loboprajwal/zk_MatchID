const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");

const ISSUER_ID = "did:zkmatch:simulated-digilocker-demo";
const ISSUER_NAME = "SIMULATED DIGILOCKER (DEMO)";
const SUPPORTED_TYPES = new Set(["aadhaar", "voter_id", "passport", "college"]);
const MAX_TOKEN_BYTES = 32 * 1024;

class DocumentProvider {
  fetchDocument() {
    throw new Error("DocumentProvider.fetchDocument must be implemented.");
  }

  verifySignature() {
    throw new Error("DocumentProvider.verifySignature must be implemented.");
  }
}

class SimulatedDigiLockerProvider extends DocumentProvider {
  constructor({ seedPath, privateKey, publicKey, now = () => Date.now() } = {}) {
    super();
    this.now = now;
    const seed = JSON.parse(fs.readFileSync(seedPath ?? path.join(__dirname, "..", "sample_credentials", "demo_seed.json"), "utf8"));
    this.holders = new Map(seed.map((holder) => [holder.phoneNumber, holder]));
    const pair = privateKey && publicKey
      ? { privateKey: crypto.createPrivateKey(privateKey), publicKey: crypto.createPublicKey(publicKey) }
      : crypto.generateKeyPairSync("ed25519");
    this.privateKey = pair.privateKey;
    this.publicKey = pair.publicKey;
    this.revoked = new Set();
    this.fingerprints = new Set();
    this.kid = `${ISSUER_ID}#demo-key-1`;
  }

  getPublicKey() {
    const der = this.publicKey.export({ format: "der", type: "spki" });
    return {
      id: this.kid,
      issuer: ISSUER_ID,
      issuerName: ISSUER_NAME,
      algorithm: "EdDSA",
      publicKey: der.subarray(der.length - 32).toString("base64url"),
      demoOnly: true,
    };
  }

  async fetchDocument(type, userContext = {}) {
    if (!SUPPORTED_TYPES.has(type)) throw coded("UNSUPPORTED_TYPE", "This demo document type is not supported.");
    const phone = userContext.verifiedPhone;
    if (typeof phone !== "string" || !/^\+91[6-9]\d{9}$/.test(phone)) {
      throw coded("PHONE_NOT_VERIFIED", "Verify the +91 phone number before requesting demo data.");
    }
    const holder = this.holders.get(phone);
    if (!holder) throw coded("PHONE_MISMATCH", "This verified demo phone has no matching sample identity.");

    const credential = this._credential(type, holder);
    const fingerprint = crypto.createHash("sha256").update(`${ISSUER_ID}\0${type}\0${holder.id}`).digest("hex");
    if (this.fingerprints.has(fingerprint)) throw coded("DUPLICATE_DOCUMENT", "This demo document is already in the wallet.");
    this.fingerprints.add(fingerprint);
    const token = this._sign(credential);
    return {
      format: "zkmatchid-digilocker-demo+jws;v=1",
      credential,
      token,
      issuerStatus: "SIMULATED",
      documentFingerprint: fingerprint,
    };
  }

  verifySignature(envelope, { now = this.now(), phoneNumber } = {}) {
    const token = envelope?.token;
    if (typeof token !== "string" || Buffer.byteLength(token) > MAX_TOKEN_BYTES) {
      return { valid: false, status: "MALFORMED", message: "Credential signature envelope is missing or too large." };
    }
    const parts = token.split(".");
    if (parts.length !== 3 || parts.some((part) => !part)) {
      return { valid: false, status: "MALFORMED", message: "Credential token is malformed." };
    }
    let header;
    let payload;
    let signature;
    try {
      header = JSON.parse(Buffer.from(parts[0], "base64url").toString("utf8"));
      payload = JSON.parse(Buffer.from(parts[1], "base64url").toString("utf8"));
      signature = Buffer.from(parts[2], "base64url");
    } catch {
      return { valid: false, status: "MALFORMED", message: "Credential token JSON is invalid." };
    }
    if (header.alg !== "EdDSA" || header.kid !== this.kid || payload.iss !== ISSUER_ID || !payload.vc) {
      return { valid: false, status: "UNTRUSTED_ISSUER", message: "Issuer or signing key is not trusted." };
    }
    if (!crypto.verify(null, Buffer.from(`${parts[0]}.${parts[1]}`), this.publicKey, signature)) {
      return { valid: false, status: "INVALID_SIGNATURE", message: "Issuer signature is invalid." };
    }
    if (!Number.isInteger(payload.exp) || payload.exp <= Math.floor(now / 1000)) {
      return { valid: false, status: "EXPIRED", message: "Credential has expired." };
    }
    const credential = payload.vc;
    if (envelope.credential && canonicalJson(envelope.credential) !== canonicalJson(credential)) {
      return { valid: false, status: "INVALID_SIGNATURE", message: "The displayed credential differs from the signed payload." };
    }
    if (credential.issuer?.id !== ISSUER_ID || credential.credentialSubject?.id !== payload.sub) {
      return { valid: false, status: "MALFORMED", message: "Credential subject or issuer does not match the signed envelope." };
    }
    if (phoneNumber && this.holders.get(phoneNumber)?.id !== credential.credentialSubject?.id) {
      return { valid: false, status: "PHONE_MISMATCH", message: "Credential does not belong to the verified demo phone." };
    }
    if (this.revoked.has(credential.id)) return { valid: false, status: "REVOKED", message: "Credential has been revoked." };
    return { valid: true, status: "VALID", message: "Demo issuer signature and expiry are valid; this is not a real DigiLocker credential." };
  }

  revoke(credentialId) {
    if (typeof credentialId !== "string" || !credentialId.startsWith("urn:uuid:")) {
      throw coded("INVALID_CREDENTIAL", "A valid demo credential ID is required.");
    }
    this.revoked.add(credentialId);
    return { credentialId, status: "REVOKED" };
  }

  createNegativeFixture(kind, envelope) {
    if (kind === "tampered") {
      const changed = { ...envelope, credential: { ...envelope.credential, credentialSubject: { ...envelope.credential.credentialSubject, name: "Tampered Demo" } } };
      return changed;
    }
    if (kind === "expired") {
      return { ...envelope, token: this._sign(envelope.credential, { validitySeconds: -1 }) };
    }
    if (kind === "phone_mismatch") return { ...envelope, testPhoneMismatch: true };
    throw coded("UNSUPPORTED_FIXTURE", "Unknown negative fixture.");
  }

  _credential(type, holder) {
    const now = new Date(this.now()).toISOString();
    const expiry = new Date(this.now() + 365 * 24 * 60 * 60 * 1000).toISOString();
    const base = {
      "@context": ["https://www.w3.org/2018/credentials/v1"],
      id: `urn:uuid:${crypto.randomUUID()}`,
      type: ["VerifiableCredential", "SimulatedDigiLockerCredential", `${type.toUpperCase()}Credential`],
      issuer: { id: ISSUER_ID, name: ISSUER_NAME },
      issuanceDate: now,
      expirationDate: expiry,
      credentialSubject: { id: holder.id, name: holder.name },
    };
    switch (type) {
      case "aadhaar":
        Object.assign(base.credentialSubject, { documentType: "Aadhaar (demo)", maskedAadhaar: `XXXX-XXXX-${holder.aadhaarLast4}`, dateOfBirth: holder.dateOfBirth, birthYear: Number(holder.dateOfBirth.slice(0, 4)), nationality: holder.nationality });
        break;
      case "voter_id":
        Object.assign(base.credentialSubject, { documentType: "Voter ID (demo)", maskedVoterId: `XX••••${holder.aadhaarLast4}`, state: holder.state, city: holder.city, birthYear: Number(holder.dateOfBirth.slice(0, 4)) });
        break;
      case "passport":
        Object.assign(base.credentialSubject, { documentType: "Passport (demo)", maskedPassport: `P••••${holder.aadhaarLast4}`, nationality: holder.nationality, birthYear: Number(holder.dateOfBirth.slice(0, 4)) });
        break;
      case "college":
        Object.assign(base.credentialSubject, { documentType: "College credential (demo)", institutionId: holder.institutionId, enrollmentStatus: "Active", program: "Demo studies", birthYear: Number(holder.dateOfBirth.slice(0, 4)) });
        break;
    }
    return base;
  }

  _sign(credential, { validitySeconds = 365 * 24 * 60 * 60 } = {}) {
    const issued = Math.floor(this.now() / 1000);
    const header = b64url({ typ: "zkmatchid-credential+jwt", alg: "EdDSA", kid: this.kid });
    const payload = b64url({ iss: ISSUER_ID, sub: credential.credentialSubject.id, iat: issued, exp: issued + validitySeconds, vc: credential });
    const input = `${header}.${payload}`;
    const signature = crypto.sign(null, Buffer.from(input), this.privateKey).toString("base64url");
    return `${input}.${signature}`;
  }
}

function b64url(value) { return Buffer.from(JSON.stringify(value)).toString("base64url"); }
function canonicalJson(value) {
  if (Array.isArray(value)) return `[${value.map(canonicalJson).join(",")}]`;
  if (value && typeof value === "object") {
    return `{${Object.keys(value).sort().map((key) => `${JSON.stringify(key)}:${canonicalJson(value[key])}`).join(",")}}`;
  }
  return JSON.stringify(value);
}
function coded(code, message) { const error = new Error(message); error.code = code; return error; }

module.exports = { DocumentProvider, SimulatedDigiLockerProvider, ISSUER_ID, ISSUER_NAME, SUPPORTED_TYPES };
