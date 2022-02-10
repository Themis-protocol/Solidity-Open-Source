pragma solidity ^0.8.0;
// SPDX-License-Identifier: SimPL-2.0


    

interface IThemisLendCompoundStorage{
    struct LendUserInfo {
        uint256 lastLendInterestShare;
        uint256 unRecvInterests;
        uint256 currTotalLend;
        uint256 userDli;
    }
    
    struct CompoundLendPool {
        address token;
        address spToken;
        uint256 curSupply;
        uint256 curBorrow;
        uint256 totalRecvInterests; //User receives interest
    }
}