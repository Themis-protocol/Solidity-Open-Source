pragma solidity ^0.8.0;
//SPDX-License-Identifier: MIT
interface IUniswapV3Oracle{
    function getNFTAmounts(uint256 _tokenId) external view returns(address _token0,address _token1,uint24 _fee,uint256 _amount0,uint256 _amount1);
    function getTWAPQuoteNft(uint256 _tokenId,address _quoteToken) external view returns(uint256 _quoteAmount,uint256 _gasEstimate);
    // function getPoolPathByTokens(address _tokenIn,address _tokenOut) external view returns (bytes memory _path);
    
}