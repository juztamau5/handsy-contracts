// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.11;

import "./Bank.sol";

contract Affiliate {
    // The bank contract.
    Bank public bankContract;

    // The maximum fee share per affiliate is 25%.
    uint256 constant public MAX_FEE_SHARE_PER_AFFILIATE = 25;

    // Mapping from affiliate's address to a mapping from block number to received funds.
    mapping(address => mapping(uint256 => uint256)) private receivedFundsPerAffiliatePerBlock;

    // Mapping from affiliate's address to a list of consumers' addresses.
    mapping(address => address[]) private affiliateToConsumers;

    // Mapping from consumer's address to affiliate's address.
    mapping(address => address) private consumerToAffiliate;

    // Event emitted when a consumer registers with an affiliate.
    event ConsumerRegistered(address indexed consumer, address indexed affiliate);

    /**
     * @dev Modifier to check if the caller is the bank contract.
     */
    modifier onlyBankContract() {
        require(msg.sender == bankContract, "Only the bank contract can call this function.");
        _;
    }

    /**
     * @dev Modifier to check if the bank contract has not been initialized.
     */
    modifier bankNotInitialized() {
        require(address(bankContract) == address(0), "Bank contract already initialized");
        _;
    }

    /**
     * @dev Set the bank contract.
     * @param _bankContract The address of the bank contract.
     */
    function setBankContract(address _bankContract) external bankNotInitialized {
        bankContract = Bank(_bankContract);
    }

    /**
     * @dev Register a consumer with an affiliate.
     * @param affiliate The address of the affiliate.
     */
    function registerAsConsumer(address affiliate) external {
        // Check if this consumer has already registered with an affiliate.
        require(consumerToAffiliate[msg.sender] == address(0), "Consumer has already registered.");

        // Add the consumer to the list of this affiliate's consumers.
        affiliateToConsumers[affiliate].push(msg.sender);

        // Register this consumer with the affiliate.
        consumerToAffiliate[msg.sender] = affiliate;

        emit ConsumerRegistered(msg.sender, affiliate);
    }

    /**
     * @dev Get the list of consumers registered with an affiliate.
     * @param affiliate The address of the affiliate.
     * @return A list of consumer addresses.
     */
    function getConsumersOfAffiliate(address affiliate) external view returns (address[] memory) {
        return affiliateToConsumers[affiliate];
    }

    /**
     * @dev Get the affiliate of a consumer.
     * @param consumer The address of the consumer.
     * @return The address of the consumer's affiliate.
     */
    function getAffiliateOfConsumer(address consumer) external view returns (address) {
        return consumerToAffiliate[consumer];
    }

    /**
     * @dev Calculate the affiliate's share and add it to the received funds.
     * @param affiliate The address of the affiliate.
     * @param totalAmount The total amount of funds received.
     * @return The affiliate's share.
     */
    function calculateAndAddAffiliateShare(address affiliate, uint256 totalAmount) external onlyBankContract returns (uint256) {
        if (affiliate != address(0)) {
            uint256 affiliateShare = (MAX_FEE_SHARE_PER_AFFILIATE * totalAmount) / 100;
            receivedFundsPerAffiliatePerBlock[affiliate][block.number] += affiliateShare;
            return affiliateShare;
        }
        return 0;
    }

    /**
     * @dev Get the received funds for an affiliate in a block.
     * @param affiliate The address of the affiliate.
     * @param blockNumber The block number.
     * @return The received funds.
     */
    function getReceivedFundsForAffiliateInBlock(address affiliate, uint256 blockNumber) public view returns (uint256) {
        return receivedFundsPerAffiliatePerBlock[affiliate][blockNumber];
    }

    /**
     * @dev Get the received funds for an affiliate in a period.
     * @param affiliate The address of the affiliate.
     * @param startBlock The start block.
     * @param endBlock The end block.
     * @return The received funds.
     */
    function getReceivedFundsForAffiliateInPeriod(address affiliate, uint256 startBlock, uint256 endBlock) external view returns (uint256) {
        uint256 totalFunds = 0;
        for (uint256 i = startBlock; i <= endBlock; i++) {
            totalFunds += getReceivedFundsForAffiliateInBlock(affiliate, i);
        }
        return totalFunds;
    }

    /**
        * @dev Retrieve the received funds for an affiliate.
     */
    function claimRewards() external {
        _claimRewards(msg.sender);
    }

    /**
     * @dev Retrieve the received funds for an affiliate.
     * @param affiliateAddress The address of the affiliate.
     */
    function _claimRewards(address affiliateAddress) private {
        AffiliateInfo storage affiliate = affiliates[affiliateAddress];
        uint256 claimableRewards = _calculateRewards(affiliateAddress);
        if (claimableRewards > 0) {
            bankContract.withdraw(claimableRewards);
            payable(affiliateAddress).transfer(claimableRewards);
        }
        affiliate.lastClaimedBlock = block.number;
    }

    /**
     * @dev Calculate the affiliate's rewards.
     * @param affiliateAddress The address of the affiliate.
     * @return The affiliate's rewards.
     */
    function _calculateRewards(address affiliateAddress) private view returns (uint256) {
        AffiliateInfo storage affiliate = affiliates[affiliateAddress];
        if (affiliate.receivedFunds == 0 || totalReceived == 0) {
            return 0;
        }
        uint256 claimableBlocks = block.number - affiliate.lastClaimedBlock;
        uint256 affiliateShare = (affiliate.receivedFunds * 1e18) / totalReceived;
        return (getReceivedFundsForAffiliateInPeriod(affiliateAddress, affiliate.lastClaimedBlock, block.number) * affiliateShare) / 1e18;
    }

    /**
     * @dev View the affiliate's rewards.
     * @param affiliateAddress The address of the affiliate.
     * @return The affiliate's rewards.
     */
    function viewClaimableRewards(address affiliateAddress) external view returns (uint256) {
        return _calculateRewards(affiliateAddress);
    }
}
