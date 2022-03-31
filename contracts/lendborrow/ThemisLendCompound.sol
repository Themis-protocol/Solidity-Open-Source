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



import "../libraries/ThemisStrings.sol";

import "../governance/RoleControl.sol";
import "./ThemisFinanceToken.sol";


import "../interfaces/IThemisLendCompoundStorage.sol";
import "../interfaces/IThemisBorrowCompound.sol";


contract ThemisLendCompound is IThemisLendCompoundStorage,RoleControl,Initializable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using Address for address;
    using ThemisStrings for string;
    using EnumerableSet for EnumerableSet.UintSet;
    
    
    event AddPoolEvent(address indexed user,address token,uint256 allocpoint,bool withUpdate);
    event UserLend(address indexed user, uint256 pid, uint256 amount);
    event UserRedeem(address indexed user, uint256 pid, uint256 amount, uint256 interests,uint256 platFormInterests);
    event DoAfterLpTransferEvent(address indexed sender,address recipient, address spToken, uint256 amount, uint256 interests,uint256 platFormInterests);
    event SetMaxBorrowRateEvent(address indexed sender,uint256 beforeRate,uint256 afterRate);
    event SetAuthContractAccessEvent(address indexed sender,address contractAddr,bool flag);
    event LoanTransferTokenEvent(address indexed sender,address toUser,uint256 pid,uint256 amount);
    event RepayTransferTokenEvent(address indexed sender,uint256 pid,uint256 amount);
    event SettlementRepayTransferTokenEvent(address indexed sender,uint256 pid,uint256 amount);
    event TransferToAuctionUpBorrowEvent(address indexed sender,uint256 pid,uint256 amount);
    event SetInterestPlatformRateEvent(address indexed sender,uint256 beforeValue,uint256 afterValue);
    event SetFunderEvent(address indexed sender,address beforeVal,address afterVal);
    event FunderClaimEvent(address indexed sender,uint256 pid,uint256 amount);
    event PausePoolEvent(address indexed sender,uint256 pid,bool flag);
    
 
    mapping(address => mapping(uint256 => LendUserInfo)) public lendUserInfos;
    mapping(address => uint256) public tokenOfPid;
    mapping(address => uint256) public spTokenOfPid;
    
    mapping (address => EnumerableSet.UintSet) private _holderLendPoolIds;
    
    mapping(address => bool) private authSpTokenMap;
    mapping(address => bool) public authContractAccessMap;
    IThemisBorrowCompound public borrowCompound;

    
    CompoundLendPool[] public lendPoolInfo;

    
    address public funder;
    
    uint256 public maxBorrowRate;
    uint256 public interestPlatformRate;
    mapping(uint256 => uint256) public funderPoolInterest;  //pid => amount

    string private constant tokenPrefix = "SP-";
    

    
    modifier authContractAccessChecker {
        if(msg.sender.isContract() || tx.origin != msg.sender){
            require(authContractAccessMap[msg.sender], "not whitelist vistor allow.");
        }
        _;
    }

    
    modifier onlySpTokenVistor {
        require(authSpTokenMap[msg.sender], "not spToken vistor allow.");
        _;
    }

    modifier onlyBorrowVistor {
        require(address(borrowCompound) == msg.sender, "not borrow vistor allow.");
        _;
    }

    modifier onlyFunderVistor {
        require(funder == msg.sender, "not funder vistor allow.");
        _;
    }
    
    function doInitialize(IThemisBorrowCompound _borrowCompound,uint256 _maxBorrowRate,uint256 _interestPlatformRate) public initializer{
        require(_maxBorrowRate < 10000,"The maximum ratio has been exceeded.");
        require(_interestPlatformRate < 10000,"The maximum ratio has been exceeded.");
        _governance = msg.sender;
        _grantRole(PAUSER_ROLE, msg.sender);

        borrowCompound = _borrowCompound;
        maxBorrowRate = _maxBorrowRate;
        interestPlatformRate = _interestPlatformRate;
    }

    function pausePool(uint256 _pid) external onlyRole(PAUSER_ROLE){
        CompoundLendPool memory _pool = lendPoolInfo[_pid];
        _grantRole(keccak256("VAR_PAUSE_POOL_ACCESS_ROLE"), _pool.token);
        emit PausePoolEvent(msg.sender,_pid,true);
    }

    function unpausePool(uint256 _pid) external onlyGovernance{
        CompoundLendPool memory _pool = lendPoolInfo[_pid];
        _revokeRole(keccak256("VAR_PAUSE_POOL_ACCESS_ROLE"), _pool.token);
        emit PausePoolEvent(msg.sender,_pid,false);
    }

    function setInterestPlatformRate(uint256 _interestPlatformRate)  external onlyGovernance{
        require(_interestPlatformRate < 10000,"The maximum ratio has been exceeded.");
        uint256 _beforeValue = interestPlatformRate;
        interestPlatformRate = _interestPlatformRate;
        emit SetInterestPlatformRateEvent(msg.sender,_beforeValue,_interestPlatformRate);
    }

    function setAuthContractAccess(address _contractAddr,bool _flag) external onlyGovernance{
        require(_contractAddr.isContract(),"address is not contract address.");
        authContractAccessMap[_contractAddr] = _flag;
        emit SetAuthContractAccessEvent(msg.sender,_contractAddr,_flag);
    }


        
    /**
     *  _withUpdate :reserved
     **/
    function addPool(ERC20 _token, bool _withUpdate) public onlyGovernance {
        require(tokenOfPid[address(_token)] == 0, "Token is exists.");
        
        address _spToken = _createToken("Supply-Provider Token", tokenPrefix.concat(_token.symbol()), _token.decimals());
        lendPoolInfo.push(
             CompoundLendPool({
                 token: address(_token),
                 spToken: _spToken,
                 curSupply: 0,
                 curBorrow: 0,
				 totalRecvInterests: 0
             })
        );
        
        tokenOfPid[address(_token)] = lendPoolInfo.length - 1;
        
        spTokenOfPid[address(_spToken)] = tokenOfPid[address(_token)];
        
        
        authSpTokenMap[_spToken] = true;
        
        borrowCompound.addBorrowPool(address(_token),_spToken);
        
        emit AddPoolEvent(msg.sender,address(_token),0,_withUpdate);
    }
    
    function setMaxBorrowRate( uint256 _maxBorrowRate) public onlyGovernance{
        uint256 _beforeRate = maxBorrowRate;
        maxBorrowRate = _maxBorrowRate;
        emit SetMaxBorrowRateEvent(msg.sender,_beforeRate,maxBorrowRate);
        
    }

    function setFunder(address _funder) external onlyGovernance{
        address _beforeVal = funder;
        funder = _funder;
        emit SetFunderEvent(msg.sender,_beforeVal,_funder);
    }

    
    function funderClaim(uint256 _pid,uint256 _amount) external onlyFunderVistor{
        checkPoolPause(lendPoolInfo[_pid].token);

        uint256 _totalAmount = funderPoolInterest[_pid];
        require(_totalAmount >= _amount,"Wrong amount.");
        funderPoolInterest[_pid] = funderPoolInterest[_pid].sub(_amount);

        borrowCompound.transferInterestToLend(_pid,funder,_amount);
        emit FunderClaimEvent(msg.sender,_pid,_amount);
    }


    function userLend(uint256 _pid, uint256 _amount) public nonReentrant whenNotPaused{
        require(_amount > 0, "lend invalid amount");
        
        CompoundLendPool storage _pool = lendPoolInfo[_pid];
        checkPoolPause(_pool.token);

        LendUserInfo storage user = lendUserInfos[msg.sender][_pid];
        
        uint256 _globalLendInterestShare = borrowCompound.getGlobalLendInterestShare(_pid);
        
        (uint256 _lendInterests,)  = pendingRedeemInterests(_pid,msg.sender);
        user.unRecvInterests = _lendInterests;
        user.lastLendInterestShare = _globalLendInterestShare;


        ThemisFinanceToken(_pool.spToken).mint(msg.sender, _amount);
        _pool.curSupply = _pool.curSupply.add(_amount);
        
        
        _updateCompound(_pid);
		
		user.currTotalLend = user.currTotalLend.add(_amount);
		user.userDli = user.userDli.add(_amount);
		
		
		_holderLendPoolIds[msg.sender].add(_pid);
		
		IERC20(_pool.token).safeTransferFrom(msg.sender, address(this), _amount);
        
        emit UserLend(msg.sender, _pid, _amount);
    }
    
    function userRedeem(uint256 _pid, uint256 _amount) public nonReentrant whenNotPaused returns(uint256){
        require(_amount >= 0, 'invalid amount');
        CompoundLendPool storage _pool = lendPoolInfo[_pid];

        checkPoolPause(_pool.token);

        LendUserInfo storage user = lendUserInfos[msg.sender][_pid];
        require(user.userDli >= _amount, 'invalid amount');


        uint256 _globalLendInterestShare = borrowCompound.getGlobalLendInterestShare(_pid);
        
        (uint256 _lendInterests,uint256 _platFormInterests) = pendingRedeemInterests(_pid,msg.sender);
        uint256 _totalInterests = _lendInterests.add(_platFormInterests);
        
        user.unRecvInterests = 0;
        user.lastLendInterestShare = _globalLendInterestShare;
        

        _pool.curSupply = _pool.curSupply.sub(_amount);
        _pool.totalRecvInterests = _pool.totalRecvInterests.add(_totalInterests);
        
        _updateCompound(_pid);
		
        if(_amount > 0){
		    user.currTotalLend = user.currTotalLend.sub(_amount);
		    user.userDli = user.userDli.sub(_amount);
        }
		

		
		if(user.userDli == 0){
		    _holderLendPoolIds[msg.sender].remove(_pid);
		}
		
        if(_amount > 0){
            ThemisFinanceToken(_pool.spToken).burn(msg.sender, _amount);
            IERC20(_pool.token).safeTransfer(msg.sender, _amount);
        }

        
        
        if(_lendInterests> 0 ){
            borrowCompound.transferInterestToLend(_pid,msg.sender,_lendInterests);
            if(_platFormInterests > 0){
                funderPoolInterest[_pid] = funderPoolInterest[_pid].add(_platFormInterests);
            }
        }
		
        emit UserRedeem(msg.sender, _pid, _amount, _lendInterests,_platFormInterests);
        
        return _lendInterests;
    }

    function doAfterLpTransfer(address spToken,address sender,address recipient, uint256 amount) onlySpTokenVistor public {
        uint256 _pid = spTokenOfPid[spToken];
        require(amount > 0, 'invalid amount');
        CompoundLendPool storage _pool = lendPoolInfo[_pid];
        checkPoolPause(_pool.token);

        LendUserInfo storage _senderUser = lendUserInfos[sender][_pid];
        require(_senderUser.userDli >= amount, 'invalid amount');

        
        _updateCompound(_pid);
        
        //sender 
        uint256 _globalLendInterestShare = borrowCompound.getGlobalLendInterestShare(_pid);
        
        (uint256 _lendInterests,uint256 _platFormInterests) = pendingRedeemInterests(_pid,sender);
        uint256 _totalInterests = _lendInterests.add(_platFormInterests);
        
        _senderUser.unRecvInterests = 0;
        _senderUser.lastLendInterestShare = _globalLendInterestShare;
        
        _pool.totalRecvInterests = _pool.totalRecvInterests.add(_totalInterests);
        
        
        _senderUser.currTotalLend = _senderUser.currTotalLend.sub(amount);
		_senderUser.userDli = _senderUser.userDli.sub(amount);

		if(_senderUser.userDli == 0){
		    _holderLendPoolIds[sender].remove(_pid);
		}
		
		// recipient
		LendUserInfo storage _recipientUser = lendUserInfos[recipient][_pid];

        (_recipientUser.unRecvInterests,) =  pendingRedeemInterests(_pid,recipient);
        _recipientUser.lastLendInterestShare = _globalLendInterestShare;
		
		_recipientUser.currTotalLend = _recipientUser.currTotalLend.add(amount);
		_recipientUser.userDli = _recipientUser.userDli.add(amount);

		
		_holderLendPoolIds[recipient].add(_pid);
		
		
		// sender is user receive Interests.
        // sender is contract ,recipient is user ,recipient receive Interests.
        // sender and recipient both contract, funder receive Interests.
		if(_lendInterests > 0){
            if(!sender.isContract()){
                borrowCompound.transferInterestToLend(_pid,sender,_lendInterests);
            }else{
                if(!recipient.isContract()){
                    borrowCompound.transferInterestToLend(_pid,recipient,_lendInterests);
                }else{
                    funderPoolInterest[_pid] = funderPoolInterest[_pid].add(_lendInterests);
                }
            }
            
            if(_platFormInterests > 0){
                funderPoolInterest[_pid] = funderPoolInterest[_pid].add(_platFormInterests);
            }
		}
        emit DoAfterLpTransferEvent(sender,recipient, spToken, amount, _lendInterests,_platFormInterests);

    }
    

    function loanTransferToken(uint256 pid,address toUser,uint256 amount)  onlyBorrowVistor external{
        CompoundLendPool storage _pool = lendPoolInfo[pid];
        checkPoolPause(_pool.token);

        require(_pool.curSupply >= amount, 'not enough amount borrow');
        _pool.curSupply = _pool.curSupply.sub(amount);
        _pool.curBorrow = _pool.curBorrow.add(amount);
        require(_pool.curBorrow.mul(10000).div(_pool.curSupply.add(_pool.curBorrow)) < maxBorrowRate,"Exceeding the maximum total lending ratio.");

        IERC20(_pool.token).safeTransfer(toUser,amount);

        emit LoanTransferTokenEvent(msg.sender,toUser,pid,amount);

    }

    function repayTransferToken(uint256 pid,uint256 amount)  onlyBorrowVistor external{
        CompoundLendPool storage _pool = lendPoolInfo[pid];
        checkPoolPause(_pool.token);

        require(_pool.curBorrow >= amount, 'current borrow amount error. ');
        _pool.curSupply = _pool.curSupply.add(amount);
        _pool.curBorrow = _pool.curBorrow.sub(amount);

        IERC20(_pool.token).safeTransferFrom(msg.sender,address(this),amount);
        emit RepayTransferTokenEvent(msg.sender,pid,amount);
    }

    function settlementRepayTransferToken(uint256 pid,uint256 amount)  onlyBorrowVistor external{
        CompoundLendPool storage _pool = lendPoolInfo[pid];
        checkPoolPause(_pool.token);

        _pool.curSupply = _pool.curSupply.add(amount);
        IERC20(_pool.token).safeTransferFrom(msg.sender,address(this),amount);
        emit SettlementRepayTransferTokenEvent(msg.sender,pid,amount);
    }

    function transferToAuctionUpBorrow(uint256 pid,uint256 amount)  onlyBorrowVistor external{
        CompoundLendPool storage _pool = lendPoolInfo[pid];
        checkPoolPause(_pool.token);

        _pool.curBorrow = _pool.curBorrow.sub(amount);
        emit TransferToAuctionUpBorrowEvent(msg.sender,pid,amount);
    }

    
    function pendingRedeemInterests(uint256 _pid, address _user) public view returns(uint256 _lendInterests,uint256 _platFormInterests) {

        LendUserInfo memory user = lendUserInfos[_user][_pid];
        
        uint256 _globalLendInterestShare = borrowCompound.getGlobalLendInterestShare(_pid);
        _lendInterests = user.userDli.mul(_globalLendInterestShare.sub(user.lastLendInterestShare)).div(1e12);
        _platFormInterests = _lendInterests.mul(interestPlatformRate).div(10_000);
        _lendInterests = _lendInterests.sub(_platFormInterests).add(user.unRecvInterests);
    }
    


    
    function getPoolLength() external view returns(uint256 poolLength){
        poolLength = lendPoolInfo.length;
    }
    
    
    function getLendPoolIdsOfOwner(address owner) external view returns (uint256[] memory) {
        uint256[] memory tokens = new uint256[](_holderLendPoolIds[owner].length());
        for (uint256 i = 0; i < _holderLendPoolIds[owner].length(); i++) {
            tokens[i] = _holderLendPoolIds[owner].at(i);
        }
        return tokens;
    }

    function checkPoolPause(address _token) public view {
        require(!hasRole(keccak256("VAR_PAUSE_POOL_ACCESS_ROLE"),_token),"This pool has been suspended.");
    }
        

    function _updateCompound(uint256 pid) private{
        borrowCompound.updateBorrowPool(pid);
        
    }
    

    function _createToken(string memory _symbol, string memory _name, uint8 _decimals) private returns(address) {
        bytes memory deploymentData = abi.encodePacked(
            type(ThemisFinanceToken).creationCode,
            abi.encode(_symbol, _name, _decimals)
        );
        bytes32 _salt = keccak256(abi.encodePacked(_symbol, _name, _decimals, block.timestamp));
        address _token;
        assembly {
            _token := create2(
                0x0, add(0x20, deploymentData), mload(deploymentData), _salt
            )
        }
		require(_token != address(0), "Create2: Failed on create token");
		return _token;
    }

    
}


