// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IssuerRegistry
 * @notice Manages authorized identity providers (Government, Universities, Banks)
 * @dev Stores strictly public keys and metadata. Zero personal data stored on-chain.
 */
contract IssuerRegistry {
    address public owner;

    enum IssuerType { Government, University, Employer, FinancialInstitution, Other }

    struct Issuer {
        string issuerId;       // e.g. "did:zkmatch:gov-uidai"
        string name;           // e.g. "Government Identity Authority"
        IssuerType issuerType;
        bytes publicKey;       // Cryptographic public key used to verify VC signatures
        bool isActive;
        uint256 registeredAt;
        uint256 updatedAt;
    }

    // Mapping from issuer ID string to Issuer record
    mapping(string => Issuer) private _issuers;
    // Mapping from issuer signing address/hash to issuer ID
    mapping(address => string) private _addressToIssuerId;
    string[] private _issuerIds;

    event IssuerRegistered(string indexed issuerId, string name, IssuerType indexed issuerType);
    event IssuerStatusUpdated(string indexed issuerId, bool isActive);
    event IssuerKeyRotated(string indexed issuerId, bytes newPublicKey);

    modifier onlyOwner() {
        require(msg.sender == owner, "IssuerRegistry: Caller is not owner");
        _;
    }

    constructor() {
        owner = msg.sender;
    }

    /**
     * @notice Onboard an authorized identity provider
     */
    function registerIssuer(
        string calldata issuerId,
        string calldata name,
        IssuerType issuerType,
        bytes calldata publicKey,
        address signingAddress
    ) external onlyOwner {
        require(bytes(issuerId).length > 0, "IssuerRegistry: Empty issuerId");
        require(!_issuers[issuerId].isActive && _issuers[issuerId].registeredAt == 0, "IssuerRegistry: Already exists");

        _issuers[issuerId] = Issuer({
            issuerId: issuerId,
            name: name,
            issuerType: issuerType,
            publicKey: publicKey,
            isActive: true,
            registeredAt: block.timestamp,
            updatedAt: block.timestamp
        });

        if (signingAddress != address(0)) {
            _addressToIssuerId[signingAddress] = issuerId;
        }

        _issuerIds.push(issuerId);
        emit IssuerRegistered(issuerId, name, issuerType);
    }

    /**
     * @notice Update issuer active status
     */
    function setIssuerStatus(string calldata issuerId, bool isActive) external onlyOwner {
        require(_issuers[issuerId].registeredAt > 0, "IssuerRegistry: Issuer not found");
        _issuers[issuerId].isActive = isActive;
        _issuers[issuerId].updatedAt = block.timestamp;
        emit IssuerStatusUpdated(issuerId, isActive);
    }

    /**
     * @notice Check whether an issuer is valid and active
     */
    function isIssuerActive(string calldata issuerId) external view returns (bool) {
        return _issuers[issuerId].isActive;
    }

    /**
     * @notice Get issuer details
     */
    function getIssuer(string calldata issuerId) external view returns (Issuer memory) {
        require(_issuers[issuerId].registeredAt > 0, "IssuerRegistry: Issuer not found");
        return _issuers[issuerId];
    }

    /**
     * @notice Get all registered issuer IDs
     */
    function getAllIssuerIds() external view returns (string[] memory) {
        return _issuerIds;
    }
}
