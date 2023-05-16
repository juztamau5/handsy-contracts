// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.11;

contract Bankroll {
    uint256 constant public STAKING_SHARE = 50;
    uint256 constant public LP_SHARE = 50;
    uint256 constant public AFFILIATE_SHARE = 50;

    address public owner;
    uint256 private lastAffiliateId;
    mapping(uint256 => uint256) private receivedFundsPerBlock;
    mapping(address => mapping(uint256 => uint256)) private receivedFundsPerAffiliatePerBlock;
    mapping(address => bool) private allowedWithdrawers;

    event FundsReceived(address indexed sender, uint256 amount, uint256 blockNumber, address affiliateA, address affiliateB);

    modifier onlyOwner() {
        require(msg.sender == owner, "Caller is not the owner");
        _;
    }

    modifier onlyAllowedWithdrawers() {
        require(allowedWithdrawers[msg.sender], "Caller is not allowed to withdraw");
        _;
    }

    constructor() {
        owner = msg.sender;
        // Allow owner to withdraw funds
        allowedWithdrawers[msg.sender] = true;
    }

    function _generateAffiliateId() private returns (uint256) {
        lastAffiliateId = lastAffiliateId + 1;
        return lastAffiliateId;
    }

    function receiveFunds(address affiliateA, address affiliateB) external payable {
        uint256 affiliateAmount;
        uint256 stakingAmount = msg.value;

        if (affiliateA != address(0) && affiliateB != address(0)) {
            affiliateAmount = msg.value / 4;
            stakingAmount -= 2 * affiliateAmount;
            receivedFundsPerAffiliatePerBlock[affiliateA][block.number] += affiliateAmount;
            receivedFundsPerAffiliatePerBlock[affiliateB][block.number] += affiliateAmount;
        } else if (affiliateA != address(0)) {
            affiliateAmount = msg.value / 2;
            stakingAmount -= affiliateAmount;
            receivedFundsPerAffiliatePerBlock[affiliateA][block.number] += affiliateAmount;
        } else if (affiliateB != address(0)) {
            affiliateAmount = msg.value / 2;
            stakingAmount -= affiliateAmount;
            receivedFundsPerAffiliatePerBlock[affiliateB][block.number] += affiliateAmount;
        }

        receivedFundsPerBlock[block.number] += stakingAmount;
        emit FundsReceived(msg.sender, msg.value, block.number, affiliateA, affiliateB);
    }

    function getReceivedFundsForAffiliateInPeriod(address affiliate, uint256 startBlock, uint256 endBlock) external view returns (uint256) {
        uint256 totalFunds = 0;
        for (uint256 i = startBlock; i <= endBlock; i++) {
            totalFunds += receivedFundsPerAffiliatePerBlock[affiliate][i];
        }
        return totalFunds;
    }

    function getReceivedFundsInPeriod(uint256 startBlock, uint256 endBlock) external view returns (uint256) {
        uint256 totalFunds = 0;
        for (uint256 i = startBlock; i <= endBlock; i++) {
            totalFunds += receivedFundsPerBlock[i];
        }
        return totalFunds;
    }

    function getReceivedFundsForStakingInPeriod(uint256 startBlock, uint256 endBlock) external view returns (uint256) {
        return this.getReceivedFundsInPeriod(startBlock, endBlock) * STAKING_SHARE / 100;
    }

    function getReceivedFundsForLPInPeriod(uint256 startBlock, uint256 endBlock) external view returns (uint256) {
        return this.getReceivedFundsInPeriod(startBlock, endBlock) * LP_SHARE / 100;
    }

    function withdraw(uint256 amount) external onlyAllowedWithdrawers {
        require(amount <= address(this).balance, "Insufficient funds");
        payable(msg.sender).call{value: amount}("");
    }

    function updateAllowedWithdrawers(address withdrawer, bool allowed) external onlyOwner {
        allowedWithdrawers[withdrawer] = allowed;
    }
}
