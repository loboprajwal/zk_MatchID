// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title CredentialSchemaRegistry
 * @notice Standardized registry for credential schema definitions & attribute specifications.
 * @dev Stores schema hashes and attribute lists. Zero personal data stored on-chain.
 */
contract CredentialSchemaRegistry {
    address public owner;

    struct CredentialSchema {
        string schemaId;       // e.g. "schema:zkmatch:age-verification-v1"
        string name;           // e.g. "Standard Age & Identity Credential"
        string version;        // e.g. "1.0.0"
        bytes32 schemaHash;    // Keccak256 hash of JSON-LD / schema specification
        string[] requiredAttributes; // e.g. ["birthYear", "nationality", "documentType"]
        uint256 createdAt;
    }

    mapping(string => CredentialSchema) private _schemas;
    string[] private _schemaIds;

    event SchemaRegistered(string indexed schemaId, string name, bytes32 schemaHash);

    modifier onlyOwner() {
        require(msg.sender == owner, "CredentialSchemaRegistry: Caller is not owner");
        _;
    }

    constructor() {
        owner = msg.sender;
    }

    function registerSchema(
        string calldata schemaId,
        string calldata name,
        string calldata version,
        bytes32 schemaHash,
        string[] calldata requiredAttributes
    ) external onlyOwner {
        require(bytes(schemaId).length > 0, "Empty schemaId");
        require(_schemas[schemaId].createdAt == 0, "Schema already exists");

        _schemas[schemaId] = CredentialSchema({
            schemaId: schemaId,
            name: name,
            version: version,
            schemaHash: schemaHash,
            requiredAttributes: requiredAttributes,
            createdAt: block.timestamp
        });

        _schemaIds.push(schemaId);
        emit SchemaRegistered(schemaId, name, schemaHash);
    }

    function getSchema(string calldata schemaId) external view returns (CredentialSchema memory) {
        require(_schemas[schemaId].createdAt > 0, "Schema not found");
        return _schemas[schemaId];
    }

    function getAllSchemaIds() external view returns (string[] memory) {
        return _schemaIds;
    }
}
