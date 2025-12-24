// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

import "./VNDTStaking.sol";

error VNDT__InvalidAmount();
error VNDT__InsufficientBalance();
error VNDT__InsufficientAllowance();
error VNDT__InvalidAddress();
error VNDT__NotAuthorized();

/// @title VNĐ₮ Token Contract
/// @notice ERC20 stablecoin pegged to Vietnamese Dong
/// @dev Minting and burning are controlled exclusively by VNĐEngine
contract VNDT is ERC20, ERC20Burnable, Ownable {
    address public stakingContract;
    address public engineContract;

    constructor(address _engineContract, address _stakingContract) 
        ERC20("VND Coin", "VNDT") 
        Ownable(msg.sender) 
    {
        engineContract = _engineContract;
        stakingContract = _stakingContract;
    }

    /// @notice Burn tokens from account (only engine can call)
    /// @param account Address to burn from
    /// @param amount Amount to burn
    function burnFrom(address account, uint256 amount) public override {
        if (msg.sender != engineContract) revert VNDT__NotAuthorized();
        return super.burnFrom(account, amount);
    }

    /// @notice Mint tokens to address (only engine can call)
    /// @param to Recipient address
    /// @param amount Amount to mint
    /// @return bool True if successful
    function mintTo(address to, uint256 amount) external returns (bool) {
        if (msg.sender != engineContract) revert VNDT__NotAuthorized();
        if (to == address(0)) revert VNDT__InvalidAddress();
        if (amount == 0) revert VNDT__InvalidAmount();
        
        _mint(to, amount);
        return true;
    }

    /// @notice Override balanceOf to handle virtual balances for staking
    function balanceOf(address account) public view override returns (uint256) {
        if (account != stakingContract) {
            return super.balanceOf(account);
        }
        VNDTStaking staking = VNDTStaking(stakingContract);
        return staking.getSharesValue(staking.totalShares());
    }

    /// @notice Override _update to handle virtual balances for staking
    function _update(address from, address to, uint256 value) internal override {
        if (from == stakingContract) {
            super._mint(to, value);
        } else if (to == stakingContract) {
            super._burn(from, value);
        } else {
            super._update(from, to, value);
        }
    }

    /// @notice Override totalSupply to handle virtual balances for staking
    function totalSupply() public view override returns (uint256) {
        uint256 baseSupply = super.totalSupply();
        if (stakingContract == address(0)) return baseSupply;
        
        VNDTStaking staking = VNDTStaking(stakingContract);
        uint256 stakingBalance = staking.getSharesValue(staking.totalShares());
        uint256 actualStakingBalance = super.balanceOf(stakingContract);
        
        return baseSupply - actualStakingBalance + stakingBalance;
    }
}
