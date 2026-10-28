const crypto = require("crypto");

/**
 * Mock Trusted Issuer Service
 * Simulates government agencies, universities, and enterprise identity providers
 * issuing digitally signed Verifiable Credentials (VCs).
 */
class IssuerService {
  constructor() {
    this.issuers = {
      "did:zkmatch:gov-uidai": {
        name: "National Identity Authority (Government)",
        type: "Government",
        publicKey: "04a1b2c3d4e5f67890abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890",
        privateKey: "gov_secret_key_mock_for_testing",
      },
      "did:zkmatch:university-pes": {
        name: "State University Academic Registry",
        type: "University",
        publicKey: "04b2c3d4e5f67890abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890a1",
        privateKey: "uni_secret_key_mock_for_testing",
      },
      "did:zkmatch:bank-apex": {
        name: "Apex National Bank & Credit Authority",
        type: "FinancialInstitution",
        publicKey: "04c3d4e5f67890abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890b2",
        privateKey: "bank_secret_key_mock_for_testing",
      },
      "did:zkmatch:municipal-bda": {
        name: "Bengaluru Municipal Authority",
        type: "Government",
        publicKey: "04d4e5f6a7b890abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890b3",
        privateKey: "municipal_secret_key_mock_for_testing",
      },
    };
  }

  /**
   * Generates a digitally signed Verifiable Credential (VC)
   */
  issueCredential({
    issuerId,
    subjectId = "did:zkmatch:holder-local",
    schemaId = "schema:zkmatch:age-verification-v1",
    credentialType = "IdentityCredential",
    attributes = {},
    validityDays = 365,
  }) {
    const issuer = this.issuers[issuerId];
    if (!issuer) {
      throw new Error(`Issuer '${issuerId}' not recognized.`);
    }

    const issuanceDate = new Date().toISOString();
    const expirationDate = new Date(
      Date.now() + validityDays * 24 * 60 * 60 * 1000
    ).toISOString();

    const credentialSubject = {
      id: subjectId,
      ...attributes,
    };

    const credentialData = {
      "@context": ["https://www.w3.org/2018/credentials/v1"],
      id: `urn:uuid:${crypto.randomUUID()}`,
      type: ["VerifiableCredential", credentialType],
      issuer: {
        id: issuerId,
        name: issuer.name,
      },
      schema: {
        id: schemaId,
        type: "JsonSchemaValidator2018",
      },
      issuanceDate,
      expirationDate,
      credentialSubject,
    };

    // Generate cryptographic signature over canonical payload
    const canonicalString = JSON.stringify(credentialData);
    const signature = crypto
      .createHmac("sha256", issuer.privateKey)
      .update(canonicalString)
      .digest("hex");

    const signedVc = {
      ...credentialData,
      proof: {
        type: "Ed25519Signature2020",
        created: issuanceDate,
        verificationMethod: `${issuerId}#key-1`,
        proofPurpose: "assertionMethod",
        signatureValue: signature,
      },
    };

    return signedVc;
  }
}

module.exports = IssuerService;

if (require.main === module) {
  const service = new IssuerService();
  const govVc = service.issueCredential({
    issuerId: "did:zkmatch:gov-uidai",
    credentialType: "NationalIdentityCredential",
    attributes: {
      documentType: "National_ID",
      dateOfBirth: "2000-01-01",
      birthYear: 2000,
      nationality: "IND",
    },
  });

  console.log("=== Generated Government Verifiable Credential ===");
  console.log(JSON.stringify(govVc, null, 2));
}
