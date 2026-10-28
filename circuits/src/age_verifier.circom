pragma circom 2.1.6;

include "../node_modules/circomlib/circuits/comparators.circom";
include "../node_modules/circomlib/circuits/poseidon.circom";

/**
 * AgeVerifier Circuit
 * 
 * Verifies that a user is older than or equal to an ageLimit without revealing
 * their exact birthYear or userSecretKey.
 * Binds the proof to a single session via Poseidon(userSecretKey, sessionNonce)
 * to prevent replay attacks.
 */
template AgeVerifier() {
    // ------------------------------------------------------------------------
    // Inputs
    // ------------------------------------------------------------------------
    // Private Inputs (never revealed to verifier)
    signal input birthYear;
    signal input userSecretKey;

    // Public Inputs (known to both prover and verifier)
    signal input currentYear;
    signal input ageLimit;
    signal input sessionNonce;

    // ------------------------------------------------------------------------
    // Outputs
    // ------------------------------------------------------------------------
    // Public Output: Nullifier linking this identity to this session nonce
    signal output nullifier;

    // ------------------------------------------------------------------------
    // Constraints & Logic
    // ------------------------------------------------------------------------
    // 1. Calculate age = currentYear - birthYear
    signal age;
    age <-- currentYear - birthYear;

    // Ensure birthYear <= currentYear (sanity check)
    signal validYearOrder;
    component yearCheck = GreaterEqThan(16);
    yearCheck.in[0] <== currentYear;
    yearCheck.in[1] <== birthYear;
    validYearOrder <== yearCheck.out;
    validYearOrder === 1;

    // Enforce relationship age + birthYear === currentYear
    age + birthYear === currentYear;

    // 2. Enforce age >= ageLimit using 16-bit comparator
    component ageComparator = GreaterEqThan(16);
    ageComparator.in[0] <== age;
    ageComparator.in[1] <== ageLimit;

    // Enforce comparator output is 1 (true)
    ageComparator.out === 1;

    // 3. Compute session-bound nullifier = Poseidon(userSecretKey, sessionNonce)
    component poseidonHasher = Poseidon(2);
    poseidonHasher.inputs[0] <== userSecretKey;
    poseidonHasher.inputs[1] <== sessionNonce;

    nullifier <== poseidonHasher.out;
}

component main {public [currentYear, ageLimit, sessionNonce]} = AgeVerifier();
