// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts@4.4.1/proxy/transparent/TransparentUpgradeableProxy.sol";

contract UniswapV3PoolWhiteProxy is TransparentUpgradeableProxy {
    
    address private constant initProxy = 0xDE240b43f489677D69C9a2568284f09C8faff5e7;

    
    constructor() TransparentUpgradeableProxy(initProxy, msg.sender, "") {

    }
    
}