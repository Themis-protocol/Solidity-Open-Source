// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts@4.4.1/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts@4.4.1/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts@4.4.1/utils/Counters.sol";
import "@openzeppelin/contracts@4.4.1/utils/math/SafeMath.sol";
import "@openzeppelin/contracts@4.4.1/utils/structs/EnumerableSet.sol";


import "../governance/RoleControl.sol";
import "../interfaces/IThemisEarlyFarmingNFTDescriptor.sol";
import "../interfaces/IThemisEarlyFarmingNFTStorage.sol";
import "../interfaces/IThemisEarlyFarming.sol";

contract ThemisEarlyFarmingNFT is IThemisEarlyFarmingNFTStorage,ERC721, ERC721Enumerable,RoleControl {
    using Counters for Counters.Counter;
    using SafeMath for uint256;
    using EnumerableSet for EnumerableSet.UintSet;

    event WithdrawAmountsEvent(address indexed sender,WithdrawNftParams withdrawNftParams);
    event SetThemisEarlyFarmingNFTDescriptorEvent(address indexed sender,address beforeAddr,address afterAddr);
    
    Counters.Counter private _tokenIdCounter;

    address public immutable miner;
    address public themisEarlyFarmingNFTDescriptor;

    mapping(uint256 => EarlyFarmingNftInfo) public earlyFarmingNftInfos;

    mapping(address => mapping(uint256 =>EnumerableSet.UintSet)) userNftPeriodPoolIdAllTokenIds; // user address => periodPoolId =>periodPoolId set // all records




    modifier onlyMinerVistor {
        require(address(miner) == msg.sender, "not miner allow.");
        _;
    }

    constructor(address themisEarlyFarming) ERC721("Themis vaults position", "TMS-POS") {
        _governance = msg.sender;
        _grantRole(PAUSER_ROLE, msg.sender);
        
        miner = themisEarlyFarming;
    }

    function setThemisEarlyFarmingNFTDescriptor(address addr) external onlyGovernance{
        address beforeAddr = themisEarlyFarmingNFTDescriptor;
        themisEarlyFarmingNFTDescriptor = addr;
        emit SetThemisEarlyFarmingNFTDescriptorEvent(msg.sender,beforeAddr,addr);
    }

    
    function nftUnlockAmount(uint256 tokenId) external view returns(uint256 unlockAmount){
        unlockAmount = _nftUnlockAmount(tokenId);
    }

    function _nftUnlockAmount(uint256 tokenId) internal view returns(uint256 unlockAmount){
        EarlyFarmingNftInfo memory nftInfo = earlyFarmingNftInfos[tokenId];
        uint256 currBlock = block.number;
        if(nftInfo.lastUnlockBlock < currBlock 
        && nftInfo.pledgeAmount > nftInfo.withdrawAmount
        && nftInfo.lastUnlockBlock <= nftInfo.endBlock){
            if( currBlock < nftInfo.endBlock){
                unlockAmount = nftInfo.perBlockUnlockAmount.mul(currBlock.sub(nftInfo.lastUnlockBlock));
            }else{
                unlockAmount = nftInfo.pledgeAmount.sub(nftInfo.withdrawAmount);
            }
        }
    }

    function withdrawUnlockAmounts(WithdrawNftParams memory withdrawNftParams) external onlyMinerVistor{
        uint256 tokenId = withdrawNftParams.tokenId;
        //withdrawUnlockAmount == 0 only harvest profit.
        if(withdrawNftParams.withdrawUnlockAmount > 0){
            require(_nftUnlockAmount(tokenId) >= withdrawNftParams.withdrawUnlockAmount,"error nft unlock amount.");
        }
        
        EarlyFarmingNftInfo storage nftInfo = earlyFarmingNftInfos[tokenId];

        uint256 withdrawBlock = withdrawNftParams.withdrawUnlockAmount.div(nftInfo.perBlockUnlockAmount);

        require(withdrawNftParams.user == nftInfo.ownerUser, "caller is not owner.");

        nftInfo.lastInterestsShare = withdrawNftParams.lastInterestsShare;
        nftInfo.lastRewardsShare = withdrawNftParams.lastRewardsShare;
        if(withdrawNftParams.withdrawUnlockAmount > 0){
            nftInfo.withdrawAmount += withdrawNftParams.withdrawUnlockAmount;
            nftInfo.lastUnlockBlock += withdrawBlock;
            if( nftInfo.lastUnlockBlock > nftInfo.endBlock){
                nftInfo.lastUnlockBlock = nftInfo.endBlock;
            }
        }
        
        emit WithdrawAmountsEvent(msg.sender,withdrawNftParams);
    }

    function safeMint(address to,EarlyFarmingNftInfo memory nftInfo) public onlyMinerVistor  {
        uint256 tokenId = _tokenIdCounter.current();
        _tokenIdCounter.increment();
        earlyFarmingNftInfos[tokenId] = nftInfo;
        earlyFarmingNftInfos[tokenId].perBlockUnlockAmount = nftInfo.pledgeAmount.div(nftInfo.endBlock.sub(nftInfo.startBlock));

        userNftPeriodPoolIdAllTokenIds[nftInfo.ownerUser][nftInfo.periodPoolId].add(tokenId);

        _safeMint(to, tokenId);
    }

    function getUserNftPeriodPoolIdAllTokenIds(address _user,uint8 _periodPoolId) external view returns(uint256[] memory){
        EnumerableSet.UintSet storage _periodPoolIdTokenIds = userNftPeriodPoolIdAllTokenIds[_user][_periodPoolId];
        uint256[] memory _tokenIds = new uint256[](_periodPoolIdTokenIds.length());
        for (uint256 i = 0; i < _periodPoolIdTokenIds.length(); i++) {
            _tokenIds[i] = _periodPoolIdTokenIds.at(i);
        }
        return _tokenIds;
    }
    

	function burn(uint256 tokenId) external whenNotPaused{
        require(_isApprovedOrOwner(_msgSender(), tokenId), "caller is not owner nor approved");
        _burn(tokenId);
    }

    function tokenURI(uint256 tokenId) public view override(ERC721) returns (string memory){
        if(themisEarlyFarmingNFTDescriptor == address(0)){
            return super.tokenURI(tokenId);
        }else{
           return IThemisEarlyFarmingNFTDescriptor(themisEarlyFarmingNFTDescriptor).tokenURI(tokenId);
        }
        
    }


    // function isApprovedOrOwner(address spender, uint256 tokenId) external view returns (bool){
    //     return _isApprovedOrOwner(spender,tokenId);
    // }
      /**
     * @dev See {IERC721-transferFrom}.
     */
    function transferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public virtual override(ERC721) whenNotPaused{
        //solhint-disable-next-line max-line-length
        require(_isApprovedOrOwner(_msgSender(), tokenId), "ERC721: transfer caller is not owner nor approved");
        _updateNftInfo(tokenId,from,to);
        super._transfer(from, to, tokenId);
    }

    /**
     * @dev See {IERC721-safeTransferFrom}.
     */
    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public virtual override(ERC721) whenNotPaused{
        safeTransferFrom(from, to, tokenId, "");
    }

    /**
     * @dev See {IERC721-safeTransferFrom}.
     */
    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId,
        bytes memory _data
    ) public virtual override(ERC721) whenNotPaused{
        require(_isApprovedOrOwner(_msgSender(), tokenId), "ERC721: transfer caller is not owner nor approved");
        _updateNftInfo(tokenId,from,to);
        super._safeTransfer(from, to, tokenId, _data);
    }

    function _updateNftInfo(uint256 tokenId,address from,address to) internal{
        EarlyFarmingNftInfo storage nftInfo = earlyFarmingNftInfos[tokenId];
        address nftOwner = nftInfo.ownerUser;
        userNftPeriodPoolIdAllTokenIds[nftOwner][nftInfo.periodPoolId].remove(tokenId);
        nftInfo.ownerUser = to;
        userNftPeriodPoolIdAllTokenIds[to][nftInfo.periodPoolId].add(tokenId);
        IThemisEarlyFarming(miner).nftTransferCall(nftInfo.periodPoolId,from,to,nftInfo.pledgeAmount.sub(nftInfo.withdrawAmount));
    }
    // The following functions are overrides required by Solidity.

    function _beforeTokenTransfer(address from, address to, uint256 tokenId)
        internal
        override(ERC721, ERC721Enumerable)
    {
        super._beforeTokenTransfer(from, to, tokenId);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC721Enumerable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
