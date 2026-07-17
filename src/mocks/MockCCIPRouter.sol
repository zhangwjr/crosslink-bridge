// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ICCIPRouter} from "../interfaces/ICCIPRouter.sol";
import {ICCIPReceiver} from "../interfaces/ICCIPReceiver.sol";

/// @title MockCCIPRouter
/// @notice Local/test CCIP router that immediately delivers messages to the destination bridge
contract MockCCIPRouter is ICCIPRouter {
    struct PendingMessage {
        uint64 destChainSelector;
        address receiver;
        bytes data;
        address sender;
    }

    uint256 private _messageCounter;

    mapping(bytes32 => PendingMessage) public messages;
    mapping(uint64 => uint64) public sourceChainSelectors;

    event MessageSent(bytes32 indexed messageId, uint64 destChainSelector, address receiver);
    event MessageDelivered(bytes32 indexed messageId, address receiver);

    function setSourceChainSelector(uint64 destChainSelector, uint64 sourceChainSelector) external {
        sourceChainSelectors[destChainSelector] = sourceChainSelector;
    }

    function ccipSend(uint64 destChainSelector, address receiver, bytes calldata data)
        external
        returns (bytes32 messageId)
    {
        messageId = keccak256(abi.encodePacked(++_messageCounter, block.timestamp, msg.sender, receiver, data));

        messages[messageId] = PendingMessage({
            destChainSelector: destChainSelector,
            receiver: receiver,
            data: data,
            sender: msg.sender
        });

        emit MessageSent(messageId, destChainSelector, receiver);
        _deliver(messageId);
    }

    function deliverMessage(bytes32 messageId) external {
        _deliver(messageId);
    }

    function _deliver(bytes32 messageId) internal {
        PendingMessage memory pending = messages[messageId];
        require(pending.receiver != address(0), "MockCCIPRouter: missing receiver");

        ICCIPReceiver.EVMTokenAmount[] memory tokenAmounts = new ICCIPReceiver.EVMTokenAmount[](0);

        ICCIPReceiver.Any2EVMMessage memory message = ICCIPReceiver.Any2EVMMessage({
            messageId: messageId,
            sourceChainSelector: sourceChainSelectors[pending.destChainSelector],
            sender: abi.encode(pending.sender),
            data: pending.data,
            tokenAmounts: tokenAmounts
        });

        ICCIPReceiver(pending.receiver).ccipReceive(message);
        emit MessageDelivered(messageId, pending.receiver);
    }
}
