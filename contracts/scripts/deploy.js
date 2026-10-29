/**
 * Deploy IssuerRegistry, CredentialSchemaRegistry, RevocationRegistry,
 * Groth16Verifier, and ZkIdentityVerifier.
 *
 * Usage:
 *   npx hardhat run scripts/deploy.js
 *   npx hardhat run scripts/deploy.js --network amoy
 */
const fs = require("fs");
const path = require("path");
const hre = require("hardhat");

async function main() {
  const [deployer] = await hre.ethers.getSigners();
  console.log("Deployer:", deployer.address);
  console.log("Network:", hre.network.name, "chainId=", (await hre.ethers.provider.getNetwork()).chainId.toString());

  const IssuerRegistry = await hre.ethers.getContractFactory("IssuerRegistry");
  const issuerRegistry = await IssuerRegistry.deploy();
  await issuerRegistry.waitForDeployment();
  console.log("IssuerRegistry:", await issuerRegistry.getAddress());

  const CredentialSchemaRegistry = await hre.ethers.getContractFactory(
    "CredentialSchemaRegistry"
  );
  const schemaRegistry = await CredentialSchemaRegistry.deploy();
  await schemaRegistry.waitForDeployment();
  console.log("CredentialSchemaRegistry:", await schemaRegistry.getAddress());

  const RevocationRegistry = await hre.ethers.getContractFactory(
    "RevocationRegistry"
  );
  const revocationRegistry = await RevocationRegistry.deploy();
  await revocationRegistry.waitForDeployment();
  console.log("RevocationRegistry:", await revocationRegistry.getAddress());

  const Groth16Verifier = await hre.ethers.getContractFactory("Groth16Verifier");
  const groth16 = await Groth16Verifier.deploy();
  await groth16.waitForDeployment();
  console.log("Groth16Verifier:", await groth16.getAddress());

  const ZkIdentityVerifier = await hre.ethers.getContractFactory(
    "ZkIdentityVerifier"
  );
  const zkIdentity = await ZkIdentityVerifier.deploy(
    await groth16.getAddress(),
    await issuerRegistry.getAddress(),
    await revocationRegistry.getAddress()
  );
  await zkIdentity.waitForDeployment();
  console.log("ZkIdentityVerifier:", await zkIdentity.getAddress());

  // Seed a demo government issuer so Amoy deployments are immediately usable.
  const demoIssuerId = "did:zkmatch:gov-uidai";
  const tx = await issuerRegistry.registerIssuer(
    demoIssuerId,
    "National Identity Authority (Government)",
    0, // IssuerType.Government
    "0x04a1b2c3d4e5f67890abcdef1234567890abcdef1234567890abcdef1234567890",
    deployer.address
  );
  await tx.wait();
  console.log("Registered demo issuer:", demoIssuerId);

  const out = {
    network: hre.network.name,
    chainId: Number((await hre.ethers.provider.getNetwork()).chainId),
    deployer: deployer.address,
    contracts: {
      IssuerRegistry: await issuerRegistry.getAddress(),
      CredentialSchemaRegistry: await schemaRegistry.getAddress(),
      RevocationRegistry: await revocationRegistry.getAddress(),
      Groth16Verifier: await groth16.getAddress(),
      ZkIdentityVerifier: await zkIdentity.getAddress(),
    },
    demoIssuerId,
    deployedAt: new Date().toISOString(),
  };

  const outDir = path.join(__dirname, "..", "deployments");
  fs.mkdirSync(outDir, { recursive: true });
  const outFile = path.join(outDir, `${hre.network.name}.json`);
  fs.writeFileSync(outFile, JSON.stringify(out, null, 2));
  console.log("Wrote", outFile);
  console.log(JSON.stringify(out, null, 2));
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
