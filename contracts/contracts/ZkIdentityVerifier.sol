// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./Groth16Verifier.sol";
import "./IssuerRegistry.sol";
import "./RevocationRegistry.sol";

/**
 * @title ZkIdentityVerifier
 * @notice Thin wrapper around the snarkjs-exported Groth16Verifier that also
 *         enforces issuer status, credential revocation, and nullifier anti-replay.
 * @dev Public signal layout from generic_verifier.circom (snarkjs order):
 *      [0] nullifier
 *      [1] predicateMode
 *      [2] thresholdA
 *      [3] thresholdB
 *      [4..8] allowedSet[5]
 *      [9] currentTimestamp
 *      [10] sessionNonce
 */
contract ZkIdentityVerifier {
    Groth16Verifier public immutable groth16;
    IssuerRegistry public immutable issuerRegistry;
    RevocationRegistry public immutable revocationRegistry;

    uint256 public constant NULLIFIER_INDEX = 0;

    mapping(uint256 => bool) public usedNullifiers;

    event IdentityVerified(
        address indexed submitter,
        string issuerId,
        bytes32 credentialHash,
        uint256 nullifier,
        uint256 predicateMode,
        uint256 thresholdA
    );

    error InvalidProof();
    error IssuerInactive();
    error CredentialRevoked();
    error NullifierAlreadyUsed();

    constructor(
        address groth16Verifier_,
        address issuerRegistry_,
        address revocationRegistry_
    ) {
        require(groth16Verifier_ != address(0), "zero groth16");
        require(issuerRegistry_ != address(0), "zero issuer registry");
        require(revocationRegistry_ != address(0), "zero revocation registry");
        groth16 = Groth16Verifier(groth16Verifier_);
        issuerRegistry = IssuerRegistry(issuerRegistry_);
        revocationRegistry = RevocationRegistry(revocationRegistry_);
    }

    /**
     * @notice Verify a Groth16 identity proof and record the nullifier.
     * @param pA Proof point A
     * @param pB Proof point B (G2)
     * @param pC Proof point C
     * @param pubSignals Circuit public signals (length 11)
     * @param issuerId Issuer DID / registry key (checked against IssuerRegistry)
     * @param credentialHash Hash of the credential being proven (checked against RevocationRegistry)
     */
    function verifyIdentity(
        uint256[2] calldata pA,
        uint256[2][2] calldata pB,
        uint256[2] calldata pC,
        uint256[11] calldata pubSignals,
        string calldata issuerId,
        bytes32 credentialHash
    ) external returns (bool) {
        if (!issuerRegistry.isIssuerActive(issuerId)) {
            revert IssuerInactive();
        }
        if (revocationRegistry.isCredentialRevoked(credentialHash)) {
            revert CredentialRevoked();
        }

        uint256 nullifier = pubSignals[NULLIFIER_INDEX];
        if (usedNullifiers[nullifier]) {
            revert NullifierAlreadyUsed();
        }

        bool ok = groth16.verifyProof(pA, pB, pC, pubSignals);
        if (!ok) {
            revert InvalidProof();
        }

        usedNullifiers[nullifier] = true;

        emit IdentityVerified(
            msg.sender,
            issuerId,
            credentialHash,
            nullifier,
            pubSignals[1],
            pubSignals[2]
        );
        return true;
    }

    /// @notice View-only Groth16 check without recording the nullifier.
    function verifyProofOnly(
        uint256[2] calldata pA,
        uint256[2][2] calldata pB,
        uint256[2] calldata pC,
        uint256[11] calldata pubSignals
    ) external view returns (bool) {
        return groth16.verifyProof(pA, pB, pC, pubSignals);
    }
}
