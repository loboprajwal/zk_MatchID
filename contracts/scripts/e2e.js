/**
 * End-to-end local demo:
 *  - Build age>=18 and income-threshold witnesses
 *  - Prove with snarkjs (timed)
 *  - Verify off-chain (timed)
 *  - Deploy contracts on the in-process Hardhat network
 *  - Verify on-chain and report gas
 *
 * Usage: npx hardhat run scripts/e2e.js
 */
const fs = require("fs");
const path = require("path");
const snarkjs = require("snarkjs");
const hre = require("hardhat");
const {
  WASM,
  ZKEY,
  VKEY,
  prove,
  ageInput,
  incomeInput,
} = require("../test/helpers/proof");

async function timeProve(label, input) {
  const t0 = Date.now();
  const result = await prove(input);
  const proveMs = Date.now() - t0;
  const vkey = JSON.parse(fs.readFileSync(VKEY, "utf8"));
  const t1 = Date.now();
  const ok = await snarkjs.groth16.verify(
    vkey,
    result.publicSignals,
    result.proof
  );
  const verifyMs = Date.now() - t1;
  if (!ok) throw new Error(`${label}: off-chain verify failed`);
  console.log(`[${label}] prove=${proveMs}ms  offchain_verify=${verifyMs}ms`);
  return { ...result, proveMs, verifyMs };
}

async function main() {
  console.log("Assets:");
  console.log("  wasm:", WASM, fs.existsSync(WASM));
  console.log("  zkey:", ZKEY, fs.existsSync(ZKEY));
  console.log("  vkey:", VKEY, fs.existsSync(VKEY));

  const age = await timeProve(
    "age>=18",
    ageInput({ sessionNonce: String(Date.now()) + "01" })
  );
  const income = await timeProve(
    "income>=4000",
    incomeInput({ sessionNonce: String(Date.now()) + "02" })
  );

  const [deployer] = await hre.ethers.getSigners();
  const IssuerRegistry = await hre.ethers.getContractFactory("IssuerRegistry");
  const issuerRegistry = await IssuerRegistry.deploy();
  await issuerRegistry.waitForDeployment();

  const RevocationRegistry = await hre.ethers.getContractFactory(
    "RevocationRegistry"
  );
  const revocationRegistry = await RevocationRegistry.deploy();
  await revocationRegistry.waitForDeployment();

  const Groth16Verifier = await hre.ethers.getContractFactory("Groth16Verifier");
  const groth16 = await Groth16Verifier.deploy();
  await groth16.waitForDeployment();

  const ZkIdentityVerifier = await hre.ethers.getContractFactory(
    "ZkIdentityVerifier"
  );
  const zkIdentity = await ZkIdentityVerifier.deploy(
    await groth16.getAddress(),
    await issuerRegistry.getAddress(),
    await revocationRegistry.getAddress()
  );
  await zkIdentity.waitForDeployment();

  const issuerId = "did:zkmatch:gov-uidai";
  await (
    await issuerRegistry.registerIssuer(
      issuerId,
      "National Identity Authority",
      0,
      "0x04a1b2c3d4e5f67890abcdef1234567890abcdef1234567890abcdef1234567890",
      deployer.address
    )
  ).wait();

  async function onchain(label, solidity, credSuffix) {
    const viewOk = await groth16.verifyProof.staticCall(
      solidity.a,
      solidity.b,
      solidity.c,
      solidity.pubSignals
    );
    console.log(`[${label}] groth16 view verify =`, viewOk);

    const tx = await zkIdentity.verifyIdentity(
      solidity.a,
      solidity.b,
      solidity.c,
      solidity.pubSignals,
      issuerId,
      hre.ethers.id(`urn:uuid:e2e-${credSuffix}`)
    );
    const receipt = await tx.wait();
    console.log(
      `[${label}] on-chain verifyIdentity gasUsed=${receipt.gasUsed.toString()} status=${receipt.status}`
    );
    return Number(receipt.gasUsed);
  }

  const ageGas = await onchain("age>=18", age.solidity, "age");
  const incomeGas = await onchain("income>=4000", income.solidity, "income");

  // Constraint count from prior compile (documented; re-read if r1cs present)
  let constraints = 350;
  try {
    const { execSync } = require("child_process");
    const info = execSync(
      `npx --prefix ../circuits snarkjs r1cs info ${path.resolve(
        __dirname,
        "../../mopro/assets/generic_verifier.r1cs"
      )}`,
      { encoding: "utf8" }
    );
    const m = info.match(/# of Constraints:\s*(\d+)/);
    if (m) constraints = Number(m[1]);
  } catch (_) {
    /* keep default */
  }

  const results = {
    circuit: "generic_verifier",
    constraints,
    ceremony: "local-dev pot12 (NOT production)",
    age: {
      proveMs: age.proveMs,
      offchainVerifyMs: age.verifyMs,
      onchainGas: ageGas,
    },
    income: {
      proveMs: income.proveMs,
      offchainVerifyMs: income.verifyMs,
      onchainGas: incomeGas,
    },
    measuredAt: new Date().toISOString(),
  };

  const outDir = path.join(__dirname, "..", "deployments");
  fs.mkdirSync(outDir, { recursive: true });
  const outFile = path.join(outDir, "e2e-local-results.json");
  fs.writeFileSync(outFile, JSON.stringify(results, null, 2));
  console.log("\n=== RESULTS ===");
  console.log(JSON.stringify(results, null, 2));
  console.log("Wrote", outFile);
  process.exit(0);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
