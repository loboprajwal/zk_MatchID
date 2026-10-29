DEV CEREMONY ONLY — NOT FOR PRODUCTION
======================================
This Powers of Tau file (pot12_final.ptau) was generated locally with:
  snarkjs powersoftau new bn128 12
  snarkjs powersoftau contribute
  snarkjs powersoftau beacon <fixed-hash> 10
  snarkjs powersoftau prepare phase2

Public Hermez / PSE ceremony mirrors were unreachable (HTTP 403) from the
build environment, so a fresh local 2^12 ceremony was used instead.

Do NOT use the resulting zkey or Groth16Verifier for mainnet or any
security-sensitive deployment. Re-run setup against powersOfTau28_hez_final_12.ptau
(or another audited multi-party ceremony) before production.
