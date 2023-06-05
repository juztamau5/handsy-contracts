// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.11;

import "./interfaces/IHandsToken.sol";
import "./Bank.sol";

contract Staking {
    IHandsToken private handsToken;
    uint256 public constant BLOCKS_PER_PERIOD = 6500;
    uint256 private constant DECIMALS = 1e18;

    struct Staker {
        uint256 stakedAmount;
        uint256 lastClaimedBlock;
    }

    uint256 public totalStaked;
    uint256 public lastPeriodEndBlock;
    uint256 public ethPerBlock;
    Bank public bankContract;
    mapping(address => Staker) public stakers;
    mapping(uint256 => uint256) private receivedFundsPerBlockForStaking;

    constructor(address _handsTokenAddress) {
        handsToken = IHandsToken(_handsTokenAddress);
        lastPeriodEndBlock = block.number;
    }

    modifier onlyBankContract() {
        require(msg.sender == address(bankContract), "Only bank contract");
        _;
    }

    modifier bankNotInitialized() {
        require(address(bankContract) == address(0), "Bank contract already initialized");
        _;
    }

    function setBankContract(address _bankContractAddress) external bankNotInitialized {
        bankContract = Bank(_bankContractAddress);
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
            bankContract.withdraw(claimableRewards);
            payable(stakerAddress).transfer(claimableRewards);
        }
        staker.lastClaimedBlock = block.number;
    }

    function _calculateRewards(address stakerAddress) private view returns (uint256) {
        Staker storage staker = stakers[stakerAddress];
        if (staker.stakedAmount == 0 || totalStaked == 0) {
            return 0;
        }
        uint256 claimableBlocks = block.number - staker.lastClaimedBlock;
        uint256 stakerShare = (staker.stakedAmount * DECIMALS) / totalStaked;
        return (ethPerBlock * claimableBlocks * stakerShare) / DECIMALS;
    }

    /**
     * @dev Starts a new period
     */
    function _startNewPeriod() private {
        require(block.number >= lastPeriodEndBlock + BLOCKS_PER_PERIOD, "New period has not started yet");

        uint256 startBlock = lastPeriodEndBlock + 1;
        uint256 endBlock = startBlock + BLOCKS_PER_PERIOD - 1;
        uint256 collectedEth = getReceivedFundsForStakingInPeriod(startBlock, endBlock);

        ethPerBlock = (collectedEth * DECIMALS) / BLOCKS_PER_PERIOD;
        lastPeriodEndBlock += BLOCKS_PER_PERIOD;
    }

    /**
     * @dev Returns the amount of funds claimable by a given address
     * @param stakerAddress Address of the staker
     * @return Amount of funds claimable by the given address
     */
    function viewClaimableRewards(address stakerAddress) external view returns (uint256) {
        return _calculateRewards(stakerAddress);
    }

    /**
     * @dev Returns the amount of funds staked by a given address
     * @param stakerAddress Address of the staker
     * @return Amount of funds staked by the given address
     */
    function stakedAmount(address stakerAddress) external view returns (uint256) {
        return stakers[stakerAddress].stakedAmount;
    }

    /**
     * @dev Returns the total amount of funds staked
     * @return Total amount of funds staked
     */
    function viewTotalStaked() external view returns (uint256) {
        return totalStaked;
    }

    /**
     * @dev Adds the amount of funds received for staking in a given block
     * @param blockNumber Block number
     * @param amount Amount of funds received for staking
     */
    function addReceivedFundsForStaking(uint256 blockNumber, uint256 amount) external onlyBankContract {
        receivedFundsPerBlockForStaking[blockNumber] += amount;
    }

    /**
     * @dev Returns the total funds received for staking in a given block range
     * @param startBlock Starting block number for the period
     * @param endBlock Ending block number for the period
     * @return Total funds received for staking in the given period
     */
    function getReceivedFundsForStakingInPeriod(uint256 startBlock, uint256 endBlock) external view returns (uint256) {
        uint256 totalFunds = 0;
        for (uint256 i = startBlock; i <= endBlock; i++) {
            totalFunds += receivedFundsPerBlockForStaking[i];
        }
        return totalFunds;
    }
}
