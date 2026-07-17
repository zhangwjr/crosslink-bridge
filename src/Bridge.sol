// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import {IAny2EVMMessageReceiver} from "./vendor/ccip/IAny2EVMMessageReceiver.sol";
import {IRouterClient} from "./vendor/ccip/IRouterClient.sol";
import {Client} from "./vendor/ccip/Client.sol";
import {BridgeMessage} from "./libraries/BridgeMessage.sol";
import {RateLimiter} from "./RateLimiter.sol";
import {WrappedToken} from "./WrappedToken.sol";

/// @title Bridge
/// @notice Lock-Mint / Burn-Release cross-chain bridge for EVM chains via Chainlink CCIP
contract Bridge is IAny2EVMMessageReceiver, IERC165, Ownable, Pausable, ReentrancyGuard, RateLimiter {
    using SafeERC20 for IERC20;

    enum BridgeMode {
        SOURCE, // lock native tokens, release on burn message
        DESTINATION // mint wrapped tokens, burn on reverse bridge
    }

    /// @dev Destination execution gas for mint/release handlers
    uint256 public constant CCIP_GAS_LIMIT = 200_000;

    BridgeMode public immutable mode;
    IRouterClient public router;
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
    error InvalidRemoteSender();
    error InsufficientFee(uint256 required, uint256 provided);
    error FeeRefundFailed();

    modifier onlyRouter() {
        if (msg.sender != address(router)) revert NotRouter();
        _;
    }

    constructor(BridgeMode bridgeMode, address router_, uint64 chainSelector_, address initialOwner)
        Ownable(initialOwner)
    {
        if (router_ == address(0)) revert ZeroAddress();
        mode = bridgeMode;
        router = IRouterClient(router_);
        chainSelector = chainSelector_;
    }

    /// @notice Allow Bridge to receive native fee refunds / top-ups
    receive() external payable {}

    function supportsInterface(bytes4 interfaceId) public pure override returns (bool) {
        return interfaceId == type(IAny2EVMMessageReceiver).interfaceId || interfaceId == type(IERC165).interfaceId;
    }

    function setRouter(address router_) external onlyOwner {
        if (router_ == address(0)) revert ZeroAddress();
        router = IRouterClient(router_);
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

    /// @notice Quote native fee required to send a bridge message via CCIP
    function getFee(uint256 amount, uint64 destChainSelector, address recipient) external view returns (uint256) {
        if (amount == 0) revert ZeroAmount();
        if (recipient == address(0)) revert ZeroAddress();

        address remoteBridge = remoteBridges[destChainSelector];
        if (remoteBridge == address(0)) revert UnsupportedChain();

        bytes memory data = mode == BridgeMode.SOURCE
            ? BridgeMessage.encodeMintRequest(recipient, amount)
            : BridgeMessage.encodeReleaseRequest(recipient, amount);

        return router.getFee(destChainSelector, _buildMessage(remoteBridge, data));
    }

    /// @notice Lock native tokens on the source chain and request mint on destination
    function lock(uint256 amount, uint64 destChainSelector, address recipient)
        external
        payable
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
        messageId = _ccipSend(destChainSelector, remoteBridge, data);

        emit TokensLocked(msg.sender, amount, destChainSelector, recipient, messageId);
    }

    /// @notice Burn wrapped tokens on the destination chain and request release on source
    function burn(uint256 amount, uint64 destChainSelector, address recipient)
        external
        payable
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
        messageId = _ccipSend(destChainSelector, remoteBridge, data);

        emit TokensBurned(msg.sender, amount, destChainSelector, recipient, messageId);
    }

    /// @inheritdoc IAny2EVMMessageReceiver
    function ccipReceive(Client.Any2EVMMessage calldata message) external override onlyRouter nonReentrant {
        if (processedMessages[message.messageId]) revert MessageAlreadyProcessed();
        processedMessages[message.messageId] = true;

        address expectedSender = remoteBridges[message.sourceChainSelector];
        if (expectedSender == address(0)) revert UnsupportedChain();

        address actualSender = abi.decode(message.sender, (address));
        if (actualSender != expectedSender) revert InvalidRemoteSender();

        (BridgeMessage.Action action, address recipient, uint256 amount) = BridgeMessage.decode(message.data);

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

    function _ccipSend(uint64 destChainSelector, address remoteBridge, bytes memory data)
        internal
        returns (bytes32 messageId)
    {
        Client.EVM2AnyMessage memory message = _buildMessage(remoteBridge, data);
        uint256 fee = router.getFee(destChainSelector, message);
        if (msg.value < fee) revert InsufficientFee(fee, msg.value);

        messageId = router.ccipSend{value: fee}(destChainSelector, message);

        if (msg.value > fee) {
            (bool ok,) = msg.sender.call{value: msg.value - fee}("");
            if (!ok) revert FeeRefundFailed();
        }
    }

    function _buildMessage(address remoteBridge, bytes memory data)
        internal
        pure
        returns (Client.EVM2AnyMessage memory)
    {
        return Client.EVM2AnyMessage({
            receiver: abi.encode(remoteBridge),
            data: data,
            tokenAmounts: new Client.EVMTokenAmount[](0),
            feeToken: address(0), // pay in native gas token
            extraArgs: Client._argsToBytes(
                Client.GenericExtraArgsV2({gasLimit: CCIP_GAS_LIMIT, allowOutOfOrderExecution: true})
            )
        });
    }
}
