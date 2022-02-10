pragma solidity ^0.7.5;
// SPDX-License-Identifier: SimPL-2.0

pragma abicoder v2;


import "@uniswap/v3-periphery/contracts/libraries/Path.sol";
import "@uniswap/v3-periphery/contracts/libraries/OracleLibrary.sol";
import "@uniswap/v3-periphery/contracts/libraries/LiquidityAmounts.sol";
import "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";

import "@chainlink/contracts/src/v0.7/interfaces/AggregatorV3Interface.sol";

import "@openzeppelin/contracts@3.4.2/math/SafeMath.sol";


import "./interfaces/INonfungiblePositionManager.sol";
import "./openzeppelin/proxy/utils/Initializable.sol";


interface IERC20{
    function decimals() external view returns (uint8);
}

contract UniswapV3ChainLinkOracle  is Initializable{

    using SafeMath for uint256;
    
    struct ChainLinkFeedStruct{
        address priceFeed;
        int decimals;
    }

    event GovernanceTransferred(address indexed previousOwner, address indexed newOwner);
    event SetTokenRefFeedEvent(address indexed sender,address[] _tokens,address[] _feedAddr);


    address public governance;
    INonfungiblePositionManager public nonfungiblePositionManager;
    IUniswapV3Factory public uniswapV3Factory;
    int256 public constant usdDefaultDecimals = 8;

    mapping(address => ChainLinkFeedStruct) public tokenRefFeed;


    modifier onlyGovernance {
        require(msg.sender == governance, "not governance");
        _;
    }

    function doInitialize(address _nonfungiblePositionManager) external initializer{
        governance = msg.sender;
        nonfungiblePositionManager = INonfungiblePositionManager(_nonfungiblePositionManager);
        uniswapV3Factory = IUniswapV3Factory(nonfungiblePositionManager.factory());
    }
    
    function setGovernance(address _governance) public onlyGovernance{
        require(governance != address(0), "new governance the zero address");
        emit GovernanceTransferred(governance, _governance);
        governance = _governance;
    }

    function setTokenRefFeed(address[] calldata _tokens,address[] calldata _feedAddr) external onlyGovernance{
        require(_tokens.length > 0,"Parameter sizes must be greater than zero.");
        require(_tokens.length == _feedAddr.length,"Parameter sizes are not equal.");
        for(uint i=0;i<_tokens.length;i++){
            AggregatorV3Interface _feedPrice = AggregatorV3Interface(_feedAddr[i]);
            int _decimals = _feedPrice.decimals();
            require(_decimals == usdDefaultDecimals,"This type is not supported.");
            tokenRefFeed[_tokens[i]]= ChainLinkFeedStruct({
                priceFeed: _feedAddr[i],
                decimals: _decimals
            });
        }
        emit SetTokenRefFeedEvent(msg.sender,_tokens,_feedAddr);
    }

    function getNFTAmounts(uint256 _tokenId) external view returns(address _token0,address _token1,uint24 _fee,uint256 _amount0,uint256 _amount1){
        (_token0,_token1,_fee,_amount0,_amount1) = _getNFTAmounts(_tokenId);
    }
    
    function getTWAPQuoteNft(uint256 _tokenId,address _quoteToken) external view returns(uint256 _quoteAmount,uint256 _gasEstimate){
        uint256 _gasBefore = gasleft();

        (int256 _quoteTokenUsdPrice,) = getLatestPrice(_quoteToken);

        (uint256 _nftUsdValue,uint256 _maxTokenDecimals) = _calNftUsdValue(_tokenId,_quoteToken,_quoteTokenUsdPrice);

        _quoteAmount = _nftUsdValue.div(uint256(_quoteTokenUsdPrice));


        uint8 _quoteDecimals = IERC20(_quoteToken).decimals();

        if(_quoteDecimals > _maxTokenDecimals){
            _quoteAmount = _quoteAmount.mul(10 ** uint256(_quoteDecimals - _maxTokenDecimals));
        }else if(_maxTokenDecimals > _quoteDecimals){
            _quoteAmount = _quoteAmount.div(10 ** uint256(_maxTokenDecimals - _quoteDecimals));
        }

        _gasEstimate = gasleft()-_gasBefore;
    }

    function getTokenQuotePrice(address _token,address _quoteToken)external view returns(uint256 _quotePrice,uint256 _gasEstimate){
        uint256 _gasBefore = gasleft();
        (int256 _tokenUsdPrice,) = getLatestPrice(_token);
        (int256 _quoteTokenUsdPrice,) = getLatestPrice(_quoteToken);

        _quotePrice = uint256(_tokenUsdPrice).mul(10 ** uint256(usdDefaultDecimals)).div(uint256(_quoteTokenUsdPrice));

        uint8 _quoteDecimals = IERC20(_quoteToken).decimals();
        if(_quoteDecimals > usdDefaultDecimals){
            _quotePrice = _quotePrice.mul(10 ** uint256(_quoteDecimals - usdDefaultDecimals));
        }else if(usdDefaultDecimals >_quoteDecimals){
            _quotePrice = _quotePrice.div(10 ** uint256(usdDefaultDecimals - _quoteDecimals));
        }

        _gasEstimate = gasleft()-_gasBefore;
    }



    function _calNftUsdValue(uint256 _tokenId,address _quoteToken,int256 _quoteTokenUsdPrice) internal view returns(uint256 _nftUsdValue,uint256 _maxTokenDecimals){
        (address _token0,address _token1,,uint256 _amount0,uint256 _amount1) = _getNFTAmounts(_tokenId);
        
        uint256 _token0UsdAmount = _calDefaultUsdDecimalsValue(_quoteTokenUsdPrice,_token0,_amount0,_quoteToken);

        uint256 _token1UsdAmount = _calDefaultUsdDecimalsValue(_quoteTokenUsdPrice,_token1,_amount1,_quoteToken);

        uint8 _token0Decimals = IERC20(_token0).decimals();
        uint8 _token1Decimals = IERC20(_token1).decimals();
        _maxTokenDecimals = _token0Decimals;

        if(_token1Decimals > _token0Decimals){
            _maxTokenDecimals = _token1Decimals;
            _token0UsdAmount = _token0UsdAmount.mul(10 ** uint256(_token1Decimals - _token0Decimals));
        }else if(_token0Decimals > _token1Decimals){
            _token1UsdAmount = _token1UsdAmount.mul(10 ** uint256(_token0Decimals - _token1Decimals));
        }

        _nftUsdValue = _token0UsdAmount.add(_token1UsdAmount);
    }

    function _calDefaultUsdDecimalsValue(int256 _tokenUsdPrice,address _token,uint256 _amount,address _quoteToken) internal view returns(uint256 _tokenUsdAmount){
        if(_amount!=0){
            if(_token!=_quoteToken){
                (_tokenUsdPrice,) = getLatestPrice(_token);
            }
            _tokenUsdAmount  = uint256(_tokenUsdPrice).mul(_amount);
        }

    }


    function _getNFTAmounts(uint256 _tokenId) internal view returns(address _token0,address _token1,uint24 _fee,uint256 _amount0,uint256 _amount1){
        int24 _tickLower;
        int24 _tickUpper;
        uint128 _liquidity;
        (,,_token0,_token1,_fee,_tickLower,_tickUpper,_liquidity,,,,) = nonfungiblePositionManager.positions(_tokenId);
        IUniswapV3Pool _uniswapV3Pool = IUniswapV3Pool(uniswapV3Factory.getPool(_token0,_token1,_fee));
        (,int24 _poolTick,,,,,) = _uniswapV3Pool.slot0();
        uint160 _sqrtRatioX96 = TickMath.getSqrtRatioAtTick(_poolTick);
        uint160 _sqrtRatioAX96 = TickMath.getSqrtRatioAtTick(_tickLower);
        uint160 _sqrtRatioBX96 = TickMath.getSqrtRatioAtTick(_tickUpper);
        (_amount0,_amount1) = LiquidityAmounts.getAmountsForLiquidity(_sqrtRatioX96,_sqrtRatioAX96,_sqrtRatioBX96,_liquidity);
    }

    /**
     * Returns the latest price
     */
    function getLatestPrice(address _token) public view returns (int256 _answer,int _decimals) {
        address _priceFeed = tokenRefFeed[_token].priceFeed;
        _decimals =  tokenRefFeed[_token].decimals;
        require(_priceFeed!=address(0),"Not configured.");
        (,_answer,,,) = AggregatorV3Interface(_priceFeed).latestRoundData();
    }

}