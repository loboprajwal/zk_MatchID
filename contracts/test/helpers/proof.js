const path = require("path");
const snarkjs = require("snarkjs");

const ASSETS = path.resolve(__dirname, "../../../mopro/assets");
const WASM = path.join(ASSETS, "generic_verifier.wasm");
const ZKEY = path.join(ASSETS, "generic_verifier_final.zkey");
const VKEY = path.join(ASSETS, "verification_key.json");

/** Convert a snarkjs proof into the Solidity calldata shape (G2 limbs swapped). */
function toSolidityProof(proof, publicSignals) {
  return {
    a: [proof.pi_a[0], proof.pi_a[1]],
    b: [
      [proof.pi_b[0][1], proof.pi_b[0][0]],
      [proof.pi_b[1][1], proof.pi_b[1][0]],
    ],
    c: [proof.pi_c[0], proof.pi_c[1]],
    pubSignals: publicSignals.map((s) => BigInt(s)),
  };
}

async function prove(input) {
  const { proof, publicSignals } = await snarkjs.groth16.fullProve(
    input,
    WASM,
    ZKEY
  );
  return { proof, publicSignals, solidity: toSolidityProof(proof, publicSignals) };
}

function ageInput(overrides = {}) {
  return {
    attributeValue: 2000,
    userSecretKey: "12345678901234567890",
    credentialExpiry: 2030,
    predicateMode: 3,
    thresholdA: 18,
    thresholdB: 2026,
    allowedSet: [0, 0, 0, 0, 0],
    currentTimestamp: 2026,
    sessionNonce: "98765432109876543210",
    ...overrides,
  };
}

function incomeInput(overrides = {}) {
  return {
    attributeValue: 5200,
    userSecretKey: "12345678901234567890",
    credentialExpiry: 2030,
    predicateMode: 1,
    thresholdA: 4000,
    thresholdB: 0,
    allowedSet: [0, 0, 0, 0, 0],
    currentTimestamp: 2026,
    sessionNonce: "11122233344455566677",
    ...overrides,
  };
}

module.exports = {
  ASSETS,
  WASM,
  ZKEY,
  VKEY,
  prove,
  toSolidityProof,
  ageInput,
  incomeInput,
};
