// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

// Constants for LayerZero Cross-Chain Arbitration System
// Defines message types and routing constants for Reality.eth arbitration across chains

// Message Flow Overview:
// 1. ARBITRATION_REQUEST: Foreign → Home (Request arbitration for a question)
// 2. ARBITRATION_ACKNOWLEDGEMENT: Home → Foreign (Acknowledge request, start dispute)
// 3. ARBITRATION_CANCELATION: Home → Foreign (Cancel rejected request)
// 4. ARBITRATION_FAILURE: Foreign → Home (Notify failure to create dispute)
// 5. ARBITRATION_ANSWER: Foreign → Home (Send final ruling from arbitrator)

// Contract Routing:
// - RealitioHomeProxyLZ handles: REQUEST, FAILURE, ANSWER
// - RealitioForeignProxyLZ handles: ACKNOWLEDGEMENT, CANCELATION

uint16 constant MSG_TYPE_ARBITRATION_REQUEST = 1;
uint16 constant MSG_TYPE_ARBITRATION_ACKNOWLEDGEMENT = 2;
uint16 constant MSG_TYPE_ARBITRATION_CANCELATION = 3;
uint16 constant MSG_TYPE_ARBITRATION_FAILURE = 4;
uint16 constant MSG_TYPE_ARBITRATION_ANSWER = 5;

// Custom errors
error InsufficientFundsForLayerZero(uint256 required, uint256 available);