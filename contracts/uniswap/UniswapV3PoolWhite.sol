pragma solidity ^0.7.5;
// SPDX-License-Identifier: SimPL-2.0



import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";

import "./interfaces/INonfungiblePositionManager.sol";

import "./openzeppelin/proxy/utils/Initializable.sol";


contract UniswapV3PoolWhite is Initializable{
  event GovernanceTransferred(address indexed previousOwner, address indexed newOwner);
  event SetV3PoolWhiteAddressesEvent(address indexed sender,address[] pools,bool allow);

  INonfungiblePositionManager public nonfungiblePositionManager;
  IUniswapV3Factory public uniswapV3Factory;

  mapping(address => bool) public v3PoolWhiteList;
  address public governance;

  modifier onlyGovernance {
    require(msg.sender == governance, "not governance");
      _;
  }

  function doInitialize(address _nonfungiblePositionManager) public initializer{
    governance = msg.sender;

    nonfungiblePositionManager = INonfungiblePositionManager(_nonfungiblePositionManager);
    uniswapV3Factory = IUniswapV3Factory(nonfungiblePositionManager.factory());
  }
  function setGovernance(address _governance) public onlyGovernance{
      require(governance != address(0), "new governance the zero address");
      emit GovernanceTransferred(governance, _governance);
      governance = _governance;
  }

  function setV3PoolWhiteAddresses(address[] calldata _pools,bool _allow) external onlyGovernance{
    for(uint256 i=0;i< _pools.length;i++){
      v3PoolWhiteList[_pools[i]] = _allow;
    }
    emit SetV3PoolWhiteAddressesEvent(msg.sender,_pools,_allow);
  }

  function checkV3PoolWhiteList(uint256 _tokenId) external view returns(bool){
    address _poolAddr = getUninswapV3Pool(_tokenId);
    if(_poolAddr == address(0)){
      return false;
    }else{
      return v3PoolWhiteList[_poolAddr];
    }
  }

  function getUninswapV3Pool(uint256 _tokenId) public view returns(address){
      (,,address _token0,address _token1, uint24 _fee,,,,,,,) = nonfungiblePositionManager.positions(_tokenId);
      return uniswapV3Factory.getPool(_token0,_token1,_fee);
   }
}