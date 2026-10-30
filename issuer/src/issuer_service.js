// Compatibility entry point. The old implementation embedded fake HMAC keys
// while labelling its output Ed25519. All demo credentials now go through the
// Ed25519-backed, explicitly simulated provider.
const { SimulatedDigiLockerProvider } = require("./document_provider");

class IssuerService {
  constructor(options) {
    this.provider = new SimulatedDigiLockerProvider(options);
  }

  issueCredential({ issuerId, credentialType, attributes = {} }) {
    if (issuerId !== "did:zkmatch:simulated-digilocker-demo") {
      throw new Error("Only the fictional simulated demo issuer is supported.");
    }
    const type = String(credentialType || "").toLowerCase().includes("college")
      ? "college"
      : "aadhaar";
    const holder = this.provider.holders.values().next().value;
    if (!holder) throw new Error("No fictional demo identities are configured.");
    const credential = this.provider._credential(type, holder);
    Object.assign(credential.credentialSubject, attributes);
    return {
      simulated: true,
      credential,
      signedToken: this.provider._sign(credential),
    };
  }
}

module.exports = IssuerService;
