// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.11;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./Bankroll.sol";

contract LPRewardsStaking is ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public immutable lpToken;
    IERC20 public immutable rewardToken;
    Bankroll public immutable bankrollContract;
    uint256 public constant BLOCKS_PER_PERIOD = 6500;

    mapping(address => uint256) public lastClaimedBlock;
    mapping(address => uint256) public stakedBalances;

    event Staked(address indexed staker, uint256 amount);
    event Unstaked(address indexed staker, uint256 amount);
    event RewardsClaimed(address indexed staker, uint256 bankrollAmount, uint256 rewardAmount);

    constructor(address _lpToken, address _rewardToken, address _bankrollContract) {
        lpToken = IERC20(_lpToken);
        rewardToken = IERC20(_rewardToken);
        bankrollContract = Bankroll(_bankrollContract);
    }

    function stake(uint256 amount) external nonReentrant {
        require(amount > 0, "Amount must be greater than 0");
        lpToken.safeTransferFrom(msg.sender, address(this), amount);
        stakedBalances[msg.sender] += amount;
        lastClaimedBlock[msg.sender] = block.number;
        emit Staked(msg.sender, amount);
    }

    function unstake(uint256 amount) external nonReentrant {
        require(amount > 0, "Amount must be greater than 0");
        require(stakedBalances[msg.sender] >= amount, "Insufficient staked balance");
        _claimRewards();
        stakedBalances[msg.sender] -= amount;
        lpToken.safeTransfer(msg.sender, amount);
        emit Unstaked(msg.sender, amount);
    }

    function claimRewards() external nonReentrant {
        _claimRewards();
    }

    function _claimRewards() private {
        uint256 stakedBalance = stakedBalances[msg.sender];
        require(stakedBalance > 0, "No staked balance");

        uint256 bankrollRewards = _calculateBankrollRewards();
        if (bankrollRewards > 0) {
            bankrollContract.withdraw(bankrollRewards);
            payable(msg.sender).transfer(bankrollRewards);
        }

        uint256 rewardTokenAmount = _calculateRewardTokenAmount();
        if (rewardTokenAmount > 0) {
            rewardToken.safeTransfer(msg.sender, rewardTokenAmount);
        }

        lastClaimedBlock[msg.sender] = block.number;
        emit RewardsClaimed(msg.sender, bankrollRewards, rewardTokenAmount);
    }

    function _calculateBankrollRewards() private view returns (uint256) {
        uint256 endBlock = block.number;
        uint256 startBlock = lastClaimedBlock[msg.sender];
        uint256 totalFunds = bankrollContract.getReceivedFundsForLPInPeriod(startBlock, endBlock);
        uint256 totalLiquidity = lpToken.balanceOf(address(this));
        uint256 stakedBalance = stakedBalances[msg.sender];
            if (totalLiquidity == 0 || totalFunds == 0) {
            return 0;
        }

        return (totalFunds * stakedBalance) / totalLiquidity;
    }

    function _calculateRewardTokenAmount() private view returns (uint256) {
        uint256 endBlock = block.number;
        uint256 startBlock = lastClaimedBlock[msg.sender];
        uint256 elapsedBlocks = endBlock - startBlock;

        uint256 totalRewardsInPeriod = rewardToken.balanceOf(address(this));
        uint256 totalLiquidity = lpToken.balanceOf(address(this));
        uint256 stakedBalance = stakedBalances[msg.sender];

        if (totalLiquidity == 0 || totalRewardsInPeriod == 0) {
            return 0;
        }

        uint256 rewardBlocks = elapsedBlocks % BLOCKS_PER_PERIOD;
        uint256 rewardsInPeriod = (totalRewardsInPeriod * rewardBlocks) / BLOCKS_PER_PERIOD;
        return (rewardsInPeriod * stakedBalance) / totalLiquidity;
    }

    function getClaimableRewards() external view returns (uint256 bankrollRewards, uint256 rewardTokenAmount) {
        bankrollRewards = _calculateBankrollRewards();
        rewardTokenAmount = _calculateRewardTokenAmount();

        return (bankrollRewards, rewardTokenAmount);
    }

    function getUserStakedBalance(address account) external view returns (uint256) {
        return stakedBalances[account];
    }

    function getTotalStakedBalance() external view returns (uint256) {
        return lpToken.balanceOf(address(this));
    }

}