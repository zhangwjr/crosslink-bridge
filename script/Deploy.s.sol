// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";

import {Bridge} from "../src/Bridge.sol";
import {Token} from "../src/Token.sol";
import {WrappedToken} from "../src/WrappedToken.sol";

/// @title Deploy
/// @notice Deploy source or destination bridge stack
/// @dev Usage (keystore signing):
///   SOURCE:  BRIDGE_MODE=source forge script script/Deploy.s.sol:Deploy --rpc-url $SEPOLIA_RPC_URL --account deployer_1 --sender $DEPLOYER_ADDRESS --broadcast
///   DEST:    BRIDGE_MODE=dest   forge script script/Deploy.s.sol:Deploy --rpc-url $BSC_TESTNET_RPC_URL --account deployer_1 --sender $DEPLOYER_ADDRESS --broadcast
contract Deploy is Script {
    /// @dev Official Chainlink CCIP chain selectors (not EVM chainIds)
    uint64 internal constant SEPOLIA_SELECTOR = 16015286601757825753;
    uint64 internal constant BSC_TESTNET_SELECTOR = 13264668187771770619;

    function run() external {
        string memory mode = vm.envOr("BRIDGE_MODE", string("source"));
        address router = vm.envAddress("CCIP_ROUTER");

        // Uses the CLI signer (--account / --private-key / hardware wallet)
        vm.startBroadcast();
        address deployer = msg.sender;

        if (_eq(mode, "source")) {
            _deploySource(deployer, router);
        } else if (_eq(mode, "dest")) {
            _deployDestination(deployer, router);
        } else {
            revert("Deploy: BRIDGE_MODE must be 'source' or 'dest'");
        }

        vm.stopBroadcast();
    }

    function _deploySource(address deployer, address router) internal {
        Token token = new Token("CrossLink Token", "CLT", deployer);
        Bridge bridge = new Bridge(Bridge.BridgeMode.SOURCE, router, SEPOLIA_SELECTOR, deployer);

        bridge.setNativeToken(address(token));

        console2.log("Source Token:", address(token));
        console2.log("Source Bridge:", address(bridge));
        console2.log("CCIP Chain Selector:", SEPOLIA_SELECTOR);
    }

    function _deployDestination(address deployer, address router) internal {
        WrappedToken wrapped = new WrappedToken("Wrapped CrossLink Token", "wCLT", deployer);
        Bridge bridge = new Bridge(Bridge.BridgeMode.DESTINATION, router, BSC_TESTNET_SELECTOR, deployer);

        bridge.setWrappedToken(address(wrapped));
        wrapped.setBridge(address(bridge));

        console2.log("Wrapped Token:", address(wrapped));
        console2.log("Destination Bridge:", address(bridge));
        console2.log("CCIP Chain Selector:", BSC_TESTNET_SELECTOR);
    }

    function _eq(string memory a, string memory b) private pure returns (bool) {
        return keccak256(bytes(a)) == keccak256(bytes(b));
    }
}
