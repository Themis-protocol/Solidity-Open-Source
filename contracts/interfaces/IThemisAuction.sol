pragma solidity ^0.8.0;
//SPDX-License-Identifier: MIT

interface IThemisAuction{
    function toAuction(address erc721Addr,uint256 tokenId,uint256 bid,address auctionToken,uint256 startAuctionAmount,uint256 startAuctioInterests) external;
}