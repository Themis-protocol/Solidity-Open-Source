// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts@4.4.1/proxy/transparent/TransparentUpgradeableProxy.sol";

contract UniswapV3ChainLinkOracleProxy is TransparentUpgradeableProxy {
    
    address private constant initProxy = 0x08cE6fED8EC9BaB309E1E60c215DcaDDb27A5791;
    
    constructor() TransparentUpgradeableProxy(initProxy, msg.sender, "") {
    }
    
}
