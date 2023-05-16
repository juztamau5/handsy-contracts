// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.11;

interface IBankroll {
    function withdraw(uint256 amount) external;
    function getReceivedFundsForStakingInPeriod(uint256 startBlock, uint256 endBlock) external view returns (uint256);
}
