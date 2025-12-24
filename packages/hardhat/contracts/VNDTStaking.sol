// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./VNDT.sol";

error Staking__InvalidAmount();
error Staking__InsufficientShares();
error Staking__NotAuthorized();

/// @title VNĐ Staking Contract
/// @notice Allows users to stake VNDT tokens and earn interest
contract VNDTStaking is Ownable {
    VNDT private i_vndt;
    address private i_engine;
    address private i_rateController;

    uint256 public totalShares;
    uint256 public totalValue;
    uint256 public lastUpdateTime;
    uint256 public stakingRate; // Annual interest rate in basis points

    mapping(address => uint256) public userShares;

    event Staked(address indexed user, uint256 amount, uint256 shares);
    event Unstaked(address indexed user, uint256 amount, uint256 shares);
    event InterestAccrued(uint256 newValue);

    modifier onlyEngine() {
        if (msg.sender != i_engine) revert Staking__NotAuthorized();
        _;
    }

    modifier onlyRateController() {
        if (msg.sender != i_rateController) revert Staking__NotAuthorized();
        _;
    }

    constructor(
        address _vndtAddress,
        address _engine,
        address _rateController
    ) Ownable(msg.sender) {
        i_vndt = VNDT(_vndtAddress);
        i_engine = _engine;
        i_rateController = _rateController;
        lastUpdateTime = block.timestamp;
        stakingRate = 500; // 5% default staking rate
    }

    /// @notice Get value of shares with accrued interest
    function getSharesValue(uint256 shares) public view returns (uint256) {
        if (totalShares == 0) return 0;
        return (shares * totalValue) / totalShares;
    }

    /// @notice Accrue interest on staked value
    function accrueInterest() public {
        uint256 timeElapsed = block.timestamp - lastUpdateTime;
        if (timeElapsed == 0 || totalShares == 0) {
            lastUpdateTime = block.timestamp;
            return;
        }

        uint256 interest = (totalValue * stakingRate * timeElapsed) / (10000 * 365 days);
        totalValue += interest;
        lastUpdateTime = block.timestamp;
        emit InterestAccrued(totalValue);
    }

    /// @notice Stake VNDT tokens
    function stake(uint256 amount) external {
        if (amount == 0) revert Staking__InvalidAmount();

        accrueInterest();

        uint256 shares;
        if (totalShares == 0) {
            shares = amount;
            totalValue = amount;
        } else {
            shares = (amount * totalShares) / totalValue;
        }

        userShares[msg.sender] += shares;
        totalShares += shares;

        bool success = i_vndt.transferFrom(msg.sender, address(this), amount);
        require(success, "Transfer failed");

        emit Staked(msg.sender, amount, shares);
    }

    /// @notice Unstake VNDT tokens
    function unstake(uint256 shares) external {
        if (shares == 0) revert Staking__InvalidAmount();
        if (userShares[msg.sender] < shares) revert Staking__InsufficientShares();

        accrueInterest();

        uint256 value = getSharesValue(shares);
        userShares[msg.sender] -= shares;
        totalShares -= shares;
        totalValue -= value;

        bool success = i_vndt.transfer(msg.sender, value);
        require(success, "Transfer failed");

        emit Unstaked(msg.sender, value, shares);
    }

    /// @notice Set staking rate (only rate controller)
    function setStakingRate(uint256 newRate) external onlyRateController {
        accrueInterest();
        stakingRate = newRate;
    }
}
