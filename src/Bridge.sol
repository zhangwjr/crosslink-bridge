// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {ICCIPRouter} from "./interfaces/ICCIPRouter.sol";
import {ICCIPReceiver} from "./interfaces/ICCIPReceiver.sol";
import {BridgeMessage} from "./libraries/BridgeMessage.sol";
import {RateLimiter} from "./RateLimiter.sol";
import {WrappedToken} from "./WrappedToken.sol";

/// @title Bridge
/// @notice Lock-Mint / Burn-Release cross-chain bridge for EVM chains
/// @dev Uses a CCIP-compatible router interface; swap MockCCIPRouter for Chainlink CCIP on testnet
contract Bridge is ICCIPReceiver, Ownable, Pausable, ReentrancyGuard, RateLimiter {
    using SafeERC20 for IERC20;

    enum BridgeMode {
        SOURCE, // lock native tokens, release on burn message
        DESTINATION // mint wrapped tokens, burn on reverse bridge
    }

    BridgeMode public immutable mode;
    ICCIPRouter public router;
    IERC20 public nativeToken;
    WrappedToken public wrappedToken;
    uint64 public chainSelector;

    mapping(uint64 => address) public remoteBridges;
    mapping(bytes32 => bool) public processedMessages;

    event RouterUpdated(address indexed router);
    event NativeTokenUpdated(address indexed token);
    event WrappedTokenUpdated(address indexed token);
    event RemoteBridgeUpdated(uint64 indexed chainSelector, address indexed bridge);
    event TokensLocked(
        address indexed user, uint256 amount, uint64 destChainSelector, address recipient, bytes32 messageId
    );
    event TokensBurned(
        address indexed user, uint256 amount, uint64 destChainSelector, address recipient, bytes32 messageId
    );
    event TokensReleased(address indexed recipient, uint256 amount, bytes32 messageId);
    event TokensMinted(address indexed recipient, uint256 amount, bytes32 messageId);

    error NotRouter();
    error NotSourceBridge();
    error NotDestinationBridge();
    error ZeroAmount();
    error ZeroAddress();
    error UnsupportedChain();
    error MessageAlreadyProcessed();
    error UnknownAction();

    modifier onlyRouter() {
        if (msg.sender != address(router)) revert NotRouter();
        _;
    }

    constructor(BridgeMode bridgeMode, address router_, uint64 chainSelector_, address initialOwner)
        Ownable(initialOwner)
    {
        mode = bridgeMode;
        router = ICCIPRouter(router_);
        chainSelector = chainSelector_;
    }

    function setRouter(address router_) external onlyOwner {
        router = ICCIPRouter(router_);
        emit RouterUpdated(router_);
    }

    function setNativeToken(address token) external onlyOwner {
        if (mode != BridgeMode.SOURCE) revert NotSourceBridge();
        nativeToken = IERC20(token);
        emit NativeTokenUpdated(token);
    }

    function setWrappedToken(address token) external onlyOwner {
        wrappedToken = WrappedToken(token);
        emit WrappedTokenUpdated(token);
    }

    function setRemoteBridge(uint64 destChainSelector, address bridge) external onlyOwner {
        if (bridge == address(0)) revert ZeroAddress();
        remoteBridges[destChainSelector] = bridge;
        emit RemoteBridgeUpdated(destChainSelector, bridge);
    }

    /// @notice Lock native tokens on the source chain and request mint on destination
    function lock(uint256 amount, uint64 destChainSelector, address recipient)
        external
        nonReentrant
        whenNotPaused
        returns (bytes32 messageId)
    {
        if (mode != BridgeMode.SOURCE) revert NotSourceBridge();
        if (amount == 0) revert ZeroAmount();
        if (recipient == address(0)) revert ZeroAddress();

        address remoteBridge = remoteBridges[destChainSelector];
        if (remoteBridge == address(0)) revert UnsupportedChain();

        _checkRateLimit(msg.sender, amount);
        nativeToken.safeTransferFrom(msg.sender, address(this), amount);

        bytes memory data = BridgeMessage.encodeMintRequest(recipient, amount);
        messageId = router.ccipSend(destChainSelector, remoteBridge, data);

        emit TokensLocked(msg.sender, amount, destChainSelector, recipient, messageId);
    }

    /// @notice Burn wrapped tokens on the destination chain and request release on source
    function burn(uint256 amount, uint64 destChainSelector, address recipient)
        external
        nonReentrant
        whenNotPaused
        returns (bytes32 messageId)
    {
        if (mode != BridgeMode.DESTINATION) revert NotDestinationBridge();
        if (amount == 0) revert ZeroAmount();
        if (recipient == address(0)) revert ZeroAddress();

        address remoteBridge = remoteBridges[destChainSelector];
        if (remoteBridge == address(0)) revert UnsupportedChain();

        _checkRateLimit(msg.sender, amount);
        wrappedToken.burn(msg.sender, amount);

        bytes memory data = BridgeMessage.encodeReleaseRequest(recipient, amount);
        messageId = router.ccipSend(destChainSelector, remoteBridge, data);

        emit TokensBurned(msg.sender, amount, destChainSelector, recipient, messageId);
    }

    /// @inheritdoc ICCIPReceiver
    function ccipReceive(Any2EVMMessage calldata message) external onlyRouter nonReentrant {
        if (processedMessages[message.messageId]) revert MessageAlreadyProcessed();
        processedMessages[message.messageId] = true;

        (BridgeMessage.Action action, address recipient, uint256 amount) =
            BridgeMessage.decode(message.data);

        if (action == BridgeMessage.Action.MINT) {
            if (mode != BridgeMode.DESTINATION) revert NotDestinationBridge();
            wrappedToken.mint(recipient, amount);
            emit TokensMinted(recipient, amount, message.messageId);
            return;
        }

        if (action == BridgeMessage.Action.RELEASE) {
            if (mode != BridgeMode.SOURCE) revert NotSourceBridge();
            nativeToken.safeTransfer(recipient, amount);
            emit TokensReleased(recipient, amount, message.messageId);
            return;
        }

        revert UnknownAction();
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }
}
