pragma solidity ^0.8.0;
//SPDX-License-Identifier: MIT
interface IUniswapV3PoolWhite{
    function checkV3PoolWhiteList(uint256 _tokenId) external view returns(bool);
}