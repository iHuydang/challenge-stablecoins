// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "./VNDT.sol";

error DEX__InvalidAmount();
error DEX__TransferFailed();

/// @title VNĐ DEX Contract
/// @notice Simple AMM for swapping ETH ↔ VNDT tokens
contract VNDTDEX {
    VNDT private i_vndt;
    
    uint256 public ethReserve;
    uint256 public vndtReserve;
    
    event SwapETHForVNDT(address indexed user, uint256 ethAmount, uint256 vndtAmount);
    event SwapVNDTForETH(address indexed user, uint256 vndtAmount, uint256 ethAmount);
    event LiquidityAdded(address indexed user, uint256 ethAmount, uint256 vndtAmount);

    constructor(address _vndtAddress) {
        i_vndt = VNDT(_vndtAddress);
    }

    /// @notice Swap ETH for VNDT tokens
    function swapETHForVNDT(uint256 minVndtOut) external payable returns (uint256) {
        if (msg.value == 0) revert DEX__InvalidAmount();
        if (ethReserve == 0 || vndtReserve == 0) revert DEX__InvalidAmount();

        uint256 ethAmountIn = msg.value;
        uint256 vndtAmountOut = getOutputAmount(ethAmountIn, ethReserve, vndtReserve);
        
        if (vndtAmountOut < minVndtOut) revert DEX__InvalidAmount();

        ethReserve += ethAmountIn;
        vndtReserve -= vndtAmountOut;

        bool success = i_vndt.transfer(msg.sender, vndtAmountOut);
        if (!success) revert DEX__TransferFailed();

        emit SwapETHForVNDT(msg.sender, ethAmountIn, vndtAmountOut);
        return vndtAmountOut;
    }

    /// @notice Swap VNDT for ETH tokens
    function swapVNDTForETH(uint256 vndtAmountIn, uint256 minEthOut) external returns (uint256) {
        if (vndtAmountIn == 0) revert DEX__InvalidAmount();
        if (ethReserve == 0 || vndtReserve == 0) revert DEX__InvalidAmount();

        uint256 ethAmountOut = getOutputAmount(vndtAmountIn, vndtReserve, ethReserve);
        
        if (ethAmountOut < minEthOut) revert DEX__InvalidAmount();

        vndtReserve += vndtAmountIn;
        ethReserve -= ethAmountOut;

        bool success = i_vndt.transferFrom(msg.sender, address(this), vndtAmountIn);
        if (!success) revert DEX__TransferFailed();

        (success, ) = payable(msg.sender).call{value: ethAmountOut}("");
        if (!success) revert DEX__TransferFailed();

        emit SwapVNDTForETH(msg.sender, vndtAmountIn, ethAmountOut);
        return ethAmountOut;
    }

    /// @notice Add liquidity to the DEX
    function addLiquidity(uint256 vndtAmount) external payable {
        if (msg.value == 0 || vndtAmount == 0) revert DEX__InvalidAmount();

        ethReserve += msg.value;
        vndtReserve += vndtAmount;

        bool success = i_vndt.transferFrom(msg.sender, address(this), vndtAmount);
        if (!success) revert DEX__TransferFailed();

        emit LiquidityAdded(msg.sender, msg.value, vndtAmount);
    }

    /// @notice Calculate output amount using constant product formula
    function getOutputAmount(
        uint256 inputAmount,
        uint256 inputReserve,
        uint256 outputReserve
    ) public pure returns (uint256) {
        if (inputAmount == 0 || inputReserve == 0 || outputReserve == 0) {
            return 0;
        }
        
        uint256 inputWithFee = inputAmount * 997; // 0.3% fee
        uint256 numerator = inputWithFee * outputReserve;
        uint256 denominator = (inputReserve * 1000) + inputWithFee;
        
        return numerator / denominator;
    }

    /// @notice Get current price of VNDT in ETH
    function getVndtPrice() external view returns (uint256) {
        if (vndtReserve == 0) return 0;
        return (ethReserve * 1e18) / vndtReserve;
    }
}
