const { expect } = require("chai");
const { ethers } = require("hardhat");
const { prove, ageInput, incomeInput } = require("./helpers/proof");

describe("ZkIdentityVerifier + Groth16Verifier", function () {
  this.timeout(120000);

  let issuerRegistry, revocationRegistry, groth16, zkIdentity;
  let owner, other;
  const issuerId = "did:zkmatch:gov-uidai";
  const credentialHash = ethers.id("urn:uuid:gov-credential-demo-1");

  before(async function () {
    [owner, other] = await ethers.getSigners();

    issuerRegistry = await (
      await ethers.getContractFactory("IssuerRegistry")
    ).deploy();
    await issuerRegistry.waitForDeployment();

    revocationRegistry = await (
      await ethers.getContractFactory("RevocationRegistry")
    ).deploy();
    await revocationRegistry.waitForDeployment();

    groth16 = await (
      await ethers.getContractFactory("Groth16Verifier")
    ).deploy();
    await groth16.waitForDeployment();

    zkIdentity = await (
      await ethers.getContractFactory("ZkIdentityVerifier")
    ).deploy(
      await groth16.getAddress(),
      await issuerRegistry.getAddress(),
      await revocationRegistry.getAddress()
    );
    await zkIdentity.waitForDeployment();

    await (
      await issuerRegistry.registerIssuer(
        issuerId,
        "National Identity Authority",
        0,
        "0x04a1b2c3d4e5f67890abcdef1234567890abcdef1234567890abcdef1234567890",
        owner.address
      )
    ).wait();
  });

  it("accepts a valid age >= 18 Groth16 proof on-chain", async function () {
    const { solidity } = await prove(ageInput());
    const ok = await groth16.verifyProof.staticCall(
      solidity.a,
      solidity.b,
      solidity.c,
      solidity.pubSignals
    );
    expect(ok).to.equal(true);

    const tx = await zkIdentity.verifyIdentity(
      solidity.a,
      solidity.b,
      solidity.c,
      solidity.pubSignals,
      issuerId,
      credentialHash
    );
    const receipt = await tx.wait();
    expect(receipt.status).to.equal(1);

    const nullifier = solidity.pubSignals[0];
    expect(await zkIdentity.usedNullifiers(nullifier)).to.equal(true);
  });

  it("accepts a valid income threshold proof (mode 1)", async function () {
    const { solidity } = await prove(
      incomeInput({ sessionNonce: "55566677788899900011" })
    );
    const ok = await groth16.verifyProof.staticCall(
      solidity.a,
      solidity.b,
      solidity.c,
      solidity.pubSignals
    );
    expect(ok).to.equal(true);

    await expect(
      zkIdentity.verifyIdentity(
        solidity.a,
        solidity.b,
        solidity.c,
        solidity.pubSignals,
        issuerId,
        ethers.id("urn:uuid:income-credential-1")
      )
    ).to.emit(zkIdentity, "IdentityVerified");
  });

  it("rejects a tampered public input", async function () {
    const { solidity } = await prove(
      ageInput({ sessionNonce: "22233344455566677788" })
    );
    // Flip age limit from 18 to 21 without regenerating the proof.
    const tampered = [...solidity.pubSignals];
    tampered[2] = 21n;

    const ok = await groth16.verifyProof.staticCall(
      solidity.a,
      solidity.b,
      solidity.c,
      tampered
    );
    expect(ok).to.equal(false);

    await expect(
      zkIdentity.verifyIdentity(
        solidity.a,
        solidity.b,
        solidity.c,
        tampered,
        issuerId,
        ethers.id("urn:uuid:tamper-1")
      )
    ).to.be.revertedWithCustomError(zkIdentity, "InvalidProof");
  });

  it("rejects a tampered proof point", async function () {
    const { solidity } = await prove(
      ageInput({ sessionNonce: "33344455566677788899" })
    );
    const badA = [BigInt(solidity.a[0]), BigInt(solidity.a[1]) ^ 1n];

    await expect(
      zkIdentity.verifyIdentity(
        badA,
        solidity.b,
        solidity.c,
        solidity.pubSignals,
        issuerId,
        ethers.id("urn:uuid:tamper-2")
      )
    ).to.be.revertedWithCustomError(zkIdentity, "InvalidProof");
  });

  it("rejects a revoked credential", async function () {
    const { solidity } = await prove(
      ageInput({ sessionNonce: "44455566677788899900" })
    );
    const revokedHash = ethers.id("urn:uuid:revoked-cred");
    await (
      await revocationRegistry.revokeCredential(issuerId, revokedHash)
    ).wait();

    await expect(
      zkIdentity.verifyIdentity(
        solidity.a,
        solidity.b,
        solidity.c,
        solidity.pubSignals,
        issuerId,
        revokedHash
      )
    ).to.be.revertedWithCustomError(zkIdentity, "CredentialRevoked");
  });

  it("rejects a nullifier replay", async function () {
    const { solidity } = await prove(
      ageInput({ sessionNonce: "66677788899900011122" })
    );
    const hash = ethers.id("urn:uuid:replay-cred");

    await (
      await zkIdentity.verifyIdentity(
        solidity.a,
        solidity.b,
        solidity.c,
        solidity.pubSignals,
        issuerId,
        hash
      )
    ).wait();

    await expect(
      zkIdentity.verifyIdentity(
        solidity.a,
        solidity.b,
        solidity.c,
        solidity.pubSignals,
        issuerId,
        hash
      )
    ).to.be.revertedWithCustomError(zkIdentity, "NullifierAlreadyUsed");
  });

  it("rejects an inactive / unknown issuer", async function () {
    const { solidity } = await prove(
      ageInput({ sessionNonce: "77788899900011122233" })
    );
    await expect(
      zkIdentity.verifyIdentity(
        solidity.a,
        solidity.b,
        solidity.c,
        solidity.pubSignals,
        "did:zkmatch:unknown",
        ethers.id("urn:uuid:unknown-issuer")
      )
    ).to.be.revertedWithCustomError(zkIdentity, "IssuerInactive");
  });
});
