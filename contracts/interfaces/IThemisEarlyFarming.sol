// SPDX-License-Identifier: SimPL-2.0
pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;

import "./IThemisEarlyFarmingStorage.sol";

interface IThemisEarlyFarming is IThemisEarlyFarmingStorage{
    function periodPools(uint8 periodId) external view returns(PeriodPool memory periodPool);
    function tokenUsersCurrDeposit(address token,address user) external view returns(uint256 userTotalDepoist);
    function userPeriodInfos(uint8 periodPoolId,address user) external view returns(UserPeriodInfo memory userPeriodInfo);
    function getPendingInterestsAndRewards(uint8 periodPoolId,address user) external view returns(uint256 _pendingInterests,uint256 _pendingRewards);
    function nftTransferCall(uint256 periodPoolId,address from,address to,uint256 _amount) external;
}