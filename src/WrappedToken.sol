// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title WrappedToken
/// @notice Destination-chain wrapped ERC-20, mint/burn restricted to the bridge
contract WrappedToken is ERC20, Ownable {
    address public bridge;

    error OnlyBridge();

    event BridgeUpdated(address indexed bridge);

    constructor(string memory name, string memory symbol, address initialOwner)
        ERC20(name, symbol)
        Ownable(initialOwner)
    {}

    function setBridge(address bridge_) external onlyOwner {
        bridge = bridge_;
        emit BridgeUpdated(bridge_);
    }

    function mint(address to, uint256 amount) external {
        if (msg.sender != bridge) revert OnlyBridge();
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external {
        if (msg.sender != bridge) revert OnlyBridge();
        _burn(from, amount);
    }
}
