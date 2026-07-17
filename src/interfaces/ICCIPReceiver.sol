// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title ICCIPReceiver
/// @notice Simplified Chainlink CCIP receiver interface for CrossLink Bridge
interface ICCIPReceiver {
    struct EVMTokenAmount {
        address token;
        uint256 amount;
    }

    struct Any2EVMMessage {
        bytes32 messageId;
        uint64 sourceChainSelector;
        bytes sender;
        bytes data;
        EVMTokenAmount[] tokenAmounts;
    }

    /// @notice Called by the CCIP Router when a cross-chain message arrives
    function ccipReceive(Any2EVMMessage calldata message) external;
}
