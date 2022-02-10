pragma solidity ^0.8.0;
// SPDX-License-Identifier: SimPL-2.0

interface IThemisEarlyFarmingNFTDescriptor{
    function tokenURI(uint256 tokenId) external view returns (string memory);
}

