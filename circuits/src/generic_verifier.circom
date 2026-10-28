pragma circom 2.1.6;

include "../node_modules/circomlib/circuits/comparators.circom";
include "../node_modules/circomlib/circuits/poseidon.circom";

/**
 * GenericVerifier Circuit
 * 
 * Configurable multi-predicate zero-knowledge verification circuit:
 * - Mode 1: Numeric Threshold Check (attributeValue >= thresholdA, e.g., Income >= $4,000, Credit Score >= 700)
 * - Mode 2: Whitelisted Set Membership Check (attributeValue in allowedSet[0..4], e.g., accredited universities or allowed jurisdictions)
 * - Mode 3: Age Derivation Check (thresholdB - attributeValue >= thresholdA, e.g., currentYear - birthYear >= ageLimit)
 * 
 * Enforces temporal validity (credentialExpiry >= currentTimestamp) and binds proof to ephemeral sessionNonce
 * via Poseidon nullifier to prevent replay attacks.
 */
template GenericVerifier() {
    // ------------------------------------------------------------------------
    // Inputs
    // ------------------------------------------------------------------------
    // Private Inputs (never revealed to verifier)
    signal input attributeValue;
    signal input userSecretKey;
    signal input credentialExpiry;

    // Public Inputs (known to verifier and prover)
    signal input predicateMode;      // 1: Direct Threshold, 2: Set Membership, 3: Age Derivation
    signal input thresholdA;         // minThreshold (e.g., 18 for age, 4000 for income)
    signal input thresholdB;         // secondary parameter (e.g., currentYear)
    signal input allowedSet[5];      // 5-element allowed set for membership mode
    signal input currentTimestamp;   // current year / Unix timestamp
    signal input sessionNonce;       // verifier challenge

    // Reject every selector except the three supported predicate modes. Without
    // this constraint a nonstandard mode could bypass all three gated checks.
    signal modeDelta12;
    signal modeSelector;
    modeDelta12 <== (predicateMode - 1) * (predicateMode - 2);
    modeSelector <== modeDelta12 * (predicateMode - 3);
    modeSelector === 0;

    // ------------------------------------------------------------------------
    // Outputs
    // ------------------------------------------------------------------------
    signal output nullifier;

    // ------------------------------------------------------------------------
    // 1. Expiry Validation: credentialExpiry >= currentTimestamp
    // ------------------------------------------------------------------------
    component expiryCheck = GreaterEqThan(32);
    expiryCheck.in[0] <== credentialExpiry;
    expiryCheck.in[1] <== currentTimestamp;
    expiryCheck.out === 1;

    // ------------------------------------------------------------------------
    // 2. Mode 1: Direct Threshold Check (attributeValue >= thresholdA)
    // ------------------------------------------------------------------------
    component thresholdCheck = GreaterEqThan(32);
    thresholdCheck.in[0] <== attributeValue;
    thresholdCheck.in[1] <== thresholdA;
    // When predicateMode == 1, thresholdCheck.out must equal 1

    // ------------------------------------------------------------------------
    // 3. Mode 2: Whitelisted Set Membership Check
    // Proves (attributeValue - allowedSet[0]) * ... * (attributeValue - allowedSet[4]) == 0
    // ------------------------------------------------------------------------
    signal diff[5];
    signal prod[4];

    for (var i = 0; i < 5; i++) {
        diff[i] <== attributeValue - allowedSet[i];
    }

    prod[0] <== diff[0] * diff[1];
    prod[1] <== prod[0] * diff[2];
    prod[2] <== prod[1] * diff[3];
    prod[3] <== prod[2] * diff[4];
    // When predicateMode == 2, prod[3] must equal 0

    // ------------------------------------------------------------------------
    // 4. Mode 3: Age Derivation Check (thresholdB - attributeValue >= thresholdA)
    // ------------------------------------------------------------------------
    signal age;
    age <-- thresholdB - attributeValue;
    age + attributeValue === thresholdB;

    component ageComparator = GreaterEqThan(32);
    ageComparator.in[0] <== age;
    ageComparator.in[1] <== thresholdA;
    // When predicateMode == 3, ageComparator.out must equal 1

    // ------------------------------------------------------------------------
    // 5. Composite Mode Enforcement
    // ------------------------------------------------------------------------
    // Mode 1 check satisfies: (predicateMode - 2) * (predicateMode - 3) * (1 - thresholdCheck.out) === 0
    signal isMode1;
    signal mode1Factor;
    mode1Factor <== (predicateMode - 2) * (predicateMode - 3);
    isMode1 <== mode1Factor * (1 - thresholdCheck.out);
    isMode1 === 0;

    // Mode 2 check satisfies: (predicateMode - 1) * (predicateMode - 3) * prod[3] === 0
    signal isMode2;
    signal mode2Factor;
    mode2Factor <== (predicateMode - 1) * (predicateMode - 3);
    isMode2 <== mode2Factor * prod[3];
    isMode2 === 0;

    // Mode 3 check satisfies: (predicateMode - 1) * (predicateMode - 2) * (1 - ageComparator.out) === 0
    signal isMode3;
    signal mode3Factor;
    mode3Factor <== (predicateMode - 1) * (predicateMode - 2);
    isMode3 <== mode3Factor * (1 - ageComparator.out);
    isMode3 === 0;

    // ------------------------------------------------------------------------
    // 6. Anti-Replay Session Nullifier
    // nullifier = Poseidon(userSecretKey, sessionNonce)
    // ------------------------------------------------------------------------
    component poseidonHasher = Poseidon(2);
    poseidonHasher.inputs[0] <== userSecretKey;
    poseidonHasher.inputs[1] <== sessionNonce;

    nullifier <== poseidonHasher.out;
}

component main {public [predicateMode, thresholdA, thresholdB, allowedSet, currentTimestamp, sessionNonce]} = GenericVerifier();
