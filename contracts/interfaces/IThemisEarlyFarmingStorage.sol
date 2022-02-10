// SPDX-License-Identifier: SimPL-2.0
pragma solidity ^0.8.0;

import "../interfaces/IThemisEarlyFarmingNFTStorage.sol";

interface IThemisEarlyFarmingStorage is IThemisEarlyFarmingNFTStorage{


    
    struct PeriodPool{
        uint256 lendPoolId;// IThemisLendCompound pool ID

        address token;
        address spToken;
        
        uint256 currTotalDeposit;

        uint256 interestsShare;
		uint256 lastInterestsBlock;
        uint256 rewardsShare;
        uint256 lastRewardBlock;
        uint256 periodBlock;

        address rewardToken;
        uint256 allocPoint;
    }
    
    struct UserPeriodInfo{
        uint256 currDeposit;
        uint256 totalRecvRewards;
        uint256 totalRecvInterests;
    }
    
    
}