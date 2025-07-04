// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IHomeArbitrationProxy
 * @dev Interface for the Home arbitration proxy contract
 */
interface IHomeArbitrationProxy {
    // Events
    event RequestNotified(bytes32 indexed questionID, address indexed requester, uint256 maxPrevious);
    event RequestRejected(bytes32 indexed questionID, address indexed requester, uint256 maxPrevious, string reason);
    event ArbitrationFailed(bytes32 indexed questionID, address indexed requester);
    event RequestAcknowledged(bytes32 indexed questionID, address indexed requester);
    event RequestCanceled(bytes32 indexed questionID, address indexed requester);
    event ArbitratorAnswered(bytes32 indexed questionID, bytes32 answer);
    event ArbitrationFinished(bytes32 indexed questionID);

    // Functions
    function metadata() external view returns (string memory);
    function handleNotifiedRequest(bytes32 questionID, address requester) external;
    function handleRejectedRequest(bytes32 questionID, address requester) external;
    function receiveArbitrationAnswer(bytes32 questionID, bytes32 answer) external;
}

/**
 * @title IForeignArbitrationProxy
 * @dev Interface for the Foreign arbitration proxy contract
 */
interface IForeignArbitrationProxy {
    // Events
    event ArbitrationRequested(bytes32 indexed questionID, address indexed requester, uint256 maxPrevious);
    event RulingRelayed(bytes32 indexed questionID, bytes32 answer);
    event ArbitrationMetaEvidence(uint256 indexed metaEvidenceID, string metaEvidence);
} 