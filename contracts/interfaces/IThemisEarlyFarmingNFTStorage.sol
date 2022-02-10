// SPDX-License-Identifier: SimPL-2.0
pragma solidity ^0.8.0;


interface IThemisEarlyFarmingNFTStorage{
    
    struct EarlyFarmingNftInfo{
        uint256 periodPoolId;
        address buyUser;
        address ownerUser;
        address pledgeToken;
        uint256 pledgeAmount;
        uint256 withdrawAmount;
        uint256 lastUnlockBlock;
        uint256 startBlock;
        uint256 endBlock;
        uint256 buyTime;
		uint256 perBlockUnlockAmount;
        
        uint256 lastInterestsShare;
        uint256 lastRewardsShare;
    }

    struct WithdrawNftParams{
        uint256 tokenId;
        address user;
        uint256 withdrawUnlockAmount;
        uint256 lastInterestsShare;
        uint256 lastRewardsShare;
    }
}