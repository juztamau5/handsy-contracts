// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.11;

contract Bankroll {
    address public owner;
    mapping(uint256 => uint256) private receivedFundsPerBlock;
    mapping(address => bool) private allowedWithdrawers;

    event FundsReceived(address indexed sender, uint256 amount, uint256 blockNumber);

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

    function receiveFunds() external payable {
        receivedFundsPerBlock[block.number] += msg.value;
        emit FundsReceived(msg.sender, msg.value, block.number);
    }

    function getReceivedFundsInPeriod(uint256 startBlock, uint256 endBlock) external view returns (uint256) {
        uint256 totalFunds = 0;
        for (uint256 i = startBlock; i <= endBlock; i++) {
            totalFunds += receivedFundsPerBlock[i];
        }
        return totalFunds;
    }

    function withdraw(uint256 amount) external onlyAllowedWithdrawers {
        require(amount <= address(this).balance, "Insufficient funds");
        payable(msg.sender).call{value: amount}("");
    }

    function updateAllowedWithdrawers(address withdrawer, bool allowed) external onlyOwner {
        allowedWithdrawers[withdrawer] = allowed;
    }
}
