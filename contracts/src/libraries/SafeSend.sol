// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title SafeSend
 * @dev Library for safe ETH transfers
 */
library SafeSend {
    /**
     * @dev Safely sends ETH to an address
     * @param recipient The address to send ETH to
     * @param amount The amount of ETH to send
     * @return success Whether the transfer was successful
     */
    function send(address payable recipient, uint256 amount) internal returns (bool success) {
        require(address(this).balance >= amount, "SafeSend: insufficient balance");
        
        // Use call instead of transfer to avoid gas limit issues
        (success, ) = recipient.call{value: amount}("");
        
        return success;
    }
    
    /**
     * @dev Safely sends ETH to an address with fallback handling
     * @param recipient The address to send ETH to
     * @param amount The amount of ETH to send
     */
    function safeSend(address payable recipient, uint256 amount) internal {
        bool success = send(recipient, amount);
        require(success, "SafeSend: transfer failed");
    }
} 