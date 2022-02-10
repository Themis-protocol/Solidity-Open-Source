// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts@4.4.1/proxy/transparent/TransparentUpgradeableProxy.sol";

contract ThemisEarlyFarmingProxy is TransparentUpgradeableProxy {
    
    address private constant initProxy = 0x822F456234e24Ea124c7571cf649f9A5F8DdF086;
    
    constructor() TransparentUpgradeableProxy(initProxy, msg.sender, "") {
    }
    
}
