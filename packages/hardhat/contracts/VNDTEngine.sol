// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./VNDT.sol";
import "./VNDTOracle.sol";
import "./VNDTStaking.sol";

error Engine__InvalidAmount();
error Engine__UnsafePositionRatio();
error Engine__NotLiquidatable();
error Engine__NotRateController();
error Engine__InsufficientCollateral();
error Engine__TransferFailed();

/// @title VNĐ Engine Contract
/// @notice Core engine managing collateral, minting, burning, and liquidation
/// @dev Manages ETH collateral with 150% collateralization ratio
contract VNDTEngine is Ownable {
    // Constants: 1000 VND = 10,000 VNDT tokens (1 VNDT = 0.1 VND)
    uint256 private constant COLLATERAL_RATIO = 150; // 150% collateralization required
    uint256 private constant LIQUIDATOR_REWARD = 10; // 10% reward for liquidators
    uint256 private constant SECONDS_PER_YEAR = 365 days;
    uint256 private constant PRECISION = 1e18;

    VNDT private i_vndt;
    VNDTOracle private i_oracle;
    VNDTStaking private i_staking;
    address private i_rateController;

    uint256 public borrowRate; // Annual interest rate for borrowers in basis points
    uint256 public totalDebtShares;
    uint256 public debtExchangeRate;
    uint256 public lastUpdateTime;

    mapping(address => uint256) public s_userCollateral;
    mapping(address => uint256) public s_userDebtShares;

    event CollateralAdded(address indexed user, uint256 indexed amount, uint256 price);
    event CollateralWithdrawn(address indexed withdrawer, uint256 indexed amount, uint256 price);
    event BorrowRateUpdated(uint256 newRate);
    event DebtSharesMinted(address indexed user, uint256 amount, uint256 shares);
    event DebtSharesBurned(address indexed user, uint256 amount, uint256 shares);
    event Liquidation(
        address indexed user,
        address indexed liquidator,
        uint256 amountForLiquidator,
        uint256 liquidatedUserDebt,
        uint256 price
    );

    modifier onlyRateController() {
        if (msg.sender != i_rateController) revert Engine__NotRateController();
        _;
    }

    constructor(
        address _oracle,
        address _vndtAddress,
        address _stakingAddress,
        address _rateController
    ) Ownable(msg.sender) {
        i_oracle = VNDTOracle(_oracle);
        i_vndt = VNDT(_vndtAddress);
        i_staking = VNDTStaking(_stakingAddress);
        i_rateController = _rateController;
        lastUpdateTime = block.timestamp;
        debtExchangeRate = PRECISION;
    }

    /// @notice Deposit ETH as collateral
    function addCollateral() public payable {
        if (msg.value == 0) revert Engine__InvalidAmount();
        
        _accrueInterest();
        s_userCollateral[msg.sender] += msg.value;
        
        uint256 ethPrice = i_oracle.getEthPrice();
        emit CollateralAdded(msg.sender, msg.value, ethPrice);
    }

    /// @notice Get collateral value in VNDT for a user
    function calculateCollateralValue(address user) public view returns (uint256) {
        uint256 collateral = s_userCollateral[user];
        uint256 ethPrice = i_oracle.getEthPrice();
        return (collateral * ethPrice) / PRECISION;
    }

    /// @notice Get current debt exchange rate with accrued interest
    function _getCurrentExchangeRate() internal view returns (uint256) {
        if (totalDebtShares == 0) return debtExchangeRate;

        uint256 timeElapsed = block.timestamp - lastUpdateTime;
        if (timeElapsed == 0 || borrowRate == 0) return debtExchangeRate;

        uint256 totalDebtValue = (totalDebtShares * debtExchangeRate) / PRECISION;
        uint256 interest = (totalDebtValue * borrowRate * timeElapsed) / (SECONDS_PER_YEAR * 10000);

        return debtExchangeRate + (interest * PRECISION) / totalDebtShares;
    }

    /// @notice Accrue interest on outstanding debt
    function _accrueInterest() internal {
        uint256 timeElapsed = block.timestamp - lastUpdateTime;
        if (timeElapsed == 0 || totalDebtShares == 0) {
            lastUpdateTime = block.timestamp;
            return;
        }

        uint256 currentExchangeRate = _getCurrentExchangeRate();
        if (currentExchangeRate > debtExchangeRate) {
            debtExchangeRate = currentExchangeRate;
        }
        lastUpdateTime = block.timestamp;
    }

    /// @notice Convert VNDT amount to debt shares
    function _getVndtToShares(uint256 amount) internal view returns (uint256) {
        uint256 currentExchangeRate = _getCurrentExchangeRate();
        return (amount * PRECISION) / currentExchangeRate;
    }

    /// @notice Get total debt value
    function _getTotalDebtValue() internal view returns (uint256) {
        return (totalDebtShares * debtExchangeRate) / PRECISION;
    }

    /// @notice Get current debt value for a user
    function getCurrentDebtValue(address user) public view returns (uint256) {
        uint256 shares = s_userDebtShares[user];
        return (shares * _getCurrentExchangeRate()) / PRECISION;
    }

    /// @notice Calculate position health ratio (collateral/debt)
    function calculatePositionRatio(address user) public view returns (uint256) {
        uint256 debtValue = getCurrentDebtValue(user);
        if (debtValue == 0) return type(uint256).max;
        
        uint256 collateralValue = calculateCollateralValue(user);
        return (collateralValue * 100) / debtValue;
    }

    /// @notice Validate user position maintains minimum collateral ratio
    function _validatePosition(address user) internal view {
        uint256 ratio = calculatePositionRatio(user);
        if (ratio < COLLATERAL_RATIO) revert Engine__UnsafePositionRatio();
    }

    /// @notice Mint VNDT tokens against collateral
    function mintVNDT(uint256 mintAmount) public {
        if (mintAmount == 0) revert Engine__InvalidAmount();
        
        _accrueInterest();
        
        uint256 shares = _getVndtToShares(mintAmount);
        s_userDebtShares[msg.sender] += shares;
        totalDebtShares += shares;
        
        bool success = i_vndt.mintTo(msg.sender, mintAmount);
        if (!success) revert Engine__TransferFailed();
        
        _validatePosition(msg.sender);
        emit DebtSharesMinted(msg.sender, mintAmount, shares);
    }

    /// @notice Set borrow rate (only rate controller)
    function setBorrowRate(uint256 newRate) external onlyRateController {
        _accrueInterest();
        borrowRate = newRate;
        emit BorrowRateUpdated(newRate);
    }

    /// @notice Repay debt with VNDT tokens
    function repayUpTo(uint256 amount) public {
        if (amount == 0) revert Engine__InvalidAmount();
        
        _accrueInterest();
        
        uint256 actualRepayment = amount;
        uint256 userDebt = getCurrentDebtValue(msg.sender);
        
        if (actualRepayment > userDebt) {
            actualRepayment = userDebt;
        }
        
        uint256 sharesToBurn = _getVndtToShares(actualRepayment);
        s_userDebtShares[msg.sender] -= sharesToBurn;
        totalDebtShares -= sharesToBurn;
        
        i_vndt.burnFrom(msg.sender, actualRepayment);
        emit DebtSharesBurned(msg.sender, actualRepayment, sharesToBurn);
    }

    /// @notice Withdraw collateral
    function withdrawCollateral(uint256 amount) external {
        if (amount == 0) revert Engine__InvalidAmount();
        if (s_userCollateral[msg.sender] < amount) revert Engine__InsufficientCollateral();
        
        _accrueInterest();
        s_userCollateral[msg.sender] -= amount;
        
        _validatePosition(msg.sender);
        
        (bool success, ) = payable(msg.sender).call{value: amount}("");
        if (!success) revert Engine__TransferFailed();
        
        uint256 ethPrice = i_oracle.getEthPrice();
        emit CollateralWithdrawn(msg.sender, amount, ethPrice);
    }

    /// @notice Check if user is liquidatable
    function isLiquidatable(address user) public view returns (bool) {
        uint256 ratio = calculatePositionRatio(user);
        return ratio < COLLATERAL_RATIO;
    }

    /// @notice Liquidate undercollateralized position
    function liquidate(address user) external {
        if (!isLiquidatable(user)) revert Engine__NotLiquidatable();
        
        _accrueInterest();
        
        uint256 userDebt = getCurrentDebtValue(user);
        uint256 collateralValue = calculateCollateralValue(user);
        
        uint256 liquidatorReward = (collateralValue * LIQUIDATOR_REWARD) / 100;
        uint256 protocolReward = collateralValue - liquidatorReward;
        
        // Burn user's debt shares
        uint256 debtShares = s_userDebtShares[user];
        totalDebtShares -= debtShares;
        s_userDebtShares[user] = 0;
        
        // Transfer collateral
        uint256 userCollateral = s_userCollateral[user];
        s_userCollateral[user] = 0;
        
        i_vndt.burnFrom(msg.sender, userDebt);
        
        (bool success, ) = payable(msg.sender).call{value: liquidatorReward}("");
        if (!success) revert Engine__TransferFailed();
        
        (success, ) = payable(owner()).call{value: protocolReward}("");
        if (!success) revert Engine__TransferFailed();
        
        uint256 ethPrice = i_oracle.getEthPrice();
        emit Liquidation(user, msg.sender, liquidatorReward, userDebt, ethPrice);
    }
}
