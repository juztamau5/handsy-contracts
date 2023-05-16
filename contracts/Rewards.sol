// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.11;

import "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "./Bankroll.sol";

contract LPRewardsStaking {
    INonfungiblePositionManager public immutable nonfungiblePositionManager;
    Bankroll public immutable bankrollContract;
    uint256 public constant BLOCKS_PER_PERIOD = 6500;

    mapping(uint256 => uint256) public lastClaimedBlock;
    mapping(uint256 => uint256) public lpTokenIds;

    event Staked(uint256 indexed tokenId, address indexed staker);
    event Unstaked(uint256 indexed tokenId, address indexed staker);
    event RewardsClaimed(uint256 indexed tokenId, address indexed staker, uint256 amount);

    constructor(address _nonfungiblePositionManager, address _bankrollContract) {
        nonfungiblePositionManager = INonfungiblePositionManager(_nonfungiblePositionManager);
        bankrollContract = Bankroll(_bankrollContract);
    }

    function stake(uint256 tokenId) external {
        require(nonfungiblePositionManager.ownerOf(tokenId) == msg.sender, "Caller is not the owner of the token");
        nonfungiblePositionManager.transferFrom(msg.sender, address(this), tokenId);
        lpTokenIds[tokenId] = tokenId;
        lastClaimedBlock[tokenId] = block.number;
        emit Staked(tokenId, msg.sender);
    }

    function unstake(uint256 tokenId) external {
        require(nonfungiblePositionManager.ownerOf(tokenId) == address(this), "Contract is not the owner of the token");
        require(lpTokenIds[tokenId] != 0, "Token is not staked");
        _claimRewards(tokenId);
        nonfungiblePositionManager.transferFrom(address(this), msg.sender, tokenId);
        delete lpTokenIds[tokenId];
        emit Unstaked(tokenId, msg.sender);
    }

    function claimRewards(uint256 tokenId) external {
        _claimRewards(tokenId);
    }

    function _claimRewards(uint256 tokenId) private {
        require(lpTokenIds[tokenId] != 0, "Token is not staked");
        uint256 rewards = _calculateRewards(tokenId);
        if (rewards > 0) {
            bankrollContract.withdraw(rewards);
            payable(msg.sender).transfer(rewards);
        }
        lastClaimedBlock[tokenId] = block.number;
        emit RewardsClaimed(tokenId, msg.sender, rewards);
    }

    function _calculateRewards(uint256 tokenId) private view returns (uint256) {
        uint256 endBlock = block.number;
        uint256 startBlock = lastClaimedBlock[tokenId];
        uint256 totalFunds = bankrollContract.getReceivedFundsForLPInPeriod(startBlock, endBlock);
        IUniswapV3Pool pool = IUniswapV3Pool(nonfungiblePositionManager.positions(tokenId).pool);
        uint256 totalLiquidity = pool.liquidity();
        uint256 userLiquidity = nonfungiblePositionManager.positions(tokenId).liquidity;
        uint256 userShare = (userLiquidity * 1e18) / totalLiquidity;
        return (totalFunds * userShare) / 1e18;
    }

    function viewClaimableRewards(uint256 tokenId) external view returns (uint256) {
        return _calculateRewards(tokenId);
    }
}
