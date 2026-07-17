// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IRouterClient} from "../vendor/ccip/IRouterClient.sol";
import {IAny2EVMMessageReceiver} from "../vendor/ccip/IAny2EVMMessageReceiver.sol";
import {Client} from "../vendor/ccip/Client.sol";

/// @title MockCCIPRouter
/// @notice Local/test CCIP router that immediately delivers messages to the destination bridge
contract MockCCIPRouter is IRouterClient {
    uint256 public constant FEE = 0.001 ether;

    struct PendingMessage {
        uint64 destChainSelector;
        address receiver;
        bytes data;
        address sender;
    }

    uint256 private _messageCounter;

    mapping(bytes32 => PendingMessage) public messages;
    mapping(uint64 => uint64) public sourceChainSelectors;
    mapping(uint64 => bool) public supportedChains;

    event MessageSent(bytes32 indexed messageId, uint64 destChainSelector, address receiver);
    event MessageDelivered(bytes32 indexed messageId, address receiver);

    function setSourceChainSelector(uint64 destChainSelector, uint64 sourceChainSelector) external {
        sourceChainSelectors[destChainSelector] = sourceChainSelector;
        supportedChains[destChainSelector] = true;
    }

    function isChainSupported(uint64 destChainSelector) external view returns (bool) {
        return supportedChains[destChainSelector];
    }

    function getFee(uint64, Client.EVM2AnyMessage memory) external pure returns (uint256) {
        return FEE;
    }

    function ccipSend(uint64 destinationChainSelector, Client.EVM2AnyMessage calldata message)
        external
        payable
        returns (bytes32 messageId)
    {
        if (!supportedChains[destinationChainSelector]) {
            revert UnsupportedDestinationChain(destinationChainSelector);
        }
        if (msg.value < FEE) revert InsufficientFeeTokenAmount();
        if (message.feeToken != address(0)) revert InvalidMsgValue();

        address receiver = abi.decode(message.receiver, (address));
        messageId =
            keccak256(abi.encodePacked(++_messageCounter, block.timestamp, msg.sender, receiver, message.data));

        messages[messageId] = PendingMessage({
            destChainSelector: destinationChainSelector,
            receiver: receiver,
            data: message.data,
            sender: msg.sender
        });

        emit MessageSent(messageId, destinationChainSelector, receiver);
        _deliver(messageId);
    }

    function deliverMessage(bytes32 messageId) external {
        _deliver(messageId);
    }

    function _deliver(bytes32 messageId) internal {
        PendingMessage memory pending = messages[messageId];
        require(pending.receiver != address(0), "MockCCIPRouter: missing receiver");

        Client.Any2EVMMessage memory message = Client.Any2EVMMessage({
            messageId: messageId,
            sourceChainSelector: sourceChainSelectors[pending.destChainSelector],
            sender: abi.encode(pending.sender),
            data: pending.data,
            destTokenAmounts: new Client.EVMTokenAmount[](0)
        });

        IAny2EVMMessageReceiver(pending.receiver).ccipReceive(message);
        emit MessageDelivered(messageId, pending.receiver);
    }
}
