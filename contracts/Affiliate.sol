// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.11;

contract Affiliate {
    
    // Mapping from affiliate's address to a list of consumers' addresses.
    mapping(address => address[]) private affiliateToConsumers;

    // Mapping from consumer's address to affiliate's address.
    mapping(address => address) private consumerToAffiliate;

    // Event emitted when a consumer registers with an affiliate.
    event ConsumerRegistered(address indexed consumer, address indexed affiliate);

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
}
