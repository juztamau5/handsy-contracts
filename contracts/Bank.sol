// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.11;

import "./Affiliate.sol";

/**
 * @title Bankroll contract
 * @dev  from Affiliate contract. 
 * Keeps track of received funds and allows for fund withdrawal.
 */
abstract contract Bankroll {
    // Defining the shares for staking and affiliate marketing
    uint256 constant public MAX_FEE_SHARE_PER_AFFILIATE = 25;

    // Instance of the Affiliate contract
    Affiliate private affiliateContract;

    // Mapping to keep track of received funds per block
    mapping(uint256 => uint256) private receivedFundsPerBlock;

    // Mapping to keep track of received funds per block for staking
    mapping(uint256 => uint256) private receivedFundsPerBlockForStaking;

    // Mapping to keep track of received funds per affiliate per block
    mapping(address => mapping(uint256 => uint256)) private receivedFundsPerAffiliatePerBlock;

    // Event emitted when funds are received
    event FundsReceived(address indexed contributor1, address indexed contributor2, uint256 amount, uint256 blockNumber, uint256 affiliateAmount, uint256 stakerAmount);

    // Constructor to set the affiliate contract
    constructor(address _affiliateContract) {
        affiliateContract = Affiliate(_affiliateContract);
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
        
        if (affiliate1 != address(0)) {
            uint256 affiliateShare = (MAX_FEE_SHARE_PER_AFFILIATE * potFee) / 100;
            receivedFundsPerAffiliatePerBlock[affiliate1][block.number] += affiliateShare;
            potFee -= affiliateShare;
        }

        if (affiliate2 != address(0)) {
            uint256 affiliateShare = (MAX_FEE_SHARE_PER_AFFILIATE * potFee) / 100;
            receivedFundsPerAffiliatePerBlock[affiliate2][block.number] += affiliateShare;
            potFee -= affiliateShare;
        }

        // Add the remaining potFee to the receivedFundsPerBlock
        receivedFundsPerBlockForStaking[block.number] += potFee;

        // Emit the event for fund receipt
        emit FundsReceived(
            contributor1,
            contributor2, 
            msg.value, 
            block.number, 
            receivedFundsPerAffiliatePerBlock[affiliate1][block.number], 
            receivedFundsPerBlockForStaking[block.number]
        );
    }

    /**
     * @dev Returns the total funds received for a particular affiliate in a given block range
     * @param affiliate Address of the affiliate
     * @param startBlock Starting block number for the period
     * @param endBlock Ending block number for the period
     * @return Total funds received for the affiliate in the given period
     */
    function getReceivedFundsForAffiliateInPeriod(address affiliate, uint256 startBlock, uint256 endBlock) external view returns (uint256) {
        uint256 totalFunds = 0;
        for (uint256 i = startBlock; i <= endBlock; i++) {
            totalFunds += receivedFundsPerAffiliatePerBlock[affiliate][i];
        }
        return totalFunds;
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
}
