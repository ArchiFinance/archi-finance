// SPDX-License-Identifier: MIT

pragma solidity =0.8.4;

import { ProxyAdmin } from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

/* 
The External contract is mainly used to export the ProxyAdmin and TransparentUpgradeableProxy contracts, 
so that the abi can be automatically generated.
*/