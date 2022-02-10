pragma solidity ^0.8.0;
// SPDX-License-Identifier: SimPL-2.0
pragma experimental ABIEncoderV2;


import "@openzeppelin/contracts@4.4.1/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts@4.4.1/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts@4.4.1/utils/math/SafeMath.sol";
import "@openzeppelin/contracts@4.4.1/utils/Address.sol";
import "@openzeppelin/contracts@4.4.1/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts@4.4.1/utils/structs/EnumerableSet.sol";

import "../governance/RoleControl.sol";


import "../interfaces/IThemisLendCompound.sol";
import "../interfaces/IThemisEarlyFarmingStorage.sol";
import "../interfaces/IThemisEarlyFarmingNFT.sol";
import "../interfaces/IThemisLendCompoundStorage.sol";



contract ThemisEarlyFarming is IThemisEarlyFarmingStorage,IThemisLendCompoundStorage,RoleControl,Initializable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using Address for address;
    using EnumerableSet for EnumerableSet.UintSet;

    event DoStartRewardEvent(address indexed sender,address rewardToken,uint256 rewardPerBlock,uint256 startRewardBlock,uint256 endRewardBlock,uint256[] _periodIds,uint256[] _allocPoints);
    event UserDepositEvent(address indexed sender,uint256 periodPoolId,uint256 amount );
    event UserWithdrawEvent(address indexed sender,uint256 indexed tokenId,uint256 amount);
    event HarvestInterestsAndRewardsEvent(address indexed sender,uint256 indexed tokenId,uint256 interests,uint256 rewards);
    event AddPeriodPoolEvent(address indexed sender,PeriodPool periodPool);
    event SetPeriodAllocPointEvent(address indexed sender,uint256 periodPoolId,uint256 beforeAllocPoint,uint256 allocPoint);
    event UpdateShareEvent(uint256 indexed periodPoolId,address sender,uint256 shareType,uint256 beforeShare,uint256 share,uint256 amounts);
    event TransferLendPoolRewardEvent(address indexed sender,address token,address to,uint256 amount);
    event NftTransferCallEvent(address indexed sender,uint256 periodPoolId,address from,address to,uint256 amount);
    event ChangeRewardEndBlockEvent(address indexed sender,uint256 beforeVal,uint256 afterValue);
    event PausePoolEvent(address indexed sender,uint256 pid,bool flag);
    
    mapping(address => uint256) public tokenCurrTotalDeposit; //token => deposit amount
    mapping(uint256 =>mapping(address => UserPeriodInfo)) public userPeriodInfos;//periodPoolId => user address =>UserPeriodInfo
    mapping(uint256 => uint256) totalRecvRewards; // periodPoolId => rewards
    mapping(uint256 => uint256) totalRecvInterests; // periodPoolId => interests

    IThemisLendCompound public themisLendCompound;
    IThemisEarlyFarmingNFT public themisEarlyFarmingNFT;
    
    PeriodPool[] public periodPools;

    //valuts info
    uint256 public startBlock;
    uint256 public endBlock;

    //reward info
    uint256 public totalAllocPoint;
    IERC20 public rewardToken;
    uint256 public rewardPerBlock;
    uint256 public startRewardBlock;
    uint256 public endRewardBlock;

    mapping(address => uint256[]) tokenPeriodIds;// token address => periodId
    
    modifier checkPeriodVaild(uint256 _periodPoolId){
        PeriodPool memory _periodPool = periodPools[_periodPoolId];
        require(address(_periodPool.token)!=address(0),"Illegal period pool.");
        require(block.number > startBlock  ,"Period pool not start.");
        require(block.number <= endBlock  ,"Period pool is end.");
        _;
    }

    modifier onlyNftCaller(){
        require(address(themisEarlyFarmingNFT) == msg.sender  ,"Not allow to call.");
        _;
    }
    
    struct InitParams{
        IThemisLendCompound themisLendCompound;
        IThemisEarlyFarmingNFT themisEarlyFarmingNFT;
        uint256 startBlock;
        uint256 endBlock;
    }
    
    function doInitialize(InitParams memory _initParams) external initializer{
        _governance = msg.sender;
        _grantRole(PAUSER_ROLE, msg.sender);

        themisLendCompound = _initParams.themisLendCompound;
        themisEarlyFarmingNFT = _initParams.themisEarlyFarmingNFT;
        startBlock = _initParams.startBlock;
        endBlock = _initParams.endBlock;
    }

    function doStartReward(address _rewardToken,uint256 _rewardPerBlock,uint256 _startRewardBlock,uint256 _endRewardBlock,uint256[] calldata _periodIds,uint256[] calldata _allocPoints) external onlyGovernance{
        require(_startRewardBlock >= startBlock,"reward start block error.");
        require(_endRewardBlock <= endBlock,"reward end block error.");
        require(address(rewardToken) == address(0),"Already reward started.");
        require(_periodIds.length == _allocPoints.length,"Error in parameter array.");
        rewardToken = IERC20(_rewardToken);
        rewardPerBlock = _rewardPerBlock;
        startRewardBlock = _startRewardBlock;
        endRewardBlock = _endRewardBlock;

        for(uint256 i=0;i<_periodIds.length;i++){
            periodPools[_periodIds[i]].lastRewardBlock = _startRewardBlock;
            periodPools[_periodIds[i]].rewardToken = address(rewardToken);
            periodPools[_periodIds[i]].allocPoint = _allocPoints[i];
            totalAllocPoint = totalAllocPoint.add(_allocPoints[i]);
        }

        emit DoStartRewardEvent(msg.sender,address(_rewardToken),_rewardPerBlock,_startRewardBlock,_endRewardBlock,_periodIds,_allocPoints);
    }

    function pausePool(uint256 _periodPoolId) external onlyRole(PAUSER_ROLE){
        PeriodPool storage _periodPool = periodPools[_periodPoolId];
        _grantRole(keccak256("VAR_PAUSE_POOL_ACCESS_ROLE"), _periodPool.token);
        emit PausePoolEvent(msg.sender,_periodPoolId,true);
    }

    function unpausePool(uint256 _periodPoolId) external onlyGovernance{
        PeriodPool storage _periodPool = periodPools[_periodPoolId];
        _revokeRole(keccak256("VAR_PAUSE_POOL_ACCESS_ROLE"), _periodPool.token);
        emit PausePoolEvent(msg.sender,_periodPoolId,false);
    }

    function changeRewardEndBlock(uint256 _endRewardBlock) external onlyGovernance{
        require(endRewardBlock >= block.number,"The end block must be larger than the current block.");
        uint256 _beforeValue = endRewardBlock;
        endRewardBlock = _endRewardBlock;
        emit ChangeRewardEndBlockEvent(msg.sender,_beforeValue,_endRewardBlock);
    }


    function addPeriodPool(address _token,uint256 _periodBlock) external onlyGovernance{
        uint256 _periodPoolId = uint256(periodPools.length);
        uint256 _lendPoolId = themisLendCompound.tokenOfPid(_token);
        CompoundLendPool memory _lendPool = themisLendCompound.lendPoolInfo(_lendPoolId);
        require(_lendPool.token == _token ,"Not exists lend pool.");

        for(uint256 i=0;i<periodPools.length;i++){
            _updatePeriodRewardShare(i);
        }   

        periodPools.push(PeriodPool({
            lendPoolId:_lendPoolId,
            token:_token,
            spToken: _lendPool.spToken,
            currTotalDeposit:0,
            interestsShare:0,
            lastInterestsBlock:block.number,
            rewardsShare:0,
            lastRewardBlock:0,
            periodBlock:_periodBlock,
            rewardToken: address(0),
            allocPoint:0
        }));

        tokenPeriodIds[_token].push(_periodPoolId);

        emit AddPeriodPoolEvent(msg.sender,periodPools[_periodPoolId]);
    }


    function setPeriodAllocPoint(uint256 _periodPoolId,uint256 _allocPoint) external onlyGovernance{
        for(uint256 i=0;i<periodPools.length;i++){
            _updatePeriodRewardShare(i);
        }   
        PeriodPool storage _periodPool = periodPools[_periodPoolId];

        uint256 _beforeAllocPoint = _periodPool.allocPoint;
        _periodPool.allocPoint = _allocPoint;
        totalAllocPoint = totalAllocPoint.add(_allocPoint).sub(_beforeAllocPoint);
 
        emit SetPeriodAllocPointEvent(msg.sender,_periodPoolId,_beforeAllocPoint,_allocPoint);
    }

    
    function userDeposit(uint256 _periodPoolId,uint256 _amount) external checkPeriodVaild(_periodPoolId) nonReentrant whenNotPaused{
        require(_amount > 0, "deposit input invalid amount.");
        address _user = msg.sender;

        _settlementProfit(_periodPoolId);
        
        uint256 _currBlock = block.number;

        PeriodPool storage _periodPool = periodPools[_periodPoolId];
        
        checkPoolPause(_periodPool.token);

        address _token = _periodPool.token;
        // update gobal
        tokenCurrTotalDeposit[_token] = tokenCurrTotalDeposit[_token].add(_amount);
        // update period pool
        _periodPool.currTotalDeposit = _periodPool.currTotalDeposit.add(_amount);
        // update user
        
        UserPeriodInfo storage _userPeriodInfo = userPeriodInfos[_periodPoolId][_user];
        _userPeriodInfo.currDeposit = _userPeriodInfo.currDeposit.add(_amount);
        
        IERC20(_token).safeTransferFrom(_user, address(this), _amount);
        
        IERC20(_token).safeApprove(address(themisLendCompound),0);
        IERC20(_token).safeApprove(address(themisLendCompound),_amount);

        themisLendCompound.userLend(_periodPool.lendPoolId,_amount);

        //send user a NFT
        EarlyFarmingNftInfo memory _nftInfo = EarlyFarmingNftInfo({
            periodPoolId:_periodPoolId,
            buyUser:_user,
            ownerUser: _user,
            pledgeToken: _token,
            pledgeAmount: _amount,
            withdrawAmount: 0,
            lastUnlockBlock: _currBlock,
            startBlock: _currBlock,
            endBlock: _currBlock + _periodPool.periodBlock,
            buyTime : block.timestamp,
            perBlockUnlockAmount:0,
            lastInterestsShare: _periodPool.interestsShare,
            lastRewardsShare: _periodPool.rewardsShare
        });

        themisEarlyFarmingNFT.safeMint(_user,_nftInfo);

        
        emit UserDepositEvent(_user,_periodPoolId,_amount);
    }
    function batchUserWithdraw(uint256[] calldata _tokenIds,uint256[] calldata _amounts) external nonReentrant whenNotPaused{
        uint256 _length = _tokenIds.length;
        require(_length == _amounts.length && _length > 0, "error parameters.");
        for(uint256 i=0;i<_length;i++){
            _userWithdraw(_tokenIds[i],_amounts[i]);
        }
    }
    function userWithdraw(uint256 _tokenId,uint256 _amount) external nonReentrant whenNotPaused{
        _userWithdraw(_tokenId,_amount);
    }

    function nftTransferCall(uint256 _periodPoolId,address _from,address _to,uint256 _amount) external onlyNftCaller{
        UserPeriodInfo storage _fromUserPeriodInfo = userPeriodInfos[_periodPoolId][_from];
        _fromUserPeriodInfo.currDeposit = _fromUserPeriodInfo.currDeposit.sub(_amount);
        UserPeriodInfo storage _toUserPeriodInfo = userPeriodInfos[_periodPoolId][_to];
        _toUserPeriodInfo.currDeposit = _toUserPeriodInfo.currDeposit.add(_amount);
        emit NftTransferCallEvent(msg.sender,_periodPoolId,_from,_to,_amount);
    }

    function _userWithdraw(uint256 _tokenId,uint256 _amount) internal{
        require(_amount > 0, 'Amount must more than zero.');
        address _user = msg.sender;
        require(themisEarlyFarmingNFT.ownerOf(_tokenId) == _user,"NFT not owner.");

        EarlyFarmingNftInfo memory _nftInfo = themisEarlyFarmingNFT.earlyFarmingNftInfos(_tokenId);
        uint256 _unlockAmount = themisEarlyFarmingNFT.nftUnlockAmount(_tokenId);
        require(_unlockAmount >= _amount,"Input amount error.");

        uint256 _periodPoolId = _nftInfo.periodPoolId;
        PeriodPool storage _periodPool = periodPools[_periodPoolId];
        
        checkPoolPause(_periodPool.token);
        
        UserPeriodInfo storage _userPeriodInfo = userPeriodInfos[_periodPoolId][_user];
        
        require(_userPeriodInfo.currDeposit >= _amount, "invalid amount");

        _updateNftAndHarvestInterestsAndRewards(_tokenId,_nftInfo,_amount);
        

        address _token = _periodPool.token;
        address _spToken = _periodPool.spToken;
          // update gobal
        tokenCurrTotalDeposit[_token] = tokenCurrTotalDeposit[_token].sub(_amount);
        // update period pool
        _periodPool.currTotalDeposit = _periodPool.currTotalDeposit.sub(_amount);
        // update user
        _userPeriodInfo.currDeposit = _userPeriodInfo.currDeposit.sub(_amount);

        IERC20(_spToken).safeTransfer(_user,_amount);
        emit UserWithdrawEvent(_user,_tokenId,_amount);
    }
    
    
    function harvestInterestsAndRewards(uint256 _tokenId) external nonReentrant whenNotPaused{
        address _user = msg.sender;
        require(themisEarlyFarmingNFT.ownerOf(_tokenId) == _user,"NFT not owner.");
        EarlyFarmingNftInfo memory _nftInfo = themisEarlyFarmingNFT.earlyFarmingNftInfos(_tokenId);

        checkPoolPause(periodPools[_nftInfo.periodPoolId].token);
        
        _updateNftAndHarvestInterestsAndRewards(_tokenId,_nftInfo,0);
    }

    function checkPoolPause(address _token) public view {
        require(!hasRole(keccak256("VAR_PAUSE_POOL_ACCESS_ROLE"),_token),"This pool has been suspended.");
    }

    function _updateNftAndHarvestInterestsAndRewards(uint256 _tokenId,EarlyFarmingNftInfo memory _nftInfo,uint256 _amount) internal{
        address _user = msg.sender;
        uint256 _periodPoolId = _nftInfo.periodPoolId;

        _settlementProfit(_periodPoolId);

        PeriodPool storage _periodPool = periodPools[_periodPoolId];

        address _token = _periodPool.token;
        
        UserPeriodInfo storage _userPeriodInfo = userPeriodInfos[_periodPoolId][_user];
        uint256 _nftBeforeAmount = _nftInfo.pledgeAmount.sub(_nftInfo.withdrawAmount);
        
        uint256 _lendInterests = _calPendingProfit(_periodPool.interestsShare,_nftBeforeAmount,_nftInfo.lastInterestsShare);
        uint256 _rewards = _calPendingProfit(_periodPool.rewardsShare,_nftBeforeAmount,_nftInfo.lastRewardsShare);

        WithdrawNftParams memory _withdrawNftParams = WithdrawNftParams({
            tokenId: _tokenId,
            user: _user,
            withdrawUnlockAmount: _amount,
            lastInterestsShare: _periodPool.interestsShare,
            lastRewardsShare: _periodPool.rewardsShare
        });
        themisEarlyFarmingNFT.withdrawUnlockAmounts(_withdrawNftParams);
        
        if(_lendInterests > 0){
            _userPeriodInfo.totalRecvInterests = _userPeriodInfo.totalRecvInterests.add(_lendInterests);
            totalRecvInterests[_periodPoolId] = totalRecvInterests[_periodPoolId].add(_lendInterests);
            IERC20(_token).safeTransfer(_user,_lendInterests);
        }
        if( _rewards > 0){
            _userPeriodInfo.totalRecvRewards = _userPeriodInfo.totalRecvRewards.add(_rewards);
            totalRecvRewards[_periodPoolId] = totalRecvRewards[_periodPoolId].add(_rewards);
            IERC20(_periodPool.rewardToken).safeTransfer(_user,_rewards);
        }
        
        emit HarvestInterestsAndRewardsEvent(_user,_tokenId,_lendInterests,_rewards);
    }
    
    function getPendingInterestsAndRewards(uint256 _tokenId) external view returns(uint256 _pendingInterests,uint256 _pendingRewards){
        EarlyFarmingNftInfo memory _nftInfo = themisEarlyFarmingNFT.earlyFarmingNftInfos(_tokenId);
        PeriodPool memory _periodPool = periodPools[_nftInfo.periodPoolId];
        uint256 _nftAmount = _nftInfo.pledgeAmount.sub(_nftInfo.withdrawAmount);
        uint256 _currInterestsShare = _periodPool.interestsShare.add(_calAddPeriodPoolInterestsShare(_periodPool.lendPoolId,_periodPool.currTotalDeposit));
        _pendingInterests = _calPendingProfit(_currInterestsShare,_nftAmount,_nftInfo.lastInterestsShare);
        
        uint256 _currRewardsShare = _periodPool.rewardsShare.add(_calAddPeriodPoolRewardShare(_nftInfo.periodPoolId,_periodPool.currTotalDeposit));
        _pendingRewards = _calPendingProfit(_currRewardsShare,_nftAmount,_nftInfo.lastRewardsShare);

    }
    
    function _calAddPeriodPoolInterestsShare(uint256 _lendPoolId,uint256 _currTotalDeposit) internal view returns(uint256 _addPeriodPoolInterestsShare){
        ( uint256 _lendInterests,) =themisLendCompound.pendingRedeemInterests(_lendPoolId,address(this));
        _addPeriodPoolInterestsShare = _lendInterests.mul(1e18).div(_currTotalDeposit);
    }
    
    function _calAddPeriodPoolRewardShare(uint256 _periodPoolId,uint256 _currTotalDeposit) internal view returns(uint256 _addPeriodPoolRewardShare){
        uint256 _minerPoolReward =_minePeriodRewards(_periodPoolId);
        _addPeriodPoolRewardShare = _minerPoolReward.mul(1e18).div(_currTotalDeposit);
    }
    
    function _settlementProfit(uint256 _periodPoolId) internal {
        PeriodPool memory _periodPool = periodPools[_periodPoolId];
        // ssettlement interests
        _updateAllInterestsShare(_periodPool.lendPoolId,_periodPool.token);
        
        // settlement rewards
        _updatePeriodRewardShare(_periodPoolId);
        
        
    }

    function _updateAllInterestsShare(uint256 _lendPoolId,address _token) internal{
        uint256[] memory _periodIds = tokenPeriodIds[_token];
        uint256 _lendTokenAllInterests = themisLendCompound.userRedeem(_lendPoolId,0);
        uint256 _currTotalDeposit = tokenCurrTotalDeposit[_token];
        if(_lendTokenAllInterests <= 0 || _currTotalDeposit <= 0){
            return;
        }
        
        for(uint256 i=0;i<_periodIds.length;i++){
            PeriodPool storage _periodPool = periodPools[_periodIds[i]];
            uint256 _currPeriodDepositAlloc = _periodPool.currTotalDeposit.mul(1e18).div(_currTotalDeposit);
            if(_currPeriodDepositAlloc > 0){
                uint256 _lendPeriodInterests = _lendTokenAllInterests.mul(_currPeriodDepositAlloc).div(1e18);
                uint256 _addPeriodInterests = _lendPeriodInterests.mul(1e18).div(_periodPool.currTotalDeposit);
                uint256 _beforeInterestShare = _periodPool.interestsShare;
                _periodPool.interestsShare = _periodPool.interestsShare.add(_addPeriodInterests);
                emit UpdateShareEvent(_periodIds[i],msg.sender,1,_beforeInterestShare,_periodPool.interestsShare,_lendPeriodInterests);
            }
            _periodPool.lastInterestsBlock = block.number;
            
        }

    }

    function _updatePeriodRewardShare(uint256 _periodPoolId) internal{
         PeriodPool storage _periodPool = periodPools[_periodPoolId];
        uint256 _minerPoolReward =_minePeriodRewards(_periodPoolId);
        uint256 _currTokenTotalDeposit = _periodPool.currTotalDeposit;
        if(_minerPoolReward > 0){
            if(_currTokenTotalDeposit>0){
                uint256 _addPeriodPoolRewardShare = _minerPoolReward.mul(1e18).div(_currTokenTotalDeposit);
                uint256 _beforeRewardsShare = _periodPool.rewardsShare;
                _periodPool.rewardsShare = _periodPool.rewardsShare.add(_addPeriodPoolRewardShare);
            
                emit UpdateShareEvent(_periodPoolId,msg.sender,2,_beforeRewardsShare,_periodPool.rewardsShare,_minerPoolReward);
            }
            _periodPool.lastRewardBlock = block.number;
        }
    }
    

    
    function _calPendingProfit(uint256 _poolShare,uint256 _amount,uint256 _userLastShare) internal pure returns(uint256 _pendingProfit){
        _pendingProfit = _amount.mul(_poolShare.sub(_userLastShare)).div(1e18);
    }



    function _minePeriodRewards(uint256 _periodPoolId) internal view returns(uint256 _periodMineRewards){
        PeriodPool memory _periodPool = periodPools[_periodPoolId];
        bool _startRewardFlag = false;
        if(address(rewardToken)!=address(0) && startRewardBlock< block.number && endRewardBlock >= block.number){
            _startRewardFlag = true;
        }
        if(_periodPool.allocPoint >0 && _startRewardFlag){
            uint256 _totalMineRewards = _getBlockRewards(rewardPerBlock,_periodPool.lastRewardBlock,block.number);
            _periodMineRewards = _totalMineRewards.mul(_periodPool.allocPoint).div(totalAllocPoint);
        }
    }

    function _getBlockRewards(uint256 _rewardPerBlock,uint256 _startBlock,uint256 _endBlock) internal pure returns (uint256 _blockReward) {
        _blockReward = _rewardPerBlock.mul(_endBlock.sub(_startBlock));

    }
    
}
