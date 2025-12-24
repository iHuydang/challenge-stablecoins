// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

/// @title VNĐ Oracle Contract
/// @notice Provides ETH/VND price feed for the stablecoin system
contract VNDTOracle {
    uint256 public ethPrice; // ETH price in VND with 18 decimals

    constructor(uint256 _ethPrice) {
        ethPrice = _ethPrice;
    }

    /// @notice Get current ETH price in VND
    function getEthPrice() public view returns (uint256) {
        return ethPrice;
    }

    /// @notice Update ETH price (simplified for testing)
    function setEthPrice(uint256 _newPrice) external {
        ethPrice = _newPrice;
    }
}
