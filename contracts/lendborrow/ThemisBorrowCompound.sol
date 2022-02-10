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

import "../governance/RoleControl.sol";

import "./ThemisFinanceToken.sol";

import "../uniswap/IUniswapV3Oracle.sol";

import "../interfaces/IThemisAuction.sol";
import "../interfaces/IThemisBorrowCompoundStorage.sol";
import "../interfaces/IThemisLendCompoundStorage.sol";


contract ThemisBorrowCompound is IThemisBorrowCompoundStorage,IThemisLendCompoundStorage,RoleControl,Initializable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using Address for address;

    using EnumerableSet for EnumerableSet.UintSet;
    

    event UserBorrow(address indexed user, uint256 indexed tokenId, uint256 indexed pid, uint256 bid, uint256 value, uint256 amount,uint256 borrowRate,address apply721Address, uint256 startBlock);
    event UserReturn(address indexed user, uint256 indexed bid,uint256 pid, uint256 amount,uint256 interests,uint256 platFormInterests);
    event TransferToAuction(uint256 indexed bid, uint256 indexed tokenId,uint256 pid);
    event SettlementBorrowEvent(uint256 indexed bid,uint256 pid,uint256 amount,uint256 interests,uint256 platFormInterests);
    
    event AddNftV3WhiteListEvent(uint256 indexed position,address sender,address token0,address token1);
    event SetNftV3WhiteListEvent(uint256 indexed position,address sender,address beforeToken0,address beforeToken1,address afterToken0,address afterToken1);
    event SetBorrowPoolOverdueRateEvent(uint256 indexed pid,address sender,uint256 beforeOverdueRate,uint256 afterOverdueRate);
    
    event SetSpecial721BorrowRateEvent(address indexed special72,address sender,uint256 beforeRate,uint256 afterRate);
    
    event ApplyRateEvent(address indexed sender,address apply721Address,uint256 specialMaxRate,uint256 tokenId);
    event setSettlementBorrowAuthEvent(address indexed sender,address user,bool flag);
    event TransferInterestToLendEvent(address indexed sender,uint256 pid,address toUser,uint256 interests);
    event SetInterestPlatformRateEvent(address indexed sender,uint256 beforeValue,uint256 afterValue);
    event SetFunderEvent(address indexed sender,address beforeVal,address afterVal);
    event FunderClaimEvent(address indexed sender,uint256 pid,uint256 amount);
    event MinSettingCollateralEvent(address indexed sender,uint256 pid,uint256 beforeVal,uint256 afterVal);
    event PausePoolEvent(address indexed sender,uint256 pid,bool flag);
 
    mapping(address => mapping(uint256 => BorrowUserInfo)) public borrowUserInfos;
    // Mapping from holder address to their (enumerable) set of owned borrow id
    mapping (address => mapping (uint256 => EnumerableSet.UintSet)) private _holderBorrowIds;
    
    mapping (address => EnumerableSet.UintSet) private _holderBorrowPoolIds;
    


    
    BorrowInfo[] public borrowInfo;

    IERC721 public uniswapV3;

    address public themisAuction ;
    
    IThemisLendCompound public lendCompound;
    CompoundBorrowPool[] public borrowPoolInfo;
    
    address[] public nftV3Token0WhiteList;
    address[] public nftV3Token1WhiteList;
    
    address[] public special721Arr;
    mapping(address => Special721Info) public special721Info;
    
    mapping(address => UserApplyRate) public userApplyRate;
    
    IUniswapV3Oracle public uniswapV3Oracle;
    
    uint256 public constant blockPerDay = 5760;
    
    uint256 public globalDefault = 650;

    mapping(address=>bool) public settlementBorrowAuth;

    mapping(uint256 => uint256) public badDebtPrincipal;
    mapping(uint256 => uint256) public badDebtInterest;

    address public funder;
    uint256 public interestPlatformRate;
    mapping(uint256 => uint256) public funderPoolInterest;  //pid => amount

    mapping(uint256 => uint256) public minSettingCollateral;// pid => min amount
    

    modifier onlyLendVistor {
        require(address(lendCompound) == msg.sender, "not lend vistor allow.");
        _;
    }

    modifier onlySettlementVistor {
        require(settlementBorrowAuth[msg.sender], "not settlement borrow vistor allow.");
        _;
    }

    modifier onlyFunderVistor {
        require(funder == msg.sender, "not funder vistor allow.");
        _;
    }

    modifier authContractAccessChecker {
        if(msg.sender.isContract() || tx.origin != msg.sender){
            require(hasRole(keccak256("CONTRACT_ACCESS_ROLE"),msg.sender), "not whitelist vistor allow.");
        }
        _;
    }
    
    function doInitialize(address _uniswapV3,address _uniswapV3Oracle, IThemisLendCompound _iThemisLendCompound,address _themisAuction,uint256 _globalDefault,uint256 _interestPlatformRate) public initializer{
        require(_globalDefault < 1_000,"The maximum ratio has been exceeded.");
        require(_interestPlatformRate < 10_000,"The maximum ratio has been exceeded.");
        _governance = msg.sender;
        _grantRole(PAUSER_ROLE, msg.sender);
        
        uniswapV3 = IERC721(_uniswapV3);
        uniswapV3Oracle  = IUniswapV3Oracle(_uniswapV3Oracle);
        lendCompound = _iThemisLendCompound;
        themisAuction = _themisAuction;
        globalDefault = _globalDefault;
        settlementBorrowAuth[themisAuction] = true;
        interestPlatformRate = _interestPlatformRate;
    }
    
    function setMinSettingCollateral(uint256 _pid,uint256 _minAmount) external onlyGovernance{
        uint256 _beforeVal = minSettingCollateral[_pid];
        minSettingCollateral[_pid] = _minAmount;
        emit MinSettingCollateralEvent(msg.sender,_pid,_beforeVal,_minAmount);
    }

    function setInterestPlatformRate(uint256 _interestPlatformRate)  external onlyGovernance{
        require(_interestPlatformRate < 10_000,"The maximum ratio has been exceeded.");
        uint256 _beforeValue = interestPlatformRate;
        interestPlatformRate = _interestPlatformRate;
        emit SetInterestPlatformRateEvent(msg.sender,_beforeValue,_interestPlatformRate);
    }

    function setSettlementBorrowAuth(address _user,bool _flag) external  onlyGovernance{
        settlementBorrowAuth[_user] = _flag;
        emit setSettlementBorrowAuthEvent(msg.sender,_user,_flag);
    }

    function pausePool(uint256 _pid) external onlyRole(PAUSER_ROLE){
        CompoundBorrowPool memory _borrowPool = borrowPoolInfo[_pid];
        _grantRole(keccak256("VAR_PAUSE_POOL_ACCESS_ROLE"), _borrowPool.token);
        emit PausePoolEvent(msg.sender,_pid,true);
    }

    function unpausePool(uint256 _pid) external onlyGovernance{
        CompoundBorrowPool memory _borrowPool = borrowPoolInfo[_pid];
        _revokeRole(keccak256("VAR_PAUSE_POOL_ACCESS_ROLE"), _borrowPool.token);
        emit PausePoolEvent(msg.sender,_pid,false);
    }


    function addBorrowPool(address borrowToken,address lendCToken) external onlyLendVistor{
        borrowPoolInfo.push(CompoundBorrowPool({
            token: borrowToken,
            ctoken: lendCToken,
            curBorrow: 0,
            curBowRate: 0,
            lastShareBlock: block.number,
            globalBowShare: 0,
            globalLendInterestShare: 0,
            totalMineInterests: 0,
            overdueRate: 800
        }));
        
    }
    
    function addNftV3WhiteList(address tokenA,address tokenB) external onlyGovernance{
        require( nftV3Token0WhiteList.length ==  nftV3Token1WhiteList.length,"error for nftV3Token0WhiteList size.");
        (address _token0, address _token1) = sortTokens(tokenA,tokenB);
        uint256 _position = nftV3Token0WhiteList.length;

        nftV3Token0WhiteList.push(_token0);
        nftV3Token1WhiteList.push(_token1);
        emit AddNftV3WhiteListEvent(_position,msg.sender,_token0,_token1);
    }
    
    function setNftV3WhiteList(uint256 position,address tokenA,address tokenB) external onlyGovernance{
        require( nftV3Token0WhiteList.length ==  nftV3Token1WhiteList.length,"error for nftV3Token0WhiteList size.");
        require( nftV3Token0WhiteList[position]!=address(0),"error for nftV3Token0WhiteList position.");
        (address _token0, address _token1) = sortTokens(tokenA,tokenB);
        address _beforeToken0 = nftV3Token0WhiteList[position];
        address _beforeToken1 = nftV3Token1WhiteList[position];
        nftV3Token0WhiteList[position] = _token0;
        nftV3Token1WhiteList[position] = _token1;
        
        emit SetNftV3WhiteListEvent(position,msg.sender,_beforeToken0,_beforeToken1,_token0,_token1);
    }
    
    function setSpecial721BorrowRate(address special721,uint256 rate,string memory name) external onlyGovernance{
        require(rate < 1000,"The maximum ratio has been exceeded.");
        uint256 beforeRate = special721Info[special721].rate;
        
        special721Info[special721].name = name;
        special721Info[special721].rate = rate;
        
        bool flag = true;
        for(uint i=0;i<special721Arr.length;i++){
            if(special721Arr[i] == special721){
                flag = false;
                break;
            }
        }
        if(flag){
            special721Arr[special721Arr.length] = special721;
        }

        emit SetSpecial721BorrowRateEvent(special721,msg.sender,beforeRate,rate);
    }
    
        
    function setBorrowPoolOverdueRate(uint256 pid,uint256 overdueRate) external onlyGovernance{
        CompoundBorrowPool storage _borrowPool = borrowPoolInfo[pid];
        uint256 beforeOverdueRate = _borrowPool.overdueRate;
        _borrowPool.overdueRate = overdueRate;
        emit SetBorrowPoolOverdueRateEvent(pid,msg.sender,beforeOverdueRate,overdueRate);
    }

    function setFunder(address _funder) external onlyGovernance{
        address _beforeVal = funder;
        funder = _funder;
        emit SetFunderEvent(msg.sender,_beforeVal,_funder);
    }

    
    function funderClaim(uint256 _pid,uint256 _amount) external onlyFunderVistor{

        uint256 _totalAmount = funderPoolInterest[_pid];
        require(_totalAmount >= _amount,"Wrong amount.");
        funderPoolInterest[_pid] = funderPoolInterest[_pid].sub(_amount);
        CompoundBorrowPool memory _borrowPool = borrowPoolInfo[_pid];
        checkPoolPause(_borrowPool.token);
        
        IERC20(_borrowPool.token).safeTransfer(funder,_amount);

        emit FunderClaimEvent(msg.sender,_pid,_amount);
    }
    

    function transferInterestToLend(uint256 pid,address toUser,uint256 interests) onlyLendVistor external{
        checkPoolPause(borrowPoolInfo[pid].token);

        IERC20(borrowPoolInfo[pid].token).safeTransfer(toUser,interests);
        emit TransferInterestToLendEvent(msg.sender,pid,toUser,interests);
    }
    
    function getUserMaxBorrowAmount(uint256 pid, uint256 tokenId, uint256 borrowAmount,address _user) public view returns(uint256 _maxBorrowAmount,bool _flag){
        require(checkNftV3WhiteList(tokenId),"Borrow error.Not uniswap V3 white list NFT.");
        CompoundBorrowPool memory _borrowPool = borrowPoolInfo[pid];

        (uint256 _value,) = uniswapV3Oracle.getTWAPQuoteNft(tokenId, _borrowPool.token);

        (,uint256 _borrowRate,,,,) = getUserApplyRate(_user);
  
        _maxBorrowAmount = _value.mul(_borrowRate).div(1000);
        _flag = _maxBorrowAmount >= borrowAmount;
    }
    
    function v3NFTBorrow(uint256 pid, uint256 tokenId, uint256 borrowAmount) public authContractAccessChecker nonReentrant whenNotPaused {
        require(checkNftV3WhiteList(tokenId),"Borrow error.Not uniswap V3 white list NFT.");
        BorrowUserInfo storage _user = borrowUserInfos[msg.sender][pid];
        CompoundBorrowPool memory _borrowPool = borrowPoolInfo[pid];
        checkPoolPause(_borrowPool.token);

        (uint256 _value,) = uniswapV3Oracle.getTWAPQuoteNft(tokenId, _borrowPool.token);

        require(_value > minSettingCollateral[pid],"The value of collateral is too low.");
        
        (,uint256 _borrowRate,,,,) = getUserApplyRate(msg.sender);

        
        uint256 _maxBorrowAmount = _value.mul(_borrowRate).div(1000);
        require(_maxBorrowAmount >= borrowAmount, 'Exceeds the maximum loanable amount');
        
        
        _upGobalBorrowInfo(pid,borrowAmount,1);
        
        borrowInfo.push(
            BorrowInfo({
                user: msg.sender,
                pid: pid,
                // borrowType: 1,
                tokenId: tokenId,
                borrowValue: _value,
                auctionValue: 0,
                amount: borrowAmount,
                repaidAmount: 0,
                startBowShare: _borrowPool.globalBowShare,
                // borrowDay: 0,
                startBlock: block.number,
                returnBlock: 0,
                interests: 0,
                state: 1
            })
        );
        uint256 _bid = borrowInfo.length - 1;

        _user.currTotalBorrow = _user.currTotalBorrow.add(borrowAmount);


        if(_holderBorrowIds[msg.sender][pid].length() == 0){

            _holderBorrowPoolIds[msg.sender].add(pid);
        }
        _holderBorrowIds[msg.sender][pid].add(_bid);
        
        uniswapV3.transferFrom(msg.sender, address(this), tokenId);
        
        lendCompound.loanTransferToken(pid,msg.sender,borrowAmount);


        
        emit UserBorrow(msg.sender, tokenId, pid, _bid, _value, borrowAmount,_borrowRate,userApplyRate[msg.sender].apply721Address, block.number);
    }
    
    function userReturn(uint256 bid,uint256 repayAmount) public authContractAccessChecker nonReentrant whenNotPaused{
        // 2021-1-18 when the collateral is to be cleared and transferred to auction, repayment can be carried out
        // require(!isBorrowOverdue(bid), 'borrow is overdue');
        BorrowInfo storage _borrowInfo = borrowInfo[bid];
        require(_borrowInfo.user == msg.sender, 'not owner');
        
        CompoundBorrowPool memory _borrowPool = borrowPoolInfo[_borrowInfo.pid];
        checkPoolPause(_borrowPool.token);
        
        BorrowUserInfo storage _user = borrowUserInfos[msg.sender][_borrowInfo.pid];
        
        uint256 _borrowInterests = _pendingReturnInterests(bid);
        require(repayAmount >= _borrowInterests,"Not enough to repay interest.");
        
        uint256 _repayAllAmount = _borrowInfo.amount.add(_borrowInterests);

        if(repayAmount > _repayAllAmount){
            repayAmount = _repayAllAmount;
        }

        uint256 _repayPrincipal = repayAmount.sub(_borrowInterests);
        
        uint256 _userBalance = IERC20(_borrowPool.token).balanceOf(msg.sender);
         require(_userBalance >= repayAmount, 'not enough amount.');

        _upGobalBorrowInfo(_borrowInfo.pid,_repayPrincipal,2);

        uint256 _platFormInterests = _borrowInterests.mul(interestPlatformRate).div(10_000);
        
        
        _updateRealReturnInterest(_borrowInfo.pid,_borrowInterests.sub(_platFormInterests));
        
        
        _user.currTotalBorrow = _user.currTotalBorrow.sub(_repayPrincipal);

        if(_repayPrincipal == _borrowInfo.amount){
            _holderBorrowIds[msg.sender][_borrowInfo.pid].remove(bid);
            if(_user.currTotalBorrow == 0){
                if(_holderBorrowIds[msg.sender][_borrowInfo.pid].length() == 0){
                    _holderBorrowPoolIds[msg.sender].remove(_borrowInfo.pid);
                }
            }
            _borrowInfo.returnBlock = block.number;
            _borrowInfo.state = 2;
            uniswapV3.transferFrom(address(this), msg.sender, _borrowInfo.tokenId);
        }else{
            _borrowInfo.amount = _borrowInfo.amount.sub(_repayPrincipal);
            _borrowInfo.startBowShare = _borrowPool.globalBowShare;
        }
        _borrowInfo.repaidAmount = _borrowInfo.repaidAmount.add(_repayPrincipal);
        _borrowInfo.interests = _borrowInfo.interests.add(_borrowInterests);

        
        IERC20(_borrowPool.token).safeTransferFrom(msg.sender, address(this), repayAmount);

        
        if(_platFormInterests > 0){
            funderPoolInterest[_borrowInfo.pid] = funderPoolInterest[_borrowInfo.pid].add(_platFormInterests);
        }

        IERC20(_borrowPool.token).safeApprove(address(lendCompound),0);
        IERC20(_borrowPool.token).safeApprove(address(lendCompound),_repayPrincipal);
        lendCompound.repayTransferToken(_borrowInfo.pid,_repayPrincipal);

        
        emit UserReturn(msg.sender, bid,_borrowInfo.pid, _repayPrincipal,_borrowInterests,_platFormInterests);
    }
    
    function applyRate(address special721,uint256 tokenId) external nonReentrant whenNotPaused{
        uint256 _confRate = special721Info[special721].rate;
        require(_confRate>0,"This 721 Contract not setting.");
        userApplyRate[msg.sender].apply721Address = special721;
        userApplyRate[msg.sender].specialMaxRate = _confRate;
        userApplyRate[msg.sender].tokenId = tokenId;
        emit ApplyRateEvent(msg.sender,special721,_confRate,tokenId);
    }

    
    
    
    function getUserApplyRate(address user) public view returns(string memory name,uint256 userMaxRate,uint256 defaultRate,uint256 tokenId,address apply721Address,bool signed){
        defaultRate = globalDefault;
        apply721Address = userApplyRate[user].apply721Address;
        signed = false;
        if(apply721Address!=address(0)){
            tokenId =  userApplyRate[user].tokenId;
            address tokenOwner = IERC721(apply721Address).ownerOf(tokenId);
            if(user == tokenOwner){
                userMaxRate = userApplyRate[user].specialMaxRate;
                signed = true;
                name = special721Info[apply721Address].name;
            }
        }
       
        if(userMaxRate == 0){
            userMaxRate = defaultRate;
        }
    }

    function transferToAuction(uint256 bid) external nonReentrant whenNotPaused{
        require(isBorrowOverdue(bid), 'can not auction now');

        BorrowInfo storage _borrowInfo = borrowInfo[bid];
        
        require(_borrowInfo.state == 1, 'borrow state error.');
        address _userAddr = _borrowInfo.user;

        CompoundBorrowPool storage _borrowPool = borrowPoolInfo[_borrowInfo.pid];
        checkPoolPause(_borrowPool.token);
        
        BorrowUserInfo storage _user = borrowUserInfos[_userAddr][_borrowInfo.pid];
        
        _borrowInfo.state = 9;

        _borrowInfo.interests = _pendingReturnInterests(bid);
        
        
        _user.currTotalBorrow = _user.currTotalBorrow.sub(_borrowInfo.amount);
        
        _holderBorrowIds[_userAddr][_borrowInfo.pid].remove(bid);
        if(_holderBorrowIds[_userAddr][_borrowInfo.pid].length() == 0){
            _holderBorrowPoolIds[_userAddr].remove(_borrowInfo.pid);
        }
        
        badDebtPrincipal[_borrowInfo.pid] = badDebtPrincipal[_borrowInfo.pid].add(_borrowInfo.amount);
        badDebtInterest[_borrowInfo.pid] = badDebtInterest[_borrowInfo.pid].add(_borrowInfo.interests);

        _upGobalBorrowInfo(_borrowInfo.pid,_borrowInfo.amount,2);
        lendCompound.transferToAuctionUpBorrow(_borrowInfo.pid,_borrowInfo.amount);
        
        
        (uint256 _value,) = uniswapV3Oracle.getTWAPQuoteNft(_borrowInfo.tokenId, _borrowPool.token);

        _borrowInfo.auctionValue = _value;
        
        IThemisAuction(themisAuction).toAuction(address(uniswapV3),_borrowInfo.tokenId,bid,_borrowPool.token,_borrowInfo.auctionValue,_borrowInfo.interests);
        
        uniswapV3.transferFrom(address(this), themisAuction, _borrowInfo.tokenId);
        
        emit TransferToAuction(bid, _borrowInfo.tokenId,_borrowInfo.pid);
    }
    
    function settlementBorrow(uint256 bid) public onlySettlementVistor nonReentrant whenNotPaused{
        BorrowInfo storage _borrowInfo = borrowInfo[bid];
        require(_borrowInfo.state == 9, 'error status');
        
    
        CompoundBorrowPool storage _borrowPool = borrowPoolInfo[_borrowInfo.pid];
        checkPoolPause(_borrowPool.token);

        _borrowInfo.state = 8;
        _borrowInfo.returnBlock = block.number;
        
        uint256 totalReturn = _borrowInfo.amount.add(_borrowInfo.interests);

        badDebtPrincipal[_borrowInfo.pid] = badDebtPrincipal[_borrowInfo.pid].sub(_borrowInfo.amount);
        badDebtInterest[_borrowInfo.pid] = badDebtInterest[_borrowInfo.pid].sub(_borrowInfo.interests);
        
        
        uint256 _platFormInterests = _borrowInfo.interests.mul(interestPlatformRate).div(10_000);
        
        
        _updateRealReturnInterest(_borrowInfo.pid,_borrowInfo.interests.sub(_platFormInterests));

        IERC20(_borrowPool.token).safeTransferFrom(msg.sender, address(this), totalReturn);

        if(_platFormInterests > 0){
            funderPoolInterest[_borrowInfo.pid] = funderPoolInterest[_borrowInfo.pid].add(_platFormInterests);
        }
        

        IERC20(_borrowPool.token).safeApprove(address(lendCompound),0);
        IERC20(_borrowPool.token).safeApprove(address(lendCompound),_borrowInfo.amount);
        lendCompound.settlementRepayTransferToken(_borrowInfo.pid,_borrowInfo.amount);
        
        emit SettlementBorrowEvent(bid, _borrowInfo.pid,_borrowInfo.amount,_borrowInfo.interests,_platFormInterests);
    }
    

    function checkNftV3WhiteList(uint256 tokenId) public view returns(bool flag) {
        (address _tokenA,address _tokenB,,,) = uniswapV3Oracle.getNFTAmounts(tokenId);
        (address _token0, address _token1) = sortTokens(_tokenA,_tokenB);
        flag = false;
        for (uint256 i = 0; i < nftV3Token0WhiteList.length; i++) {
            if(nftV3Token0WhiteList[i] == _token0 && nftV3Token1WhiteList[i] == _token1){
                flag = true;
                break;
            }
        }

    }
    
    function getSpecial721Length() external view returns(uint256){
        return special721Arr.length;
    }
    
    function pendingReturnInterests(uint256 bid) external view returns(uint256) {
        if (isBorrowOverdue(bid)) {
            return 0;
        }
       
        return _pendingReturnInterests(bid);
    }

    function checkPoolPause(address _token) public view {
        require(!hasRole(keccak256("VAR_PAUSE_POOL_ACCESS_ROLE"),_token),"This pool has been suspended.");
    }

    function _pendingReturnInterests(uint256 bid) private view returns(uint256) {

        BorrowInfo memory _borrowInfo = borrowInfo[bid];
        CompoundBorrowPool memory _borrowPool = borrowPoolInfo[_borrowInfo.pid];
        uint256 addBowShare = _calAddBowShare(_borrowPool.curBowRate,_borrowPool.lastShareBlock,block.number);
        return _borrowPool.globalBowShare.add(addBowShare).sub(_borrowInfo.startBowShare).mul(_borrowInfo.amount).div(1e12);
    }



    function getGlobalLendInterestShare(uint256 pid) external view returns(uint256 globalLendInterestShare){
        globalLendInterestShare = borrowPoolInfo[pid].globalLendInterestShare;
    }

    
    function isBorrowOverdue(uint256 bid) public view returns(bool) {
        BorrowInfo memory _borrowInfo = borrowInfo[bid];
    
        CompoundBorrowPool memory _borrowPool = borrowPoolInfo[_borrowInfo.pid];
        (uint256 _currValue,) = uniswapV3Oracle.getTWAPQuoteNft(_borrowInfo.tokenId, _borrowPool.token);
        
        uint256 auctionThreshold = _currValue.mul(_borrowPool.overdueRate).div(1000);

        
        uint256 interests = _pendingReturnInterests(bid);
        
        if (interests.add(_borrowInfo.amount) > auctionThreshold) {
            return true;
        }else{
            return false;
        }
        
    }
    
    function updateBorrowPool(uint256 pid ) external onlyLendVistor{
        _updateCompound(pid);
    }
    
    function getBorrowIdsOfOwnerAndPoolId(address owner,uint256 pid) external view returns (uint256[] memory) {
        uint256[] memory tokens = new uint256[](_holderBorrowIds[owner][pid].length());
        for (uint256 i = 0; i < _holderBorrowIds[owner][pid].length(); i++) {
            tokens[i] = _holderBorrowIds[owner][pid].at(i);
        }
        return tokens;
    }
    
    function getBorrowPoolIdsOfOwner(address owner) external view returns (uint256[] memory) {
        uint256[] memory tokens = new uint256[](_holderBorrowPoolIds[owner].length());
        for (uint256 i = 0; i < _holderBorrowPoolIds[owner].length(); i++) {
            tokens[i] = _holderBorrowPoolIds[owner].at(i);
        }
        return tokens;
    }
    
    function getFundUtilization(uint256 pid) public view returns(uint256) {
        CompoundLendPool memory _lendPool = lendCompound.lendPoolInfo(pid);
        
        if (_lendPool.curSupply.add(_lendPool.curBorrow) <= 0) {
            return 0;
        }
        return _lendPool.curBorrow.mul(1e12).div(_lendPool.curSupply.add(_lendPool.curBorrow));
    }
    
    function getBorrowingRate(uint256 pid) public view returns(uint256) {
        return getFundUtilization(pid).mul(200000000000).div(1e12).add(25000000000);
    }
    
    function getLendingRate(uint256 pid) public view returns(uint256) {
        return getFundUtilization(pid).mul(getBorrowingRate(pid)).div(1e12);
    }
    
        // returns sorted token addresses, used to handle return values from pairs sorted in this order
    function sortTokens(address tokenA, address tokenB) public pure returns (address token0, address token1) {
        require(tokenA != tokenB, 'V3 NFT: IDENTICAL_ADDRESSES');
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), 'V3 NFT: ZERO_ADDRESS');
    }
    
    
    function _upGobalBorrowInfo(uint256 pid,uint256 amount,uint optType) private{
        
        CompoundBorrowPool storage _borrowPool = borrowPoolInfo[pid];
        
        if(optType == 1){
             _borrowPool.curBorrow = _borrowPool.curBorrow.add(amount);
        }else{
             _borrowPool.curBorrow = _borrowPool.curBorrow.sub(amount);
        }
        _updateCompound(pid);
         
    }
    
     //must excute after Compound pool value update
    function _updateCompound(uint256 _pid) private {
        CompoundBorrowPool storage _borrowPool = borrowPoolInfo[_pid];
        if (_borrowPool.lastShareBlock >= block.number) {
            return;
        }
		uint256 addBowShare = _calAddBowShare(_borrowPool.curBowRate,_borrowPool.lastShareBlock,block.number);
 
        _borrowPool.lastShareBlock = block.number;
        _borrowPool.curBowRate = getBorrowingRate(_pid);
        _borrowPool.globalBowShare = _borrowPool.globalBowShare.add(addBowShare);

    }
    
    function _updateRealReturnInterest(uint256 _pid,uint256 _interests) private {
        if(_interests > 0){
            CompoundBorrowPool storage _borrowPool = borrowPoolInfo[_pid];
            uint256 lpSupply = ThemisFinanceToken(_borrowPool.ctoken).totalSupply();
            if (lpSupply > 0) {
                _borrowPool.globalLendInterestShare = _borrowPool.globalLendInterestShare.add(_interests.mul(1e12).div(lpSupply));
            }
        }

    }

    function _calAddBowShare(uint256 _curBowRate,uint256 _lastShareBlock,uint256 _blockNuber) pure internal returns(uint256 addBowShare){
        addBowShare = _curBowRate.mul(_blockNuber.sub(_lastShareBlock)).div(blockPerDay * 365);
    }


    
}

