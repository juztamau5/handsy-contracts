// SPDX-License-Identifier: Unlicense
// This contract uses the Unlicense SPDX license identifier.

pragma solidity ^0.8.11;

// Importing necessary interfaces and contract.
import "./interfaces/IHandsToken.sol";
import "./interfaces/IStaking.sol";
import "./Bank.sol";

// Staking contract which enables users to stake and earn rewards.
contract Staking is IStaking {

    // Token contract of Hands Token
    IHandsToken private handsToken;
    // The number of blocks for a staking period.
    uint256 public constant BLOCKS_PER_PERIOD = 6500;
    // Decimal places for calculations.
    uint256 private constant DECIMALS = 1e18;

    // Struct for a staker with amount staked and the last claimed block.
    struct Staker {
        uint256 stakedAmount;
        uint256 lastClaimedBlock;
    }

    // Total amount staked across all stakers.
    uint256 public totalStaked;
    // Last block number when the staking period ended.
    uint256 public lastPeriodEndBlock;
    // Amount of ETH rewards per block.
    uint256 public ethPerBlock;
    // Instance of the Bank contract.
    Bank public bankContract;

    // Mapping of staker address to their Staker struct.
    mapping(address => Staker) public stakers;
    // Mapping of block number to received funds for staking in that block.
    mapping(uint256 => uint256) private receivedFundsPerBlockForStaking;

    // Constructor function to set the address of Hands Token.
    constructor(address _handsTokenAddress) {
        handsToken = IHandsToken(_handsTokenAddress);
        lastPeriodEndBlock = block.number;
    }

    // Modifier to restrict function calls to the Bank contract only.
    modifier onlyBankContract() {
        require(msg.sender == address(bankContract), "Only bank contract");
        _;
    }

    // Modifier to ensure that the bank contract is not initialized more than once.
    modifier bankNotInitialized() {
        require(address(bankContract) == address(0), "Bank contract already initialized");
        _;
    }

    // Function to set the address of the Bank contract.
    function setBankContract(address _bankContractAddress) external bankNotInitialized {
        bankContract = Bank(_bankContractAddress);
    }

    // Function to stake a certain amount of tokens.
    function stake(uint256 amount) external {
        handsToken.transferFrom(msg.sender, address(this), amount);
        totalStaked += amount;
        stakers[msg.sender].stakedAmount += amount;
        _claimRewards(msg.sender);

        emit Staked(msg.sender, amount);
    }

    // Function to unstake a certain amount of tokens.
    function unstake(uint256 amount) external {
        require(stakers[msg.sender].stakedAmount >= amount, "Insufficient staked amount");
        handsToken.transfer(msg.sender, amount);
        totalStaked -= amount;
        stakers[msg.sender].stakedAmount -= amount;
        _claimRewards(msg.sender);

        emit Unstaked(msg.sender, amount);
    }

    /**
     * @dev View function to get the amount of funds received for staking in a given period
     * @param startBlock Start block of the period
    * @param endBlock End block of the period
     */
    function getReceivedFundsForStakingInPeriod(uint256 startBlock, uint256 endBlock) public view returns (uint256) {
        uint256 totalFunds = 0;
        for (uint256 i = startBlock; i <= endBlock; i++) {
            totalFunds += receivedFundsPerBlockForStaking[i];
        }
        return totalFunds;
    }

    /**
     * @dev Function to receive funds for staking
     */
    function claimRewards() external {
        _claimRewards(msg.sender);
    }

    /**
     * @dev Function to receive funds for staking
     */
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
        emit RewardsClaimed(stakerAddress, claimableRewards);
    }

    /**
     * @dev Function to calculate the amount of funds claimable by a given address
     * @param stakerAddress Address of the staker
     * @return Amount of funds claimable by the given address
     */
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

}
