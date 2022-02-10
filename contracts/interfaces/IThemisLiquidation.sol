pragma solidity ^0.8.0;
// SPDX-License-Identifier: SimPL-2.0

interface IThemisLiquidation{
    function disposalNFT(uint256 bid,address erc721,uint256 tokenId,address targetToken) external;
}
