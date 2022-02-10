//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;

import "./IThemisLendCompoundStorage.sol";


interface IThemisLendCompound is IThemisLendCompoundStorage{
    function tokenOfPid(address token) external view returns(uint256 pid);
    function lendPoolInfo(uint256 pid) external view returns(CompoundLendPool memory pool);
    function getPoolLength() external view returns(uint256 poolLength);
    function doAfterLpTransfer(address ctoken,address sender,address recipient, uint256 amount) external;

    function loanTransferToken(uint256 pid,address toUser,uint256 amount) external;
    function repayTransferToken(uint256 pid,uint256 amount) external;
    function lendUserInfos(address user,uint256 pid) external view returns(LendUserInfo memory lendUserInfo);
    function userLend(uint256 _pid, uint256 _amount) external;
    function userRedeem(uint256 pid, uint256 _amount) external returns(uint256);
    function pendingRedeemInterests(uint256 _pid, address _user) external view returns(uint256 _lendInterests,uint256 _platFormInterests);
    function settlementRepayTransferToken(uint256 pid,uint256 amount) external;
    function transferToAuctionUpBorrow(uint256 pid,uint256 amount) external;
}