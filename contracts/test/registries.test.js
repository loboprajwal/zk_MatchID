const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("Trust registries", function () {
  it("restricts issuer registration and supports suspension", async function () {
    const [owner, outsider] = await ethers.getSigners();
    const Registry = await ethers.getContractFactory("IssuerRegistry");
    const registry = await Registry.deploy();
    const issuerId = "did:zkmatch:demo-issuer";
    const key = ethers.toUtf8Bytes("demo-public-key");

    await expect(
      registry.connect(outsider).registerIssuer(issuerId, "Demo", 4, key, ethers.ZeroAddress),
    ).to.be.revertedWith("IssuerRegistry: Caller is not owner");

    await registry.registerIssuer(issuerId, "Demo issuer", 4, key, owner.address);
    expect(await registry.isIssuerActive(issuerId)).to.equal(true);
    expect((await registry.getIssuer(issuerId)).publicKey).to.equal(ethers.hexlify(key));
    await expect(
      registry.registerIssuer(issuerId, "Duplicate", 4, key, ethers.ZeroAddress),
    ).to.be.revertedWith("IssuerRegistry: Already exists");

    await registry.setIssuerStatus(issuerId, false);
    expect(await registry.isIssuerActive(issuerId)).to.equal(false);
    await expect(registry.getIssuer("did:missing")).to.be.revertedWith(
      "IssuerRegistry: Issuer not found",
    );
  });

  it("stores immutable schema identifiers and attribute requirements", async function () {
    const [owner, outsider] = await ethers.getSigners();
    const Registry = await ethers.getContractFactory("CredentialSchemaRegistry");
    const registry = await Registry.deploy();
    const schemaId = "schema:zkmatch:demo-v1";
    const schemaHash = ethers.id("demo schema");

    await expect(
      registry.connect(outsider).registerSchema(schemaId, "Demo", "1.0.0", schemaHash, ["name"]),
    ).to.be.revertedWith("CredentialSchemaRegistry: Caller is not owner");
    await registry.registerSchema(schemaId, "Demo", "1.0.0", schemaHash, ["name", "expiresAt"]);
    const schema = await registry.getSchema(schemaId);
    expect(schema.schemaHash).to.equal(schemaHash);
    expect(schema.requiredAttributes).to.deep.equal(["name", "expiresAt"]);
    await expect(
      registry.registerSchema(schemaId, "Duplicate", "1.0.0", schemaHash, []),
    ).to.be.revertedWith("Schema already exists");
  });

  it("enforces authorized revocation and updates its commitment root", async function () {
    const [owner, issuer, outsider] = await ethers.getSigners();
    const Registry = await ethers.getContractFactory("RevocationRegistry");
    const registry = await Registry.deploy();
    const issuerId = "did:zkmatch:demo-issuer";
    const credentialHash = ethers.id("fictional credential");
    const root = ethers.id("revocation root");

    await expect(
      registry.connect(outsider).revokeCredential(issuerId, credentialHash),
    ).to.be.revertedWith("RevocationRegistry: Not authorized for issuer");
    await registry.setAuthorizedRevoker(issuerId, issuer.address, true);
    await registry.connect(issuer).revokeCredential(issuerId, credentialHash);
    expect(await registry.isCredentialRevoked(credentialHash)).to.equal(true);
    await registry.connect(issuer).updateRevocationRoot(issuerId, root);
    expect(await registry.getRevocationRoot(issuerId)).to.equal(root);
    await registry.connect(issuer).unrevokeCredential(issuerId, credentialHash);
    expect(await registry.isCredentialRevoked(credentialHash)).to.equal(false);
  });
});
