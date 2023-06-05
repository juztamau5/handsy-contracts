// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.11;

import "./Affiliate.sol";
import "./Staking.sol";

/**
 * @title Bank contract
 * @dev  from Affiliate contract. 
 * Keeps track of received funds and allows for fund withdrawal.
 */
contract Bank {
    // Instance of the Affiliate contract
    Affiliate private affiliateContract;

    // Instance of the Staking contract
    Staking private stakingContract;


    // Mapping to keep track of received funds per block
    mapping(uint256 => uint256) private receivedFundsPerBlock;

    // Event emitted when funds are received
    event FundsReceived(address indexed contributor1, address indexed contributor2, uint256 amount, uint256 blockNumber, uint256 affiliateAmount, uint256 stakerAmount);

    // Only the affiliate contract can call this function
    modifier onlyAffiliateContract() {
        require(msg.sender == address(affiliateContract), "Only the affiliate contract can call this function.");
        _;
    }

    // Only the staking contract can call this function
    modifier onlyStakingContract() {
        require(msg.sender == address(stakingContract), "Only the staking contract can call this function.");
        _;
    }

    // Constructor to set the affiliate contract
    constructor(address _affiliateContract, address _stakingContract) {
        affiliateContract = Affiliate(_affiliateContract);
        stakingContract = Staking(_stakingContract);

        affiliateContract.setBankContract(address(this));
        stakingContract.setBankContract(address(this));
    }

    /**
     * @dev Allows contributors to deposit funds and emits a FundsReceived event
     * @param contributor1 Address of the first contributor
     * @param contributor2 Address of the second contributor
     */
    function receiveFunds(address contributor1, address contributor2) public payable {
        uint256 potFee = msg.value;

        // Check if the contributors are consumers and calculate the affiliate's share
        address affiliate1 = affiliateContract.getAffiliateOfConsumer(contributor1);
        address affiliate2 = affiliateContract.getAffiliateOfConsumer(contributor2);
        
        potFee -= affiliateContract.calculateAndAddAffiliateShare(affiliate1, potFee);
        potFee -= affiliateContract.calculateAndAddAffiliateShare(affiliate2, potFee);

        // Add the remaining potFee to the receivedFundsPerBlock
        stakingContract.addReceivedFundsForStaking(block.number, potFee); // Call the addReceivedFundsForStaking function from the Staking contract

        // Emit the event for fund receipt
        emit FundsReceived(
            contributor1,
            contributor2, 
            msg.value, 
            block.number, 
            affiliateContract.getReceivedFundsForAffiliateInBlock(affiliate1, block.number), 
            stakingContract.getReceivedFundsForStakingInPeriod(block.number, block.number)
        );
    }

    /**
     * @dev Returns the total funds received in a given block range
     * @param startBlock Starting block number for the period
     * @param endBlock Ending block number for the period
     * @return Total funds received in the given period
     */
    function getReceivedFundsInPeriod(uint256 startBlock, uint256 endBlock) external view returns (uint256) {
        uint256 totalFunds = 0;
        for (uint256 i = startBlock; i <= endBlock; i++) {
            totalFunds += receivedFundsPerBlock[i];
        }
        return totalFunds;
    }

    /**
     * @dev Allows the affiliate and contract to withdraw funds and emits a Withdrawal event
     * @param amount Amount to withdraw
     */
    function withdraw(uint256 amount) external onlyAffiliateContract onlyStakingContract {
        require(amount <= address(this).balance, "Not enough funds in the contract.");
        payable(msg.sender).transfer(amount);
    }
}
