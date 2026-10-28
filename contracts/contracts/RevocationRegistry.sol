// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title RevocationRegistry
 * @notice Manages credential revocation status via cryptographic hashes and Merkle accumulator roots.
 * @dev Stores only status flags and roots. Zero personal data stored on-chain.
 */
contract RevocationRegistry {
    address public owner;

    // Mapping from issuer ID => authorized address => canRevoke
    mapping(string => mapping(address => bool)) public authorizedRevokers;

    // Mapping from credential hash => isRevoked
    mapping(bytes32 => bool) private _revokedCredentials;

    // Mapping from issuer ID => Merkle Root of current Cryptographic Revocation List (CRL)
    mapping(string => bytes32) private _issuerRevocationRoots;

    event CredentialRevoked(bytes32 indexed credentialHash, string indexed issuerId, uint256 timestamp);
    event CredentialUnrevoked(bytes32 indexed credentialHash, string indexed issuerId, uint256 timestamp);
    event RevocationRootUpdated(string indexed issuerId, bytes32 newRoot, uint256 timestamp);

    modifier onlyAuthorized(string calldata issuerId) {
        require(
            msg.sender == owner || authorizedRevokers[issuerId][msg.sender],
            "RevocationRegistry: Not authorized for issuer"
        );
        _;
    }

    constructor() {
        owner = msg.sender;
    }

    function setAuthorizedRevoker(string calldata issuerId, address revoker, bool isAuthorized) external {
        require(msg.sender == owner, "Only owner");
        authorizedRevokers[issuerId][revoker] = isAuthorized;
    }

    /**
     * @notice Revoke a specific credential by its unique cryptographic hash
     */
    function revokeCredential(string calldata issuerId, bytes32 credentialHash) external onlyAuthorized(issuerId) {
        _revokedCredentials[credentialHash] = true;
        emit CredentialRevoked(credentialHash, issuerId, block.timestamp);
    }

    /**
     * @notice Unrevoke / reinstate a credential
     */
    function unrevokeCredential(string calldata issuerId, bytes32 credentialHash) external onlyAuthorized(issuerId) {
        _revokedCredentials[credentialHash] = false;
        emit CredentialUnrevoked(credentialHash, issuerId, block.timestamp);
    }

    /**
     * @notice Check whether a credential has been revoked
     */
    function isCredentialRevoked(bytes32 credentialHash) external view returns (bool) {
        return _revokedCredentials[credentialHash];
    }

    /**
     * @notice Update the accumulator / Merkle root of the issuer's revocation tree
     */
    function updateRevocationRoot(string calldata issuerId, bytes32 newRoot) external onlyAuthorized(issuerId) {
        _issuerRevocationRoots[issuerId] = newRoot;
        emit RevocationRootUpdated(issuerId, newRoot, block.timestamp);
    }

    /**
     * @notice Get current revocation Merkle root for an issuer
     */
    function getRevocationRoot(string calldata issuerId) external view returns (bytes32) {
        return _issuerRevocationRoots[issuerId];
    }
}
