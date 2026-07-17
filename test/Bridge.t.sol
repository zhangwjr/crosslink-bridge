// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

import {Bridge} from "../src/Bridge.sol";
import {Token} from "../src/Token.sol";
import {WrappedToken} from "../src/WrappedToken.sol";
import {MockCCIPRouter} from "../src/mocks/MockCCIPRouter.sol";
import {Client} from "../src/vendor/ccip/Client.sol";
import {BridgeMessage} from "../src/libraries/BridgeMessage.sol";

contract BridgeTest is Test {
    /// @dev Official Chainlink CCIP selectors
    uint64 internal constant SEPOLIA_SELECTOR = 16015286601757825753;
    uint64 internal constant BSC_SELECTOR = 13264668187771770619;

    MockCCIPRouter internal router;
    Token internal nativeToken;
    WrappedToken internal wrappedToken;
    Bridge internal sourceBridge;
    Bridge internal destBridge;

    address internal owner = makeAddr("owner");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    uint256 internal constant INITIAL_BALANCE = 10_000 ether;
    uint256 internal constant BRIDGE_AMOUNT = 1_000 ether;
    uint256 internal fee;

    function setUp() public {
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);

        vm.startPrank(owner);

        router = new MockCCIPRouter();
        fee = router.FEE();
        nativeToken = new Token("CrossLink Token", "CLT", owner);
        wrappedToken = new WrappedToken("Wrapped CrossLink Token", "wCLT", owner);

        sourceBridge = new Bridge(Bridge.BridgeMode.SOURCE, address(router), SEPOLIA_SELECTOR, owner);
        destBridge = new Bridge(Bridge.BridgeMode.DESTINATION, address(router), BSC_SELECTOR, owner);

        sourceBridge.setNativeToken(address(nativeToken));
        destBridge.setWrappedToken(address(wrappedToken));
        wrappedToken.setBridge(address(destBridge));

        sourceBridge.setRemoteBridge(BSC_SELECTOR, address(destBridge));
        destBridge.setRemoteBridge(SEPOLIA_SELECTOR, address(sourceBridge));

        router.setSourceChainSelector(BSC_SELECTOR, SEPOLIA_SELECTOR);
        router.setSourceChainSelector(SEPOLIA_SELECTOR, BSC_SELECTOR);

        nativeToken.mint(alice, INITIAL_BALANCE);
        nativeToken.mint(bob, INITIAL_BALANCE);

        vm.stopPrank();
    }

    function test_lock_mints_wrapped_on_destination() public {
        vm.startPrank(alice);
        nativeToken.approve(address(sourceBridge), BRIDGE_AMOUNT);
        sourceBridge.lock{value: fee}(BRIDGE_AMOUNT, BSC_SELECTOR, alice);
        vm.stopPrank();

        assertEq(nativeToken.balanceOf(address(sourceBridge)), BRIDGE_AMOUNT);
        assertEq(wrappedToken.balanceOf(alice), BRIDGE_AMOUNT);
        assertEq(nativeToken.balanceOf(alice), INITIAL_BALANCE - BRIDGE_AMOUNT);
    }

    function test_burn_releases_native_on_source() public {
        _bridgeToDestination(alice, BRIDGE_AMOUNT);

        vm.prank(alice);
        destBridge.burn{value: fee}(BRIDGE_AMOUNT, SEPOLIA_SELECTOR, alice);

        assertEq(nativeToken.balanceOf(alice), INITIAL_BALANCE);
        assertEq(wrappedToken.balanceOf(alice), 0);
        assertEq(nativeToken.balanceOf(address(sourceBridge)), 0);
    }

    function test_rejects_replayed_message() public {
        vm.startPrank(alice);
        nativeToken.approve(address(sourceBridge), BRIDGE_AMOUNT);
        bytes32 messageId = sourceBridge.lock{value: fee}(BRIDGE_AMOUNT, BSC_SELECTOR, alice);
        vm.stopPrank();

        Client.Any2EVMMessage memory replay = Client.Any2EVMMessage({
            messageId: messageId,
            sourceChainSelector: SEPOLIA_SELECTOR,
            sender: abi.encode(address(sourceBridge)),
            data: BridgeMessage.encodeMintRequest(alice, BRIDGE_AMOUNT),
            destTokenAmounts: new Client.EVMTokenAmount[](0)
        });

        vm.prank(address(router));
        vm.expectRevert(Bridge.MessageAlreadyProcessed.selector);
        destBridge.ccipReceive(replay);
    }

    function test_rejects_non_router_caller() public {
        Client.Any2EVMMessage memory message = Client.Any2EVMMessage({
            messageId: keccak256("fake"),
            sourceChainSelector: SEPOLIA_SELECTOR,
            sender: abi.encode(address(sourceBridge)),
            data: BridgeMessage.encodeMintRequest(alice, BRIDGE_AMOUNT),
            destTokenAmounts: new Client.EVMTokenAmount[](0)
        });

        vm.prank(alice);
        vm.expectRevert(Bridge.NotRouter.selector);
        destBridge.ccipReceive(message);
    }

    function test_rejects_invalid_remote_sender() public {
        Client.Any2EVMMessage memory message = Client.Any2EVMMessage({
            messageId: keccak256("spoof"),
            sourceChainSelector: SEPOLIA_SELECTOR,
            sender: abi.encode(alice),
            data: BridgeMessage.encodeMintRequest(alice, BRIDGE_AMOUNT),
            destTokenAmounts: new Client.EVMTokenAmount[](0)
        });

        vm.prank(address(router));
        vm.expectRevert(Bridge.InvalidRemoteSender.selector);
        destBridge.ccipReceive(message);
    }

    function test_rejects_insufficient_fee() public {
        vm.startPrank(alice);
        nativeToken.approve(address(sourceBridge), BRIDGE_AMOUNT);
        vm.expectRevert(abi.encodeWithSelector(Bridge.InsufficientFee.selector, fee, uint256(0)));
        sourceBridge.lock(BRIDGE_AMOUNT, BSC_SELECTOR, alice);
        vm.stopPrank();
    }

    function test_getFee_matches_router() public view {
        uint256 quoted = sourceBridge.getFee(BRIDGE_AMOUNT, BSC_SELECTOR, alice);
        assertEq(quoted, fee);
    }

    function test_pause_blocks_lock() public {
        vm.prank(owner);
        sourceBridge.pause();

        vm.startPrank(alice);
        nativeToken.approve(address(sourceBridge), BRIDGE_AMOUNT);
        vm.expectRevert();
        sourceBridge.lock{value: fee}(BRIDGE_AMOUNT, BSC_SELECTOR, alice);
        vm.stopPrank();
    }

    function test_rate_limit_blocks_excess_transfer() public {
        vm.prank(owner);
        sourceBridge.setUserDailyLimit(100 ether);

        vm.startPrank(alice);
        nativeToken.approve(address(sourceBridge), BRIDGE_AMOUNT);
        vm.expectRevert();
        sourceBridge.lock{value: fee}(BRIDGE_AMOUNT, BSC_SELECTOR, alice);
        vm.stopPrank();
    }

    function test_bidirectional_flow_for_two_users() public {
        _bridgeToDestination(alice, 500 ether);
        _bridgeToDestination(bob, 300 ether);

        assertEq(wrappedToken.balanceOf(alice), 500 ether);
        assertEq(wrappedToken.balanceOf(bob), 300 ether);

        vm.prank(alice);
        destBridge.burn{value: fee}(200 ether, SEPOLIA_SELECTOR, alice);

        vm.prank(bob);
        destBridge.burn{value: fee}(300 ether, SEPOLIA_SELECTOR, bob);

        assertEq(nativeToken.balanceOf(alice), INITIAL_BALANCE - 500 ether + 200 ether);
        assertEq(nativeToken.balanceOf(bob), INITIAL_BALANCE);
        assertEq(wrappedToken.balanceOf(alice), 300 ether);
        assertEq(wrappedToken.balanceOf(bob), 0);
    }

    function test_source_bridge_rejects_burn() public {
        vm.prank(alice);
        vm.expectRevert(Bridge.NotDestinationBridge.selector);
        sourceBridge.burn{value: fee}(BRIDGE_AMOUNT, BSC_SELECTOR, alice);
    }

    function test_destination_bridge_rejects_lock() public {
        vm.prank(alice);
        vm.expectRevert(Bridge.NotSourceBridge.selector);
        destBridge.lock{value: fee}(BRIDGE_AMOUNT, SEPOLIA_SELECTOR, alice);
    }

    function _bridgeToDestination(address user, uint256 amount) internal {
        vm.startPrank(user);
        nativeToken.approve(address(sourceBridge), amount);
        sourceBridge.lock{value: fee}(amount, BSC_SELECTOR, user);
        vm.stopPrank();
    }
}
