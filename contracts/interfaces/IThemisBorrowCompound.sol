pragma solidity ^0.8.0;
// SPDX-License-Identifier: SimPL-2.0
pragma experimental ABIEncoderV2;

import "./IThemisBorrowCompoundStorage.sol";


interface IThemisBorrowCompound is IThemisBorrowCompoundStorage{

    function borrowPoolInfo(uint256 pid) external view returns(CompoundBorrowPool memory borrowPool);
    function borrowInfo(uint256 bid) external view returns(BorrowInfo memory borrow);
    function settlementBorrow(uint256 bid) external;
    function doAfterLpTransfer(address ctoken,address sender,address recipient, uint256 amount) external;
    function updateBorrowPool(uint256 pid) external;
    function addBorrowPool(address borrowToken,address ctoken) external;
    function getGlobalLendInterestShare(uint256 pid) external view returns(uint256 globalLendInterestShare);
    function transferInterestToLend(uint256 pid,address toUser,uint256 interests) external;
    function getBorrowingRate(uint256 pid) external view returns(uint256);
    function getLendingRate(uint256 pid) external view returns(uint256);
    function borrowUserInfos(address user,uint256 pid) external view returns(BorrowUserInfo memory borrowUserInfo);
}