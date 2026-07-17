// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title ICCIPRouter
/// @notice Simplified Chainlink CCIP router interface for CrossLink Bridge
interface ICCIPRouter {
    /// @notice Send a cross-chain message to a remote receiver
    /// @param destChainSelector Destination chain identifier
    /// @param receiver Remote bridge contract address (ABI-encoded as bytes32 in production CCIP)
    /// @param data Encoded bridge payload
    /// @return messageId Unique message identifier
    function ccipSend(uint64 destChainSelector, address receiver, bytes calldata data)
        external
        returns (bytes32 messageId);
}
