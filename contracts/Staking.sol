// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.11;

import "./interfaces/IHandsToken.sol";
import "./interfaces/IBankroll.sol";

contract HandsStaking {
    IHandsToken private handsToken;
    IBankroll private bankrollContract;
    uint256 public constant BLOCKS_PER_PERIOD = 6500;
    uint256 private constant DECIMALS = 1e18;

    struct Staker {
        uint256 stakedAmount;
        uint256 lastClaimedBlock;
    }

    uint256 public totalStaked;
    uint256 public lastPeriodEndBlock;
    uint256 public ethPerBlock;
    mapping(address => Staker) public stakers;

    constructor(address _handsTokenAddress, address _bankrollContractAddress) {
        handsToken = IHandsToken(_handsTokenAddress);
        bankrollContract = IBankroll(_bankrollContractAddress);
        lastPeriodEndBlock = block.number;
    }

    function stake(uint256 amount) external {
        handsToken.transferFrom(msg.sender, address(this), amount);
        totalStaked += amount;
        stakers[msg.sender].stakedAmount += amount;
        _claimRewards(msg.sender);
    }

    function unstake(uint256 amount) external {
        require(stakers[msg.sender].stakedAmount >= amount, "Insufficient staked amount");
        handsToken.transfer(msg.sender, amount);
        totalStaked -= amount;
        stakers[msg.sender].stakedAmount -= amount;
        _claimRewards(msg.sender);
    }

    function claimRewards() external {
        _claimRewards(msg.sender);
    }

    function _claimRewards(address stakerAddress) private {
        Staker storage staker = stakers[stakerAddress];
        if (block.number >= lastPeriodEndBlock + BLOCKS_PER_PERIOD) {
            _startNewPeriod();
        }
        uint256 claimableRewards = _calculateRewards(stakerAddress);
        if (claimableRewards > 0) {
            bankrollContract.withdraw(claimableRewards);
            payable(stakerAddress).transfer(claimableRewards);
        }
        staker.lastClaimedBlock = block.number;
    }

    function _calculateRewards(address stakerAddress) private view returns (uint256) {
        Staker storage staker = stakers[stakerAddress];
        uint256 claimableBlocks = block.number - staker.lastClaimedBlock;
        uint256 stakerShare = (staker.stakedAmount * DECIMALS) / totalStaked;
        return (ethPerBlock * claimableBlocks * stakerShare) / DECIMALS;
    }

    function _startNewPeriod() private {
        require(block.number >= lastPeriodEndBlock + BLOCKS_PER_PERIOD, "New period has not started yet");

        uint256 startBlock = lastPeriodEndBlock + 1;
        uint256 endBlock = startBlock + BLOCKS_PER_PERIOD - 1;
        uint256 collectedEth = bankrollContract.getReceivedFundsForStakingInPeriod(startBlock, endBlock);

        ethPerBlock = (collectedEth * DECIMALS) / BLOCKS_PER_PERIOD;
        lastPeriodEndBlock += BLOCKS_PER_PERIOD;
    }

    function viewClaimableRewards(address stakerAddress) external view returns (uint256) {
        return _calculateRewards(stakerAddress);
    }
}
