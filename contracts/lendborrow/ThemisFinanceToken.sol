//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts@4.4.1/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts@4.4.1/access/Ownable.sol";
import "@openzeppelin/contracts@4.4.1/utils/structs/EnumerableSet.sol";

import "../interfaces/IThemisLendCompound.sol";


contract ThemisFinanceToken is ERC20,Ownable {
    using EnumerableSet for EnumerableSet.AddressSet;
    
    
    uint8 private _decimals = 18;


	constructor(string memory _name, string memory _symbol, uint8 _decimalsTmp) ERC20(_name, _symbol)  {
		_decimals = _decimalsTmp;
	}
	
	function decimals() public view override returns (uint8) {
        return _decimals;
    }
	
    function mint(address _to, uint256 _amount) onlyOwner external {
        _mint(_to, _amount);
    }
    
    function burn(address _to, uint256 _amount) onlyOwner external {
        _burn(_to, _amount);
    }

    
    function transfer(address recipient, uint256 amount) public override returns (bool) {
        
        IThemisLendCompound(owner()).doAfterLpTransfer(address(this),msg.sender,recipient,amount);

        return super.transfer(recipient, amount);
    }
    
    function transferFrom(address sender, address recipient, uint256 amount) public override returns (bool) {
        
        IThemisLendCompound(owner()).doAfterLpTransfer(address(this),sender,recipient,amount);
        
        return super.transferFrom(sender, recipient, amount);
    }
    

    
    
}