// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title RateLimiter
/// @notice Global and per-user daily transfer limits to reduce blast radius of exploits
abstract contract RateLimiter is Ownable {
    uint256 public dailyLimit = type(uint256).max;
    uint256 public userDailyLimit = type(uint256).max;

    uint256 private _dailyUsed;
    uint256 private _lastResetDay;

    mapping(address => uint256) private _userDailyUsed;
    mapping(address => uint256) private _userLastResetDay;

    event DailyLimitUpdated(uint256 newLimit);
    event UserDailyLimitUpdated(uint256 newLimit);

    error DailyLimitExceeded();
    error UserDailyLimitExceeded();

    function setDailyLimit(uint256 limit) external onlyOwner {
        dailyLimit = limit;
        emit DailyLimitUpdated(limit);
    }

    function setUserDailyLimit(uint256 limit) external onlyOwner {
        userDailyLimit = limit;
        emit UserDailyLimitUpdated(limit);
    }

    function dailyUsed() external view returns (uint256) {
        return _dailyUsed;
    }

    function userDailyUsed(address user) external view returns (uint256) {
        return _userDailyUsed[user];
    }

    function _checkRateLimit(address user, uint256 amount) internal {
        _resetDailyIfNeeded();
        _resetUserDailyIfNeeded(user);

        if (_dailyUsed + amount > dailyLimit) revert DailyLimitExceeded();
        if (_userDailyUsed[user] + amount > userDailyLimit) revert UserDailyLimitExceeded();

        _dailyUsed += amount;
        _userDailyUsed[user] += amount;
    }

    function _resetDailyIfNeeded() private {
        uint256 today = block.timestamp / 1 days;
        if (today > _lastResetDay) {
            _dailyUsed = 0;
            _lastResetDay = today;
        }
    }

    function _resetUserDailyIfNeeded(address user) private {
        uint256 today = block.timestamp / 1 days;
        if (today > _userLastResetDay[user]) {
            _userDailyUsed[user] = 0;
            _userLastResetDay[user] = today;
        }
    }
}
