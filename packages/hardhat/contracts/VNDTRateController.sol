// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";

interface IVNDTEngine {
    function setBorrowRate(uint256 newRate) external;
}

interface IVNDTStaking {
    function setStakingRate(uint256 newRate) external;
}

/// @title VNĐ Rate Controller Contract
/// @notice Manages interest rates for minting/burning to maintain peg
contract VNDTRateController is Ownable {
    IVNDTEngine public engine;
    IVNDTStaking public staking;
    
    uint256 public borrowRate; // Annual interest rate for borrowers
    uint256 public stakingRate; // Annual interest rate for stakers

    event BorrowRateUpdated(uint256 newRate);
    event StakingRateUpdated(uint256 newRate);

    constructor(address _engine, address _staking) Ownable(msg.sender) {
        engine = IVNDTEngine(_engine);
        staking = IVNDTStaking(_staking);
        borrowRate = 500; // 5% default
        stakingRate = 300; // 3% default
    }

    /// @notice Update borrow rate to incentivize minting/burning
    function updateBorrowRate(uint256 newRate) external onlyOwner {
        borrowRate = newRate;
        engine.setBorrowRate(newRate);
        emit BorrowRateUpdated(newRate);
    }

    /// @notice Update staking rate to incentivize staking
    function updateStakingRate(uint256 newRate) external onlyOwner {
        stakingRate = newRate;
        staking.setStakingRate(newRate);
        emit StakingRateUpdated(newRate);
    }
}
