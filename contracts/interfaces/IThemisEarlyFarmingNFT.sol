// SPDX-License-Identifier: SimPL-2.0
pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts@4.4.1/token/ERC721/IERC721.sol";

import "../interfaces/IThemisEarlyFarmingNFTStorage.sol";

interface IThemisEarlyFarmingNFT is IThemisEarlyFarmingNFTStorage,IERC721{
    function earlyFarmingNftInfos(uint256 tokenId) external view returns(EarlyFarmingNftInfo calldata nftInfo);
    function safeMint(address to,EarlyFarmingNftInfo memory nftInfo) external;
    function nftUnlockAmount(uint256 tokenId) external view returns(uint256 unlockAmount);
    function withdrawUnlockAmounts(WithdrawNftParams memory withdrawNftParams) external;
}