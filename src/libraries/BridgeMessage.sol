// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title BridgeMessage
/// @notice Encode/decode cross-chain bridge payloads
library BridgeMessage {
    enum Action {
        MINT, // lock on source -> mint wrapped on destination
        RELEASE // burn on destination -> release native on source
    }

    error InvalidPayload();

    function encodeMintRequest(address recipient, uint256 amount) internal pure returns (bytes memory) {
        return abi.encode(Action.MINT, recipient, amount);
    }

    function encodeReleaseRequest(address recipient, uint256 amount) internal pure returns (bytes memory) {
        return abi.encode(Action.RELEASE, recipient, amount);
    }

    function decode(bytes calldata data)
        internal
        pure
        returns (Action action, address recipient, uint256 amount)
    {
        (action, recipient, amount) = abi.decode(data, (Action, address, uint256));
        if (recipient == address(0) || amount == 0) revert InvalidPayload();
    }
}
