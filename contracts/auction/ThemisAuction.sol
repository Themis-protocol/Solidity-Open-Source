pragma solidity ^0.8.0;
// SPDX-License-Identifier: SimPL-2.0
pragma experimental ABIEncoderV2;


import "@openzeppelin/contracts@4.4.1/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts@4.4.1/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts@4.4.1/utils/math/SafeMath.sol";
import "@openzeppelin/contracts@4.4.1/utils/Address.sol";
import "@openzeppelin/contracts@4.4.1/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts@4.4.1/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts@4.4.1/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts@4.4.1/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts@4.4.1/utils/structs/EnumerableMap.sol";



import "../libraries/ThemisStrings.sol";
import "../governance/RoleControl.sol";

import "../uniswap/IUniswapV3Oracle.sol";
import "../interfaces/IThemisBorrowCompound.sol";
import "../interfaces/IThemisLiquidation.sol";



contract ThemisAuction is RoleControl,IThemisBorrowCompoundStorage,Initializable{
    
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using Strings for string;
    using EnumerableSet for EnumerableSet.UintSet;
    
    struct AuctionInfo{
        address erc721Addr;
        uint256 tokenId;
        uint256 bid;
        uint256 auctionStartTime;
        address auctionToken;
        address auctionUser;
        uint256 startAuctionValue;
        uint256 startAuctionInterests;
        uint256 saledAmount;
        uint256 latestBidPrice;
        uint state;  // 0 read auction, 1 auctioning,2 auctioned
        uint256 totalBidAmount;
    }
    
    struct AuctionRecord{
        address auctionUser;
        uint256 auctionAmount;
        uint blockTime;
        bool returnPay;
        uint256 mulReduce;
    }

    struct BidAuctionInfo{
        uint256 auctionId;
        address harvestAddress;
        bool harvestFlag;
    }
    
    event ToAuctionEvent(uint256 indexed bid, uint256 indexed tokenId,address erc721Addr,address auctionToken,uint256 startAuctionAmount,uint256 startAuctioInterests);
    event DoAuctionEvent(uint256 indexed bid, uint256 indexed tokenId,uint256 indexed auctionId,uint256 auctionAmount,address userAddr);
    event DoHarvestAuctionEvent(uint256 indexed bid, uint256 indexed tokenId,uint256 indexed auctionId,address userAddr,uint256 bidArid,uint256 bidAmount,uint256 totalBidAmount);
    event AbortiveAuctionEvent(uint256 indexed auctionId,address toAddress);
    event SetActionConfigEvent(address sender,uint256 reductionRatio,uint256 reductionTime,uint256 riskFactor,uint256 onePriceRatio);
    event SetThemisLiquidationEvent(address sender,address themisLiquidation);
    event SetFunderEvent(address indexed sender,address beforeVal,address afterVal);
    event FunderClaimEvent(address indexed sender,address token,uint256 amount);
    event SetStreamingProcessorEvent(address indexed sender,address beforeVal,address afterVal);
    event ChangeUniswapV3OracleEvent(address indexed sender,address beforeVal,address afterVal);
    
    mapping(uint256 => AuctionInfo) public auctionInfos;
    uint256 public reductionTime = 14_400;
    uint256 public reductionRatio = 950;
    uint256 public riskFactor = 975;
    uint256 public onePriceRatio = 950;
    
    
    uint256[] private auctionIds;

    EnumerableSet.UintSet private _holderAuctioningIds;
    EnumerableSet.UintSet private _holderAuctionIds;
    EnumerableSet.UintSet private _holderBidAuctionIds;
    EnumerableSet.UintSet private _holderAuctionSaledIds;
    
    mapping(uint256 => AuctionRecord[]) public auctionRecords;
    
    address public funder;
    IThemisBorrowCompound public borrowCompound;
    IThemisLiquidation public themisLiquidation;
    IUniswapV3Oracle public uniswapV3Oracle;

    mapping(address => uint256) public funderPoolInterest;  //token => amount

    address public streamingProcessor;
    
    modifier onlyBorrowVistor {
        require(address(borrowCompound) == msg.sender, "not borrow vistor allow.");
        _;
    }

    modifier onlyFunderVistor {
        require(funder == msg.sender, "not funder vistor allow.");
        _;
    }
    
    
    function doInitialize(IThemisBorrowCompound _borrowCompound,IUniswapV3Oracle _uniswapV3Oracle,uint256 _reductionTime,uint256 _reductionRatio,uint256 _onePriceRatio,uint256 _riskFactor,address _streamingProcessor) external initializer{
        _governance = msg.sender;
        _grantRole(PAUSER_ROLE, msg.sender);
        borrowCompound = _borrowCompound;
        reductionTime = _reductionTime;
        riskFactor = _riskFactor;
        reductionRatio = _reductionRatio;
        uniswapV3Oracle = _uniswapV3Oracle;
        onePriceRatio = _onePriceRatio;
        streamingProcessor = _streamingProcessor;
    }

    function changeUniswapV3Oracle(address _uniswapV3Oracle) external onlyGovernance{
        address _beforeVal = address(uniswapV3Oracle);
        uniswapV3Oracle  = IUniswapV3Oracle(_uniswapV3Oracle);
        emit ChangeUniswapV3OracleEvent(msg.sender,_beforeVal,_uniswapV3Oracle);
    }
    
    function setActionConfig(uint256 _reductionRatio,uint256 _reductionTime,uint256 _riskFactor,uint256 _onePriceRatio) onlyGovernance external{
        require(_reductionRatio <1_000, "max reductionRatio.");
        require(_onePriceRatio <1_000, "max onePriceRatio.");
        require(_riskFactor <1_000, "max riskFactor.");
        reductionRatio = _reductionRatio;
        riskFactor = _riskFactor;
        onePriceRatio = _onePriceRatio;

        if(_reductionTime > 0 ){
            reductionTime = _reductionTime;
        }
          
        emit SetActionConfigEvent(msg.sender,_reductionRatio,_reductionTime,_riskFactor,_onePriceRatio);
    }

    function setThemisLiquidation(address _themisLiquidation) onlyGovernance external{
        themisLiquidation = IThemisLiquidation(_themisLiquidation);
        emit SetThemisLiquidationEvent(msg.sender,_themisLiquidation);
    }

    function setStreamingProcessor(address _streamingProcessor) external onlyGovernance{
        address _beforeVal = streamingProcessor;
        streamingProcessor = _streamingProcessor;
        emit SetStreamingProcessorEvent(msg.sender,_beforeVal,_streamingProcessor);
    }

    function setFunder(address _funder) external onlyGovernance{
        address _beforeVal = funder;
        funder = _funder;
        emit SetFunderEvent(msg.sender,_beforeVal,_funder);
    }

    
    function funderClaim(address _token,uint256 _amount) external onlyFunderVistor{

        uint256 _totalAmount = funderPoolInterest[_token];
        require(_totalAmount >= _amount,"Wrong amount.");
        funderPoolInterest[_token] = funderPoolInterest[_token].sub(_amount);

        IERC20(_token).safeTransfer(funder,_amount);
        emit FunderClaimEvent(msg.sender,_token,_amount);
    }
    
    function toAuction(address erc721Addr,uint256 tokenId,uint256 bid,address auctionToken,uint256 startAuctionValue,uint256 startAuctionInterests) onlyBorrowVistor external {
        
        uint256 auctionId = auctionIds.length;
        auctionIds.push(auctionId);
        auctionInfos[auctionId] = AuctionInfo({
            erc721Addr:erc721Addr,
            tokenId:tokenId,
            bid:bid,
            auctionStartTime:block.timestamp,
            auctionToken:auctionToken,
            auctionUser:address(0),
            startAuctionValue:startAuctionValue,
            startAuctionInterests:startAuctionInterests,
            saledAmount:0,
            latestBidPrice:0,
            state: 0,
            totalBidAmount: 0
        });
        _holderAuctioningIds.add(auctionId);
        _holderAuctionIds.add(auctionId);
        
        emit ToAuctionEvent(bid,tokenId,erc721Addr,auctionToken,startAuctionValue,startAuctionInterests);
    }
    
    function doAuction(uint256 auctionId,uint256 amount) external nonReentrant whenNotPaused{
        require(_holderAuctioningIds.contains(auctionId),"This auction not exist.");
        (uint256 _auctionAmount,uint256 _onePrice,uint256 _remainTime,uint256 mulReduce,,,) = _getCurrSaleInfo(auctionId);
        require(_remainTime >0,"Over time.");
        
        AuctionInfo storage _auctionInfo = auctionInfos[auctionId];
        require(_auctionInfo.state == 0 || _auctionInfo.state == 1,"This auction state error.");

        require(amount > _auctionInfo.latestBidPrice,"Must be greater than the existing maximum bid.");
        require(amount > _auctionAmount,"Must be greater than the starting price.");
        

        IERC20 _payToken = IERC20(_auctionInfo.auctionToken);
        
        AuctionRecord[] storage _auctionRecords = auctionRecords[auctionId];
        _auctionRecords.push(AuctionRecord({
            auctionUser: msg.sender,
            auctionAmount: amount,
            blockTime: block.timestamp,
            returnPay: false,
            mulReduce: mulReduce
        }));
        
        _auctionInfo.latestBidPrice = amount;
        _auctionInfo.state = 1;
        _auctionInfo.totalBidAmount =  _auctionInfo.totalBidAmount.add(amount);
        
        if(!_holderBidAuctionIds.contains(auctionId)){
            _holderBidAuctionIds.add(auctionId);
        }
        
        
        _payToken.safeTransferFrom(msg.sender,address(this),amount);
        
        if(_auctionRecords.length > 1){
            AuctionRecord storage _returnRecord = _auctionRecords[_auctionRecords.length-2];
            if(!_returnRecord.returnPay ){
                _returnRecord.returnPay = true;
                _payToken.safeTransfer(_returnRecord.auctionUser,_returnRecord.auctionAmount);
            }
        }
        
        if(amount >= _onePrice){
            _doHarvestAuction(auctionId,true);
        }
        
        emit DoAuctionEvent(_auctionInfo.bid,_auctionInfo.tokenId,auctionId,amount,msg.sender);
    }
    function doHarvestAuction(uint256 auctionId) external nonReentrant whenNotPaused{
        _doHarvestAuction(auctionId,false);
    }
    
    function _doHarvestAuction(uint256 auctionId,bool onePriceFlag) private{
        require(_holderAuctioningIds.contains(auctionId),"This auction not exist.");
        AuctionInfo storage _auctionInfo = auctionInfos[auctionId];
        require(_auctionInfo.state == 1,"Error auction state.");
        
        AuctionRecord[] memory _auctionRecords = auctionRecords[auctionId]; 
        
        (uint256 _maxBidArid,uint256 _maxBidAmount,uint256 _totalBidAmount,bool _harvestFlag,) = _getHarvestAuction(auctionId);
        require(_harvestFlag || onePriceFlag,"Not harverst in time.");
        
     
            
        AuctionRecord memory _auctionRecord = _auctionRecords[_maxBidArid];
        if(_auctionRecords.length > 0){
            
            require(_auctionRecord.auctionUser == msg.sender,"This auction does not belong to you.");
            require(_auctionRecord.returnPay == false,"This auction has been refunded.");
            
            IERC20 _payToken = IERC20(_auctionInfo.auctionToken);
            _auctionInfo.auctionUser = msg.sender;
            _auctionInfo.saledAmount = _auctionRecord.auctionAmount;
            _auctionInfo.state = 2;
            
            _holderAuctioningIds.remove(auctionId);
            _holderBidAuctionIds.remove(auctionId);
            _holderAuctionSaledIds.add(auctionId);
            
            
            BorrowInfo memory borrow = borrowCompound.borrowInfo(_auctionInfo.bid);    
            uint256 _returnAmount = borrow.amount.add(borrow.interests);
            
            if(_auctionRecord.auctionAmount > _returnAmount){
                uint256 _funderAmount = _auctionRecord.auctionAmount.sub(_returnAmount);
                funderPoolInterest[_auctionInfo.auctionToken] = funderPoolInterest[_auctionInfo.auctionToken].add(_funderAmount);
            }
            _payToken.safeApprove(address(borrowCompound),0);
            _payToken.safeApprove(address(borrowCompound),_returnAmount);
            borrowCompound.settlementBorrow(_auctionInfo.bid);
            
            IERC721(_auctionInfo.erc721Addr).transferFrom(address(this), msg.sender, _auctionInfo.tokenId);

        }
        
        emit DoHarvestAuctionEvent(_auctionInfo.bid,_auctionInfo.tokenId,auctionId,msg.sender,_maxBidArid,_maxBidAmount,_totalBidAmount);
    }
    
    

    function abortiveAuction(uint256 auctionId) external nonReentrant whenNotPaused{
        require(_holderAuctioningIds.contains(auctionId),"This auction not exist.");
        (uint256 _auctionAmount,,,, bool _bidFlag,,) = _getCurrSaleInfo(auctionId);
        require(_auctionAmount == 0,"In time.");
        require(!_bidFlag,"already bid.");
        
        
        AuctionInfo storage _auctionInfo = auctionInfos[auctionId];
        _auctionInfo.state = 9;
        
        _holderAuctioningIds.remove(auctionId);
        _holderBidAuctionIds.remove(auctionId);
        address _processor;
        if(address(themisLiquidation) == address(0)){
            require(streamingProcessor != address(0),"streamingProcessor address not config.");
            _processor = streamingProcessor;
            IERC721(_auctionInfo.erc721Addr).transferFrom(address(this), streamingProcessor, _auctionInfo.tokenId);
        }else{
            _processor = address(themisLiquidation);
            IERC721(_auctionInfo.erc721Addr).approve(_processor,_auctionInfo.tokenId);
            themisLiquidation.disposalNFT(_auctionInfo.bid,_auctionInfo.erc721Addr, _auctionInfo.tokenId,_auctionInfo.auctionToken);
        }
        
        
        emit AbortiveAuctionEvent(auctionId,_processor);
    }
    
    
    function getHolderAuctionIds() external view returns (uint256[] memory) {
        uint256[] memory actionIds = new uint256[](_holderAuctionIds.length());
        for (uint256 i = 0; i < _holderAuctionIds.length(); i++) {
            actionIds[i] = _holderAuctionIds.at(i);
        }
        return actionIds;
    }
    
    function getAuctioningIds() external view returns (uint256[] memory) {
        uint256[] memory actionIds = new uint256[](_holderAuctioningIds.length());
        for (uint256 i = 0; i < _holderAuctioningIds.length(); i++) {
            actionIds[i] = _holderAuctioningIds.at(i);
        }
        return actionIds;
    }
    
    function getBidAuctioningIds() external view returns (uint256[] memory) {
        uint256[] memory actionIds = new uint256[](_holderBidAuctionIds.length());
        for (uint256 i = 0; i < _holderBidAuctionIds.length(); i++) {
            actionIds[i] = _holderBidAuctionIds.at(i);
        }
        return actionIds;
    }
    
    function getUserBidAuctioningIds(address user) public view returns (uint256[] memory) {
        uint256[] memory _actionIdsTmp = new uint256[](_holderBidAuctionIds.length());
        uint _length = 0;
        uint256 _maximum = ~ uint256(0);
        for (uint256 i = 0; i < _holderBidAuctionIds.length(); i++) {
            uint256 _bidAuctionId = _holderBidAuctionIds.at(i);
            AuctionRecord[] memory _auctionRecords = auctionRecords[_bidAuctionId]; 
            bool _flag = false;
            for(uint256 _arId = 0; _arId < _auctionRecords.length; ++_arId){
                if(_auctionRecords[_arId].auctionUser == user){
                    _actionIdsTmp[i] = _bidAuctionId;
                    _length = _length+1;
                    _flag = true;
                    break;
                }
            }
            
            if(!_flag){
                _actionIdsTmp[i] =_maximum;
            }
        }
        
         uint256[] memory _actionIds = new uint256[](_length);
         uint _k = 0;
         for(uint256 j=0;j<_actionIdsTmp.length;j++){
             if(_actionIdsTmp[j]!=_maximum){
                 _actionIds[_k]=_actionIdsTmp[j];
                 _k = _k+1;
             }
         }
         
        return _actionIds;
    }
    
    
    function getUserBidAuctioningInfos(address user) external view returns (BidAuctionInfo[] memory ) {
        
        uint256[] memory _actionIds = getUserBidAuctioningIds(user);
        BidAuctionInfo[] memory _bidAuctionInfo = new BidAuctionInfo[](_actionIds.length);
        for (uint256 i = 0; i < _actionIds.length; i++) {
            uint256 _bidAuctionId = _actionIds[i];
            (,,,bool _harvestFlag,address _harvestAddress) = _getHarvestAuction(_bidAuctionId);
            _bidAuctionInfo[i].auctionId = _bidAuctionId;
            _bidAuctionInfo[i].harvestAddress = _harvestAddress;
            _bidAuctionInfo[i].harvestFlag = _harvestFlag;

        }
        return _bidAuctionInfo;
    }
    
    
    function getCurrSaleInfo (uint256 auctionId) external view returns(uint256 amount,uint256 onePrice,uint256 remainTime,uint256 mulReduce,bool bidFlag){
        (amount,onePrice,remainTime,mulReduce,bidFlag,,) = _getCurrSaleInfo(auctionId);
    }
    
    function getCurrSaleInfoV2 (uint256 auctionId) external view returns(uint256 amount,uint256 onePrice,uint256 remainTime,uint256 mulReduce,bool bidFlag,bool harvestFlag,address harvestAddress){
        (amount,onePrice,remainTime,mulReduce,bidFlag,harvestFlag,harvestAddress) = _getCurrSaleInfo(auctionId);
    }
    
    function getHarvestAuction(uint256 auctionId) external view returns(uint256 maxBidArid,uint256 maxBidAmount,uint256 totalBidAmount){
        (maxBidArid,maxBidAmount,totalBidAmount,,) = _getHarvestAuction(auctionId);
    }
    
    function getHarvestAuctionV2(uint256 auctionId) external view returns(uint256 maxBidArid,uint256 maxBidAmount,uint256 totalBidAmount,bool harvestFlag,address harvestAddress){
        (maxBidArid,maxBidAmount,totalBidAmount,harvestFlag,harvestAddress) = _getHarvestAuction(auctionId);
    }
    
    function getAuctionRecordLength(uint256 auctionId) external view returns(uint256 length){
        AuctionRecord[] memory _auctionRecords = auctionRecords[auctionId]; 
        length = _auctionRecords.length;
    }
    

    function _getCurrSaleInfo(uint256 auctionId) internal view returns(uint256 amount,uint256 onePrice,uint256 remainTime,uint256 mulReduce,bool bidFlag,bool harvestFlag,address harvestAddress){
        require(_holderAuctioningIds.contains(auctionId),"This auction not exist.");
        
        AuctionInfo memory _auctionInfo = auctionInfos[auctionId];
        bidFlag = (_auctionInfo.state == 1);

        uint256 _startValue = _auctionInfo.startAuctionValue.add(_auctionInfo.startAuctionInterests);


        uint256 _diffTime = uint256(block.timestamp).sub(_auctionInfo.auctionStartTime);
        if(!bidFlag){
            mulReduce = _diffTime.div(reductionTime);
            amount = _calAuctionPriceByRiskFactor(_auctionInfo,_startValue,mulReduce);
            if(amount > 0){
                remainTime = reductionTime.sub(_diffTime.sub(reductionTime.mul(mulReduce)));
                onePrice = _calOnePrice(amount);
            }

        }else{
            AuctionRecord memory _lastAuctionRecord = _getLastAuctionRecord(auctionId);
            require(_lastAuctionRecord.auctionUser != address(0),"Auction record error.");
            amount = _lastAuctionRecord.auctionAmount;
            mulReduce = _lastAuctionRecord.mulReduce;

            uint256 _auctionNextTime = _auctionInfo.auctionStartTime + (mulReduce+1)*reductionTime;
            if(_auctionNextTime > block.timestamp ){
                remainTime = _auctionNextTime - _lastAuctionRecord.blockTime;
                onePrice = _calOnePrice(_calAuctionPrice(_startValue,mulReduce));
            }else{
                harvestFlag == true;
                harvestAddress = _lastAuctionRecord.auctionUser;
            }
        }
    }

    function _calOnePrice(uint256 auctionPrice) internal view returns(uint256 onePrice){
        onePrice = auctionPrice.mul(1_000).div(onePriceRatio);
    }

    function _calAuctionPriceByRiskFactor(AuctionInfo memory auctionInfo,uint256 startValue,uint256 mulReduce) internal view returns(uint256 auctionPrice){
        auctionPrice = _calAuctionPrice(startValue,mulReduce);
        if(auctionPrice > 0){
            if(!_checkCanAuction(auctionInfo,auctionPrice)){
                auctionPrice = 0;
            }
        }
    }

    function _calAuctionPrice(uint256 startValue,uint256 mulReduce) internal view returns(uint256 auctionPrice){
        auctionPrice = startValue*1_000*reductionRatio**mulReduce/(1_000**mulReduce)/1_000;
    } 

    function _checkCanAuction(AuctionInfo memory auctionInfo,uint256 auctionPrice) internal view returns(bool _canSell){
        
        (uint256 _nftCurrValue,) = uniswapV3Oracle.getTWAPQuoteNft(auctionInfo.tokenId, auctionInfo.auctionToken);
        BorrowInfo memory _borrow = borrowCompound.borrowInfo(auctionInfo.bid);

        uint256 _needRepay = _borrow.amount.add(_borrow.interests).mul(1_000);

        if(_needRepay.div(auctionPrice) < riskFactor && _needRepay.div(_nftCurrValue) < riskFactor ){
            _canSell = true;
        }

    }

    function _getLastAuctionRecord(uint256 auctionId) internal view returns(AuctionRecord memory lastAuctionRecord){
        AuctionRecord[] memory _auctionRecords = auctionRecords[auctionId]; 
        if(_auctionRecords.length > 0){
            lastAuctionRecord = _auctionRecords[_auctionRecords.length-1];
        }
    }
    
    function _getHarvestAuction(uint256 auctionId) internal view returns(uint256 maxBidArid,uint256 maxBidAmount,uint256 totalBidAmount,bool harvestFlag,address harvestAddress){
        AuctionInfo memory _auctionInfo = auctionInfos[auctionId];
        totalBidAmount = _auctionInfo.totalBidAmount;
        if(_auctionInfo.state == 1){
            AuctionRecord[] memory _auctionRecords = auctionRecords[auctionId]; 
            if(_auctionRecords.length > 0){
                maxBidArid = _auctionRecords.length-1;
                AuctionRecord memory _lastAuctionRecord = _auctionRecords[maxBidArid];
                maxBidAmount = _lastAuctionRecord.auctionAmount;
                uint256 _auctionNextTime = _auctionInfo.auctionStartTime + (_lastAuctionRecord.mulReduce+1)*reductionTime;
                if(_auctionNextTime < block.timestamp ){
                    harvestFlag = true;
                    harvestAddress = _lastAuctionRecord.auctionUser;
                }
            }
            
        }
    }
    
    
}