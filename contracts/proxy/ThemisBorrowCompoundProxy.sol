// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts@4.4.1/proxy/transparent/TransparentUpgradeableProxy.sol";

contract ThemisBorrowCompoundProxy is TransparentUpgradeableProxy {
    
    address private constant initProxy = 0xf50Db1CE7924e860a712e186A794BA61dbDB9D58;
    
    constructor() TransparentUpgradeableProxy(initProxy, msg.sender, "") {
    }
    
}
