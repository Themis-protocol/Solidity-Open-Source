// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts@4.4.1/proxy/transparent/TransparentUpgradeableProxy.sol";

contract ThemisEarlyFarmingNFTDescriptorProxy is TransparentUpgradeableProxy {
    
    address private constant initProxy = 0x9ea2CF27F6fca47b99Ad443f38b68750EdA1159e;
    
    constructor() TransparentUpgradeableProxy(initProxy, msg.sender, "") {
    }
    
}
