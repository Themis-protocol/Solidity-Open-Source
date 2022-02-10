pragma solidity ^0.8.0;
// SPDX-License-Identifier: SimPL-2.0


    

interface IThemisBorrowCompoundStorage{
    struct BorrowUserInfo {
        uint256 currTotalBorrow;
    }
    
    struct UserApplyRate{
        address apply721Address;
        uint256 specialMaxRate;
        uint256 tokenId;
    }
    
    struct BorrowInfo {
        address user;
        uint256 pid;
        // uint256 borrowType;     //1.v3 nft
        uint256 tokenId;
        uint256 borrowValue;
        uint256 auctionValue;
        uint256 amount;
        uint256 repaidAmount;
        uint256 startBowShare;
        // uint256 borrowDay;
        uint256 startBlock;
        uint256 returnBlock;
        uint256 interests;
        uint256 state;      //0.init 1.borrowing 2.return 8.settlement 9.overdue
    }
    
    struct CompoundBorrowPool {
        address token;
        address ctoken;
        uint256 curBorrow;
        uint256 curBowRate;
        uint256 lastShareBlock;
        uint256 globalBowShare;
        uint256 globalLendInterestShare;
        uint256 totalMineInterests;
        uint256 overdueRate;
    }
    
    struct Special721Info{
        string name;
        uint256 rate;
    }
    
}